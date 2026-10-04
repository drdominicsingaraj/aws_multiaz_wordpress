# Unit tests for the WordPress module. Run with `terraform test` from modules/wordpress.
# The provider is mocked, so no AWS credentials are needed and nothing is created.
# File-level variables mirror a dev-like environment; individual runs override them.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  # Mocked policy documents must still be valid JSON for IAM/S3 policy attributes
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_data "aws_elb_service_account" {
    defaults = {
      arn = "arn:aws:iam::127311923021:root"
    }
  }
}

variables {
  project                   = "deham9"
  environment               = "dev"
  vpc_cidr                  = "10.0.0.0/16"
  azs                       = ["us-east-1a", "us-east-1b"]
  ami_id                    = "ami-0230bd60aa48260c6"
  asg_min_size              = 2
  asg_max_size              = 3
  asg_desired_capacity      = 2
  standalone_instance_count = 1
}

run "vpc_and_subnets" {
  command = plan

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR must come from var.vpc_cidr"
  }

  assert {
    condition     = aws_vpc.main.enable_dns_hostnames && aws_vpc.main.enable_dns_support
    error_message = "VPC must enable DNS hostnames and DNS support"
  }

  assert {
    condition     = aws_subnet.public-1.availability_zone == "us-east-1a" && aws_subnet.public-2.availability_zone == "us-east-1b"
    error_message = "Public subnets must use the two AZs from var.azs"
  }

  assert {
    condition     = aws_subnet.private-1.availability_zone == "us-east-1a" && aws_subnet.private-2.availability_zone == "us-east-1b"
    error_message = "Private subnets must use the two AZs from var.azs"
  }

  assert {
    condition     = aws_subnet.public-1.map_public_ip_on_launch && aws_subnet.public-2.map_public_ip_on_launch
    error_message = "Public subnets must auto-assign public IPs"
  }

  assert {
    condition     = !coalesce(aws_subnet.private-1.map_public_ip_on_launch, false) && !coalesce(aws_subnet.private-2.map_public_ip_on_launch, false)
    error_message = "Private subnets must not auto-assign public IPs"
  }

  assert {
    condition = length(distinct([
      aws_subnet.public-1.cidr_block,
      aws_subnet.public-2.cidr_block,
      aws_subnet.private-1.cidr_block,
      aws_subnet.private-2.cidr_block,
    ])) == 4
    error_message = "Subnet CIDR blocks must not overlap/duplicate"
  }

  assert {
    condition = alltrue([
      for s in [aws_subnet.public-1, aws_subnet.public-2, aws_subnet.private-1, aws_subnet.private-2] :
      cidrsubnet(var.vpc_cidr, 8, tonumber(split(".", cidrhost(s.cidr_block, 0))[2])) == s.cidr_block
    ])
    error_message = "All subnets must be /24 blocks inside the VPC CIDR"
  }
}

run "routing" {
  command = plan

  assert {
    condition     = one(aws_route_table.RB_Public_RouteTable.route).cidr_block == "0.0.0.0/0"
    error_message = "Public route table must route 0.0.0.0/0"
  }

  assert {
    condition     = length(aws_nat_gateway.nat) == 1 && length(aws_eip.nat_eip) == 1
    error_message = "NAT gateway and EIP are created by default"
  }

  assert {
    condition     = one(aws_route_table.RB_Private_RouteTable.route).cidr_block == "0.0.0.0/0"
    error_message = "Private route table must route 0.0.0.0/0 via the NAT gateway"
  }
}

run "no_nat_gateway" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.nat) == 0 && length(aws_eip.nat_eip) == 0
    error_message = "enable_nat_gateway = false must create neither NAT gateway nor EIP"
  }
}

