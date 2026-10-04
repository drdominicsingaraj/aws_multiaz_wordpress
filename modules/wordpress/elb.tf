# Application Load Balancer Configuration
# Creates an ALB with target group and listener for distributing traffic to EC2 instances

# Target group for load balancer
# Defines the targets (EC2 instances) that the load balancer will route traffic to
resource "aws_lb_target_group" "target-group" {
  name        = "${local.prefix}-tg"
  port        = 80         # Port that targets receive traffic on
  protocol    = "HTTP"     # Protocol for routing requests
  target_type = "instance" # Target type (instance, IP, or lambda)
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.prefix}-target-group"
  }

  # Health check configuration
  # ALB uses these settings to determine if targets are healthy
  health_check {
    enabled             = true
    interval            = 10             # Health check interval in seconds
    path                = "/"            # Health check path
    port                = "traffic-port" # Use the same port as target
    protocol            = "HTTP"
    matcher             = "200-399" # A fresh WordPress answers 302 (installer redirect)
    timeout             = 5         # Health check timeout
    healthy_threshold   = 2         # Consecutive successful checks to mark healthy
    unhealthy_threshold = 2         # Consecutive failed checks to mark unhealthy
  }
}

# Application Load Balancer
# Distributes incoming traffic across multiple EC2 instances for high availability
resource "aws_lb" "application-lb" {
  name               = "${local.prefix}-alb"
  internal           = false                                            # Internet-facing ALB
  load_balancer_type = "application"                                    # Application Load Balancer
  subnets            = [aws_subnet.public-1.id, aws_subnet.public-2.id] # Deploy across public subnets
  security_groups    = [aws_security_group.sg_alb.id]                   # ALB-only security group
  ip_address_type    = "ipv4"                                           # IPv4 addressing

  enable_deletion_protection = var.deletion_protection
  drop_invalid_header_fields = true # Drop malformed HTTP headers (request smuggling hardening)

  # Access logs go to the S3 log bucket (the bucket policy must exist first)
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = local.alb_log_prefix
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]

  tags = {
    Name = "${local.prefix}-application-lb"
  }
}

# Load balancer listener
# Defines how the ALB listens for requests and routes them to targets.
#   - with CloudFront: only requests carrying the origin secret header are served (rule below),
#     everything else (anyone who found the ALB address) gets a 403
#   - with certificate_arn (no CloudFront): HTTP only redirects to HTTPS
resource "aws_lb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.application-lb.arn
  port              = "80"   # Listen on port 80 (HTTP)
  protocol          = "HTTP" # HTTP protocol

  dynamic "default_action" {
    for_each = local.cloudfront_enabled ? [1] : []
    content {
      type = "fixed-response"

      fixed_response {
        content_type = "text/plain"
        message_body = "Forbidden"
        status_code  = "403"
      }
    }
  }

  dynamic "default_action" {
    for_each = !local.cloudfront_enabled && var.certificate_arn == "" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.target-group.arn
    }
  }

  dynamic "default_action" {
    for_each = !local.cloudfront_enabled && var.certificate_arn != "" ? [1] : []
    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

# Requests from CloudFront carry X-Origin-Verify: forward only those to WordPress
resource "aws_lb_listener_rule" "from_cloudfront" {
  count = local.cloudfront_enabled ? 1 : 0

  listener_arn = aws_lb_listener.alb-listener.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target-group.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [random_password.origin_secret[0].result]
    }
  }
}

# HTTPS listener (only when an ACM certificate is provided and CloudFront is not used;
# with CloudFront the ALB security group does not open 443)
resource "aws_lb_listener" "https" {
  count = var.certificate_arn == "" || local.cloudfront_enabled ? 0 : 1

  load_balancer_arn = aws_lb.application-lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target-group.arn
  }
}

# Target group attachment
# Attaches EC2 instances to the target group so they can receive traffic
resource "aws_lb_target_group_attachment" "ec2_attach" {
  count            = length(aws_instance.instance) # Attach all instances
  target_group_arn = aws_lb_target_group.target-group.arn
  target_id        = aws_instance.instance[count.index].id # Instance ID to attach
}