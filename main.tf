# Create a VPC to launch our instances into
# This VPC will contain all our AWS resources and provide network isolation
resource "aws_vpc" "dev_vpc" {
  cidr_block           = "10.0.0.0/16" # Provides 65,536 IP addresses
  enable_dns_hostnames = true          # Enable DNS hostnames for instances
  enable_dns_support   = true          # Enable DNS resolution

  tags = {
    Name = "deham9-vpc"
  }
}

# Public subnet in first availability zone
# Resources in this subnet will have direct internet access via Internet Gateway
resource "aws_subnet" "public-1" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.0.1.0/24" # 256 IP addresses
  availability_zone       = "us-east-1a"  # First AZ for high availability
  map_public_ip_on_launch = true          # Auto-assign public IPs

  tags = {
    Name = "deham9-public-subnet-1"
    Type = "Public"
  }
}

# Private subnet in first availability zone
# Resources here will access internet via NAT Gateway for security
resource "aws_subnet" "private-1" {
  vpc_id            = aws_vpc.dev_vpc.id
  cidr_block        = "10.0.2.0/24" # 256 IP addresses
  availability_zone = "us-east-1a"  # Same AZ as public-1

  tags = {
    Name = "deham9-private-subnet-1"
    Type = "Private"
  }
}

# Public subnet in second availability zone
# Provides redundancy and high availability for public resources
resource "aws_subnet" "public-2" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.0.3.0/24" # 256 IP addresses
  availability_zone       = "us-east-1b"  # Second AZ for HA
  map_public_ip_on_launch = true          # Auto-assign public IPs

  tags = {
    Name = "deham9-public-subnet-2"
    Type = "Public"
  }
}

# Private subnet in second availability zone
# Provides redundancy for private resources like RDS instances
resource "aws_subnet" "private-2" {
  vpc_id            = aws_vpc.dev_vpc.id
  cidr_block        = "10.0.4.0/24" # 256 IP addresses
  availability_zone = "us-east-1b"  # Second AZ for HA

  tags = {
    Name = "deham9-private-subnet-2"
    Type = "Private"
  }
}

# Internet Gateway for public internet access
# Allows resources in public subnets to communicate with the internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dev_vpc.id

  tags = {
    Name = "deham9-igw"
  }
}

# Allocate Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# NAT Gateway for private subnet internet access
# Allows resources in private subnets to access internet while remaining private
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public-1.id # Must be in a public subnet

  # NAT Gateway depends on Internet Gateway
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "deham9-nat-gateway"
  }
}

# Route table for public subnets
# Routes traffic to Internet Gateway for public internet access
resource "aws_route_table" "RB_Public_RouteTable" {
  vpc_id = aws_vpc.dev_vpc.id

  # Route all traffic (0.0.0.0/0) to Internet Gateway
  route {
    cidr_block = var.CIDR_BLOCK # Should be "0.0.0.0/0" for all traffic
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "deham9-public-route-table"
  }
}

# Route table for private subnets
# Routes traffic to NAT Gateway for secure internet access
resource "aws_route_table" "RB_Private_RouteTable" {
  vpc_id = aws_vpc.dev_vpc.id

  # Route all traffic (0.0.0.0/0) to NAT Gateway for secure internet access
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id # Correct attribute for NAT Gateway
  }

  tags = {
    Name = "deham9-private-route-table"
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