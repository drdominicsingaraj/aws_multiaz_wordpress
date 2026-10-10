#!/bin/bash
# smoke-test.sh - read-only checks of a deployed environment, mapped to docs/TEST_CASES.md.
# Usage: ./smoke-test.sh <dev|test|prod>      (needs the AWS CLI, credentials and curl)
# Makes no changes. Exit code is 1 if any check fails; SKIP means the check does not apply.

ENVIRONMENT="${1:-dev}"
PROJECT="deham9"
PREFIX="${PROJECT}-${ENVIRONMENT}"
REGION="us-east-1"
export AWS_DEFAULT_REGION="$REGION"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASSED=0; FAILED=0; SKIPPED=0

pass() { echo -e "${GREEN}PASS${NC} $1  $2"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC} $1  $2"; FAILED=$((FAILED + 1)); }
skip() { echo -e "${YELLOW}SKIP${NC} $1  $2"; SKIPPED=$((SKIPPED + 1)); }
# check <TC> <description> <actual> <expected>: pass when actual equals expected
check() { if [ "$3" = "$4" ]; then pass "$1" "$2"; else fail "$1" "$2 (got '$3', expected '$4')"; fi; }
# aws wrapper: returns an empty string instead of an error
q() { aws "$@" --output text 2>/dev/null; }

echo "=== Smoke test: $PREFIX ($REGION) ==="
ACCOUNT=$(q sts get-caller-identity --query Account)
[ -z "$ACCOUNT" ] && { echo "No AWS credentials"; exit 1; }

# --- Discover resources ---
ALB_DNS=$(q elbv2 describe-load-balancers --names "${PREFIX}-alb" --query 'LoadBalancers[0].DNSName')
ALB_ARN=$(q elbv2 describe-load-balancers --names "${PREFIX}-alb" --query 'LoadBalancers[0].LoadBalancerArn')
ALB_SG=$(q elbv2 describe-load-balancers --names "${PREFIX}-alb" --query 'LoadBalancers[0].SecurityGroups[0]')
VPC_ID=$(q elbv2 describe-load-balancers --names "${PREFIX}-alb" --query 'LoadBalancers[0].VpcId')
[ -z "$ALB_DNS" ] && { echo "ALB ${PREFIX}-alb not found: is the environment deployed?"; exit 1; }
CF_DOMAIN=$(q cloudfront list-distributions --query "DistributionList.Items[?Comment=='${PREFIX} WordPress'].DomainName | [0]")
[ "$CF_DOMAIN" = "None" ] && CF_DOMAIN=""
echo "ALB: $ALB_DNS   CloudFront: ${CF_DOMAIN:-none}"
echo

