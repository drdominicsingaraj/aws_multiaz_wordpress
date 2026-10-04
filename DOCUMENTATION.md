# Scalable and Fault-Tolerant WordPress on AWS

## Overview

Terraform code that deploys a highly available, scalable WordPress site on AWS in `us-east-1`. One shared module (`modules/wordpress`) is used by three environments (`dev`, `test`, `prod`), each with its own state, variables and VPC, so all three can live side by side in one AWS account.

The site is served by CloudFront (HTTPS, edge cache, WAF) in front of an Application Load Balancer, which feeds an Auto Scaling Group of Graviton web servers in two Availability Zones. WordPress files live on a shared EFS file system, data in an Aurora MySQL cluster, and sessions/objects are cached in ElastiCache Redis. There is no application code in this repository: WordPress is downloaded and installed by the instances on first boot.

## Architecture

### Diagrams

Generated from each environment's `terraform.tfvars` by `python docs/gen_diagrams.py`; rerun it after changing sizes or flags (CI fails if the SVGs are stale).

- All environments side by side, with a comparison table: [static](docs/architecture-all-environments.svg) and [animated](docs/architecture-all-environments-animated.svg)
- Per environment: dev ([static](docs/architecture-dev.svg), [animated](docs/architecture-dev-animated.svg)), test ([static](docs/architecture-test.svg), [animated](docs/architecture-test-animated.svg)), prod ([static](docs/architecture-prod.svg), [animated](docs/architecture-prod-animated.svg))

The animated versions make the arrows flow and send dots along the request path (Internet, CloudFront, ALB, web instances, then Aurora, Redis, EFS and the log bucket); the instance boxes and the CloudWatch box pulse. Animation is plain CSS and SVG, works in browsers and in GitHub's image rendering, and is switched off for visitors who prefer reduced motion. Use the static files for slides and PDFs.

![All environments (animated)](docs/architecture-all-environments-animated.svg)

### Traffic flow

1. User -> CloudFront (HTTPS, WAF in test/prod, edge cache for `/wp-content` and `/wp-includes`) -> ALB over HTTP, with a secret header. Without CloudFront (`enable_cloudfront = false`): User -> Internet Gateway -> ALB (HTTP :80, or HTTPS :443 with `certificate_arn`).
2. ALB -> web instances on port 80 (health checks and load distribution). Only the ALB security group can reach them. Dev also has one standalone EC2.
3. Web instances -> EFS (NFS 2049, TLS): `/var/www/html` is the shared file system, mounted at boot.
4. Web instances -> Aurora MySQL (3306) and Redis (6379, TLS) in the private subnets.
5. Private subnets -> NAT gateway -> internet: only when `enable_nat_gateway = true` (false in every environment, so the private subnets have no internet route).
6. Logs: ALB access logs -> S3 (alb-logs bucket); CloudFront access logs and VPC Flow Logs -> S3 (audit-logs bucket); WAF request log, Apache logs and Aurora logs -> CloudWatch Logs. Metrics from the ALB, ASG, instances, Aurora and EFS -> CloudWatch alarms -> SNS topic.

### Security groups

| Group | Rules |
|---|---|
| `sg_alb` | With CloudFront: HTTP 80 from the CloudFront origin-facing prefix list only. Without: 80/443 from `CIDR_BLOCK`. Egress 80 to the VPC. |
| `sg_vpc` (web tier) | HTTP 80 from `sg_alb` only. Egress 443 (anywhere), 2049 and 3306 (VPC CIDR), 6379 (VPC CIDR, with the cache). |
| `allow_ssh` | SSH 22 from `ssh_cidr_blocks`. Empty by default = no rule at all (use SSM Session Manager). No egress rule. |
| `efs` | NFS 2049 from `sg_vpc` only. |
| `allow_aurora_access` | MySQL 3306 from `sg_vpc` (plus `CIDR_BLOCK` only if `db_publicly_accessible`, default false). |
| `cache` | Redis 6379 from `sg_vpc` only. |

### Environments