run "security_groups" {
  command = plan

  assert {
    condition     = toset([for r in aws_security_group.sg_alb.ingress : r.from_port]) == toset([80, 443])
    error_message = "The ALB security group must allow exactly ports 80 and 443 inbound"
  }

  assert {
    condition     = one(aws_security_group.sg_vpc.ingress).from_port == 80 && length(coalesce(one(aws_security_group.sg_vpc.ingress).cidr_blocks, [])) == 0
    error_message = "The web tier must accept only port 80, and only from the ALB security group (no CIDR)"
  }

  assert {
    condition     = toset([for r in aws_security_group.sg_vpc.egress : r.from_port]) == toset([443, 2049, 3306])
    error_message = "Web tier egress must be limited to 443, 2049 and 3306"
  }

  assert {
    condition     = length(var.ssh_cidr_blocks) == 0
    error_message = "SSH must be closed by default (empty ssh_cidr_blocks)"
  }

  assert {
    condition     = length(aws_security_group.allow_aurora_access.ingress) == 1
    error_message = "Aurora SG must have a single ingress rule when the DB is not public"
  }

  assert {
    condition     = one(aws_security_group.allow_aurora_access.ingress).from_port == 3306 && one(aws_security_group.allow_aurora_access.ingress).to_port == 3306
    error_message = "Aurora SG must only allow port 3306"
  }

  assert {
    condition     = length(coalesce(one(aws_security_group.allow_aurora_access.ingress).cidr_blocks, [])) == 0
    error_message = "Aurora SG must not allow any CIDR when the DB is not public"
  }

}

run "aurora_open_to_cidr_when_public" {
  command = plan

  variables {
    db_publicly_accessible = true
  }

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.clusterinstance : i.publicly_accessible])
    error_message = "Instances must be publicly accessible when db_publicly_accessible is true"
  }
}

run "load_balancer" {
  command = plan

  assert {
    condition     = aws_lb.application-lb.name == "deham9-dev-alb" && !aws_lb.application-lb.internal
    error_message = "ALB must be named <project>-<env>-alb and internet-facing (load-test.sh derives the name)"
  }

  assert {
    condition     = aws_lb.application-lb.load_balancer_type == "application"
    error_message = "Load balancer must be an application LB"
  }

  assert {
    condition     = aws_lb_target_group.target-group.name == "deham9-dev-tg" && aws_lb_target_group.target-group.port == 80
    error_message = "Target group must be <project>-<env>-tg on port 80"
  }

  assert {
    condition     = one(aws_lb_target_group.target-group.health_check).path == "/"
    error_message = "Health check must target /"
  }

  assert {
    condition     = one(aws_lb_target_group.target-group.health_check).timeout < one(aws_lb_target_group.target-group.health_check).interval
    error_message = "Health check timeout must be shorter than the interval"
  }

  assert {
    condition     = aws_lb_listener.alb-listener.port == 80 && aws_lb_listener.alb-listener.protocol == "HTTP"
    error_message = "Listener must serve HTTP on port 80"
  }

  assert {
    condition     = one(aws_lb_listener.alb-listener.default_action).type == "forward"
    error_message = "Listener default action must forward"
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.ec2_attach) == 1
    error_message = "The standalone instance must be attached to the target group"
  }

  assert {
    condition     = !aws_lb.application-lb.enable_deletion_protection
    error_message = "Deletion protection is off by default"
  }
}

run "auto_scaling" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.web.name == "deham9-dev-asg"
    error_message = "ASG name must be <project>-<env>-asg (load-test.sh derives it)"
  }

  assert {
    condition = (
      aws_autoscaling_group.web.min_size <= aws_autoscaling_group.web.desired_capacity &&
      aws_autoscaling_group.web.desired_capacity <= aws_autoscaling_group.web.max_size
    )
    error_message = "ASG sizes must satisfy min <= desired <= max"
  }

  assert {
    condition     = aws_autoscaling_group.web.health_check_type == "ELB"
    error_message = "ASG must use ELB health checks"
  }

  assert {
    condition     = aws_launch_template.web.name == "deham9-dev-web-launch-template"
    error_message = "Launch template name must carry the environment prefix"
  }

  assert {
    condition     = aws_launch_template.web.image_id == "ami-0230bd60aa48260c6"
    error_message = "Launch template must use var.ami_id"
  }

  assert {
    condition     = aws_autoscaling_policy.cpu.policy_type == "TargetTrackingScaling"
    error_message = "Scaling policy must be target tracking"
  }

  assert {
    condition     = one(aws_autoscaling_policy.cpu.target_tracking_configuration).target_value == 70
    error_message = "CPU target must default to 70%"
  }
}

