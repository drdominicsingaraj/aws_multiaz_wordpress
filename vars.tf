variable "cidr_block_RB_Public_Subnet1" {
  default = "10.0.1.0/24"    #Public Subnet-1
}

variable "CIDR_BLOCK" {
  default = "0.0.0.0/0"    #Public CIDR
}

variable "AWS_REGION" { 
  default = "us-east-1"
  description = "AWS Region"  
}

variable "AMIs" {
  type = map(string)
  description = "Region specific AMI"
  default = {
    us-east-1 = "ami-0230bd60aa48260c6"
    eu-central-1 = "ami-0ec8c354f85e48227"
  }
}