| | dev | test | prod |
|---|---|---|---|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| Web instance type | t4g.micro (arm64) | t4g.micro (arm64) | t4g.small (arm64) |
| Standalone EC2 | 1 | 0 | 0 |
| ASG min / desired / max | 5 / 5 / 6 | 5 / 5 / 6 | 5 / 5 / 6 |
| Off-hours scale down | yes | yes | no |
| Aurora | 1 x db.t3.small | 2 x db.t3.small | 2 x db.t3.medium |
| Backup retention | 1 day | 3 days | 14 days |
| Deletion protection | off | off | on (final snapshot) |
| Redis object cache | 1 node | 1 node | 2 nodes, failover |
| CloudFront | on | on | on |
| WAF | off | on | on |
| SSH (port 22) | closed, use SSM | closed, use SSM | closed, use SSM |
| NAT gateway | off | off | off |
| VPC Flow Logs | on | on | on |
| CloudTrail + GuardDuty (account level) | off | off | on |
| Log / alarm retention | 14 days | 30 days | 90 days |

### Network

- **Availability Zones**: us-east-1a and us-east-1b.
- **Subnets** (`cidrsubnet(vpc_cidr, 8, n)`), shown for dev: public 1 `10.0.1.0/24` (1a), private 1 `10.0.2.0/24` (1a), public 2 `10.0.3.0/24` (1b), private 2 `10.0.4.0/24` (1b).
- **Route tables**: public goes to the internet gateway; private gets a default route through the NAT gateway only when `enable_nat_gateway` is true.
- The web tier runs in the public subnets with public IPs. `web_tier_in_private_subnets` moves it to the private subnets; it needs `enable_nat_gateway = true` (WordPress download, SSM, Secrets Manager), so it is off. A precondition on the ASG rejects the combination without NAT.

## Components

### Compute (`auto_scaling.tf`, `ec2.tf`, `iam.tf`)

- **Launch template** `<prefix>-web-launch-template`: IMDSv2 required, encrypted root volume, IAM instance profile `<prefix>-web-profile`, key pair `deham9-iam`.
- **AMI**: the latest Amazon Linux 2023 for `cpu_architecture` (SSM public parameter), so new instances are always patched. Set `ami_id` to pin one. All environments run Graviton (`arm64`, t4g types); a launch-template precondition rejects an instance type that does not match the architecture.
- **ASG** `<prefix>-asg`: both AZs, attached to the ALB target group, ELB health checks with a 300 s grace period. The target group accepts 200-399 on `/` because a fresh WordPress redirects to its installer.
- **Scaling**: two target-tracking policies, average CPU (`cpu_target_value`, 70) and ALB requests per instance per minute (`request_count_target`, 1000). It can only scale out when max > min. `desired_capacity` is ignored after creation because scaling changes it at runtime.
- **Off-hours schedule** (`enable_off_hours_schedule`, dev and test): scales to `off_hours_capacity` (1) at 19:00 UTC and on weekends, back up at 06:00 UTC Mon-Fri. Applying Terraform while scaled down resets `min_size`.
- **Instance refresh**: the ASG uses the launch template's latest version with a rolling refresh (80% healthy), so a new AMI, boot script or instance type replaces running instances gradually.
- **Standalone EC2** (optional, `standalone_instance_count`, dev): sits in public-1, same boot script, security groups, IAM profile, IMDSv2 and encrypted root volume as the ASG instances; attached to the target group. Its AMI is in `ignore_changes`.
- **IAM** (`iam.tf`): role `<prefix>-web-role` with `AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy` and `secretsmanager:GetSecretValue` on the one Aurora secret. No S3 access.

### Boot script (`userdatalaunchtemplate.tpl`)

Runs on every web instance:

1. Install Apache, PHP, the MariaDB client, `amazon-efs-utils` and the CloudWatch agent.
2. Mount the EFS at `/var/www/html` over TLS (and add it to `/etc/fstab`).
3. If `wp-config.php` is missing, the first instance to take an atomic lock (`mkdir .init-lock`) installs WordPress:
   - downloads WordPress onto the EFS;
   - creates a dedicated database user `wordpress` with a random password (the RDS master password rotates about every 7 days, so WordPress never uses it);
   - writes `wp-config.php` with that user, freshly generated authentication keys and salts, proxy settings (trusts the forwarded protocol, builds `WP_HOME`/`WP_SITEURL` from the requested host) and, if enabled, the Redis settings plus the Redis Object Cache drop-in; the file is moved into place last so a half-finished install is never mistaken for a complete one.
   Other instances wait. A lock older than 10 minutes (an instance that died mid-install) is taken over, and a failed install is retried.
4. Start Apache and the CloudWatch agent.

The master password is read from Secrets Manager only during that first install, and the boot log never contains passwords. Every instance then serves identical code, plugins, themes and uploads, and a replacement instance needs no copy step. The instances need outbound internet (public IPs) to download WordPress the first time.

### Load balancing (`elb.tf`)