run "database" {
  command = plan

  assert {
    condition     = aws_rds_cluster.auroracluster.engine == "aurora-mysql"
    error_message = "Cluster engine must be aurora-mysql"
  }

  assert {
    condition     = aws_rds_cluster.auroracluster.cluster_identifier == "deham9-dev-aurora"
    error_message = "Cluster identifier must carry the environment prefix"
  }

  assert {
    condition     = aws_rds_cluster.auroracluster.manage_master_user_password == true
    error_message = "Master password must be managed by Secrets Manager, not hard-coded"
  }

  assert {
    condition     = length(aws_rds_cluster_instance.clusterinstance) == 2
    error_message = "Aurora must default to two instances"
  }

  assert {
    condition     = toset([for i in aws_rds_cluster_instance.clusterinstance : i.availability_zone]) == toset(var.azs)
    error_message = "Aurora instances must be spread across the two AZs"
  }

  assert {
    condition     = length(distinct([for i in aws_rds_cluster_instance.clusterinstance : i.identifier])) == 2
    error_message = "Aurora instance identifiers must be unique"
  }

  assert {
    condition     = !aws_rds_cluster.auroracluster.deletion_protection && aws_rds_cluster.auroracluster.skip_final_snapshot
    error_message = "Non-protected environments skip the final snapshot"
  }

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.clusterinstance : !i.publicly_accessible])
    error_message = "Aurora must not be publicly accessible by default"
  }
}

run "storage" {
  command = plan

  assert {
    condition     = aws_s3_bucket.alb_logs.bucket == "deham9-dev-alb-logs-123456789012"
    error_message = "Log bucket name must contain environment and account ID"
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.alb_logs.versioning_configuration).status == "Enabled"
    error_message = "Bucket versioning must be enabled"
  }
}

run "standalone_instance" {
  command = plan

  assert {
    condition     = length(aws_instance.instance) == 1
    error_message = "One standalone instance expected"
  }

  assert {
    condition     = aws_instance.instance[0].ami == "ami-0230bd60aa48260c6"
    error_message = "Instance must use var.ami_id"
  }

  assert {
    condition     = aws_instance.instance[0].associate_public_ip_address
    error_message = "Instance must get a public IP"
  }

  assert {
    condition     = aws_instance.instance[0].tags["Type"] == "WordPress-Server"
    error_message = "Instance must be tagged Type=WordPress-Server"
  }
}

run "no_standalone_instance" {
  command = plan

  variables {
    standalone_instance_count = 0
  }

  assert {
    condition     = length(aws_instance.instance) == 0 && length(aws_lb_target_group_attachment.ec2_attach) == 0
    error_message = "standalone_instance_count = 0 must create neither the instance nor its attachment"
  }
}

run "custom_cidr_block_flows_to_security_group" {
  command = plan

  variables {
    CIDR_BLOCK = "10.1.0.0/16"
  }

  assert {
    condition     = alltrue([for r in aws_security_group.sg_alb.ingress : contains(r.cidr_blocks, "10.1.0.0/16")])
    error_message = "var.CIDR_BLOCK must drive the ALB HTTP/HTTPS ingress rules"
  }

  assert {
    condition     = one(aws_route_table.RB_Public_RouteTable.route).cidr_block == "10.1.0.0/16"
    error_message = "var.CIDR_BLOCK must drive the public route"
  }
}

run "ssh_cidr_blocks_restrict_ssh" {
  command = plan

  variables {
    ssh_cidr_blocks = ["10.0.0.0/16"]
  }

  assert {
    condition     = one(aws_security_group.allow_ssh.ingress).from_port == 22 && join(",", one(aws_security_group.allow_ssh.ingress).cidr_blocks) == "10.0.0.0/16"
    error_message = "ssh_cidr_blocks must drive the SSH rule"
  }
}

# ---- Environment-specific behaviour ----

