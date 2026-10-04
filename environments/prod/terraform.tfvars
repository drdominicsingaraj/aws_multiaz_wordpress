# prod environment values (auto-loaded by terraform). Contains no secrets.
project     = "deham9"
environment = "prod"
owner       = "ds"
aws_region  = "us-east-1"
azs         = ["us-east-1a", "us-east-1b"]
vpc_cidr    = "10.2.0.0/16"

# Network
enable_nat_gateway = false # no NAT gateway: private subnets (Aurora) have no outbound internet

# Access
CIDR_BLOCK      = "0.0.0.0/0"
ssh_cidr_blocks = [] # SSH closed; connect with SSM Session Manager (add a CIDR here to open port 22)
key_name        = "deham9-iam"

# Compute and scaling
# AMI: empty = latest Amazon Linux 2023 for the architecture (set ami_id to pin one)
cpu_architecture          = "arm64" # Graviton: cheaper and more energy efficient, needs a t4g instance type
instance_type             = "t4g.small"
standalone_instance_count = 0
asg_min_size              = 5
asg_max_size              = 6
asg_desired_capacity      = 5

# Database
db_instance_class        = "db.t3.medium"
db_instance_count        = 2
db_backup_retention_days = 14
db_publicly_accessible   = false

# Protection
deletion_protection      = true
force_destroy_log_bucket = false

# Monitoring and logging
log_retention_days = 90
alarm_email        = "" # set an address to receive CloudWatch alarm emails

# HTTPS: set an ACM certificate ARN to serve 443 and redirect HTTP to HTTPS
# certificate_arn = "arn:aws:acm:us-east-1:<account>:certificate/<id>"

# Edge: CloudFront gives HTTPS without a domain and caches static files; WAF filters requests (needs us-east-1)
enable_cloudfront = true
enable_waf        = true

# Cost: scale the ASG down to 1 instance from 19:00 UTC and on weekends, back up at 06:00 UTC Mon-Fri
enable_off_hours_schedule = false
off_hours_capacity        = 1

# Audit and security logging (CloudTrail and GuardDuty are ACCOUNT level: enabled in prod only)
enable_flow_logs  = true
enable_cloudtrail = true
enable_guardduty  = true

# Performance: ElastiCache Redis object cache for WordPress
enable_object_cache = true
cache_node_type     = "cache.t4g.micro"
cache_node_count    = 2

# Web tier in private subnets: needs enable_nat_gateway = true, which is off, so it stays false
web_tier_in_private_subnets = false
