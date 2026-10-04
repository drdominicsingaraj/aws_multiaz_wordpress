# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Terraform (AWS provider `~> 5.0`, random provider `~> 3.0`, region `us-east-1`) project split into a shared module (`modules/wordpress`) and three environments (`environments/dev|test|prod`, each with its own state and tfvars). It deploys a multi-AZ WordPress site: CloudFront (+ WAF) in front of an ALB, an Auto Scaling Group of Graviton web servers sharing an EFS file system, an Aurora MySQL cluster, an ElastiCache Redis object cache, S3 log buckets, CloudWatch monitoring and audit logging. There is no application code (the boot script installs WordPress). `DOCUMENTATION.md` holds the full narrative, cost estimate and troubleshooting; `README.md` is the short intro. Diagrams are in `docs/`.

## Commands

Run from an environment directory (`environments/dev`, `test` or `prod`), or use `./deploy.sh <env> <action>` / `.\deploy.ps1`:

```bash
terraform init
terraform fmt -recursive   # formatting is the only lint used
terraform validate
terraform plan
terraform apply
terraform destroy
```

Unit tests: `cd modules/wordpress && terraform init -backend=false && terraform test` (mock provider, Terraform >= 1.7).

Tests live in `modules/wordpress/tests/infrastructure.tftest.hcl` and use `command = plan`, so values only known after apply (subnet ID sets, security group IDs, user data that embeds resource IDs) can't be asserted; compare config-derived values instead. Mocked unset attributes are null (wrap in `coalesce`). The mock provider supplies valid JSON for `aws_iam_policy_document`, an ELB account ARN and region `us-east-1`; add `mock_data` entries when a new data source needs a realistic value. When changing hard-coded names, ports, thresholds or defaults, update the matching assertions.

Diagrams: `python docs/gen_diagrams.py` regenerates all eight `docs/architecture-*.svg` (static and `-animated` per environment, plus the combined pair) from the tfvars. The animated ones add CSS flow/glow and SMIL packets (`animate=True` in `build()`/`combined()`); routes for the packets are hard-coded coordinates next to the arrows they follow, so move them together. CI fails if the files are stale, so run it after changing tfvars or the generator.

Load testing a deployed environment: `./load-test.sh <env>` (ab; targets the CloudFront domain, or `TARGET_URL`) or `locust -f locustfile.py --host=https://<cloudfront domain>`.

## Architecture (spans multiple files)

```text
Internet -> CloudFront (+WAF) -> ALB (X-Origin-Verify header required) -> ASG instances (public-1 / public-2)
                                                                       |-> EFS /var/www/html (mount target per AZ)
                                                                       |-> Aurora (private-1 / private-2)
                                                                       |-> ElastiCache Redis (private subnets)
dev also has one standalone EC2 in public-1 (same boot script). The NAT gateway exists only when enable_nat_gateway = true (false everywhere).
Logs: ALB -> S3 alb-logs; CloudFront + VPC Flow Logs (+CloudTrail in prod) -> S3 audit-logs; WAF/Apache/Aurora -> CloudWatch Logs.
```

Names are `deham9-<env>-...` (`local.prefix = "<project>-<env>"`; ALB/target group names are limited to 32 chars, so keep project + environment short). Changing `project`/`environment` renames, and so recreates, resources.

Files in `modules/wordpress/`:

