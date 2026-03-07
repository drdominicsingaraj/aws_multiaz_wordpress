# Terraform configuration block
# Specifies required providers and their versions
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Using latest stable AWS provider version
    }
  }
}

# AWS Provider configuration
# Configures the AWS provider with the target region
provider "aws" {
  region = "us-east-1" # US East (N. Virginia) region
}
