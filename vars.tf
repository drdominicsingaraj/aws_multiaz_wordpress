# Variable definitions for the WordPress infrastructure
# These variables allow customization of the deployment

# CIDR block for the first public subnet
# Currently unused in the configuration - consider removing
variable "cidr_block_RB_Public_Subnet1" {
  description = "CIDR block for public subnet 1"
  type        = string
  default     = "10.0.1.0/24" # 256 IP addresses
}

# CIDR block for public internet access
# Used in route tables to define routes to internet (0.0.0.0/0 = all traffic)
variable "CIDR_BLOCK" {
  description = "CIDR block for public internet access"
  type        = string
  default     = "0.0.0.0/0" # All traffic
}

# AWS Region for resource deployment
# Defines which AWS region to deploy resources in
variable "AWS_REGION" {
  description = "AWS Region for resource deployment"
  type        = string
  default     = "us-east-1" # US East (N. Virginia)
}

# Region-specific AMI IDs for EC2 instances
# Maps AWS regions to their corresponding Amazon Linux 2023 AMI IDs
variable "AMIs" {
  description = "Region-specific AMI IDs for EC2 instances"
  type        = map(string)
  default = {
    us-east-1    = "ami-0230bd60aa48260c6" # Amazon Linux 2023 in us-east-1
    eu-central-1 = "ami-0ec8c354f85e48227" # Amazon Linux 2023 in eu-central-1
  }
}