Internet-facing ALB `<prefix>-alb` across both public subnets, HTTP :80 (HTTPS :443 with `certificate_arn`, when CloudFront is off), invalid header fields dropped, target group `<prefix>-tg`, deletion protection follows `deletion_protection`. With CloudFront the listener answers 403 to everything except requests carrying the secret `X-Origin-Verify` header (a listener rule forwards those).

### Edge: CloudFront and WAF (`cloudfront.tf`)

- **CloudFront** (`enable_cloudfront`, all environments) serves the site over HTTPS on its `*.cloudfront.net` name, so no domain or certificate is needed. HTTP is redirected to HTTPS. Pages, `wp-admin` and logins are never cached; `/wp-content/*` and `/wp-includes/*` are cached at the edge. Open the site with the `site_url` output.
- The ALB accepts port 80 from the CloudFront prefix list only, and only with the secret header (a generated 40-character `random_password`), so another CloudFront distribution cannot reach WordPress through the ALB.
- **WAF** (`enable_waf`, test and prod): AWS managed rule groups (common, known bad inputs, SQL injection) plus a per-IP rate limit (`waf_rate_limit`, 2000 requests per 5 minutes). Must be in us-east-1 (checked by a precondition). Request log in the CloudWatch Logs group `aws-waf-logs-<prefix>` with authorization and cookie headers redacted.
- Custom domain: set `cloudfront_aliases` and `cloudfront_certificate_arn` (ACM certificate in us-east-1).

### Database (`rds.tf`)

Aurora MySQL cluster `<prefix>-aurora` in the private subnets, database `auroradb`, admin user `admin`, `db_instance_count` instances alternating over the AZs, storage encrypted. The engine is the latest Aurora MySQL 3 (MySQL 8.0 compatible) release unless `db_engine_version` pins one. The master password is generated and rotated by AWS in Secrets Manager (`db_master_secret_arn` output). Error and slow-query logs are exported to CloudWatch Logs. Prod has deletion protection and a final snapshot.

### Shared WordPress storage: EFS (`efs.tf`)

Encrypted EFS `<prefix>-wordpress-efs` with elastic throughput, files untouched for 30 days move to Infrequent Access, automatic backups, and a resource policy that allows mounting only over TLS. One mount target per public subnet, guarded by the `efs` security group.

### Object cache: ElastiCache Redis (`cache.tf`)

`enable_object_cache` (all environments): replication group `<prefix>-cache` in the private subnets, encrypted at rest and in transit (TLS), reachable on 6379 from the web tier only; with 2 nodes it fails over to the other AZ. If the plugin download fails at first boot, the site simply runs without the cache.

### Logging

- **ALB log bucket** (`s3.tf`) `<prefix>-alb-logs-<account id>`: ALB access logs under `alb/`, public access blocked, SSE-S3, versioning, a bucket policy for the regional ELB service account, expiry after `log_retention_days`.
- **Audit bucket** (`audit.tf`) `<prefix>-audit-logs-<account id>`: CloudFront access logs (`cloudfront/`), VPC Flow Logs (`vpc-flow/`, `enable_flow_logs`) and CloudTrail (`cloudtrail/`, `enable_cloudtrail`). Public access blocked, SSE-S3, TLS-only, expiry after `log_retention_days`. ACLs stay enabled (`BucketOwnerPreferred`) because CloudFront standard logging delivers through a bucket ACL.
- `force_destroy_log_bucket` lets Terraform delete the buckets while they contain objects (true in dev and test, false in prod).
- **CloudTrail** (multi-region, log file validation) and **GuardDuty** are account-level: enabled in prod only. GuardDuty allows a single detector per account and region, so a second environment enabling it fails (import an existing detector or leave the flag off).

### Monitoring: CloudWatch (`monitoring.tf`)

- **SNS topic** `<prefix>-alarms` receives every alarm and recovery notification. Set `alarm_email` in `terraform.tfvars` to subscribe an address (AWS sends a confirmation email).
- **Alarms** (10; missing data counts as OK):

