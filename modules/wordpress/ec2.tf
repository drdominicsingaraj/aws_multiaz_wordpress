# Standalone EC2 instance for WordPress
# Sits in the first public subnet and is attached to the load balancer target group.
# Separate from the ASG instances; set standalone_instance_count = 0 to omit it.
# Boots with the same script as the ASG instances (mounts the shared EFS).
resource "aws_instance" "instance" {
  count = var.standalone_instance_count

  ami                         = local.ami_id
  instance_type               = var.instance_type
  associate_public_ip_address = !var.web_tier_in_private_subnets
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.sg_vpc.id, aws_security_group.allow_ssh.id]
  subnet_id                   = local.web_subnet_ids[0]
  iam_instance_profile        = aws_iam_instance_profile.web.name # SSM + read access to the DB secret (iam.tf)

  tags = {
    Name = "${local.prefix}-wordpress"
    Type = "WordPress-Server"
  }

  # Boot script shared with the ASG instances (mounts the EFS, installs WordPress on first boot)
  user_data = local.web_user_data

  # Require IMDSv2 (session tokens)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Encrypted root volume
  root_block_device {
    encrypted = true
  }

  # A newer AMI must not replace the instance (the ASG instances roll automatically)
  lifecycle {
    ignore_changes = [ami]
  }

  # The EFS mount targets must exist before the instance boots
  depends_on = [aws_efs_mount_target.public-1, aws_efs_mount_target.public-2]

  # Local provisioner to log instance metadata
  provisioner "local-exec" {
    command = "echo Instance Type = ${self.instance_type}, Instance ID = ${self.id}, Public IP = ${self.public_ip}, AMI ID = ${self.ami} >> metadata"
  }
}
