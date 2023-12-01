# Create an S3 bucket
resource "aws_s3_bucket" "deham9alblogs" {
  bucket = "deham9alblogs"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name        = "deham9"
    Environment = "Dev"
  }
}