| Alarm | Metric | Fires when |
|---|---|---|
| `<prefix>-alb-5xx` | ALB `HTTPCode_ELB_5XX_Count` | sum >= 5 for 3 minutes |
| `<prefix>-target-5xx` | `HTTPCode_Target_5XX_Count` | sum >= 10 for 3 minutes |
| `<prefix>-unhealthy-hosts` | `UnHealthyHostCount` | >= 1 for 3 minutes |
| `<prefix>-response-time` | `TargetResponseTime` | average > 2 s for 5 minutes |
| `<prefix>-asg-cpu-high` | EC2 `CPUUtilization` of the ASG | average > 85% for 5 minutes |
| `<prefix>-asg-memory-high` | CWAgent `mem_used_percent` | average > 85% for 5 minutes |
| `<prefix>-db-cpu-high` | Aurora `CPUUtilization` | average > 80% for 5 minutes |
| `<prefix>-db-connections-high` | `DatabaseConnections` | > 100 for 5 minutes |
| `<prefix>-db-memory-low` | `FreeableMemory` | < 256 MB for 5 minutes |
| `<prefix>-efs-io-limit` | EFS `PercentIOLimit` | > 90% for 15 minutes |

- **Dashboard** `<prefix>-wordpress`: ALB requests and errors, response time and target health, ASG CPU/memory/size, Aurora CPU/connections/memory, EFS I/O and alarm status (`dashboard_url` output).
- **Instances**: detailed 1-minute EC2 monitoring and the CloudWatch agent (memory and disk metrics in namespace `CWAgent`; Apache access/error logs and the boot log in `/<prefix>/web/apache-access`, `apache-error`, `user-data`).
- **Aurora logs**: `/aws/rds/cluster/<prefix>-aurora/error` and `.../slowquery`.
- All log groups are kept `log_retention_days`.

### Networking (`network.tf`)

VPC, two public and two private /24 subnets, internet gateway and route tables. The NAT gateway and its Elastic IP exist only when `enable_nat_gateway = true`.

## Security

| Area | Control |
|---|---|
| Network exposure | Only the ALB security group takes web traffic (from CloudFront only, with the secret header). The web tier accepts port 80 from the ALB only; Aurora, Redis and EFS accept connections from the web tier only. |
| Egress | Web instances may only send 443 (any), 2049, 3306 and 6379 (inside the VPC). The ALB sends 80 to the VPC. |
| Administration | Port 22 is closed. Use SSM Session Manager (`aws ssm start-session --target <instance-id>`). Add a CIDR to `ssh_cidr_blocks` to open SSH. |
| Database | Private subnets, never publicly accessible, storage encrypted, master password generated by AWS in Secrets Manager (never in code). WordPress uses its own database user and unique keys and salts. |
| IAM | One least-privilege role per environment, created by Terraform. |
| Instances | IMDSv2 required (hop limit 1), encrypted root volumes, latest patched AMI. |
| Storage | EFS encrypted, TLS-only mounts, automatic backups. Redis encrypted at rest and in transit. |
| Transport | HTTPS enforced at CloudFront (HTTP redirects). |
| Edge | WAF managed rules and rate limit (test, prod). |
| Audit | VPC Flow Logs everywhere; CloudTrail and GuardDuty in prod; ALB, CloudFront and WAF request logs. |
| Log buckets | Public access blocked, SSE-S3, TLS-only, expiry. |
| Terraform state | `bootstrap/` creates a versioned, encrypted, TLS-only S3 bucket and a DynamoDB lock table; environments opt in through `backend.tf`. |

Do not set `db_publicly_accessible = true`. If a database password was ever committed to git, rotate it.

## Outputs

Run `terraform output` in an environment directory. Main groups:

- **Site**: `site_url`, `cloudfront_domain_name`, `cloudfront_distribution_id`, `waf_web_acl_arn`, `alb_dns_name`, `alb_url`, `alb_arn`, `alb_zone_id`, `listener_arn`, `https_listener_arn`, `target_group_arn`.
- **Compute**: `asg_name`, `asg_arn`, `launch_template_id`, `scaling_policy_name`, `ami_id`, `standalone_instance_ids`, `standalone_instance_private_ips`, `public_ip`.
- **Network**: `vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_subnet_ids`, `internet_gateway_id`, `nat_gateway_id`, `nat_public_ip`, route table IDs.
- **Security**: security group IDs, `web_role_arn`, `web_instance_profile_name`.
- **Data**: `db_endpoint`, `db_reader_endpoint`, `db_cluster_id`, `db_cluster_arn`, `db_port`, `db_name`, `db_instance_ids`, `db_subnet_group_name`, `db_master_secret_arn`, `efs_*`, `cache_endpoint`.
- **Logging and monitoring**: `log_bucket`, `log_bucket_arn`, `alb_log_prefix`, `audit_bucket`, `flow_log_id`, `cloudtrail_arn`, `guardduty_detector_id`, `waf_log_group`, `sns_topic_arn`, `dashboard_name`, `dashboard_url`, `alarm_names`, `aurora_log_group_names`.

