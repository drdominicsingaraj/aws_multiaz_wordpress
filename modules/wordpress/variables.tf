# Input variables for the WordPress module.
# Environment-specific values are supplied from environments/<env>/terraform.tfvars.

# ---------- Identity ----------

variable "project" {
  description = "Project name, used as the first part of every resource name"
  type        = string
  default     = "deham9"
}

variable "environment" {
  description = "Deployment environment (dev, test or prod); used in resource names and tags"
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, prod."
  }
}

# ---------- Network ----------

variable "vpc_cidr" {
  description = "CIDR block of the VPC (a /16); subnets are carved out of it as /24 blocks"
  type        = string
}

variable "azs" {
  description = "Exactly two availability zones to spread subnets, ASG and database instances across"
  type        = list(string)

  validation {
    condition     = length(var.azs) == 2
    error_message = "azs must contain exactly two availability zones."
  }
}

variable "CIDR_BLOCK" {
  description = "CIDR block allowed to reach the web tier (HTTP/HTTPS) and used for the public route"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to the instances. Empty (default) closes port 22; use SSM Session Manager instead"
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, the ALB serves HTTPS on 443 and redirects HTTP to HTTPS (empty = HTTP only)"
  type        = string
  default     = ""
}

# ---------- Compute ----------

variable "ami_id" {
  description = "AMI ID to pin. Empty (default) uses the latest Amazon Linux 2023 AMI for cpu_architecture, so new instances are always patched"
  type        = string
  default     = ""
}

variable "cpu_architecture" {
  description = "CPU architecture of the web instances: x86_64, or arm64 (Graviton, needs a g instance type such as t4g.micro)"
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.cpu_architecture)
    error_message = "cpu_architecture must be x86_64 or arm64."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
  default     = "deham9-iam"
}

variable "standalone_instance_count" {
  description = "Number of standalone (non-ASG) web instances behind the load balancer"
  type        = number
  default     = 1
}

# ---------- Auto scaling ----------

variable "asg_min_size" {
  description = "Minimum number of ASG instances"
  type        = number
}

variable "asg_max_size" {
  description = "Maximum number of ASG instances; must exceed min for the CPU policy to scale out"
  type        = number
}

variable "asg_desired_capacity" {
  description = "Desired number of ASG instances"
  type        = number
}

variable "cpu_target_value" {
  description = "Target average CPU utilisation (%) for the scaling policy"
  type        = number
  default     = 70
}

# ---------- Database ----------

variable "db_engine_version" {
  description = "Aurora MySQL engine version to pin. Empty (default) uses the latest Aurora MySQL 3 (MySQL 8.0 compatible) release"
  type        = string
  default     = ""
}

variable "db_instance_class" {
  description = "Instance class of the Aurora instances"
  type        = string
  default     = "db.t3.small"
}

variable "db_instance_count" {
  description = "Number of Aurora instances (1 = writer only, 2 = writer + reader in the second AZ)"
  type        = number
  default     = 2
}

variable "db_backup_retention_days" {
  description = "Days to keep automated Aurora backups"
  type        = number
  default     = 1
}

variable "db_publicly_accessible" {
  description = "Make Aurora publicly reachable (opens port 3306 to CIDR_BLOCK); keep false, the DB sits in private subnets and the web tier is the only client"
  type        = bool
  default     = false
}

# ---------- Protection ----------

variable "deletion_protection" {
  description = "Protect the ALB and Aurora cluster from deletion and take a final DB snapshot on destroy"
  type        = bool
  default     = false
}

variable "force_destroy_log_bucket" {
  description = "Allow Terraform to delete the log bucket even when it still contains objects"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway (and EIP) giving the private subnets outbound internet access"
  type        = bool
  default     = true
}

# ---------- Monitoring and logging ----------

variable "log_retention_days" {
  description = "Days to keep ALB access logs in S3 and Aurora logs in CloudWatch Logs"
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Email address subscribed to the CloudWatch alarm topic (empty = topic only, no subscription)"
  type        = string
  default     = ""
}

# ---------- Scaling ----------

variable "request_count_target" {
  description = "Target requests per minute per instance for the request-count scaling policy (scales with traffic, not only CPU)"
  type        = number
  default     = 1000
}

variable "enable_off_hours_schedule" {
  description = "Scale the ASG down to off_hours_capacity outside working hours to save cost (non-production)"
  type        = bool
  default     = false
}

variable "off_hours_capacity" {
  description = "Number of instances kept during off hours"
  type        = number
  default     = 1
}

variable "off_hours_scale_down_cron" {
  description = "Cron (UTC) when the ASG scales down"
  type        = string
  default     = "0 19 * * *"
}

variable "off_hours_scale_up_cron" {
  description = "Cron (UTC) when the ASG scales back up to its configured size"
  type        = string
  default     = "0 6 * * MON-FRI"
}

# ---------- Edge: CloudFront and WAF ----------

variable "enable_cloudfront" {
  description = "Put CloudFront in front of the ALB: HTTPS without a domain, edge caching of static files, ALB reachable from CloudFront only"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Attach AWS WAF (managed rules + rate limit) to the CloudFront distribution; needs enable_cloudfront and us-east-1"
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes per IP before WAF blocks it"
  type        = number
  default     = 2000
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_100 = US, Canada, Europe)"
  type        = string
  default     = "PriceClass_100"
}

variable "cloudfront_aliases" {
  description = "Custom domain names for the distribution (needs cloudfront_certificate_arn)"
  type        = list(string)
  default     = []
}

variable "cloudfront_certificate_arn" {
  description = "ACM certificate (must be in us-east-1) for the custom domain; empty = default *.cloudfront.net certificate"
  type        = string
  default     = ""
}

# ---------- Audit, security and performance options ----------

variable "enable_flow_logs" {
  description = "Record VPC Flow Logs (accepted and rejected traffic) in the audit log bucket"
  type        = bool
  default     = false
}

variable "enable_cloudtrail" {
  description = "Create a multi-region CloudTrail trail. ACCOUNT level: enable in one environment only"
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Enable GuardDuty. ACCOUNT level (one detector per account and region): enable in one environment only"
  type        = bool
  default     = false
}

variable "enable_object_cache" {
  description = "ElastiCache Redis object cache for WordPress (Redis Object Cache drop-in installed at first boot)"
  type        = bool
  default     = false
}

variable "cache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "cache_node_count" {
  description = "Number of cache nodes (2 = primary + replica in the other AZ with automatic failover)"
  type        = number
  default     = 1
}

variable "web_tier_in_private_subnets" {
  description = "Run the web instances in the private subnets without public IPs. Needs enable_nat_gateway = true (WordPress download, SSM, Secrets Manager)"
  type        = bool
  default     = false
}
