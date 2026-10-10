# User Stories: Multi-AZ WordPress on AWS

Derived from [BUSINESS_REQUIREMENTS.md](BUSINESS_REQUIREMENTS.md) (BR-1 to BR-17). Each story lists the requirement it serves and the test cases in [TEST_CASES.md](TEST_CASES.md) that prove it. Priorities follow the requirement (Must / Should / Could).

**Personas:** Visitor (reads the site), Content editor (publishes in WordPress), Platform engineer (builds and runs the infrastructure), Security officer (protects data and audits), Site owner (pays for it and signs it off).

## Visitor

**US-01: Fast, secure page loads** (BR-3, BR-9, BR-15; Should)
As a visitor, I want pages to load quickly over HTTPS, so that I can read the site without waiting or seeing security warnings.
- HTTP redirects to HTTPS and pages answer successfully (TC-20).
- Static files come from the CloudFront cache on repeat requests (TC-54).
- With 100 concurrent users, errors stay under 1% and p95 response time is 2 s or less (TC-69).

**US-02: Site survives a data-centre failure** (BR-1; Must)
As a visitor, I want the site to stay up when one Availability Zone fails, so that I never notice an outage.
- Web servers, database and file system run in two AZs (TC-10).
- Losing a web server, a whole AZ's servers or the database writer does not take the site down (TC-11, TC-12, TC-13).

**US-03: Site copes with traffic spikes** (BR-2, BR-15; Must)
As a visitor, I want the site to stay responsive when many people arrive at once, so that busy periods do not break it.
- Under load the Auto Scaling group adds servers, up to the configured maximum (TC-14).
- After the load ends, capacity shrinks back (TC-15).

## Content editor

**US-04: Uploads are visible everywhere** (BR-12; Must)
As a content editor, I want images and files I upload to appear on the site regardless of which server handles the request, so that nothing looks broken.
- A file uploaded through one server can be read from another (TC-52).
- Mounts of the shared storage are encrypted in transit (TC-26).

**US-05: Content survives server replacement** (BR-12, BR-14; Must)
As a content editor, I want my media and themes to remain when a server is replaced, so that I never have to re-upload.
- The shared file system has backups enabled (TC-66).
- A replacement server mounts the same storage and serves the same site (TC-68).

**US-06: Snappy admin screens** (BR-9; Should)
As a content editor, I want the WordPress dashboard to respond quickly, so that editing is not slowed by database load.
- With the Redis object cache on, cache hits are recorded and database load drops (TC-53).

## Platform engineer

**US-07: One-command environments** (BR-10; Should)
As a platform engineer, I want to deploy or destroy an environment with one command, so that I can build and remove environments reliably.
- `./deploy.sh <env> apply` succeeds on an empty account and `plan` afterwards shows no changes (TC-60, TC-61).
- `./deploy.sh <env> destroy` removes everything (TC-64).

**US-08: Self-configuring servers** (BR-14; Must)
As a platform engineer, I want new web servers to configure themselves, so that scaling and replacement need no manual steps.
- When several servers start together, exactly one installs WordPress (TC-55).
- WordPress uses its own database user, and no password is printed in logs (TC-27).
- A replacement server becomes healthy with no manual action (TC-68).

**US-09: Admin access without open SSH** (BR-5; Must)
As a platform engineer, I want to reach servers through SSM Session Manager, so that no SSH port is exposed.
- No ingress rule exists for port 22 by default (TC-08).
- SSH times out and an SSM session opens (TC-29).

**US-10: Self-healing** (BR-2; Must)
As a platform engineer, I want unhealthy servers replaced automatically, so that I am not paged for routine failures.
- A server with a stopped web service is marked unhealthy and replaced (TC-16).

**US-11: Zero-downtime changes** (BR-10; Should)
As a platform engineer, I want launch template changes to roll out gradually, so that updates cause no downtime.
- Changing the instance type replaces servers by rolling refresh while the site stays up (TC-62).

