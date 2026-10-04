# RDS Aurora MySQL Database Configuration
# Aurora cluster whose size, protection and backups are set per environment.

# Database subnet group for Aurora cluster
# Groups private subnets across both AZs for database deployment
resource "aws_db_subnet_group" "db_subnet" {
  name       = "${local.prefix}-db-subnet-group"
  subnet_ids = [aws_subnet.private-1.id, aws_subnet.private-2.id] # Private subnets only

  tags = {
    Name = "${local.prefix}-db-subnet-group"
  }
}

# Aurora MySQL cluster
# Main database cluster that manages the database instances
resource "aws_rds_cluster" "auroracluster" {
  cluster_identifier = "${local.prefix}-aurora"

  # Database engine configuration
  engine         = "aurora-mysql"
  engine_version = local.db_engine_version

  # Lifecycle rule to prevent accidental engine version changes
  lifecycle {
    ignore_changes = [engine_version]
  }

  # Database configuration
  database_name   = "auroradb"
  master_username = "admin"

  # AWS generates the master password and stores it in Secrets Manager
  # (see the db_master_secret_arn output). No password lives in the code.
  manage_master_user_password = true

  # Encrypt the cluster storage, backups and snapshots at rest
  storage_encrypted = true

  # Backup and snapshot configuration
  backup_retention_period   = var.db_backup_retention_days
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection # Take a final snapshot where deletion protection is on
  final_snapshot_identifier = var.deletion_protection ? "${local.prefix}-aurora-final-snapshot" : null

  # Ship the error and slow query logs to CloudWatch Logs (retention: see monitoring.tf)
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.allow_aurora_access.id]

  tags = {
    Name = "${local.prefix}-aurora-db"
  }

  depends_on = [aws_cloudwatch_log_group.aurora]
}

# Aurora cluster instances
# Instances are spread over the two AZs (first one is the writer)
resource "aws_rds_cluster_instance" "clusterinstance" {
  count               = var.db_instance_count
  identifier          = "${local.prefix}-aurora-${count.index}"
  cluster_identifier  = aws_rds_cluster.auroracluster.id
  instance_class      = var.db_instance_class
  engine              = "aurora-mysql"
  availability_zone   = var.azs[count.index % length(var.azs)]
  publicly_accessible = var.db_publicly_accessible

  monitoring_interval = 0 # Basic CloudWatch metrics; no Enhanced Monitoring role needed

  tags = {
    Name = "${local.prefix}-aurora-instance${count.index + 1}"
  }
}

# Connection instructions (commented for reference)
# To connect to the database from EC2:
# 1. Install MariaDB client: sudo yum install mariadb
# 2. Read the password from the Secrets Manager secret (db_master_secret_arn output)
# 3. Connect: mysql -h <endpoint> -P 3306 -u admin -p
