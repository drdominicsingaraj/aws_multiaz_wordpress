# CloudWatch monitoring
# SNS topic for notifications, alarms on the load balancer, web tier, Aurora and EFS,
# and one dashboard per environment. Metrics need no agent; Aurora error/slow-query logs
# are exported to CloudWatch Logs (see rds.tf) and ALB access logs go to S3 (see s3.tf).

resource "aws_sns_topic" "alarms" {
  name = "${local.prefix}-alarms"

  tags = {
    Name = "${local.prefix}-alarms"
  }
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Retention for the exported Aurora logs. RDS creates these log groups itself once the
# exports are enabled; creating them here first lets Terraform own the retention setting.
resource "aws_cloudwatch_log_group" "aurora" {
  for_each = toset(["error", "slowquery"])

  name              = "/aws/rds/cluster/${local.prefix}-aurora/${each.key}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.prefix}-aurora-${each.key}"
  }
}

# Apache and boot logs from the web instances (written by the CloudWatch agent)
resource "aws_cloudwatch_log_group" "web" {
  for_each = toset(["apache-access", "apache-error", "user-data"])

  name              = "${local.web_log_ns}/${each.key}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.prefix}-web-${each.key}"
  }
}

# ---------- Load balancer ----------

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.prefix}-alb-5xx"
  alarm_description   = "The ALB itself returned 5xx errors"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.application-lb.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${local.prefix}-target-5xx"
  alarm_description   = "WordPress instances returned 5xx errors"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 10
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.application-lb.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.prefix}-unhealthy-hosts"
  alarm_description   = "At least one target is failing ALB health checks"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.application-lb.arn_suffix
    TargetGroup  = aws_lb_target_group.target-group.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "response_time" {
  alarm_name          = "${local.prefix}-response-time"
  alarm_description   = "Average target response time above 2 seconds"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 2
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.application-lb.arn_suffix
  }
}

# ---------- Web tier ----------

resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  alarm_name          = "${local.prefix}-asg-cpu-high"
  alarm_description   = "Average ASG CPU above 85% (the scaling policy targets ${var.cpu_target_value}%)"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}

resource "aws_cloudwatch_metric_alarm" "asg_memory_high" {
  alarm_name          = "${local.prefix}-asg-memory-high"
  alarm_description   = "Average memory use of the web instances above 85% (CloudWatch agent)"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}

# ---------- Aurora ----------

resource "aws_cloudwatch_metric_alarm" "db_cpu_high" {
  alarm_name          = "${local.prefix}-db-cpu-high"
  alarm_description   = "Aurora CPU above 80%"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.auroracluster.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "db_connections_high" {
  alarm_name          = "${local.prefix}-db-connections-high"
  alarm_description   = "Aurora connection count is high for the instance class"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 100
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.auroracluster.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "db_memory_low" {
  alarm_name          = "${local.prefix}-db-memory-low"
  alarm_description   = "Aurora freeable memory below 256 MB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 256 * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.auroracluster.cluster_identifier
  }
}

# ---------- EFS ----------

resource "aws_cloudwatch_metric_alarm" "efs_io_limit" {
  alarm_name          = "${local.prefix}-efs-io-limit"
  alarm_description   = "EFS is close to its General Purpose I/O limit (WordPress file reads will slow down)"
  namespace           = "AWS/EFS"
  metric_name         = "PercentIOLimit"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 90
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress.id
  }
}

# ---------- Dashboard ----------

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.prefix}-wordpress"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "ALB requests and errors"
          region = data.aws_region.current.name
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.application-lb.arn_suffix],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "ALB response time and target health"
          region = data.aws_region.current.name
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.application-lb.arn_suffix, { stat = "Average" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.application-lb.arn_suffix, "TargetGroup", aws_lb_target_group.target-group.arn_suffix, { stat = "Minimum", yAxis = "right" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", aws_lb.application-lb.arn_suffix, "TargetGroup", aws_lb_target_group.target-group.arn_suffix, { stat = "Maximum", yAxis = "right" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "ASG CPU, memory and size"
          region = data.aws_region.current.name
          period = 60
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.web.name, { stat = "Average" }],
            ["CWAgent", "mem_used_percent", "AutoScalingGroupName", aws_autoscaling_group.web.name, { stat = "Average" }],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.web.name, { stat = "Average", yAxis = "right" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Aurora CPU, connections and memory"
          region = data.aws_region.current.name
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.auroracluster.cluster_identifier, { stat = "Average" }],
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", aws_rds_cluster.auroracluster.cluster_identifier, { stat = "Maximum", yAxis = "right" }],
            ["AWS/RDS", "FreeableMemory", "DBClusterIdentifier", aws_rds_cluster.auroracluster.cluster_identifier, { stat = "Minimum", yAxis = "right" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title  = "EFS I/O and throughput"
          region = data.aws_region.current.name
          period = 300
          metrics = [
            ["AWS/EFS", "PercentIOLimit", "FileSystemId", aws_efs_file_system.wordpress.id, { stat = "Average" }],
            ["AWS/EFS", "DataReadIOBytes", "FileSystemId", aws_efs_file_system.wordpress.id, { stat = "Sum", yAxis = "right" }],
            ["AWS/EFS", "DataWriteIOBytes", "FileSystemId", aws_efs_file_system.wordpress.id, { stat = "Sum", yAxis = "right" }],
          ]
        }
      },
      {
        type = "alarm", x = 12, y = 12, width = 12, height = 6
        properties = {
          title = "Alarm status"
          alarms = [
            aws_cloudwatch_metric_alarm.alb_5xx.arn,
            aws_cloudwatch_metric_alarm.target_5xx.arn,
            aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.response_time.arn,
            aws_cloudwatch_metric_alarm.asg_cpu_high.arn,
            aws_cloudwatch_metric_alarm.asg_memory_high.arn,
            aws_cloudwatch_metric_alarm.db_cpu_high.arn,
            aws_cloudwatch_metric_alarm.db_connections_high.arn,
            aws_cloudwatch_metric_alarm.db_memory_low.arn,
            aws_cloudwatch_metric_alarm.efs_io_limit.arn,
          ]
        }
      },
    ]
  })
}
