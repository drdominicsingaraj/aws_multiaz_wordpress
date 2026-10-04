# Shared naming. Every resource name derives from this prefix so that the
# environments can live side by side in one AWS account without clashing.
# Keep project + environment short: ALB and target group names are limited to 32 characters.
locals {
  prefix = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  db_app_user    = "wordpress" # dedicated WordPress DB user (the RDS master password rotates)
  alb_log_prefix = "alb"       # key prefix of the ALB access logs in the log bucket
}

# Boot script for every web instance: mount the shared EFS and serve WordPress from it
locals {
  web_user_data = base64encode(templatefile("${path.module}/userdatalaunchtemplate.tpl", {
    efs_id        = aws_efs_file_system.wordpress.id
    db_host       = aws_rds_cluster.auroracluster.endpoint
    db_name       = aws_rds_cluster.auroracluster.database_name
    db_admin_user = aws_rds_cluster.auroracluster.master_username
    db_app_user   = local.db_app_user
    db_secret_arn = aws_rds_cluster.auroracluster.master_user_secret[0].secret_arn
    region        = data.aws_region.current.name
    log_group     = local.web_log_ns
    cache_host    = local.cache_host
    cache_prefix  = local.prefix
  }))
}

# Latest Amazon Linux 2023 AMI (patched) unless an AMI is pinned with ami_id
data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == "" ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.cpu_architecture}"
}

locals {
  ami_id     = var.ami_id != "" ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023[0].value) # public AMI ID, not a secret
  web_log_ns = "/${local.prefix}/web"                                                               # CloudWatch Logs group prefix for the web instances
}

locals {
  # Web instances: public subnets, or private subnets (behind the NAT gateway) when requested
  web_subnet_ids = var.web_tier_in_private_subnets ? [aws_subnet.private-1.id, aws_subnet.private-2.id] : [aws_subnet.public-1.id, aws_subnet.public-2.id]

  cache_host = var.enable_object_cache ? aws_elasticache_replication_group.cache[0].primary_endpoint_address : ""
}

# Latest Aurora MySQL 3 (MySQL 8.0) release unless a version is pinned with db_engine_version.
# (The old Aurora MySQL 2 / MySQL 5.7 line is out of standard support.)
data "aws_rds_engine_version" "aurora" {
  count   = var.db_engine_version == "" ? 1 : 0
  engine  = "aurora-mysql"
  version = "8.0"
  latest  = true
}

locals {
  db_engine_version = var.db_engine_version != "" ? var.db_engine_version : data.aws_rds_engine_version.aurora[0].version
}
