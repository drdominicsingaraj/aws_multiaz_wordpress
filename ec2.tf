# Local values for consistent naming and tagging
# These values are used throughout the configuration for consistency
locals {
  name  = "awsrestartproject" # Base name for EC2 instances
  owner = "ds"                # Owner identifier for resource tracking
}

# Data source to fetch the latest Amazon Linux 2023 AMI
# This ensures we always use the most recent AMI for security updates
data "aws_ami" "latest_linux_ami" {
  most_recent = true
  owners      = ["amazon"] # Only consider AMIs owned by Amazon

  # Filter for Amazon Linux 2023 AMIs for x86_64 architecture
  filter {
    name   = "name"
    values = ["al2023-ami-2023*x86_64"]
  }
}

# EC2 instance for WordPress application
# This instance will host the WordPress application and connect to RDS
resource "aws_instance" "instance" {
  # Using predefined AMI from variables instead of data source for consistency
  ami                         = var.AMIs[var.AWS_REGION]
  instance_type               = "t3.micro"                     # Free tier eligible
  availability_zone           = "us-east-1a"                   # Same AZ as public subnet
  associate_public_ip_address = true                           # Assign public IP
  key_name                    = "deham9-iam"                   # SSH key pair name
  vpc_security_group_ids      = [aws_security_group.sg_vpc.id] # Security group
  subnet_id                   = aws_subnet.public-1.id         # Deploy in public subnet
  iam_instance_profile        = "deham10_ec2"                  # IAM role for S3 access
  count                       = 1                              # Single instance

  tags = {
    Name = local.name
    Type = "WordPress-Server"
  }

  # User data script for initial server setup
  user_data = base64encode(data.template_file.ec2userdatatemplate.rendered)

  # Local provisioner to log instance metadata
  provisioner "local-exec" {
    command = "echo Instance Type = ${self.instance_type}, Instance ID = ${self.id}, Public IP = ${self.public_ip}, AMI ID = ${self.ami} >> metadata"
  }
}


# Template file data source for user data script
# Reads the user data script from external template file
data "template_file" "ec2userdatatemplate" {
  template = file("userdata.tpl") # Removed unnecessary string interpolation
}

# Output the rendered user data template for debugging
output "ec2rendered" {
  description = "Rendered user data script for EC2 instance"
  value       = data.template_file.ec2userdatatemplate.rendered
}

# Output the public IP address of the EC2 instance
output "public_ip" {
  description = "Public IP address of the WordPress server"
  value       = aws_instance.instance[0].public_ip
}