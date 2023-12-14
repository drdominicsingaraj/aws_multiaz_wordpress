#! /bin/bash
# Install updates
sudo yum update -y
# Install Apache server
sudo yum install -y httpd
# Install MariaDB, PHP and necessary tools
sudo yum install -y mariadb105-server php php-mysqlnd unzip

# Set database variables

# DBName='aurora_db'
# DBUser='admin'
# DBPassword='wWkTAeM3n3ZQUlOBQzh0'
# DBRootPassword='wWkTAeM3n3ZQUlOBQzh0'
#DBHost='clusterinstance-0.cyoauc7cwdyr.us-east-1.rds.amazonaws.com'

# Start Apache server and enable it on system startup

sudo systemctl start httpd
sudo systemctl enable httpd

# Start MariaDB service and enable it on system startup

sudo systemctl start mariadb
sudo systemctl enable mariadb

# Set Mariadb root password

mysqladmin -u root password $DBRootPassword

# Download and install Wordpress

# wget http://wordpress.org/latest.tar.gz -P /var/www/html
# cd /var/www/html
# tar -zxvf latest.tar.gz 
# cp -rvf wordpress/* . 
# rm -R wordpress 
# rm latest.tar.gz

# Configure Wordpress

# Making changes to the wp-config.php file, setting the DB name
# cp ./wp-config-sample.php ./wp-config.php # rename the file from sample to clean
# sed -i "s/'database_name_here'/'$DBName'/g" wp-config.php 
# sed -i "s/'username_here'/'$DBUser'/g" wp-config.php 
# sed -i "s/'password_here'/'$DBPassword'/g" wp-config.php
# sed -i "s/'localhost'/'$DBHost'/g" wp-config.php
# Grant permissions

# usermod -a -G apache ec2-user 
# chown -R ec2-user:apache /var/www 
# chmod 2775 /var/www 
# find /var/www -type d -exec chmod 2775 {} \; 
# find /var/www -type f -exec chmod 0664 {} \; 

cd /var/www/html
aws s3 sync s3://restartproject/ .
