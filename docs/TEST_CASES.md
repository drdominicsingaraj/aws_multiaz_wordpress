# Test Cases: Multi-AZ WordPress on AWS

Date: 2026-10-10. Traces to [BUSINESS_REQUIREMENTS.md](BUSINESS_REQUIREMENTS.md).

**Test levels:** **A** = automated, no AWS needed (`terraform test`, `fmt`, `validate`, CI). **D** = deployed environment (manual or scripted). **M** = manual review, no AWS needed. Run deployed tests in dev or test first; prod only for read-only checks unless a change window is agreed.

**Setup (level A):** `cd modules/wordpress && terraform init -backend=false && terraform test`
**Setup (level D):** `./deploy.sh <env> apply`, then take the `site_url` output as `<site>`.

## 1. Automated tests

| ID | BR | Test | Steps | Expected result | Level |
| --- | --- | --- | --- | --- | --- |
| TC-01 | BR-10 | Formatting | `terraform fmt -recursive -check` | No files reported | A |
| TC-02 | BR-10 | Validation | `terraform validate` in dev, test, prod and bootstrap | Success in all four | A |
| TC-03 | BR-10 | Module unit tests | `terraform test` in `modules/wordpress` | All assertions pass | A |
| TC-04 | BR-10, BR-17 | Diagram freshness | `python docs/gen_diagrams.py`, then `git diff docs` | No changes to the SVG files | A |
| TC-05 | BR-10 | CI pipeline | Push a branch | fmt, tests, validate and diagram jobs are green; Checkov findings reviewed | A |
| TC-06 | BR-2 | Instance and architecture precondition | Plan with `cpu_architecture = "arm64"` and an x86 instance type | Plan fails with the precondition message | A |
| TC-07 | BR-3 | WAF region precondition | Plan with `enable_waf = true` in a region other than us-east-1 | Plan fails with the precondition message | A |
| TC-08 | BR-5 | SSH closed by default | Plan with `ssh_cidr_blocks = []` | No ingress rule on port 22 | A |

## 2. Availability and scaling

| ID | BR | Test | Steps | Expected result | Level |
| --- | --- | --- | --- | --- | --- |
| TC-10 | BR-1 | Resources span two AZs | List subnets, ASG instances, EFS mount targets and Aurora instances | Each tier has resources in both AZs | D |
| TC-11 | BR-1, BR-2 | Instance failure | Terminate one web instance | Site stays up; ASG launches a replacement; target group returns to healthy | D |
| TC-12 | BR-1 | AZ failure simulation | Terminate all web instances in one AZ (dev or test) | Site keeps serving from the other AZ; ASG rebalances | D |
| TC-13 | BR-1 | Database failover | Fail over the Aurora cluster (`aws rds failover-db-cluster`) | Brief interruption only; writer moves to the other AZ; site recovers without manual action | D |
| TC-14 | BR-2, BR-15 | Scale out under load | `./load-test.sh <env>` or `locust -f locustfile.py --host=https://<cloudfront domain>` | Scaling policy triggers; desired capacity rises above the starting value and stays at or below `asg_max_size` | D |
| TC-15 | BR-2, BR-15 | Scale in after load | Stop the load test and wait for cool-down | Capacity returns toward `asg_min_size` | D |
| TC-16 | BR-2 | Health check replacement | Stop Apache on one instance | ELB health check marks it unhealthy; ASG replaces it | D |
| TC-17 | BR-11 | Off-hours schedule | Set `enable_off_hours_schedule = true` and apply | Scheduled actions exist; capacity drops to `off_hours_capacity` at 19:00 UTC and returns at 06:00 UTC Mon-Fri | D |

## 3. Security

