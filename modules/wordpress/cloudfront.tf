# CloudFront and WAF in front of the load balancer (enable_cloudfront / enable_waf)
#
# CloudFront gives the site HTTPS without owning a domain (the *.cloudfront.net certificate),
# caches WordPress static files at the edge, and lets the ALB accept traffic from CloudFront
# only (CloudFront origin-facing prefix list in sg_alb). WAF filters requests at the edge.
# Viewers use HTTPS (HTTP is redirected); CloudFront reaches the ALB over HTTP inside AWS.
#
# WAF for CloudFront must be created in us-east-1, so that is where the environments run.

locals {
  cloudfront_enabled = var.enable_cloudfront
  waf_enabled        = var.enable_cloudfront && var.enable_waf
}

# Origin-facing CloudFront addresses, kept current by AWS
data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = local.cloudfront_enabled ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_cloudfront_cache_policy" "disabled" {
  count = local.cloudfront_enabled ? 1 : 0
  name  = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "optimized" {
  count = local.cloudfront_enabled ? 1 : 0
  name  = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  count = local.cloudfront_enabled ? 1 : 0
  name  = "Managed-AllViewer"
}

# Shared secret between CloudFront and the ALB: the ALB serves only requests that carry it
resource "random_password" "origin_secret" {
  count = local.cloudfront_enabled ? 1 : 0

  length  = 40
  special = false
}

resource "aws_cloudfront_distribution" "main" {
  count = local.cloudfront_enabled ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  comment         = "${local.prefix} WordPress"
  price_class     = var.cloudfront_price_class
  aliases         = var.cloudfront_aliases
  web_acl_id      = local.waf_enabled ? aws_wafv2_web_acl.main[0].arn : null

  origin {
    domain_name = aws_lb.application-lb.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.origin_secret[0].result
    }
  }

  # Access logs in the audit bucket (cloudfront/ prefix)
  logging_config {
    bucket          = aws_s3_bucket.audit.bucket_domain_name
    prefix          = "cloudfront/"
    include_cookies = false
  }

  # Pages, admin and logins are dynamic: never cached, all cookies/headers/query strings reach WordPress
  default_cache_behavior {
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled[0].id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer[0].id
  }

  # Static files (themes, plugins, uploads, core assets) are cached at the edge
  dynamic "ordered_cache_behavior" {
    for_each = toset(["/wp-content/*", "/wp-includes/*"])
    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = "alb"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true
      cache_policy_id        = data.aws_cloudfront_cache_policy.optimized[0].id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Default *.cloudfront.net certificate unless a custom domain certificate (us-east-1) is given
  viewer_certificate {
    cloudfront_default_certificate = var.cloudfront_certificate_arn == ""
    acm_certificate_arn            = var.cloudfront_certificate_arn == "" ? null : var.cloudfront_certificate_arn
    ssl_support_method             = var.cloudfront_certificate_arn == "" ? null : "sni-only"
    minimum_protocol_version       = var.cloudfront_certificate_arn == "" ? null : "TLSv1.2_2021"
  }

  tags = {
    Name = "${local.prefix}-cloudfront"
  }

  depends_on = [aws_s3_bucket_acl.audit]
}

# ---------- WAF ----------

resource "aws_wafv2_web_acl" "main" {
  count = local.waf_enabled ? 1 : 0

  name        = "${local.prefix}-waf"
  description = "Managed rule groups and a rate limit in front of ${local.prefix}"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  lifecycle {
    precondition {
      condition     = data.aws_region.current.name == "us-east-1"
      error_message = "WAF for CloudFront must be created in us-east-1"
    }
  }

  dynamic "rule" {
    for_each = {
      common     = { priority = 1, name = "AWSManagedRulesCommonRuleSet" }
      bad_inputs = { priority = 2, name = "AWSManagedRulesKnownBadInputsRuleSet" }
      sqli       = { priority = 3, name = "AWSManagedRulesSQLiRuleSet" }
    }
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.prefix}-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  # Per-IP rate limit (requests per 5 minutes)
  rule {
    name     = "rate-limit"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${local.prefix}-waf"
  }
}

# WAF request log in CloudWatch Logs (the group name must start with aws-waf-logs-)
resource "aws_cloudwatch_log_group" "waf" {
  count = local.waf_enabled ? 1 : 0

  name              = "aws-waf-logs-${local.prefix}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.prefix}-waf-logs"
  }
}

data "aws_iam_policy_document" "waf_logs" {
  count = local.waf_enabled ? 1 : 0

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.waf[0].arn}:*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  count = local.waf_enabled ? 1 : 0

  policy_name     = "${local.prefix}-waf-logs"
  policy_document = data.aws_iam_policy_document.waf_logs[0].json
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = local.waf_enabled ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.main[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  # Do not log credentials
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.waf]
}
