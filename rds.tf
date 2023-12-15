# Not yet finished

#creating DB Subnet Group

resource "aws_db_subnet_group" "db_subnet" {
  name = "rdssubnetgroup"
  subnet_ids = [aws_subnet.private-1.id,aws_subnet.private-2.id]

  tags = {
    Name = "deham9"
  }
}

resource "aws_rds_cluster" "auroracluster" {
  cluster_identifier        = "auroracluster"
  # availability_zones        = ["us-east-1a", "us-east-1b"]

  engine                    = "aurora-mysql"
  engine_version            = "5.7.mysql_aurora.2.11.1"
  
  lifecycle {
    ignore_changes        = [engine_version]
  }

  database_name             = "auroradb"
  master_username           = "admin"
  master_password           = "wWkTAeM3n3ZQUlOBQzh0"

  skip_final_snapshot       = true
  final_snapshot_identifier = "aurora-final-snapshot"

  db_subnet_group_name = aws_db_subnet_group.db_subnet.name

  vpc_security_group_ids = [aws_security_group.allow_aurora_access.id]
  

  tags = {
    Name = "auroracluster-db"
  }
}

# Be sure to use this when connecting to your DB from EC2
# sudo yum install mariadb
# use the writers instance endpoint
# mysql -h <endpoint> -P 3306 -u <mymasteruser> -p

resource "aws_rds_cluster_instance" "clusterinstance" {
  count              = 2
  identifier         = "clusterinstance-${count.index}"
  cluster_identifier = aws_rds_cluster.auroracluster.id
  instance_class     = "db.t3.small"
  engine             = "aurora-mysql"
  availability_zone  = "us-east-1${count.index == 0 ? "a" : "b"}"
  publicly_accessible = true

  tags = {
    Name = "auroracluster-db-instance${count.index + 1}"
  }
}

