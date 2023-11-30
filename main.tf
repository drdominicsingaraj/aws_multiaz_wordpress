# Create a VPC to launch our instances into
resource "aws_vpc" "dev_vpc" {
  cidr_block = "10.0.0.0/16"

  tags       =  {
    name     = "dev_vpc"
  }       
}