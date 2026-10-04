output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (the site's entry point)"
  value       = aws_lb.application-lb.dns_name
}

output "alb_name" {
  description = "Name of the Application Load Balancer"
  value       = aws_lb.application-lb.name
}

output "asg_name" {
  description = "Name of the Auto Scaling Group (used by load-test.sh)"
  value       = aws_autoscaling_group.web.name
}

output "public_ip" {
  description = "Public IP address of the standalone WordPress server (null when none is deployed)"
  value       = one(aws_instance.instance[*].public_ip)
}

output "db_endpoint" {
  description = "Writer endpoint of the Aurora cluster"
  value       = aws_rds_cluster.auroracluster.endpoint
}

output "db_master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the Aurora master password"
  value       = aws_rds_cluster.auroracluster.master_user_secret[0].secret_arn
}

output "log_bucket" {
  description = "Name of the ALB log bucket"
  value       = aws_s3_bucket.alb_logs.bucket
}

# ---- Network ----

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = [aws_subnet.public-1.id, aws_subnet.public-2.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = [aws_subnet.private-1.id, aws_subnet.private-2.id]
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.igw.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = one(aws_nat_gateway.nat[*].id)
}

output "nat_public_ip" {
  description = "Elastic IP of the NAT gateway (egress IP of the private subnets)"
  value       = one(aws_eip.nat_eip[*].public_ip)
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.RB_Public_RouteTable.id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.RB_Private_RouteTable.id
}

# ---- Security groups ----

output "sg_vpc_id" {
  description = "ID of the security group shared by the ALB and web instances"
  value       = aws_security_group.sg_vpc.id
}

output "ssh_security_group_id" {
  description = "ID of the SSH security group"
  value       = aws_security_group.allow_ssh.id
}

output "aurora_security_group_id" {
  description = "ID of the Aurora access security group"
  value       = aws_security_group.allow_aurora_access.id
}

# ---- Load balancer ----

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.application-lb.arn
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route 53 alias records)"
  value       = aws_lb.application-lb.zone_id
}

output "alb_url" {
  description = "HTTP URL of the site"
  value       = "http://${aws_lb.application-lb.dns_name}"
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.target-group.arn
}

output "listener_arn" {
  description = "ARN of the ALB listener"
  value       = aws_lb_listener.alb-listener.arn
}

# ---- Compute ----

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.arn
}

output "launch_template_id" {
  description = "ID of the launch template used by the ASG"
  value       = aws_launch_template.web.id
}

output "scaling_policy_name" {
  description = "Name of the CPU target-tracking scaling policy"
  value       = aws_autoscaling_policy.cpu.name
}

output "standalone_instance_ids" {
  description = "IDs of the standalone EC2 instances (empty when none)"
  value       = aws_instance.instance[*].id
}

output "standalone_instance_private_ips" {
  description = "Private IPs of the standalone EC2 instances (empty when none)"
  value       = aws_instance.instance[*].private_ip
}

# ---- Database ----

output "db_reader_endpoint" {
  description = "Reader endpoint of the Aurora cluster"
  value       = aws_rds_cluster.auroracluster.reader_endpoint
}

output "db_cluster_id" {
  description = "Identifier of the Aurora cluster"
  value       = aws_rds_cluster.auroracluster.cluster_identifier
}

output "db_cluster_arn" {
  description = "ARN of the Aurora cluster"
  value       = aws_rds_cluster.auroracluster.arn
}

output "db_port" {
  description = "Port of the Aurora cluster"
  value       = aws_rds_cluster.auroracluster.port
}

output "db_name" {
  description = "Name of the initial database"
  value       = aws_rds_cluster.auroracluster.database_name
}

output "db_instance_ids" {
  description = "Identifiers of the Aurora cluster instances"
  value       = aws_rds_cluster_instance.clusterinstance[*].identifier
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.db_subnet.name
}

# ---- Storage ----

output "log_bucket_arn" {
  description = "ARN of the ALB log bucket"
  value       = aws_s3_bucket.alb_logs.arn
}

# ---- Shared file storage ----

output "efs_id" {
  description = "ID of the EFS file system holding the WordPress files"
  value       = aws_efs_file_system.wordpress.id
}

