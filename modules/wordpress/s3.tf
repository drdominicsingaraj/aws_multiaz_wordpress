# S3 Bucket Configuration
# Creates an S3 bucket for storing application load balancer logs

# S3 bucket for ALB access logs
# Stores access logs from the Application Load Balancer for monitoring and analysis
resource "aws_s3_bucket" "deham9alblogs" {
  bucket = "deham9alblogs" # Must be globally unique across all AWS accounts

  tags = {
    Name        = "deham9-alb-logs"
    Environment = "Dev"
    Purpose     = "ALB Access Logs"
  }
}

# S3 bucket versioning configuration
# Enables versioning on the S3 bucket to maintain object history
resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.deham9alblogs.id

  versioning_configuration {
    status = "Enabled" # Keep multiple versions of objects
  }
}