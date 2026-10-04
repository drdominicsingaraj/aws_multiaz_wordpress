# Auto Scaling Configuration
# Launch template, auto scaling group and scaling policy for the WordPress instances.
# Sizing (min/max/desired, instance type) is set per environment.

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "web" {
  name                   = "${local.prefix}-web-launch-template"
  image_id               = local.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.sg_vpc.id, aws_security_group.allow_ssh.id]
  key_name               = var.key_name

  # 1-minute CloudWatch metrics for the instances (faster scaling decisions)
  monitoring {
    enabled = true
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.web.name # SSM + read access to the DB secret (iam.tf)
  }

  # Boot script: mounts the shared EFS at /var/www/html and serves WordPress from it
  user_data = local.web_user_data

  # Require IMDSv2 (session tokens) so SSRF cannot steal the instance role credentials
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Encrypted root volume
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted             = true
      delete_on_termination = true
    }
  }

  tags = {
    Name = "${local.prefix}-launch-template"
  }

  lifecycle {
    precondition {
      condition     = (var.cpu_architecture == "arm64") == can(regex("^[a-z]+[0-9]+g[a-z]*\\.", var.instance_type))
      error_message = "instance_type ${var.instance_type} does not match cpu_architecture ${var.cpu_architecture} (arm64 needs a Graviton type such as t4g.micro)."
    }
  }
}

# Auto Scaling Group
# Automatically manages the number of EC2 instances based on demand
resource "aws_autoscaling_group" "web" {
  name             = "${local.prefix}-asg"
  max_size         = var.asg_max_size
  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_capacity

  # Deploy across both AZs for high availability (public subnets, or private with web_tier_in_private_subnets)
  vpc_zone_identifier = local.web_subnet_ids

  # Load balancer integration
  target_group_arns         = [aws_lb_target_group.target-group.arn]
  health_check_type         = "ELB" # Use ELB health checks
  health_check_grace_period = 300   # Grace period before health checks start

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version # A new version rolls the instances (see below)
  }

  # Replace instances gradually when the launch template changes (new AMI, boot script, ...)
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 80
      instance_warmup        = 300
    }
  }

  # Scheduled actions and target tracking change the desired capacity at runtime
  lifecycle {
    ignore_changes = [desired_capacity]

    precondition {
      condition     = !var.web_tier_in_private_subnets || var.enable_nat_gateway
      error_message = "web_tier_in_private_subnets needs enable_nat_gateway = true: the instances must reach the internet (WordPress download), SSM and Secrets Manager."
    }
  }

  # Instances mount EFS at boot, so the mount targets must exist first
  depends_on = [aws_efs_mount_target.public-1, aws_efs_mount_target.public-2]

  tag {
    key                 = "Name"
    value               = "${local.prefix}-asg-instance"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy
# Keeps average CPU across the group near the target. It can only scale out when
# asg_max_size is greater than asg_min_size.
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${local.prefix}-cpu-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.web.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}

# Scale with traffic as well as CPU: keeps the request rate per instance near the target.
# (CPU alone is a weak signal on burstable instances.)
resource "aws_autoscaling_policy" "requests" {
  name                   = "${local.prefix}-request-count-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.web.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.application-lb.arn_suffix}/${aws_lb_target_group.target-group.arn_suffix}"
    }
    target_value = var.request_count_target
  }

  depends_on = [aws_lb_listener.alb-listener]
}

# Optional off-hours schedule (non-production): fewer instances at night and on weekends.
# Applying Terraform while scaled down resets min_size to the configured value.
resource "aws_autoscaling_schedule" "scale_down" {
  count = var.enable_off_hours_schedule ? 1 : 0

  scheduled_action_name  = "${local.prefix}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.web.name
  recurrence             = var.off_hours_scale_down_cron
  time_zone              = "UTC"
  min_size               = var.off_hours_capacity
  max_size               = var.asg_max_size
  desired_capacity       = var.off_hours_capacity
}

resource "aws_autoscaling_schedule" "scale_up" {
  count = var.enable_off_hours_schedule ? 1 : 0

  scheduled_action_name  = "${local.prefix}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.web.name
  recurrence             = var.off_hours_scale_up_cron
  time_zone              = "UTC"
  min_size               = var.asg_min_size
  max_size               = var.asg_max_size
  desired_capacity       = var.asg_desired_capacity
}
