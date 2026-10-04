# Security Groups Configuration
# Defines network access rules for the tiers of the infrastructure.
# Names are prefixed with the environment so each environment gets its own groups.
#
#   Internet -> sg_alb (80/443) -> sg_vpc (web tier, 80 from the ALB only) -> Aurora (3306) / EFS (2049)

# Load balancer: the only component that accepts web traffic (from the internet, or from CloudFront only)
resource "aws_security_group" "sg_alb" {
  name        = "${local.prefix}-sg-alb"
  description = "Application load balancer - HTTP and HTTPS from CIDR_BLOCK"
  vpc_id      = aws_vpc.main.id

  # Without CloudFront the ALB is the internet-facing entry point (HTTP, plus HTTPS with a certificate)
  dynamic "ingress" {
    for_each = local.cloudfront_enabled ? [] : [80, 443]
    content {
      description = ingress.value == 80 ? "HTTP traffic" : "HTTPS traffic"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.CIDR_BLOCK]
    }
  }

  # With CloudFront only CloudFront can reach the ALB (origin-facing prefix list, HTTP)
  dynamic "ingress" {
    for_each = local.cloudfront_enabled ? [1] : []
    content {
      description     = "HTTP from CloudFront"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront[0].id]
    }
  }

  # The ALB only talks to the web tier inside the VPC. A CIDR is used rather than a
  # reference to sg_vpc, because sg_vpc already references this group (circular dependency).
  egress {
    description = "HTTP to the web tier"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${local.prefix}-sg-alb"
  }
}

# Web tier security group (ASG and standalone instances)
# HTTP only from the load balancer; nothing else can reach the instances directly.
resource "aws_security_group" "sg_vpc" {
  name        = "${local.prefix}-sg-vpc"
  description = "Web tier - HTTP from the load balancer only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from the load balancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_alb.id]
  }

  # Outbound is limited to what the instances need
  egress {
    description = "HTTPS (WordPress download, package repos, Secrets Manager, SSM)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "NFS to the WordPress EFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "MySQL to Aurora"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  dynamic "egress" {
    for_each = var.enable_object_cache ? [1] : []
    content {
      description = "Redis object cache"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  tags = {
    Name = "${local.prefix}-sg-vpc"
  }
}

# Optional SSH access to the instances, attached next to sg_vpc.
# ssh_cidr_blocks is empty by default (no SSH at all): use SSM Session Manager instead.
# It has no egress rule on purpose, so it never widens what sg_vpc allows outbound.
resource "aws_security_group" "allow_ssh" {
  name        = "${local.prefix}-allow-ssh"
  description = "Optional SSH to the web instances (empty ssh_cidr_blocks = closed)"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = length(var.ssh_cidr_blocks) > 0 ? [1] : []
    content {
      description = "SSH access"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_cidr_blocks
    }
  }

  tags = {
    Name = "${local.prefix}-allow-ssh"
  }
}

# Security group for Aurora database cluster
# MySQL (3306) is reachable from the web tier only. db_publicly_accessible (default false)
# additionally opens 3306 to CIDR_BLOCK; do not enable it outside a throwaway environment.
resource "aws_security_group" "allow_aurora_access" {
  name        = "${local.prefix}-allow-aurora-access"
  description = "Allow access to Aurora MySQL database"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from the web tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_vpc.id]
  }

  dynamic "ingress" {
    for_each = var.db_publicly_accessible ? [1] : []
    content {
      description = "MySQL from CIDR_BLOCK (public access enabled)"
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = [var.CIDR_BLOCK]
    }
  }

  tags = {
    Name = "${local.prefix}-aurora-allow-mysql"
  }
}