run "prod_like_settings" {
  command = plan

  variables {
    environment               = "prod"
    vpc_cidr                  = "10.2.0.0/16"
    asg_min_size              = 2
    asg_max_size              = 6
    deletion_protection       = true
    force_destroy_log_bucket  = false
    standalone_instance_count = 0
  }

  assert {
    condition     = aws_lb.application-lb.name == "deham9-prod-alb" && aws_autoscaling_group.web.name == "deham9-prod-asg"
    error_message = "Names must switch to the prod prefix"
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.2.0.0/16" && aws_subnet.public-1.cidr_block == "10.2.1.0/24"
    error_message = "Subnets must follow the VPC CIDR of the environment"
  }

  assert {
    condition     = aws_lb.application-lb.enable_deletion_protection && aws_rds_cluster.auroracluster.deletion_protection
    error_message = "Prod must enable deletion protection on ALB and Aurora"
  }

  assert {
    condition     = !aws_rds_cluster.auroracluster.skip_final_snapshot && aws_rds_cluster.auroracluster.final_snapshot_identifier == "deham9-prod-aurora-final-snapshot"
    error_message = "Prod must take a final snapshot"
  }

  assert {
    condition     = !aws_s3_bucket.alb_logs.force_destroy
    error_message = "Prod log bucket must not be force-destroyed"
  }

  assert {
    condition     = aws_autoscaling_group.web.max_size > aws_autoscaling_group.web.min_size && aws_autoscaling_group.web.min_size >= 2
    error_message = "Prod ASG needs >= 2 instances for multi-AZ and headroom to scale out"
  }
}

run "single_db_instance" {
  command = plan

  variables {
    db_instance_count = 1
  }

  assert {
    condition     = length(aws_rds_cluster_instance.clusterinstance) == 1
    error_message = "db_instance_count must control the number of Aurora instances"
  }
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

run "rejects_wrong_az_count" {
  command = plan

  variables {
    azs = ["us-east-1a"]
  }

  expect_failures = [var.azs]
}

run "efs_wordpress_storage" {
  command = plan

  assert {
    condition     = aws_efs_file_system.wordpress.encrypted
    error_message = "The WordPress EFS must be encrypted"
  }

  assert {
    condition     = aws_efs_file_system.wordpress.creation_token == "deham9-dev-wordpress-efs"
    error_message = "EFS name must derive from the prefix"
  }

  assert {
    condition     = one(aws_security_group.efs.ingress).from_port == 2049 && one(aws_security_group.efs.ingress).to_port == 2049
    error_message = "EFS security group must allow only NFS (2049)"
  }

  assert {
    condition     = aws_efs_file_system.wordpress.lifecycle_policy[0].transition_to_ia == "AFTER_30_DAYS"
    error_message = "EFS must move cold files to Infrequent Access after 30 days"
  }
}

run "alb_access_logs_to_s3" {
  command = plan

  assert {
    condition     = one(aws_lb.application-lb.access_logs).enabled && one(aws_lb.application-lb.access_logs).prefix == "alb"
    error_message = "ALB must write access logs to the S3 log bucket under the alb prefix"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.alb_logs.block_public_acls && aws_s3_bucket_public_access_block.alb_logs.restrict_public_buckets
    error_message = "The log bucket must block public access"
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.alb_logs.rule).expiration).days == 30
    error_message = "Logs must expire after var.log_retention_days (default 30)"
  }
}

run "cloudwatch_monitoring" {
  command = plan

  assert {
    condition     = aws_sns_topic.alarms.name == "deham9-dev-alarms"
    error_message = "SNS topic name must derive from the prefix"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "No email subscription without alarm_email"
  }

  assert {
    condition     = aws_cloudwatch_dashboard.main.dashboard_name == "deham9-dev-wordpress"
    error_message = "Dashboard name must derive from the prefix"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts.metric_name == "UnHealthyHostCount" && aws_cloudwatch_metric_alarm.db_cpu_high.threshold == 80
    error_message = "Alarm metrics and thresholds changed"
  }

  assert {
    condition     = one(aws_launch_template.web.monitoring).enabled
    error_message = "ASG instances must use detailed (1-minute) monitoring"
  }

  assert {
    condition     = aws_rds_cluster.auroracluster.enabled_cloudwatch_logs_exports == toset(["error", "slowquery"])
    error_message = "Aurora must export error and slowquery logs to CloudWatch"
  }
}

run "alarm_email_subscription" {
  command = plan

  variables {
    alarm_email = "ops@example.com"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "alarm_email must create one subscription"
  }
}

run "hardening" {
  command = plan

  assert {
    condition     = one(aws_launch_template.web.metadata_options).http_tokens == "required"
    error_message = "ASG instances must require IMDSv2"
  }

  assert {
    condition     = one(one(aws_launch_template.web.block_device_mappings).ebs).encrypted == "true"
    error_message = "ASG root volumes must be encrypted"
  }

  assert {
    condition     = one(aws_instance.instance[0].metadata_options).http_tokens == "required" && one(aws_instance.instance[0].root_block_device).encrypted
    error_message = "The standalone instance must require IMDSv2 and encrypt its root volume"
  }

  assert {
    condition     = aws_rds_cluster.auroracluster.storage_encrypted
    error_message = "Aurora storage must be encrypted"
  }

  assert {
    condition     = aws_iam_role.web.name == "deham9-dev-web-role" && aws_iam_instance_profile.web.name == "deham9-dev-web-profile"
    error_message = "The web IAM role and profile must be created per environment"
  }
}

