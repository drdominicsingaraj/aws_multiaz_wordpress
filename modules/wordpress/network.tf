# Create a VPC to launch our instances into
# This VPC will contain all our AWS resources and provide network isolation
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr # /16 per environment, see terraform.tfvars
  enable_dns_hostnames = true         # Enable DNS hostnames for instances
  enable_dns_support   = true         # Enable DNS resolution

  tags = {
    Name = "${local.prefix}-vpc"
  }
}

# Public subnet in first availability zone
# Resources in this subnet will have direct internet access via Internet Gateway
resource "aws_subnet" "public-1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1) # 256 IP addresses
  availability_zone       = var.azs[0]                     # First AZ for high availability
  map_public_ip_on_launch = true                           # Auto-assign public IPs

  tags = {
    Name = "${local.prefix}-public-subnet-1"
    Type = "Public"
  }
}

# Private subnet in first availability zone
# Resources here will access internet via NAT Gateway for security
resource "aws_subnet" "private-1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2) # 256 IP addresses
  availability_zone = var.azs[0]                     # Same AZ as public-1

  tags = {
    Name = "${local.prefix}-private-subnet-1"
    Type = "Private"
  }
}

# Public subnet in second availability zone
# Provides redundancy and high availability for public resources
resource "aws_subnet" "public-2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 3) # 256 IP addresses
  availability_zone       = var.azs[1]                     # Second AZ for HA
  map_public_ip_on_launch = true                           # Auto-assign public IPs

  tags = {
    Name = "${local.prefix}-public-subnet-2"
    Type = "Public"
  }
}

# Private subnet in second availability zone
# Provides redundancy for private resources like RDS instances
resource "aws_subnet" "private-2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 4) # 256 IP addresses
  availability_zone = var.azs[1]                     # Second AZ for HA

  tags = {
    Name = "${local.prefix}-private-subnet-2"
    Type = "Private"
  }
}

# Internet Gateway for public internet access
# Allows resources in public subnets to communicate with the internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.prefix}-igw"
  }
}

# Allocate Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
}

# NAT Gateway for private subnet internet access
# Allows resources in private subnets to access internet while remaining private
resource "aws_nat_gateway" "nat" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat_eip[0].id
  subnet_id     = aws_subnet.public-1.id # Must be in a public subnet

  # NAT Gateway depends on Internet Gateway
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "${local.prefix}-nat-gateway"
  }
}

# Route table for public subnets
# Routes traffic to Internet Gateway for public internet access
resource "aws_route_table" "RB_Public_RouteTable" {
  vpc_id = aws_vpc.main.id

  # Route all traffic (0.0.0.0/0) to Internet Gateway
  route {
    cidr_block = var.CIDR_BLOCK # Should be "0.0.0.0/0" for all traffic
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.prefix}-public-route-table"
  }
}

# Route table for private subnets
# Routes traffic to NAT Gateway for secure internet access
resource "aws_route_table" "RB_Private_RouteTable" {
  vpc_id = aws_vpc.main.id

  # Default route via the NAT Gateway; omitted when enable_nat_gateway = false
  # (private subnets then have no internet access, which Aurora does not need)
  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat[0].id
    }
  }

  tags = {
    Name = "${local.prefix}-private-route-table"
  }
}
# Associate public subnet 1 with public route table
# This enables internet access for resources in public-1 subnet
resource "aws_route_table_association" "Public_Subnet1_Asso" {
  route_table_id = aws_route_table.RB_Public_RouteTable.id
  subnet_id      = aws_subnet.public-1.id
  # Note: depends_on is not needed here as Terraform handles implicit dependencies
}

# Associate private subnet 1 with private route table
# This enables NAT Gateway access for resources in private-1 subnet
resource "aws_route_table_association" "Private_Subnet1_Asso" {
  route_table_id = aws_route_table.RB_Private_RouteTable.id
  subnet_id      = aws_subnet.private-1.id
  # Note: depends_on is not needed here as Terraform handles implicit dependencies
}

# Associate public subnet 2 with public route table
# This enables internet access for resources in public-2 subnet
resource "aws_route_table_association" "Public_Subnet2_Asso" {
  route_table_id = aws_route_table.RB_Public_RouteTable.id
  subnet_id      = aws_subnet.public-2.id
  # Note: depends_on is not needed here as Terraform handles implicit dependencies
}

# Associate private subnet 2 with private route table
# This enables NAT Gateway access for resources in private-2 subnet
resource "aws_route_table_association" "Private_Subnet2_Asso" {
  route_table_id = aws_route_table.RB_Private_RouteTable.id
  subnet_id      = aws_subnet.private-2.id
  # Note: depends_on is not needed here as Terraform handles implicit dependencies
}