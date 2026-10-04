# Audit and security logging
#
#   - one audit log bucket per environment, used by CloudFront access logs, VPC Flow Logs
#     and (optionally) CloudTrail
#   - VPC Flow Logs (enable_flow_logs): accepted and rejected traffic of the VPC
#   - CloudTrail (enable_cloudtrail) and GuardDuty (enable_guardduty): ACCOUNT-level services.
#     Enable them in one environment only (prod); GuardDuty allows a single detector per
#     account and region, so a second environment enabling it would fail.

resource "aws_s3_bucket" "audit" {
  bucket        = "${local.prefix}-audit-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy_log_bucket

  tags = {
    Name    = "${local.prefix}-audit-logs"
    Purpose = "CloudFront, VPC Flow Logs and CloudTrail"
  }
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket = aws_s3_bucket.audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront standard logging delivers with a bucket ACL, so ACLs must stay enabled
resource "aws_s3_bucket_ownership_controls" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "audit" {
  bucket = aws_s3_bucket.audit.id
  acl    = "private"

  depends_on = [aws_s3_bucket_ownership_controls.audit, aws_s3_bucket_public_access_block.audit]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    id     = "expire-audit-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_retention_days
    }
  }
}

data "aws_iam_policy_document" "audit" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.audit.arn, "${aws_s3_bucket.audit.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # VPC Flow Logs delivery
  dynamic "statement" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      sid       = "FlowLogsWrite"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.audit.arn}/vpc-flow/*"]

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      sid       = "FlowLogsAclCheck"
      effect    = "Allow"
      actions   = ["s3:GetBucketAcl"]
      resources = [aws_s3_bucket.audit.arn]

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }
    }
  }

  # CloudTrail delivery
  dynamic "statement" {
    for_each = var.enable_cloudtrail ? [1] : []
    content {
      sid       = "CloudTrailAclCheck"
      effect    = "Allow"
      actions   = ["s3:GetBucketAcl"]
      resources = [aws_s3_bucket.audit.arn]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_cloudtrail ? [1] : []
    content {
      sid       = "CloudTrailWrite"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.audit.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = data.aws_iam_policy_document.audit.json

  depends_on = [aws_s3_bucket_public_access_block.audit]
}

# ---------- VPC Flow Logs ----------

resource "aws_flow_log" "vpc" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = "${aws_s3_bucket.audit.arn}/vpc-flow/"

  tags = {
    Name = "${local.prefix}-vpc-flow-logs"
  }

  depends_on = [aws_s3_bucket_policy.audit]
}

# ---------- CloudTrail (account level) ----------

resource "aws_cloudtrail" "main" {
  count = var.enable_cloudtrail ? 1 : 0

  name                          = "${local.prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.audit.id
  s3_key_prefix                 = "cloudtrail"
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  tags = {
    Name = "${local.prefix}-trail"
  }

  depends_on = [aws_s3_bucket_policy.audit]
}

# ---------- GuardDuty (account level, one detector per account and region) ----------

resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable = true

  tags = {
    Name = "${local.prefix}-guardduty"
  }
}
