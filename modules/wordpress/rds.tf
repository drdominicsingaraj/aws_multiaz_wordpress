# RDS Aurora MySQL Database Configuration
# Creates a highly available Aurora MySQL cluster with instances across multiple AZs

# Database subnet group for Aurora cluster
# Groups private subnets across multiple AZs for database deployment
resource "aws_db_subnet_group" "db_subnet" {
  name       = "rdssubnetgroup"
  subnet_ids = [aws_subnet.private-1.id, aws_subnet.private-2.id] # Private subnets only

  tags = {
    Name = "deham9-db-subnet-group"
  }
}

# Aurora MySQL cluster
# Main database cluster that manages the database instances
resource "aws_rds_cluster" "auroracluster" {
  cluster_identifier = "auroracluster"

  # Database engine configuration
  engine         = "aurora-mysql"
  engine_version = "5.7.mysql_aurora.2.11.1" # Specific version for consistency

  # Lifecycle rule to prevent accidental engine version changes
  lifecycle {
    ignore_changes = [engine_version]
  }

  # Database configuration
  database_name   = "auroradb"
  master_username = "admin"
  master_password = "wWkTAeM3n3ZQUlOBQzh0" # WARNING: Hard-coded password - use AWS Secrets Manager

  # Backup and snapshot configuration
  skip_final_snapshot       = true                    # Skip final snapshot on deletion
  final_snapshot_identifier = "aurora-final-snapshot" # Name for final snapshot if created

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.allow_aurora_access.id]

  tags = {
    Name = "auroracluster-db"
  }
}

# Aurora cluster instances
# Individual database instances within the cluster for high availability
resource "aws_rds_cluster_instance" "clusterinstance" {
  count               = 2                                # Two instances for HA
  identifier          = "clusterinstance-${count.index}" # Unique names: clusterinstance-0, clusterinstance-1
  cluster_identifier  = aws_rds_cluster.auroracluster.id
  instance_class      = "db.t3.small" # Instance size
  engine              = "aurora-mysql"
  availability_zone   = "us-east-1${count.index == 0 ? "a" : "b"}" # Distribute across AZs
  publicly_accessible = true                                       # WARNING: Database should not be publicly accessible

  tags = {
    Name = "auroracluster-db-instance${count.index + 1}"
  }
}

# Connection instructions (commented for reference)
# To connect to the database from EC2:
# 1. Install MariaDB client: sudo yum install mariadb
# 2. Use the writer instance endpoint
# 3. Connect: mysql -h <endpoint> -P 3306 -u admin -p

