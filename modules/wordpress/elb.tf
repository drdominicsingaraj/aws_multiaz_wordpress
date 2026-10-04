# Application Load Balancer Configuration
# Creates an ALB with target group and listener for distributing traffic to EC2 instances

# Target group for load balancer
# Defines the targets (EC2 instances) that the load balancer will route traffic to
resource "aws_lb_target_group" "target-group" {
  name        = "nit-tg"
  port        = 80         # Port that targets receive traffic on
  protocol    = "HTTP"     # Protocol for routing requests
  target_type = "instance" # Target type (instance, IP, or lambda)
  vpc_id      = aws_vpc.dev_vpc.id

  tags = {
    Name = "deham9-target-group"
  }

  # Health check configuration
  # ALB uses these settings to determine if targets are healthy
  health_check {
    enabled             = true
    interval            = 10             # Health check interval in seconds
    path                = "/"            # Health check path
    port                = "traffic-port" # Use the same port as target
    protocol            = "HTTP"
    timeout             = 5 # Health check timeout
    healthy_threshold   = 2 # Consecutive successful checks to mark healthy
    unhealthy_threshold = 2 # Consecutive failed checks to mark unhealthy
  }
}

# Application Load Balancer
# Distributes incoming traffic across multiple EC2 instances for high availability
resource "aws_lb" "application-lb" {
  name               = "nit-alb"
  internal           = false                                            # Internet-facing ALB
  load_balancer_type = "application"                                    # Application Load Balancer
  subnets            = [aws_subnet.public-1.id, aws_subnet.public-2.id] # Deploy across public subnets
  security_groups    = [aws_security_group.sg_vpc.id]                   # Security group for ALB
  ip_address_type    = "ipv4"                                           # IPv4 addressing

  tags = {
    Name = "deham9-application-lb"
  }
}

# Load balancer listener
# Defines how the ALB listens for requests and routes them to targets
resource "aws_lb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.application-lb.arn
  port              = "80"   # Listen on port 80 (HTTP)
  protocol          = "HTTP" # HTTP protocol

  # Default action - forward traffic to target group
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