run "http_only_without_certificate" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.https) == 0
    error_message = "No HTTPS listener without certificate_arn"
  }
}

run "https_with_certificate" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1 && aws_lb_listener.https[0].port == 443
    error_message = "certificate_arn must create the HTTPS listener on 443"
  }

  assert {
    condition     = one(aws_lb_listener.alb-listener.default_action).type == "redirect"
    error_message = "HTTP must redirect to HTTPS when a certificate is set"
  }
}

run "well_architected_fixes" {
  command = plan

  assert {
    condition     = one(aws_lb_target_group.target-group.health_check).matcher == "200-399"
    error_message = "Health check must accept WordPress redirects (200-399)"
  }

  assert {
    condition     = aws_lb.application-lb.drop_invalid_header_fields
    error_message = "ALB must drop invalid header fields"
  }

  assert {
    condition     = one(aws_autoscaling_group.web.instance_refresh).strategy == "Rolling"
    error_message = "ASG must roll instances when the launch template changes"
  }

  assert {
    condition     = one(aws_efs_backup_policy.wordpress.backup_policy).status == "ENABLED"
    error_message = "EFS backups must be enabled"
  }

  assert {
    condition     = aws_efs_file_system.wordpress.throughput_mode == "elastic"
    error_message = "EFS must use elastic throughput"
  }

  assert {
    condition     = local.db_app_user == "wordpress"
    error_message = "WordPress must use its own DB user, not the rotating master credentials"
  }
}

run "scaling_on_request_count" {
  command = plan

  assert {
    condition     = one(aws_autoscaling_policy.requests.target_tracking_configuration).target_value == 1000
    error_message = "Request-count scaling policy must use var.request_count_target"
  }

  assert {
    condition     = length(aws_autoscaling_schedule.scale_down) == 0 && length(aws_autoscaling_schedule.scale_up) == 0
    error_message = "No off-hours schedule unless enabled"
  }
}

run "off_hours_schedule" {
  command = plan

  variables {
    enable_off_hours_schedule = true
    off_hours_capacity        = 1
  }

  assert {
    condition     = aws_autoscaling_schedule.scale_down[0].desired_capacity == 1 && aws_autoscaling_schedule.scale_up[0].desired_capacity == 2
    error_message = "Scale down to off_hours_capacity and back up to asg_desired_capacity"
  }
}

run "graviton_needs_arm_instance_type" {
  command = plan

  variables {
    cpu_architecture = "arm64"
    instance_type    = "t3.micro"
  }

  expect_failures = [aws_launch_template.web]
}

run "graviton_ok" {
  command = plan

  variables {
    cpu_architecture = "arm64"
    instance_type    = "t4g.micro"
    ami_id           = ""
  }

  assert {
    condition     = data.aws_ssm_parameter.al2023[0].name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    error_message = "arm64 must look up the arm64 Amazon Linux 2023 AMI"
  }
}

run "cloudfront_and_waf" {
  command = plan

  variables {
    enable_cloudfront = true
    enable_waf        = true
  }

  assert {
    condition     = one(aws_cloudfront_distribution.main[0].default_cache_behavior).viewer_protocol_policy == "redirect-to-https"
    error_message = "CloudFront must redirect HTTP to HTTPS"
  }

  assert {
    condition     = one(aws_security_group.sg_alb.ingress).from_port == 80 && length(coalesce(one(aws_security_group.sg_alb.ingress).cidr_blocks, [])) == 0
    error_message = "With CloudFront the ALB must accept port 80 from the CloudFront prefix list only, not from a CIDR"
  }

  assert {
    condition     = aws_wafv2_web_acl.main[0].scope == "CLOUDFRONT"
    error_message = "WAF must be scoped to CloudFront"
  }
}

run "no_cloudfront_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.main) == 0 && length(aws_wafv2_web_acl.main) == 0
    error_message = "CloudFront and WAF are opt-in"
  }
}

