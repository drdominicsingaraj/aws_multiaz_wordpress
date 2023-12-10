# Create an S3 bucket
resource "aws_s3_bucket" "deham9alblogs" {
  bucket = "deham9alblogs"

  tags = {
    Name        = "deham9"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.deham9alblogs.id
  versioning_configuration {
    status = "Enabled"
  }
}