**US-12: Isolated environments** (BR-13; Should)
As a platform engineer, I want dev, test and prod to be fully separate, so that a mistake in dev cannot touch prod.
- Separate VPC ranges (10.0, 10.1, 10.2 /16) and separate state (TC-63).
- Resource names and tags carry the environment name (TC-67).

**US-13: Safe, shared Terraform state** (BR-16; Should)
As a platform engineer, I want state stored remotely with locking, so that two people cannot apply at once or lose state.
- A second concurrent apply is blocked by the lock (TC-70).
- The state bucket is versioned, encrypted and not public; the lock table uses `LockID` (TC-71).

**US-14: Errors caught before release** (BR-10; Should)
As a platform engineer, I want formatting, validation, unit tests and diagram checks to run in CI, so that broken changes never reach an environment.
- `fmt`, `validate`, `terraform test` and the diagram freshness check pass on every push (TC-01 to TC-05).
- Mismatched instance type and architecture, or WAF outside us-east-1, fail the plan (TC-06, TC-07).

## Security officer

**US-15: Only CloudFront can reach the site** (BR-3; Must)
As a security officer, I want all public traffic to pass through CloudFront and the WAF, so that abusive traffic is filtered and the load balancer is not exposed.
- Direct requests to the load balancer return 403 or no connection (TC-21).
- Requests carrying the origin header are forwarded (TC-22).
- Requests above the rate limit are blocked and logged (TC-23).
- Security groups allow only the intended sources and ports (TC-24).

**US-16: Data encrypted everywhere** (BR-4; Must)
As a security officer, I want data encrypted at rest and in transit, so that a stolen disk or captured packet exposes nothing.
- Aurora, EFS, volumes, cache and S3 report encryption on (TC-25).
- Unencrypted EFS and Redis connections are refused (TC-26).
- Servers require IMDSv2 and the database is not public (TC-28, TC-30).

**US-17: Audit trail in prod** (BR-7; Should)
As a security officer, I want flow logs, CloudTrail and GuardDuty in prod with configurable retention, so that I can investigate incidents.
- Logs arrive in the audit bucket (TC-43).
- The trail is logging and one GuardDuty detector is active (TC-44).
- Retention matches `log_retention_days` (TC-45).

## Site owner

**US-18: Know when something is wrong** (BR-6; Must)
As the site owner, I want alarms and a dashboard, so that the team is told about problems before visitors are.
- Ten alarms exist, all wired to the notification topic (TC-41).
- A forced alarm sends an email (TC-40).
- The dashboard shows data after traffic (TC-42) and ALB access logs are delivered (TC-46).

**US-19: Data can be recovered** (BR-8; Should)
As the site owner, I want database backups and deletion protection in prod, so that a mistake or attack cannot destroy the data.
- Prod deletion is blocked by protection (TC-50).
- Backups exist and a snapshot restores successfully (TC-51).

**US-20: Pay only for what we use** (BR-11; Could)
As the site owner, I want cost levers such as an off-hours schedule and no NAT gateway by default, so that dev and test stay cheap.
- With the schedule on, capacity drops at 19:00 UTC and returns at 06:00 UTC on weekdays (TC-17).
- No NAT gateway or Elastic IP exists by default (TC-65).

**US-21: Documentation and costs stay honest** (BR-17; Could)
As the site owner, I want diagrams, docs and the cost estimate to match the code, so that I can approve budgets with confidence.
- Diagrams regenerate with no changes (TC-04).
- The cost table matches the tfvars, and docs list every variable and output (TC-72).

## Traceability

| Requirement | Stories |
| --- | --- |
| BR-1 | US-02 |
| BR-2 | US-03, US-10 |
| BR-3 | US-01, US-15 |
| BR-4 | US-16 |
| BR-5 | US-09 |
| BR-6 | US-18 |
| BR-7 | US-17 |
| BR-8 | US-19 |
| BR-9 | US-01, US-06 |
| BR-10 | US-07, US-11, US-14 |
| BR-11 | US-20 |
| BR-12 | US-04, US-05 |
| BR-13 | US-12 |
| BR-14 | US-05, US-08 |
| BR-15 | US-01, US-03 |
| BR-16 | US-13 |
| BR-17 | US-21 |