## File structure

```text
.
├── environments/
│   └── dev|test|prod/
│       ├── main.tf              # calls modules/wordpress
│       ├── variables.tf
│       ├── terraform.tfvars     # environment-specific values (no secrets)
│       ├── providers.tf         # region and default tags
│       ├── outputs.tf
│       └── backend.tf           # opt-in S3 backend (local state by default)
├── modules/wordpress/
│   ├── network.tf               # VPC, subnets, IGW, optional NAT, route tables
│   ├── sg.tf                    # security groups
│   ├── iam.tf                   # web instance role and profile
│   ├── auto_scaling.tf          # launch template, ASG, scaling policies, schedule
│   ├── ec2.tf                   # optional standalone instance
│   ├── elb.tf                   # ALB, target group, listeners
│   ├── cloudfront.tf            # CloudFront distribution, WAF, origin secret
│   ├── rds.tf                   # Aurora cluster and instances
│   ├── efs.tf                   # shared WordPress file system
│   ├── cache.tf                 # ElastiCache Redis
│   ├── s3.tf                    # ALB log bucket
│   ├── audit.tf                 # audit bucket, VPC Flow Logs, CloudTrail, GuardDuty
│   ├── monitoring.tf            # SNS, alarms, dashboard, log groups
│   ├── locals.tf, variables.tf, outputs.tf, versions.tf
│   ├── userdatalaunchtemplate.tpl   # boot script for all web instances
│   └── tests/infrastructure.tftest.hcl
├── bootstrap/                   # one-off: S3 state bucket + DynamoDB lock table
├── docs/                        # architecture diagrams (SVG) and gen_diagrams.py
├── .github/workflows/           # CI
├── deploy.sh, deploy.ps1        # run one environment by argument
├── load-test.sh, locustfile.py  # load testing
└── README.md, DOCUMENTATION.md, CLAUDE.md
```

## Prerequisites

- Terraform >= 1.7, AWS CLI v2, and AWS credentials able to create the resources above (VPC, EC2, ELB, Auto Scaling, RDS, EFS, ElastiCache, S3, IAM roles, CloudFront, WAF, CloudWatch, SNS, CloudTrail, GuardDuty, Secrets Manager, SSM read).
- An EC2 key pair named `deham9-iam` in `us-east-1` (`aws ec2 describe-key-pairs --key-names deham9-iam`). Nothing else has to exist: the IAM role and instance profile are created by Terraform.
- For load tests: Apache Bench (`ab`) or Locust. For the diagrams: Python 3.
- The environments must run in `us-east-1` (WAF for CloudFront requirement).

## Deploying

```text
./deploy.sh dev init           # Git Bash / WSL
./deploy.sh dev plan
./deploy.sh dev apply
.\deploy.ps1 -Environment dev -Action apply    # PowerShell
```

Arguments: `<dev|test|prod> <init|plan|apply|destroy|output|validate>`; extra arguments go to Terraform. Or run Terraform directly in `environments/<env>`.

1. Review `terraform.tfvars` (optionally set `alarm_email`).
2. `terraform apply`. Expect roughly 15-25 minutes: Aurora and ElastiCache take the longest, CloudFront a few minutes.
3. `terraform output site_url` and open it. The first visit shows the WordPress installer; complete it. During the first minutes the instances install WordPress onto the EFS.
4. Check the dashboard (`dashboard_url`) and confirm the SNS email subscription if `alarm_email` is set.

Optional remote state: run `bootstrap/` once per account (`terraform init && terraform apply`), put its `backend_snippet` output into `environments/<env>/backend.tf` and run `terraform init -migrate-state`. State holds the generated origin secret, so keep the bucket private.

## Operations

- **Shell access**: `aws ssm start-session --target <instance-id>`. Boot log: `/var/log/user-data.log`; Apache logs and metrics are also in CloudWatch.
- **Database password**: the master secret rotates automatically; WordPress is unaffected because it uses its own user. Read the master secret from `db_master_secret_arn` if you need admin access.
- **Updates**: change the launch template inputs (AMI, instance type, boot script) and apply; the instance refresh replaces instances gradually. WordPress core, plugins and themes are updated from the WordPress admin and apply to all instances because they live on the EFS.
- **Backups and restore**: Aurora automated backups (`db_backup_retention_days`) and a final snapshot in prod; EFS backups through AWS Backup (restore from the AWS Backup console).
- **Scaling**: adjust `asg_*`, `cpu_target_value` and `request_count_target`. The off-hours schedule applies to dev and test.
- **Custom domain**: request an ACM certificate in us-east-1, set `cloudfront_aliases` and `cloudfront_certificate_arn`, and point a CNAME/alias at the distribution.
- **Alarms**: acknowledge via the SNS email; see the alarm table above for thresholds.

