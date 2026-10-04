output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (the site's entry point)"
  value       = module.wordpress.alb_dns_name
}

output "alb_name" {
  description = "Name of the Application Load Balancer"
  value       = module.wordpress.alb_name
}

output "asg_name" {
  description = "Name of the Auto Scaling Group (used by load-test.sh)"
  value       = module.wordpress.asg_name
}

output "public_ip" {
  description = "Public IP address of the standalone WordPress server (null when none is deployed)"
  value       = module.wordpress.public_ip
}

output "db_endpoint" {
  description = "Writer endpoint of the Aurora cluster"
  value       = module.wordpress.db_endpoint
}

output "db_master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the Aurora master password"
  value       = module.wordpress.db_master_secret_arn
}

output "log_bucket" {
  description = "Name of the ALB log bucket"
  value       = module.wordpress.log_bucket
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.wordpress.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.wordpress.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.wordpress.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.wordpress.private_subnet_ids
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = module.wordpress.internet_gateway_id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = module.wordpress.nat_gateway_id
}

output "nat_public_ip" {
  description = "Elastic IP of the NAT gateway (egress IP of the private subnets)"
  value       = module.wordpress.nat_public_ip
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = module.wordpress.public_route_table_id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = module.wordpress.private_route_table_id
}

output "sg_vpc_id" {
  description = "ID of the security group shared by the ALB and web instances"
  value       = module.wordpress.sg_vpc_id
}

output "ssh_security_group_id" {
  description = "ID of the SSH security group"
  value       = module.wordpress.ssh_security_group_id
}

output "aurora_security_group_id" {
  description = "ID of the Aurora access security group"
  value       = module.wordpress.aurora_security_group_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.wordpress.alb_arn
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route 53 alias records)"
  value       = module.wordpress.alb_zone_id
}

output "alb_url" {
  description = "HTTP URL of the site"
  value       = module.wordpress.alb_url
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = module.wordpress.target_group_arn
}

output "listener_arn" {
  description = "ARN of the ALB listener"
  value       = module.wordpress.listener_arn
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = module.wordpress.asg_arn
}

output "launch_template_id" {
  description = "ID of the launch template used by the ASG"
  value       = module.wordpress.launch_template_id
}

output "scaling_policy_name" {
  description = "Name of the CPU target-tracking scaling policy"
  value       = module.wordpress.scaling_policy_name
}

output "standalone_instance_ids" {
  description = "IDs of the standalone EC2 instances (empty when none)"
  value       = module.wordpress.standalone_instance_ids
}

output "standalone_instance_private_ips" {
  description = "Private IPs of the standalone EC2 instances (empty when none)"
  value       = module.wordpress.standalone_instance_private_ips
}

output "db_reader_endpoint" {
  description = "Reader endpoint of the Aurora cluster"
  value       = module.wordpress.db_reader_endpoint
}

output "db_cluster_id" {
  description = "Identifier of the Aurora cluster"
  value       = module.wordpress.db_cluster_id
}

output "db_cluster_arn" {
  description = "ARN of the Aurora cluster"
  value       = module.wordpress.db_cluster_arn
}

output "db_port" {
  description = "Port of the Aurora cluster"
  value       = module.wordpress.db_port
}

output "db_name" {
  description = "Name of the initial database"
  value       = module.wordpress.db_name
}

output "db_instance_ids" {
  description = "Identifiers of the Aurora cluster instances"
  value       = module.wordpress.db_instance_ids
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = module.wordpress.db_subnet_group_name
}

output "log_bucket_arn" {
  description = "ARN of the ALB log bucket"
  value       = module.wordpress.log_bucket_arn
}

output "efs_id" {
  description = "ID of the EFS file system holding the WordPress files"
  value       = module.wordpress.efs_id
}

output "efs_arn" {
  description = "ARN of the WordPress EFS file system"
  value       = module.wordpress.efs_arn
}

output "efs_dns_name" {
  description = "DNS name of the WordPress EFS file system"
  value       = module.wordpress.efs_dns_name
}

output "efs_mount_target_ids" {
  description = "IDs of the EFS mount targets (one per AZ)"
  value       = module.wordpress.efs_mount_target_ids
}

output "efs_security_group_id" {
  description = "ID of the security group guarding the EFS mount targets"
  value       = module.wordpress.efs_security_group_id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic that receives CloudWatch alarm notifications"
  value       = module.wordpress.sns_topic_arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = module.wordpress.dashboard_name
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard in the AWS console"
  value       = module.wordpress.dashboard_url
}

output "alarm_names" {
  description = "Names of the CloudWatch alarms"
  value       = module.wordpress.alarm_names
}

output "alb_log_prefix" {
  description = "S3 location where the ALB access logs are written"
  value       = module.wordpress.alb_log_prefix
}

output "aurora_log_group_names" {
  description = "CloudWatch Logs groups holding the Aurora error and slow query logs"
  value       = module.wordpress.aurora_log_group_names
}

output "alb_security_group_id" {
  description = "ID of the load balancer security group (the only one open to the internet)"
  value       = module.wordpress.alb_security_group_id
}

output "web_role_arn" {
  description = "ARN of the IAM role used by the web instances"
  value       = module.wordpress.web_role_arn
}

output "web_instance_profile_name" {
  description = "Name of the IAM instance profile used by the web instances"
  value       = module.wordpress.web_instance_profile_name
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (null when no certificate_arn is set)"
  value       = module.wordpress.https_listener_arn
}

output "site_url" {
  description = "URL of the site: the CloudFront HTTPS domain when enabled, otherwise the ALB"
  value       = module.wordpress.site_url
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution (null when disabled)"
  value       = module.wordpress.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution (null when disabled)"
  value       = module.wordpress.cloudfront_distribution_id
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF web ACL (null when disabled)"
  value       = module.wordpress.waf_web_acl_arn
}

output "ami_id" {
  description = "AMI used by the web instances"
  value       = module.wordpress.ami_id
}

output "audit_bucket" {
  description = "Name of the audit log bucket (CloudFront logs, VPC Flow Logs, CloudTrail)"
  value       = module.wordpress.audit_bucket
}

output "flow_log_id" {
  description = "ID of the VPC Flow Log (null when disabled)"
  value       = module.wordpress.flow_log_id
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail (null when disabled)"
  value       = module.wordpress.cloudtrail_arn
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector (null when disabled)"
  value       = module.wordpress.guardduty_detector_id
}

output "cache_endpoint" {
  description = "Primary endpoint of the Redis object cache (null when disabled)"
  value       = module.wordpress.cache_endpoint
}

output "waf_log_group" {
  description = "CloudWatch Logs group of the WAF request log (null when disabled)"
  value       = module.wordpress.waf_log_group
}
