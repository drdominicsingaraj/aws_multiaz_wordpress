# Create a VPC to launch our instances into
resource "aws_vpc" "dev_vpc" {
  cidr_block = "10.0.0.0/16"

  tags       =  {
    name     = "deham9"
  }       
}

resource "aws_subnet" "public-1" {
  vpc_id     = aws_vpc.dev_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "deham9"
  }
}

resource "aws_subnet" "private-1" {
  vpc_id     = aws_vpc.dev_vpc.id 
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "deham9" 
  }
}

resource "aws_subnet" "public-2" {
  vpc_id     = aws_vpc.dev_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "deham9"
  }
}

resource "aws_subnet" "private-2" {
  vpc_id     = aws_vpc.dev_vpc.id 
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "deham9" 
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dev_vpc.id
  tags = {
    Name = "deham9"
  }
}


resource "aws_route_table" "RB_Public_RouteTable" {
  vpc_id = aws_vpc.dev_vpc.id

  route {
    cidr_block = var.CIDR_BLOCK
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "deham9"
  }
}
/*
resource "aws_route_table" "RB_Private_RouteTable" {
  vpc_id = aws_vpc.dev_vpc.id

  route {
    cidr_block = var.CIDR_BLOCK
    gateway_id = "local"
  }
  tags = {
    Name = "deham9"
  }
}*/
resource "aws_route_table_association" "Public_Subnet1_Asso" {
  route_table_id = aws_route_table.RB_Public_RouteTable.id
  subnet_id      = aws_subnet.public-1.id
  depends_on     = [aws_route_table.RB_Public_RouteTable, aws_subnet.public-1]
}
/*
resource "aws_route_table_association" "Private_Subnet1_Asso" {
  route_table_id = aws_route_table.RB_Private_RouteTable.id
  subnet_id      = aws_subnet.private-1.id
  depends_on     = [aws_route_table.RB_Private_RouteTable, aws_subnet.private-1]
}
*/
resource "aws_route_table_association" "Public_Subnet2_Asso" {
  route_table_id = aws_route_table.RB_Public_RouteTable.id
  subnet_id      = aws_subnet.public-2.id
  depends_on     = [aws_route_table.RB_Public_RouteTable, aws_subnet.public-2]
}
/*
resource "aws_route_table_association" "Private_Subnet2_Asso" {
  route_table_id = aws_route_table.RB_Private_RouteTable.id
  subnet_id      = aws_subnet.private-2.id
  depends_on     = [aws_route_table.RB_Private_RouteTable, aws_subnet.private-2]
}*/