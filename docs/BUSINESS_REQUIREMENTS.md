# Business Requirements Document: Multi-AZ WordPress on AWS

Date: 2026-10-10

## 1. Purpose and background

The business needs a public WordPress website that stays online through an Availability Zone failure, absorbs traffic spikes and is protected against common web attacks. The platform is delivered as repeatable infrastructure-as-code (Terraform on AWS, region us-east-1), so dev, test and prod are built identically from one shared module and can be created or destroyed on demand.

## 2. Business objectives

- **High availability:** no single point of failure; web, database and file storage span two Availability Zones.
- **Elastic capacity:** the web tier scales automatically on CPU and requests per target, and scales down off-hours to save cost.
- **Security and compliance:** traffic is filtered by a WAF, the origin is reachable only through CloudFront, data is encrypted, and audit logs are retained.
- **Operational visibility:** alarms notify the team by email and a dashboard shows site health.
- **Repeatability and cost control:** one module and three environments (dev, test, prod) with right-sized settings per environment.

## 3. Scope

**In scope:** network (VPC, 2 public and 2 private subnets), CloudFront with WAF, load balancer, Auto Scaling web servers (Graviton), shared EFS storage, Aurora MySQL, optional Redis object cache, S3 log buckets, monitoring and alarms, audit logging, and automated tests and CI.

**Out of scope:** WordPress content, themes and plugins; custom application code; DNS and TLS certificate procurement for a custom domain; multi-region disaster recovery.

## 4. Business requirements

| ID | Requirement | Priority |
| --- | --- | --- |
| BR-1 | Site stays available if one Availability Zone fails (web, database, file system in two AZs). | Must |
| BR-2 | Web servers scale out and in automatically with load; health checks replace failed instances. | Must |
| BR-3 | All public traffic enters via CloudFront with WAF (managed rules and rate limiting); direct access to the load balancer is blocked. | Must |
| BR-4 | Data is encrypted at rest and in transit; database credentials are managed in Secrets Manager and never printed. | Must |
| BR-5 | Admin access without open SSH ports (SSM Session Manager). | Must |
| BR-6 | Alarms (CPU, errors, latency, database) notify the team; a dashboard shows health. | Must |
| BR-7 | Audit trail in prod: VPC Flow Logs, CloudTrail and GuardDuty; log retention is configurable. | Should |
| BR-8 | Database backups and deletion protection in prod. | Should |
| BR-9 | Optional Redis object cache to cut database load and page latency. | Should |
| BR-10 | Environments deploy with one command and are validated by automated tests and CI before release. | Should |
| BR-11 | Cost levers: off-hours scaling schedule, no NAT gateway by default, right-sized instances in dev and test. | Could |

## 5. Environments, constraints and assumptions

- **Environments:** dev, test and prod, each with its own state, variables and VPC range (10.0, 10.1, 10.2 /16). Prod adds CloudTrail, GuardDuty, deletion protection and a final database snapshot.
- **Constraints:** AWS only, region us-east-1 (required for CloudFront WAF); resource names follow `deham9-<env>`; no secrets in source control.
- **Assumptions:** the EC2 key pair `deham9-iam` exists in the account; an alarm email address is supplied; web instances use public IPs for outbound internet unless a NAT gateway is enabled; the cost estimate in DOCUMENTATION.md is approved.

## 6. Success criteria, risks and approval

- **Success criteria:** the site is served over HTTPS through CloudFront; it survives loss of one instance or AZ without manual action; load tests show the Auto Scaling group adding capacity under load; tests, validation and the diagram check pass in CI; all alarms deliver to the email list.
- **Risks:** cost growth from scaling or NAT (mitigate with schedules and alarms); changing project or environment names recreates resources; GuardDuty allows one detector per account and region; a single-region design does not cover a regional outage.

| Role | Name | Decision | Date |
| --- | --- | --- | --- |
| Business sponsor | | | |
| Product owner | | | |
| Cloud / platform lead | | | |
