# test environment: calls the shared WordPress module with this environment's values.
module "wordpress" {
  source = "../../modules/wordpress"

  project     = var.project
  environment = var.environment

  # Network
  vpc_cidr           = var.vpc_cidr
  azs                = var.azs
  CIDR_BLOCK         = var.CIDR_BLOCK
  ssh_cidr_blocks    = var.ssh_cidr_blocks
  enable_nat_gateway = var.enable_nat_gateway
  certificate_arn    = var.certificate_arn

  # Compute
  ami_id                    = var.ami_id
  cpu_architecture          = var.cpu_architecture
  instance_type             = var.instance_type
  key_name                  = var.key_name
  standalone_instance_count = var.standalone_instance_count

  # Edge
  enable_cloudfront          = var.enable_cloudfront
  enable_waf                 = var.enable_waf
  cloudfront_aliases         = var.cloudfront_aliases
  cloudfront_certificate_arn = var.cloudfront_certificate_arn

  # Cost: scale down outside working hours
  enable_off_hours_schedule = var.enable_off_hours_schedule
  off_hours_capacity        = var.off_hours_capacity

  # Audit, security and performance
  enable_flow_logs            = var.enable_flow_logs
  enable_cloudtrail           = var.enable_cloudtrail
  enable_guardduty            = var.enable_guardduty
  enable_object_cache         = var.enable_object_cache
  cache_node_type             = var.cache_node_type
  cache_node_count            = var.cache_node_count
  web_tier_in_private_subnets = var.web_tier_in_private_subnets

  # Auto scaling
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity

  # Database
  db_instance_class        = var.db_instance_class
  db_instance_count        = var.db_instance_count
  db_backup_retention_days = var.db_backup_retention_days
  db_publicly_accessible   = var.db_publicly_accessible

  # Protection
  deletion_protection      = var.deletion_protection
  force_destroy_log_bucket = var.force_destroy_log_bucket

  # Monitoring and logging
  log_retention_days = var.log_retention_days
  alarm_email        = var.alarm_email
}