run "waf_needs_us_east_1" {
  command = plan

  variables {
    enable_cloudfront = true
    enable_waf        = true
  }

  override_data {
    target = data.aws_region.current
    values = {
      name = "eu-central-1"
    }
  }

  expect_failures = [aws_wafv2_web_acl.main]
}

run "web_instance_monitoring" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.asg_memory_high.namespace == "CWAgent" && length(aws_cloudwatch_log_group.web) == 3
    error_message = "CloudWatch agent memory alarm and three web log groups expected"
  }
}

run "origin_secret_header" {
  command = plan

  variables {
    enable_cloudfront = true
    certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/abc"
  }

  assert {
    condition     = one(aws_lb_listener.alb-listener.default_action).type == "fixed-response"
    error_message = "With CloudFront the ALB default action must be a 403 (only the origin header is served)"
  }

  assert {
    condition     = length(aws_lb_listener_rule.from_cloudfront) == 1 && length(aws_lb_listener.https) == 0
    error_message = "A header rule forwards CloudFront requests; no HTTPS listener behind CloudFront"
  }
}

run "no_origin_rule_without_cloudfront" {
  command = plan

  assert {
    condition     = length(aws_lb_listener_rule.from_cloudfront) == 0 && one(aws_lb_listener.alb-listener.default_action).type == "forward"
    error_message = "Without CloudFront the listener forwards directly"
  }
}

run "waf_logging" {
  command = plan

  variables {
    enable_cloudfront = true
    enable_waf        = true
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].name == "aws-waf-logs-deham9-dev"
    error_message = "WAF log group names must start with aws-waf-logs-"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.main) == 1
    error_message = "WAF logging must be configured with WAF"
  }
}

run "audit_logging_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_flow_log.vpc) == 0 && length(aws_cloudtrail.main) == 0 && length(aws_guardduty_detector.main) == 0
    error_message = "Flow logs, CloudTrail and GuardDuty are opt-in"
  }

  assert {
    condition     = aws_s3_bucket.audit.bucket == "deham9-dev-audit-logs-123456789012"
    error_message = "Audit bucket name must carry the prefix and the account ID"
  }
}

run "audit_logging_enabled" {
  command = plan

  variables {
    enable_flow_logs  = true
    enable_cloudtrail = true
    enable_guardduty  = true
  }

  assert {
    condition     = length(aws_flow_log.vpc) == 1 && length(aws_cloudtrail.main) == 1 && length(aws_guardduty_detector.main) == 1
    error_message = "Flow logs, CloudTrail and GuardDuty must be created when enabled"
  }

  assert {
    condition     = aws_cloudtrail.main[0].enable_log_file_validation && aws_cloudtrail.main[0].is_multi_region_trail
    error_message = "CloudTrail must be multi-region with log file validation"
  }
}

run "object_cache" {
  command = plan

  variables {
    enable_object_cache = true
    cache_node_count    = 2
  }

  assert {
    condition     = aws_elasticache_replication_group.cache[0].transit_encryption_enabled && aws_elasticache_replication_group.cache[0].at_rest_encryption_enabled
    error_message = "The Redis cache must be encrypted in transit and at rest"
  }

  assert {
    condition     = aws_elasticache_replication_group.cache[0].automatic_failover_enabled && aws_elasticache_replication_group.cache[0].multi_az_enabled
    error_message = "Two cache nodes must enable failover across AZs"
  }

  assert {
    condition     = one(aws_security_group.cache[0].ingress).from_port == 6379
    error_message = "Redis must be reachable on 6379 only"
  }
}

run "no_object_cache_by_default" {
  command = plan

  assert {
    condition     = length(aws_elasticache_replication_group.cache) == 0
    error_message = "The object cache is opt-in"
  }
}

run "private_web_tier_needs_nat" {
  command = plan

  variables {
    web_tier_in_private_subnets = true
    enable_nat_gateway          = false
  }

  expect_failures = [aws_autoscaling_group.web]
}

run "private_web_tier_with_nat" {
  command = plan

  variables {
    web_tier_in_private_subnets = true
    enable_nat_gateway          = true
  }

  assert {
    condition     = !aws_instance.instance[0].associate_public_ip_address
    error_message = "Instances in private subnets must not get public IPs"
  }
}
