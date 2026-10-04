# Shared WordPress file storage
# One EFS file system holds the WordPress files (/var/www/html). Every ASG instance
# mounts it at boot (see userdatalaunchtemplate.tpl), so all instances serve the same
# code, themes, plugins and uploads, and new instances need no copy step.

resource "aws_efs_file_system" "wordpress" {
  creation_token = "${local.prefix}-wordpress-efs"
  encrypted      = true

  # Pay for the throughput actually used; WordPress reads many small files
  throughput_mode = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS" # Move cold files to cheaper Infrequent Access storage
  }

  tags = {
    Name = "${local.prefix}-wordpress-efs"
  }
}

# Security group for the mount targets: NFS (2049) from the web tier only
resource "aws_security_group" "efs" {
  name        = "${local.prefix}-efs"
  description = "Allow NFS from the web tier to the WordPress EFS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS from the web tier"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_vpc.id]
  }

  tags = {
    Name = "${local.prefix}-efs"
  }
}

# One mount target per AZ, in the public subnets where the web instances run
resource "aws_efs_mount_target" "public-1" {
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.public-1.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "public-2" {
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.public-2.id
  security_groups = [aws_security_group.efs.id]
}

# Automatic AWS Backup of the WordPress files (recover from a bad plugin update or a deletion)
resource "aws_efs_backup_policy" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id

  backup_policy {
    status = "ENABLED"
  }
}

# Resource policy: clients may mount and write, but only over TLS
data "aws_iam_policy_document" "efs" {
  statement {
    sid       = "AllowMountOverTLS"
    effect    = "Allow"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite", "elasticfilesystem:ClientRootAccess"]
    resources = [aws_efs_file_system.wordpress.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["true"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["*"]
    resources = [aws_efs_file_system.wordpress.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_efs_file_system_policy" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id
  policy         = data.aws_iam_policy_document.efs.json
}