output "efs_arn" {
  description = "ARN of the WordPress EFS file system"
  value       = aws_efs_file_system.wordpress.arn
}

output "efs_dns_name" {
  description = "DNS name of the WordPress EFS file system"
  value       = aws_efs_file_system.wordpress.dns_name
}

output "efs_mount_target_ids" {
  description = "IDs of the EFS mount targets (one per AZ)"
  value       = [aws_efs_mount_target.public-1.id, aws_efs_mount_target.public-2.id]
}

output "efs_security_group_id" {
  description = "ID of the security group guarding the EFS mount targets"
  value       = aws_security_group.efs.id
}

# ---- Monitoring and logging ----

output "sns_topic_arn" {
  description = "ARN of the SNS topic that receives CloudWatch alarm notifications"
  value       = aws_sns_topic.alarms.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard in the AWS console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "alarm_names" {
  description = "Names of the CloudWatch alarms"
  value       = [for a in [aws_cloudwatch_metric_alarm.alb_5xx, aws_cloudwatch_metric_alarm.target_5xx, aws_cloudwatch_metric_alarm.unhealthy_hosts, aws_cloudwatch_metric_alarm.response_time, aws_cloudwatch_metric_alarm.asg_cpu_high, aws_cloudwatch_metric_alarm.asg_memory_high, aws_cloudwatch_metric_alarm.db_cpu_high, aws_cloudwatch_metric_alarm.db_connections_high, aws_cloudwatch_metric_alarm.db_memory_low, aws_cloudwatch_metric_alarm.efs_io_limit] : a.alarm_name]
}

output "alb_log_prefix" {
  description = "S3 location where the ALB access logs are written"
  value       = "s3://${aws_s3_bucket.alb_logs.bucket}/${local.alb_log_prefix}/"
}

output "aurora_log_group_names" {
  description = "CloudWatch Logs groups holding the Aurora error and slow query logs"
  value       = [for g in aws_cloudwatch_log_group.aurora : g.name]
}

# ---- Security ----

output "alb_security_group_id" {
  description = "ID of the load balancer security group (the only one open to the internet)"
  value       = aws_security_group.sg_alb.id
}

output "web_role_arn" {
  description = "ARN of the IAM role used by the web instances"
  value       = aws_iam_role.web.arn
}

output "web_instance_profile_name" {
  description = "Name of the IAM instance profile used by the web instances"
  value       = aws_iam_instance_profile.web.name
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (null when no certificate_arn is set)"
  value       = one(aws_lb_listener.https[*].arn)
}

# ---- Edge: CloudFront and WAF ----

output "site_url" {
  description = "URL of the site: the CloudFront HTTPS domain when enabled, otherwise the ALB"
  value       = local.cloudfront_enabled ? "https://${aws_cloudfront_distribution.main[0].domain_name}" : "http://${aws_lb.application-lb.dns_name}"
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution (null when disabled)"
  value       = one(aws_cloudfront_distribution.main[*].domain_name)
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution (null when disabled)"
  value       = one(aws_cloudfront_distribution.main[*].id)
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF web ACL (null when disabled)"
  value       = one(aws_wafv2_web_acl.main[*].arn)
}

output "ami_id" {
  description = "AMI used by the web instances"
  value       = local.ami_id
}

# ---- Audit, security and performance ----

output "audit_bucket" {
  description = "Name of the audit log bucket (CloudFront logs, VPC Flow Logs, CloudTrail)"
  value       = aws_s3_bucket.audit.bucket
}

output "flow_log_id" {
  description = "ID of the VPC Flow Log (null when disabled)"
  value       = one(aws_flow_log.vpc[*].id)
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail (null when disabled)"
  value       = one(aws_cloudtrail.main[*].arn)
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector (null when disabled)"
  value       = one(aws_guardduty_detector.main[*].id)
}

output "cache_endpoint" {
  description = "Primary endpoint of the Redis object cache (null when disabled)"
  value       = one(aws_elasticache_replication_group.cache[*].primary_endpoint_address)
}

output "waf_log_group" {
  description = "CloudWatch Logs group of the WAF request log (null when disabled)"
  value       = one(aws_cloudwatch_log_group.waf[*].name)
}
