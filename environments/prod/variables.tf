# Variables for this environment; values live in terraform.tfvars.

variable "project" {
  description = "Project name used in resource names and tags"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, test or prod)"
  type        = string
}

variable "owner" {
  description = "Owner identifier for resource tracking"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (a /16, unique per environment)"
  type        = string
}

variable "azs" {
  description = "Two availability zones in aws_region"
  type        = list(string)
}

variable "CIDR_BLOCK" {
  description = "CIDR block allowed to reach HTTP/HTTPS"
  type        = string
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to the instances"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair name"
  type        = string
}

variable "standalone_instance_count" {
  description = "Number of standalone web instances outside the ASG"
  type        = number
}

variable "asg_min_size" {
  description = "Minimum ASG size"
  type        = number
}

variable "asg_max_size" {
  description = "Maximum ASG size"
  type        = number
}

variable "asg_desired_capacity" {
  description = "Desired ASG size"
  type        = number
}

variable "db_instance_class" {
  description = "Aurora instance class"
  type        = string
}

variable "db_instance_count" {
  description = "Number of Aurora instances"
  type        = number
}

variable "db_backup_retention_days" {
  description = "Days to keep Aurora automated backups"
  type        = number
}

variable "db_publicly_accessible" {
  description = "Make Aurora publicly reachable"
  type        = bool
}

variable "deletion_protection" {
  description = "Protect ALB and Aurora from deletion; take a final snapshot"
  type        = bool
}

variable "force_destroy_log_bucket" {
  description = "Allow deleting the log bucket while it contains objects"
  type        = bool
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway for the private subnets"
  type        = bool
}

variable "log_retention_days" {
  description = "Days to keep ALB access logs (S3) and Aurora logs (CloudWatch Logs)"
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Email subscribed to the CloudWatch alarm topic (empty = no subscription)"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS on the ALB (empty = HTTP only)"
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "AMI to pin. Empty = latest Amazon Linux 2023 for cpu_architecture"
  type        = string
  default     = ""
}

variable "cpu_architecture" {
  description = "x86_64 or arm64 (Graviton: use a t4g instance type)"
  type        = string
  default     = "x86_64"
}

variable "enable_cloudfront" {
  description = "Serve the site through CloudFront (HTTPS, edge caching, ALB reachable from CloudFront only)"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Attach WAF (managed rules + rate limit) to CloudFront"
  type        = bool
  default     = false
}

variable "cloudfront_aliases" {
  description = "Custom domain names for CloudFront"
  type        = list(string)
  default     = []
}

variable "cloudfront_certificate_arn" {
  description = "ACM certificate (us-east-1) for the custom domain; empty = *.cloudfront.net"
  type        = string
  default     = ""
}

variable "enable_off_hours_schedule" {
  description = "Scale the ASG down outside working hours (non-production)"
  type        = bool
  default     = false
}

variable "off_hours_capacity" {
  description = "Instances kept during off hours"
  type        = number
  default     = 1
}

variable "enable_flow_logs" {
  description = "Record VPC Flow Logs in the audit bucket"
  type        = bool
  default     = false
}

variable "enable_cloudtrail" {
  description = "Create a multi-region CloudTrail trail (account level: one environment only)"
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Enable GuardDuty (account level: one environment only)"
  type        = bool
  default     = false
}

variable "enable_object_cache" {
  description = "ElastiCache Redis object cache for WordPress"
  type        = bool
  default     = false
}

variable "cache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "cache_node_count" {
  description = "Number of cache nodes (2 = replica with automatic failover)"
  type        = number
  default     = 1
}

variable "web_tier_in_private_subnets" {
  description = "Run the web instances in private subnets (needs enable_nat_gateway = true)"
  type        = bool
  default     = false
}