- `network.tf`: VPC, 2 public + 2 private /24 subnets via `cidrsubnet`, IGW, optional NAT gateway/EIP (`enable_nat_gateway`), route tables.
- `sg.tf`: `sg_alb` (with CloudFront: port 80 from the CloudFront prefix list only; otherwise 80/443 from `CIDR_BLOCK`; its egress uses the VPC CIDR, not `sg_vpc`, to avoid a circular reference), `sg_vpc` = web tier (80 from `sg_alb`, egress 443/2049/3306 and 6379 with the cache), `allow_ssh` (a rule only when `ssh_cidr_blocks` is non-empty; default empty = SSH closed, use SSM; no egress rule), `allow_aurora_access` (3306 from `sg_vpc`, plus `CIDR_BLOCK` only if `db_publicly_accessible`).
- `iam.tf`: per-env role `<prefix>-web-role` + instance profile (SSM core, CloudWatch agent, `GetSecretValue` on the Aurora secret). No manual IAM profile is needed.
- `auto_scaling.tf`: launch template (IMDSv2, encrypted root volume, `monitoring` on), ASG `<prefix>-asg` (ELB health checks, 300 s grace), CPU and `ALBRequestCountPerTarget` tracking policies, optional off-hours schedule. AMI = latest AL2023 for `cpu_architecture` from the SSM public parameter (`ami_id` pins one); a precondition checks the instance type matches the architecture (envs run arm64/t4g); `web_tier_in_private_subnets` requires `enable_nat_gateway`. `desired_capacity` is in `ignore_changes`; the ASG uses the template's `latest_version` plus a rolling `instance_refresh`.
- `userdatalaunchtemplate.tpl` (`local.web_user_data` in `locals.tf`): installs packages, mounts the EFS, and the first instance (atomic `mkdir` lock with a 10-minute stale-lock takeover) installs WordPress with a dedicated `wordpress` DB user (never the rotating RDS master password), generated salts, proxy settings and optional Redis settings; then starts Apache and the CloudWatch agent.
- `ec2.tf`: optional standalone instance (`standalone_instance_count`, dev), same boot script, security groups and profile as the ASG, attached to the target group; `ami` is in `ignore_changes`.
- `elb.tf`: ALB `<prefix>-alb` (drops invalid headers, access logs to S3), target group `<prefix>-tg` (health check `/`, matcher 200-399 because a fresh WordPress redirects to its installer), HTTP listener, HTTPS listener only with `certificate_arn` and without CloudFront. With CloudFront the listener's default action is a 403 and a listener rule forwards requests carrying `X-Origin-Verify`.
- `cloudfront.tf`: distribution (HTTP-only origin = the ALB, redirect to HTTPS, no caching for dynamic pages, caching for `/wp-content/*` and `/wp-includes/*`, access logs to the audit bucket), the `random_password` origin secret and, with `enable_waf`, a WAFv2 ACL (managed rules + rate limit; must be us-east-1) with logging to CloudWatch Logs. `alb_dns_name` is not browsable with CloudFront: use the `site_url` output.
- `rds.tf`: Aurora `<prefix>-aurora`, encrypted, engine = latest Aurora MySQL 3 (8.0) via `aws_rds_engine_version` unless `db_engine_version` pins one, `db_instance_count` instances alternating over the AZs, password managed by Secrets Manager, error/slowquery log exports; prod has deletion protection and a final snapshot.
- `efs.tf`: encrypted EFS with elastic throughput, backup policy, a resource policy allowing mounts over TLS only, one mount target per public subnet, NFS (2049) allowed from `sg_vpc` only.
- `cache.tf`: optional ElastiCache Redis (`enable_object_cache`), private subnets, TLS and at-rest encryption, 6379 from `sg_vpc` only.
- `s3.tf`: ALB log bucket `<prefix>-alb-logs-<account id>` (versioning, public access block, SSE-S3, lifecycle expiry `log_retention_days`, bucket policy for the ELB service account).
- `audit.tf`: audit bucket `<prefix>-audit-logs-<account id>` (ACLs enabled for CloudFront logging, TLS-only), `enable_flow_logs`, `enable_cloudtrail` and `enable_guardduty` (ACCOUNT-level: prod only; GuardDuty allows one detector per account and region).
- `monitoring.tf`: SNS topic `<prefix>-alarms` (email subscription only if `alarm_email` is set), 10 CloudWatch alarms, the `<prefix>-wordpress` dashboard, Aurora and web log groups.
- `locals.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `tests/`.

Other directories:

- `environments/<env>/`: `main.tf` (calls the module), `variables.tf`, `terraform.tfvars` (environment values, no secrets), `providers.tf` (region + `default_tags`), `outputs.tf` (passes the module outputs through), `backend.tf` (S3 backend commented out; local state by default). Each env has its own VPC CIDR (10.0/10.1/10.2 /16).
- `bootstrap/`: one-off config (local state) creating the S3 state bucket and DynamoDB lock table; environments stay on local state until their `backend.tf` is switched.
- `.github/workflows/terraform.yml`: fmt, tests, validate (envs + bootstrap), Checkov (soft fail), diagram freshness.

## Gotchas

- The boot script is a `templatefile()`: write literal `${...}` as `$${...}` (the CloudWatch agent config does this) and avoid braces on new shell variables. It must never print passwords (no `set -x`).
- New outputs go in `modules/wordpress/outputs.tf` and must be repeated in each `environments/*/outputs.tf`; new module variables need the same in each environment's `variables.tf`, `main.tf` and `terraform.tfvars`.
- `load-test.sh <env>` derives `deham9-<env>-asg` / `deham9-<env>-alb` and the CloudFront comment `<prefix> WordPress`; update it if the naming scheme changes.
- The EC2 key pair `deham9-iam` must already exist in the account.
- `ssh_cidr_blocks` is `[]` in every environment, so port 22 is closed: use `aws ssm start-session --target <id>` or add an admin CIDR.
- The instances need outbound internet (public IPs) to download WordPress; `web_tier_in_private_subnets` therefore needs the NAT gateway.
- WAF for CloudFront needs the environment to run in us-east-1 (precondition).
- State, plan files, `.terraform.lock.hcl` and `metadata` (written by a `local-exec` provisioner on the standalone instance) are git-ignored; don't commit them.