| ID | BR | Test | Steps | Expected result | Level |
| --- | --- | --- | --- | --- | --- |
| TC-20 | BR-3 | Site served via CloudFront over HTTPS | `curl -I http://<site>` and `https://<site>` | HTTP redirects to HTTPS; HTTPS returns 200 or a WordPress redirect | D |
| TC-21 | BR-3 | Direct ALB access blocked | `curl -I http://<alb dns name>` | 403 (no `X-Origin-Verify` header) or no connection | D |
| TC-22 | BR-3 | Origin header accepted | `curl -I -H "X-Origin-Verify: <secret>" http://<alb dns name>` | Request is forwarded to WordPress (200-399) | D |
| TC-23 | BR-3 | WAF blocks abuse | Send requests above the rate limit from one IP | Requests are blocked (403); events appear in the WAF log group | D |
| TC-24 | BR-3 | Security group scope | Inspect `sg_alb`, `sg_vpc`, Aurora, EFS and cache groups | ALB: port 80 from the CloudFront prefix list only; web: 80 from ALB only; DB 3306, EFS 2049 and cache 6379 from the web group only | D |
| TC-25 | BR-4 | Encryption at rest | Check Aurora, EFS, root volumes, ElastiCache and S3 | All report encryption enabled | D |
| TC-26 | BR-4, BR-12 | Encryption in transit | Mount EFS without TLS; connect to Redis without TLS | Both are refused | D |
| TC-27 | BR-4, BR-14 | Secrets handling | Review boot logs (`/var/log/cloud-init-output.log`) and Terraform output | No passwords printed; database password is held in Secrets Manager | D |
| TC-28 | BR-4 | IMDSv2 enforced | `curl http://169.254.169.254/latest/meta-data/` from an instance without a token | Request is rejected (401) | D |
| TC-29 | BR-5 | No SSH, SSM works | Try `ssh` to an instance; run `aws ssm start-session --target <id>` | SSH times out; SSM session opens | D |
| TC-30 | BR-4 | Aurora not public | Connect to the Aurora endpoint from outside the VPC | No connection (`db_publicly_accessible = false`) | D |

## 4. Monitoring and audit

| ID | BR | Test | Steps | Expected result | Level |
| --- | --- | --- | --- | --- | --- |
| TC-40 | BR-6 | Alarm notification | Set `alarm_email`, confirm the SNS subscription, force an alarm (`aws cloudwatch set-alarm-state`) | Email arrives within a few minutes | D |
| TC-41 | BR-6 | Alarm inventory | List alarms with prefix `deham9-<env>` | 10 alarms exist, each wired to the SNS topic | D |
| TC-42 | BR-6 | Dashboard | Open `deham9-<env>-wordpress` in CloudWatch | Widgets show data after traffic is sent | D |
| TC-43 | BR-7 | Flow logs and audit bucket | Check S3 `deham9-<env>-audit-logs-<account>` after traffic | CloudFront and VPC flow log objects are present | D |
| TC-44 | BR-7 | CloudTrail and GuardDuty (prod) | Check trail and detector status | Trail logging; one GuardDuty detector enabled | D |
| TC-45 | BR-7 | Log retention | Check bucket lifecycle and log group retention | Expiry equals `log_retention_days` | D |
| TC-46 | BR-6 | ALB access logs | Send traffic; list `deham9-<env>-alb-logs-<account>` | Log files are delivered | D |

## 5. Data protection and performance

| ID | BR | Test | Steps | Expected result | Level |
| --- | --- | --- | --- | --- | --- |
| TC-50 | BR-8 | Prod deletion protection | `terraform destroy` plan or `aws rds delete-db-cluster` on prod | Blocked by deletion protection | D |
| TC-51 | BR-8 | Backup retention and snapshot | Check `db_backup_retention_days` (prod: 14); restore a snapshot into a test cluster | Backups exist; restore succeeds | D |
| TC-52 | BR-12 | Shared file system | Upload a media file on one instance; read it on another | File is present on all instances (EFS) | D |
| TC-53 | BR-9 | Object cache active | With `enable_object_cache = true`, check WordPress cache status and Redis metrics | Cache hits recorded; database load lower than with cache off | D |
| TC-54 | BR-9 | Static content caching | Request `/wp-content/...` twice | Second response shows a CloudFront cache hit; dynamic pages are not cached | D |
| TC-55 | BR-14, BR-1 | WordPress installs once | Launch several instances together | Exactly one installs WordPress (boot lock); all serve the same site | D |
| TC-66 | BR-12 | EFS backup | Check the backup policy of the EFS file system (`aws efs describe-backup-policy`) | Status is ENABLED | D |
| TC-69 | BR-15 | Load targets met | `./load-test.sh <env>` with 100 concurrent users (see `ab` results) | Error rate under 1%; p95 response time 2 s or less | D |

## 6. Deployment and operations

