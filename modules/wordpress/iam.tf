# IAM role for the web instances (ASG and standalone), created here instead of by hand.
# Least privilege: SSM Session Manager (so SSH can stay closed) and read access to the
# one Secrets Manager secret holding the Aurora master password. No S3 access.

data "aws_iam_policy_document" "web_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name               = "${local.prefix}-web-role"
  assume_role_policy = data.aws_iam_policy_document.web_assume.json

  tags = {
    Name = "${local.prefix}-web-role"
  }
}

# Session Manager shell access without opening port 22
resource "aws_iam_role_policy_attachment" "web_ssm" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent: memory/disk metrics and Apache logs
resource "aws_iam_role_policy_attachment" "web_cloudwatch_agent" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Read the generated Aurora master password at boot (wp-config.php)
data "aws_iam_policy_document" "web_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_rds_cluster.auroracluster.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "web_secret" {
  name   = "${local.prefix}-read-db-secret"
  role   = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.web_secret.json
}

resource "aws_iam_instance_profile" "web" {
  name = "${local.prefix}-web-profile"
  role = aws_iam_role.web.name
}