### Load testing

```text
./load-test.sh <env>                                      # ab for 5 minutes plus ASG/CloudWatch monitoring
locust -f locustfile.py --host=https://<site_url domain>  # add --users/--spawn-rate/--run-time/--headless
```

`load-test.sh` targets the CloudFront domain (or `TARGET_URL`). Dynamic pages are not cached, so the load reaches the instances. The WAF rate limit (test, prod) blocks a single IP at high request rates; expect 403 responses in heavy tests from one machine.

## Testing and CI

- Unit tests: `cd modules/wordpress && terraform init -backend=false && terraform test`. They use a mocked AWS provider (no credentials) and `command = plan`, so values only known after apply cannot be asserted.
- Formatting: `terraform fmt -recursive`.
- GitHub Actions (`.github/workflows/terraform.yml`): format check, unit tests, `terraform validate` for each environment and `bootstrap/`, a Checkov scan (reporting only), and a check that `docs/*.svg` match `gen_diagrams.py`.

## Cost estimate (approximate)

On-demand us-east-1 list prices, 730 hours a month, low traffic; check the AWS Pricing Calculator for real numbers.

| Item | dev | test | prod |
|---|---|---|---|
| Web instances (t4g) | ~$16 (off-hours scale down) | ~$16 | ~$61 |
| Standalone EC2 | ~$6 | - | - |
| Public IPv4 addresses ($0.005/h each) | ~$13 | ~$9 | ~$18 |
| Aurora instances | ~$30 | ~$60 | ~$120 |
| ALB (incl. its addresses) | ~$27 | ~$27 | ~$27 |
| ElastiCache | ~$12 | ~$12 | ~$23 |
| WAF | - | ~$10 | ~$10 |
| CloudWatch, SNS, Secrets Manager, EFS, EBS | ~$12 | ~$12 | ~$15 |
| CloudFront, S3, CloudTrail, GuardDuty | ~$2 | ~$2 | ~$15 |
| **Total (rounded)** | **~$120** | **~$145** | **~$290** |

Biggest levers: ASG size (5 instances everywhere), Aurora instance count and class, public IPv4 addresses (moving to private subnets removes them but adds NAT cost), and the Redis nodes. Dev and test already scale down outside working hours; `terraform destroy` removes an environment completely.

## Troubleshooting

- **Targets unhealthy / 502 from CloudFront**: check `/var/log/user-data.log` (via SSM). Usual causes: EFS not mounted (security group or mount target), no outbound internet to download WordPress, or the database user creation failed. The ASG replaces instances that stay unhealthy.
- **Site shows the installer on every instance**: `wp-config.php` was not written; look for "WordPress install failed" in the boot log. A stale `.init-lock` older than 10 minutes is taken over automatically.
- **403 from the ALB address**: expected, the ALB only serves requests from CloudFront. Use `site_url`.
- **403 during a load test**: the WAF rate limit; use a smaller test or `enable_waf = false` in a test environment.
- **Cannot connect to Aurora from your machine**: it is private by design; connect from an instance through SSM with the master secret.
- **GuardDuty apply error "detector already exists"**: set `enable_guardduty = false` or import the existing detector.
- **Plan wants to replace instances after an AMI release**: expected; the instance refresh does it gradually.

## Cleanup

```text
./deploy.sh <env> destroy
```

Destroy removes the environment's resources. S3 buckets are deleted even when not empty only where `force_destroy_log_bucket` is true (dev, test); prod keeps deletion protection on the ALB and Aurora, so disable `deletion_protection` and apply before destroying prod. CloudFront deletion takes several minutes. The `bootstrap/` bucket has `prevent_destroy` on purpose.

## Known limitations

- The web tier runs in public subnets (needs the NAT gateway for private subnets, which is off by choice).
- CloudTrail and GuardDuty are account-wide and only enabled in prod.
- No alarms yet on the cache or on WAF blocks.
- The code has not been applied to a real account in this repository's history; review the first `apply` carefully, especially the audit bucket ACLs, the WAF log policy and the Redis plugin download.