| ID | BR | Test | Steps | Expected result | Level |
| --- | --- | --- | --- | --- | --- |
| TC-60 | BR-10 | Clean deploy | `./deploy.sh dev apply` on an empty account | Applies without error; `site_url` loads the WordPress installer or site | D |
| TC-61 | BR-10 | Idempotency | Run `terraform plan` immediately after apply | No changes | D |
| TC-62 | BR-10 | Rolling update | Change the launch template (for example `instance_type`) and apply | Instance refresh replaces instances without downtime | D |
| TC-63 | BR-13, BR-10 | Environment isolation | Compare dev, test and prod VPC CIDRs and state | Ranges 10.0, 10.1, 10.2 /16; separate states; no overlap | D |
| TC-64 | BR-10 | Clean destroy | `./deploy.sh dev destroy` | All resources removed; no orphaned costs | D |
| TC-65 | BR-11 | NAT gateway off by default | Check route tables and resources in each environment | No NAT gateway or EIP | D |
| TC-67 | BR-13 | Environment naming and tags | List resources and their `Environment` tag in dev, test and prod | Names start with `deham9-<env>`; tags match the environment | D |
| TC-68 | BR-14 | Self-configuring instance | Terminate one web instance and wait for its replacement | The new instance mounts EFS, serves WordPress and goes healthy with no manual action | D |
| TC-70 | BR-16 | Remote state and locking | Apply `bootstrap/`, switch an environment's `backend.tf` to S3, then start two applies at once | State bucket and lock table exist; the second apply is blocked by the lock | D |
| TC-71 | BR-16 | State bucket protections | After applying `bootstrap/`, check the state bucket and lock table (`aws s3api get-bucket-versioning`, `get-bucket-encryption`, `get-public-access-block`; `aws dynamodb describe-table`) | Versioning enabled; KMS encryption; all public access blocked; lock table has hash key `LockID` | D |
| TC-72 | BR-17 | Documentation and cost estimate current | Compare instance types, counts and the off-hours schedule in each `terraform.tfvars` with the cost table in `DOCUMENTATION.md`; check `README.md` and `CLAUDE.md` mention any new variable or output | Estimate matches the configuration; docs list every variable and output; reviewed on any change that adds or resizes resources | M |

## 7. Execution log

| Run date | Environment | Tester | Test IDs | Pass | Fail | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |

## 8. Entry and exit criteria

- **Entry:** code merged to the branch under test; automated tests (TC-01 to TC-08) pass; target environment deployed.
- **Exit:** all Must-priority BRs (BR-1 to BR-6, BR-12 and BR-14) have every linked test passed; defects open at severity high are zero; results are recorded in the execution log.

## 9. Traceability to user stories

Stories are in [USER_STORIES.md](USER_STORIES.md).

| Test case | User stories |
| --- | --- |
| TC-01 | US-14 |
| TC-04 | US-21 |
| TC-05 | US-14 |
| TC-06 | US-14 |
| TC-07 | US-14 |
| TC-08 | US-09 |
| TC-10 | US-02 |
| TC-11 | US-02 |
| TC-12 | US-02 |
| TC-13 | US-02 |
| TC-14 | US-03 |
| TC-15 | US-03 |
| TC-16 | US-10 |
| TC-17 | US-20 |
| TC-20 | US-01 |
| TC-21 | US-15 |
| TC-22 | US-15 |
| TC-23 | US-15 |
| TC-24 | US-15 |
| TC-25 | US-16 |
| TC-26 | US-04, US-16 |
| TC-27 | US-08 |
| TC-28 | US-16 |
| TC-29 | US-09 |
| TC-30 | US-16 |
| TC-40 | US-18 |
| TC-41 | US-18 |
| TC-42 | US-18 |
| TC-43 | US-17 |
| TC-44 | US-17 |
| TC-45 | US-17 |
| TC-46 | US-18 |
| TC-50 | US-19 |
| TC-51 | US-19 |
| TC-52 | US-04 |
| TC-53 | US-06 |
| TC-54 | US-01 |
| TC-55 | US-08 |
| TC-60 | US-07 |
| TC-61 | US-07 |
| TC-62 | US-11 |
| TC-63 | US-12 |
| TC-64 | US-07 |
| TC-65 | US-20 |
| TC-66 | US-05 |
| TC-67 | US-12 |
| TC-68 | US-05, US-08 |
| TC-69 | US-01 |
| TC-70 | US-13 |
| TC-71 | US-13 |
| TC-72 | US-21 |
