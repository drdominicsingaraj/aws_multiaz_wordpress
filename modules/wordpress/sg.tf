# Security Groups Configuration
# Defines network access rules for different components of the infrastructure

# Main security group for VPC resources
# Controls access to EC2 instances and load balancer
resource "aws_security_group" "sg_vpc" {
  name        = "sg_vpc"
  description = "Security group for VPC resources - allows HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.dev_vpc.id

  # Inbound rule for HTTP traffic (port 80)
  # Allows web traffic from anywhere on the internet
  ingress {
    description = "HTTP traffic from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.CIDR_BLOCK] # 0.0.0.0/0 - all internet traffic
  }

  # Inbound rule for HTTPS traffic (port 443)
  # Allows secure web traffic from anywhere on the internet
  ingress {
    description = "HTTPS traffic from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.CIDR_BLOCK] # 0.0.0.0/0 - all internet traffic
  }

  # Inbound rule for SSH access (port 22)
  # WARNING: This allows SSH from anywhere - consider restricting to specific IPs
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.CIDR_BLOCK] # TODO: Restrict to specific IP ranges for security
  }

  # Outbound rule - allows all outbound traffic
  # Enables instances to access internet for updates, downloads, etc.
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"             # -1 means all protocols
    cidr_blocks = [var.CIDR_BLOCK] # 0.0.0.0/0 - all destinations
  }

  tags = {
    Name = "sg-vpc-main"
  }
}

# Security group for SSH access to EC2 instances
# Separate security group for SSH access management
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH traffic to EC2 instances"
  vpc_id      = aws_vpc.dev_vpc.id

  # Inbound SSH access from anywhere
  # WARNING: Consider restricting to specific IP ranges for better security
  ingress {
    description = "SSH access from internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # TODO: Restrict to admin IP ranges
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

# Security group for EC2 to Aurora database communication
# Controls outbound access from EC2 instances to RDS Aurora cluster
resource "aws_security_group" "allow_ec2_aurora" {
  name        = "allow_ec2_aurora"
  description = "Allow EC2 to Aurora database traffic"
  vpc_id      = aws_vpc.dev_vpc.id

  # Outbound MySQL/Aurora access
  # Allows EC2 instances to connect to Aurora database on port 3306
  egress {
    description = "MySQL/Aurora database access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Could be restricted to VPC CIDR for better security
  }

  tags = {
    Name = "allow_ec2_aurora"
  }
}

# Security group for Aurora database cluster
# Controls inbound access to the RDS Aurora MySQL cluster
resource "aws_security_group" "allow_aurora_access" {
  name        = "allow_aurora_access"
  description = "Allow access to Aurora MySQL database"
  vpc_id      = aws_vpc.dev_vpc.id

  # Inbound rule allowing all traffic from anywhere
  # WARNING: This is overly permissive for a database
  # TODO: Restrict to only MySQL port 3306 from EC2 security groups
  ingress {
    description = "All traffic (overly permissive - should be restricted)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # Better approach would be:
    # from_port = 3306
    # to_port = 3306
    # protocol = "tcp"
    # security_groups = [aws_security_group.sg_vpc.id]
  }

  tags = {
    Name = "aurora-stack-allow-aurora-MySQL"
  }
}