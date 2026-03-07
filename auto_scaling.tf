# Auto Scaling Configuration
# Creates launch template, auto scaling group, and scaling policies for WordPress instances

# Commented out AMI data source and user data template
# These are alternatives to the current configuration
# data "aws_ami" "amzLinux" {
#   most_recent = true
#   owners = ["amazon"]
#   filter {
#     name = "name"
#     values = ["al2023-ami-2023*x86_64"]
#   }
# }

# data "template_file" "userdatatemplate" {
#   template = file("userdatalaunchtemplate.tpl")
# }

# output "rendered" {
#   value = data.template_file.userdatatemplate.rendered
# }

# Launch Template for Auto Scaling Group
# Defines the configuration for instances launched by the auto scaling group
resource "aws_launch_template" "dev-launch-template" {
  name                   = "WebserverLaunchTemplate"
  image_id               = "ami-05c9d06873bde2328"        # Amazon Linux 2023 AMI
  instance_type          = "t2.micro"                     # Free tier eligible instance type
  vpc_security_group_ids = [aws_security_group.sg_vpc.id] # Security group for instances
  key_name               = "deham9-iam"                   # SSH key pair for access

  # User data script for instance initialization
  # Currently commented out - uncomment to enable automated setup
  # user_data = base64encode(data.template_file.userdatatemplate.rendered)

  tags = {
    Name = "deham9-launch-template"
  }
}

# Auto Scaling Group
# Automatically manages the number of EC2 instances based on demand
resource "aws_autoscaling_group" "dev-AutoScalingGroup" {
  name             = "awsrestart-autoscaling-group"
  max_size         = 2 # Maximum number of instances
  min_size         = 2 # Minimum number of instances
  desired_capacity = 2 # Desired number of instances

  # Network configuration - deploy across public subnets for high availability
  vpc_zone_identifier = [aws_subnet.public-1.id, aws_subnet.public-2.id]

  # Load balancer integration
  target_group_arns         = [aws_lb_target_group.target-group.arn]
  health_check_type         = "ELB" # Use ELB health checks
  health_check_grace_period = 300   # Grace period before health checks start

  # Launch template configuration
  launch_template {
    id      = aws_launch_template.dev-launch-template.id
    version = "$Latest" # Always use latest version
  }

  tags = [
    {
      key                 = "Name"
      value               = "deham9-asg-instance"
      propagate_at_launch = true
    }
  ]
}

# Auto Scaling Policy
# Defines when and how the auto scaling group should scale instances
resource "aws_autoscaling_policy" "dev_policy" {
  name                   = "CPUpolicy"
  policy_type            = "TargetTrackingScaling" # Target tracking scaling policy
  autoscaling_group_name = aws_autoscaling_group.dev-AutoScalingGroup.name

  # Target tracking configuration
  # Automatically adjusts capacity to maintain target CPU utilization
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization" # Track average CPU across instances
    }
    target_value = 70.0 # Target 70% CPU utilization
  }
}