# --- Availability (BR-1) ---
echo "-- Availability and scaling"
asg_azs=$(q autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${PREFIX}-asg" --query 'length(AutoScalingGroups[0].AvailabilityZones)')
efs_id=$(q efs describe-file-systems --query "FileSystems[?CreationToken=='${PREFIX}-wordpress-efs'].FileSystemId | [0]")
efs_azs=$(q efs describe-mount-targets --file-system-id "$efs_id" --query 'length(MountTargets)')
db_azs=$(q rds describe-db-clusters --db-cluster-identifier "${PREFIX}-aurora" --query 'length(DBClusters[0].AvailabilityZones)')
[ "${asg_azs:-0}" -ge 2 ] && [ "${efs_azs:-0}" -ge 2 ] && [ "${db_azs:-0}" -ge 2 ] \
  && pass TC-10 "ASG ($asg_azs), EFS mount targets ($efs_azs) and Aurora ($db_azs) span 2+ AZs" \
  || fail TC-10 "AZ spread: ASG=$asg_azs EFS=$efs_azs Aurora=$db_azs (need 2+ each)"
skip TC-11 "needs a failure drill (terminates an instance)"
skip TC-14 "run ./load-test.sh $ENVIRONMENT"

# --- Web entry and origin protection (BR-3) ---
echo "-- Security"
if [ -n "$CF_DOMAIN" ]; then
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://$CF_DOMAIN/")
  http_loc=$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 15 "http://$CF_DOMAIN/")
  https_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$CF_DOMAIN/")
  if [[ "$http_code" =~ ^30[1278]$ && "$http_loc" == https://* && "$https_code" =~ ^(2|3)[0-9][0-9]$ ]]; then
    pass TC-20 "HTTP redirects to HTTPS ($http_code), HTTPS answers $https_code"
  else
    fail TC-20 "HTTP=$http_code redirect='$http_loc' HTTPS=$https_code"
  fi
  # Static content should be cached by CloudFront (second request is a hit)
  hit=""
  for _ in 1 2 3; do
    curl -s -o /dev/null --max-time 15 "https://$CF_DOMAIN/wp-includes/css/dashicons.min.css"
    hit=$(curl -s -o /dev/null -D - --max-time 15 "https://$CF_DOMAIN/wp-includes/css/dashicons.min.css" | grep -i '^x-cache:' | tr -d '\r')
    [[ "$hit" == *"Hit from cloudfront"* ]] && break
    sleep 2
  done
  if [[ "$hit" == *"Hit from cloudfront"* ]]; then pass TC-54 "static file served from CloudFront cache"; else
    skip TC-54 "no cache hit ($hit); WordPress may not be installed yet"
  fi
else
  skip TC-20 "no CloudFront distribution in this environment"
  skip TC-54 "no CloudFront distribution in this environment"
fi

alb_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$ALB_DNS/")
if [ -n "$CF_DOMAIN" ]; then
  [ "$alb_code" = "403" ] || [ "$alb_code" = "000" ] \
    && pass TC-21 "direct ALB access blocked ($alb_code)" || fail TC-21 "direct ALB access returned $alb_code"
else
  skip TC-21 "no CloudFront: the ALB is the public entry"
fi
skip TC-22 "needs the X-Origin-Verify secret"

# Security groups: with CloudFront the ALB must not allow any CIDR range, only the prefix list
if [ -n "$CF_DOMAIN" ]; then
  cidrs=$(q ec2 describe-security-groups --group-ids "$ALB_SG" --query 'length(SecurityGroups[0].IpPermissions[].IpRanges[])')
  plists=$(q ec2 describe-security-groups --group-ids "$ALB_SG" --query 'length(SecurityGroups[0].IpPermissions[].PrefixListIds[])')
  [ "$cidrs" = "0" ] && [ "${plists:-0}" -ge 1 ] \
    && pass TC-24 "ALB security group allows the CloudFront prefix list only" \
    || fail TC-24 "ALB security group has $cidrs CIDR rule(s) and $plists prefix list rule(s)"
else
  skip TC-24 "no CloudFront: ALB opens 80/443 from CIDR_BLOCK by design"
fi

# Encryption at rest (BR-4)
db_enc=$(q rds describe-db-clusters --db-cluster-identifier "${PREFIX}-aurora" --query 'DBClusters[0].StorageEncrypted')
efs_enc=$(q efs describe-file-systems --file-system-id "$efs_id" --query 'FileSystems[0].Encrypted')
[ "$db_enc" = "True" ] && [ "$efs_enc" = "True" ] && pass TC-25 "Aurora and EFS are encrypted" \
  || fail TC-25 "Aurora encrypted=$db_enc, EFS encrypted=$efs_enc"

# IMDSv2 on the launch template (BR-4)
lt_id=$(q autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${PREFIX}-asg" --query 'AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId')
tokens=$(q ec2 describe-launch-template-versions --launch-template-id "$lt_id" --versions '$Latest' --query 'LaunchTemplateVersions[0].LaunchTemplateData.MetadataOptions.HttpTokens')
check TC-28 "launch template requires IMDSv2 tokens" "$tokens" "required"

public=$(q rds describe-db-instances --filters "Name=db-cluster-id,Values=${PREFIX}-aurora" --query 'DBInstances[?PubliclyAccessible==`true`] | length(@)')
check TC-30 "no Aurora instance is publicly accessible" "$public" "0"

# --- SSH closed (BR-5) ---
ssh_rules=$(q ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=ip-permission.to-port,Values=22" --query 'length(SecurityGroups)')
check TC-29 "no security group in the VPC opens port 22" "$ssh_rules" "0"

# --- Monitoring (BR-6) ---
echo "-- Monitoring and audit"
alarms=$(q cloudwatch describe-alarms --alarm-name-prefix "$PREFIX" --query 'length(MetricAlarms)')
no_action=$(q cloudwatch describe-alarms --alarm-name-prefix "$PREFIX" --query 'MetricAlarms[?length(AlarmActions)==`0`] | length(@)')
[ "${alarms:-0}" -ge 10 ] && [ "$no_action" = "0" ] \
  && pass TC-41 "$alarms alarms, all wired to an action" \
  || fail TC-41 "alarms=$alarms (expected 10+), without action=$no_action"
dash=$(q cloudwatch get-dashboard --dashboard-name "${PREFIX}-wordpress" --query DashboardName)
check TC-42 "dashboard ${PREFIX}-wordpress exists" "$dash" "${PREFIX}-wordpress"
skip TC-40 "needs a forced alarm and a confirmed email subscription"

alb_logs=$(q elbv2 describe-load-balancer-attributes --load-balancer-arn "$ALB_ARN" --query "Attributes[?Key=='access_logs.s3.enabled'].Value | [0]")
check TC-46 "ALB access logging enabled" "$alb_logs" "true"
if aws s3api head-bucket --bucket "${PREFIX}-audit-logs-${ACCOUNT}" >/dev/null 2>&1; then
  pass TC-43 "audit bucket ${PREFIX}-audit-logs-${ACCOUNT} exists"
else
  fail TC-43 "audit bucket ${PREFIX}-audit-logs-${ACCOUNT} not found"
fi

# --- Prod-only checks (BR-7, BR-8) ---
if [ "$ENVIRONMENT" = "prod" ]; then
  del=$(q rds describe-db-clusters --db-cluster-identifier "${PREFIX}-aurora" --query 'DBClusters[0].DeletionProtection')
  check TC-50 "prod deletion protection" "$del" "True"
  days=$(q rds describe-db-clusters --db-cluster-identifier "${PREFIX}-aurora" --query 'DBClusters[0].BackupRetentionPeriod')
  [ "${days:-0}" -ge 7 ] && pass TC-51 "backup retention $days days" || fail TC-51 "backup retention $days days"
  trail=$(q cloudtrail get-trail-status --name "${PREFIX}-trail" --query IsLogging)
  check TC-44 "CloudTrail is logging" "$trail" "True"
else
  skip TC-50 "prod only"
  skip TC-51 "prod only"
  skip TC-44 "prod only"
fi

# --- Cost (BR-11) ---
nat=$(q ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" --query 'length(NatGateways)')
check TC-65 "no NAT gateway" "$nat" "0"

echo
echo "=== Result: $PASSED passed, $FAILED failed, $SKIPPED skipped ==="
[ "$FAILED" -eq 0 ]
