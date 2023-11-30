# Create a Security Group for the VPC
resource "aws_security_group" "sg_vpc" {
  name        = "sg_vpc"
  description = "allow shh"
  vpc_id      = aws_vpc.dev_vpc.id

  # Add inbound rules
  # Add a rule for HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.CIDR_BLOCK]
  }

  # Add a rule for HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.CIDR_BLOCK]
  }

  # Add a rule for SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.CIDR_BLOCK]
  }

  # Add an outbound rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.CIDR_BLOCK]
  }
  tags = {
    Name = "sg-vpc"
  }
}