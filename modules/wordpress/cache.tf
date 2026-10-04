# Object cache for WordPress: ElastiCache for Redis (enable_object_cache)
# WordPress keeps query results and options in Redis instead of re-reading the database on
# every request. The boot script installs the Redis Object Cache plugin's drop-in and points
# wp-config.php at the cluster (TLS in transit, encrypted at rest, private subnets only).

resource "aws_elasticache_subnet_group" "cache" {
  count = var.enable_object_cache ? 1 : 0

  name       = "${local.prefix}-cache"
  subnet_ids = [aws_subnet.private-1.id, aws_subnet.private-2.id]
}

# Redis accepts connections from the web tier only
resource "aws_security_group" "cache" {
  count = var.enable_object_cache ? 1 : 0

  name        = "${local.prefix}-cache"
  description = "Redis object cache - from the web tier only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from the web tier"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_vpc.id]
  }

  tags = {
    Name = "${local.prefix}-cache"
  }
}

resource "aws_elasticache_replication_group" "cache" {
  count = var.enable_object_cache ? 1 : 0

  replication_group_id = "${local.prefix}-cache"
  description          = "WordPress object cache for ${local.prefix}"
  engine               = "redis"
  node_type            = var.cache_node_type
  num_cache_clusters   = var.cache_node_count
  port                 = 6379

  # A second node gives automatic failover across the two AZs
  automatic_failover_enabled = var.cache_node_count > 1
  multi_az_enabled           = var.cache_node_count > 1

  subnet_group_name  = aws_elasticache_subnet_group.cache[0].name
  security_group_ids = [aws_security_group.cache[0].id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  apply_immediately = true

  tags = {
    Name = "${local.prefix}-cache"
  }
}
