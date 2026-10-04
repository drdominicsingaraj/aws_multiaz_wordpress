#!/bin/bash
# Boot script for the web instances: mount the shared EFS at /var/www/html and serve WordPress from it.
# The first instance to boot installs WordPress onto the EFS; later instances reuse the files.
# No `set -x`: this log must never contain passwords.
exec > >(tee /var/log/user-data.log) 2>&1

WEBROOT=/var/www/html
EFS_ID="${efs_id}"
DB_HOST="${db_host}"
DB_NAME="${db_name}"
DB_ADMIN_USER="${db_admin_user}"
DB_APP_USER="${db_app_user}"
DB_SECRET_ARN="${db_secret_arn}"
REGION="${region}"
CACHE_HOST="${cache_host}"
CACHE_PREFIX="${cache_prefix}"

dnf install -y httpd php php-mysqlnd php-gd php-xml php-mbstring amazon-efs-utils amazon-cloudwatch-agent mariadb105 jq tar unzip

# Mount EFS (TLS, persistent across reboots)
mkdir -p $WEBROOT
grep -q "$EFS_ID" /etc/fstab || echo "$EFS_ID:/ $WEBROOT efs _netdev,tls 0 0" >> /etc/fstab
for i in $(seq 1 30); do
  mount -a -t efs && mountpoint -q $WEBROOT && break
  sleep 10
done
mountpoint -q $WEBROOT || { echo "EFS mount failed"; exit 1; }

# Install WordPress onto the EFS (first instance only; mkdir is an atomic lock).
# The RDS master password rotates, so WordPress gets its own database user instead of
# the master credentials. Its password lives only in wp-config.php on the encrypted EFS.
install_wordpress() {
  curl -sL https://wordpress.org/latest.tar.gz | tar -xz -C /tmp || return 1
  cp -a /tmp/wordpress/. $WEBROOT/ || return 1

  MASTER_PW=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$DB_SECRET_ARN" \
    --query SecretString --output text | jq -r .password) || return 1
  APP_PW=$(openssl rand -hex 24)
  mysql -h "$DB_HOST" -u "$DB_ADMIN_USER" -p"$MASTER_PW" <<SQL || return 1
CREATE USER IF NOT EXISTS '$DB_APP_USER'@'%' IDENTIFIED BY '$APP_PW';
ALTER USER '$DB_APP_USER'@'%' IDENTIFIED BY '$APP_PW';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_APP_USER'@'%';
FLUSH PRIVILEGES;
SQL

  # Build the config next to the final name and move it into place last, so a half-finished
  # install is never mistaken for a complete one.
  cp $WEBROOT/wp-config-sample.php $WEBROOT/wp-config.php.tmp
  sed -i "s/database_name_here/$DB_NAME/; s/username_here/$DB_APP_USER/; s/password_here/$APP_PW/; s/localhost/$DB_HOST/" $WEBROOT/wp-config.php.tmp
  # Unique authentication keys and salts (the sample file ships with placeholders)
  for k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
    sed -i "/'$k'/s/put your unique phrase here/$(openssl rand -hex 32)/" $WEBROOT/wp-config.php.tmp
  done
  # Behind CloudFront/ALB: trust the forwarded protocol and build site URLs from the requested host,
  # so the site works on the CloudFront domain, a custom domain, or the ALB name.
  cat > /tmp/wp-proxy.php <<'PHP'
if (isset($_SERVER['HTTP_CLOUDFRONT_FORWARDED_PROTO']) && $_SERVER['HTTP_CLOUDFRONT_FORWARDED_PROTO'] === 'https') { $_SERVER['HTTPS'] = 'on'; }
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') { $_SERVER['HTTPS'] = 'on'; }
if (isset($_SERVER['HTTP_HOST'])) {
  $scheme = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ? 'https' : 'http';
  define('WP_HOME', $scheme . '://' . $_SERVER['HTTP_HOST']);
  define('WP_SITEURL', WP_HOME);
}
PHP
  sed -i '/^<?php/r /tmp/wp-proxy.php' $WEBROOT/wp-config.php.tmp
  # Object cache (ElastiCache Redis): point WordPress at it and install the plugin's drop-in.
  # The cache is optional, so a failed plugin download must not fail the install.
  if [ -n "$CACHE_HOST" ]; then
    cat > /tmp/wp-cache.php <<'PHP'
define('WP_REDIS_HOST', '@HOST@');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_SCHEME', 'tls');
define('WP_REDIS_DATABASE', 0);
define('WP_REDIS_PREFIX', '@PFX@');
define('WP_CACHE_KEY_SALT', '@PFX@');
PHP
    sed -i "s/@HOST@/$CACHE_HOST/; s/@PFX@/$CACHE_PREFIX/g" /tmp/wp-cache.php
    sed -i '/^<?php/r /tmp/wp-cache.php' $WEBROOT/wp-config.php.tmp
    if curl -sfL https://downloads.wordpress.org/plugin/redis-cache.latest-stable.zip -o /tmp/redis-cache.zip \
       && unzip -q -o /tmp/redis-cache.zip -d $WEBROOT/wp-content/plugins/; then
      cp $WEBROOT/wp-content/plugins/redis-cache/includes/object-cache.php $WEBROOT/wp-content/object-cache.php
    else
      echo "Redis Object Cache plugin not installed; WordPress runs without the object cache"
    fi
  fi
  chmod 640 $WEBROOT/wp-config.php.tmp
  chown -R apache:apache $WEBROOT
  mv $WEBROOT/wp-config.php.tmp $WEBROOT/wp-config.php
}

for i in $(seq 1 120); do
  [ -f $WEBROOT/wp-config.php ] && break
  if mkdir $WEBROOT/.init-lock 2>/dev/null; then
    if install_wordpress; then echo "WordPress installed on EFS"; else echo "WordPress install failed, will be retried"; sleep 15; fi
    rmdir $WEBROOT/.init-lock
    continue
  fi
  # A lock older than 10 minutes belongs to an instance that died mid-install: take it over
  if [ -n "$(find $WEBROOT/.init-lock -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rmdir $WEBROOT/.init-lock 2>/dev/null
    continue
  fi
  sleep 5
done

systemctl enable --now httpd

# CloudWatch agent: memory and disk metrics (per ASG) and Apache/boot logs in CloudWatch Logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/web.json <<'JSON'
{
  "agent": { "metrics_collection_interval": 60 },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": { "AutoScalingGroupName": "$${aws:AutoScalingGroupName}" },
    "aggregation_dimensions": [["AutoScalingGroupName"]],
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["used_percent"], "resources": ["/"] }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/httpd/access_log", "log_group_name": "${log_group}/apache-access", "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/httpd/error_log", "log_group_name": "${log_group}/apache-error", "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/user-data.log", "log_group_name": "${log_group}/user-data", "log_stream_name": "{instance_id}" }
        ]
      }
    }
  }
}
JSON
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/web.json
