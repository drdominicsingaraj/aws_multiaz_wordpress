#!/bin/bash
# load-test.sh - Complete load testing script for WordPress Auto Scaling
# This script tests the Auto Scaling Group by generating load and monitoring the response

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ASG_NAME="awsrestart-autoscaling-group"
REGION="us-east-1"
TEST_DURATION=300  # 5 minutes
CONCURRENT_USERS=100

echo -e "${GREEN}=== WordPress Auto Scaling Load Test ===${NC}\n"

# 1. Get initial state
echo -e "${YELLOW}=== Step 1: Getting Initial State ===${NC}"
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names nit-alb \
  --region $REGION \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

if [ -z "$ALB_DNS" ]; then
  echo -e "${RED}Error: Could not find ALB DNS name${NC}"
  exit 1
fi

echo "ALB DNS: $ALB_DNS"
echo -e "\nCurrent ASG Configuration:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $REGION \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' \
  --output table

echo -e "\nCurrent Instances:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $REGION \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
  --output table

# 2. Check if Apache Bench is installed
echo -e "\n${YELLOW}=== Step 2: Checking Prerequisites ===${NC}"
if ! command -v ab &> /dev/null; then
  echo -e "${RED}Apache Bench (ab) is not installed${NC}"
  echo "Install it with:"
  echo "  - Amazon Linux/RHEL: sudo yum install httpd-tools -y"
  echo "  - Ubuntu/Debian: sudo apt-get install apache2-utils -y"
  echo "  - macOS: brew install httpd"
  exit 1
fi
echo -e "${GREEN}Apache Bench is installed${NC}"

# 3. Start monitoring in background
echo -e "\n${YELLOW}=== Step 3: Starting Monitoring ===${NC}"
MONITOR_LOG="monitor-$(date +%Y%m%d-%H%M%S).log"
echo "Monitoring log: $MONITOR_LOG"

(
  echo "Timestamp,DesiredCapacity,RunningInstances,AvgCPU" > $MONITOR_LOG
  while true; do
    CAPACITY=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names $ASG_NAME \
      --region $REGION \
      --query 'AutoScalingGroups[0].DesiredCapacity' \
      --output text 2>/dev/null || echo "N/A")
    
    RUNNING=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names $ASG_NAME \
      --region $REGION \
      --query 'length(AutoScalingGroups[0].Instances[?LifecycleState==`InService`])' \
      --output text 2>/dev/null || echo "N/A")
    
    CPU=$(aws cloudwatch get-metric-statistics \
      --namespace AWS/EC2 \
      --metric-name CPUUtilization \
      --dimensions Name=AutoScalingGroupName,Value=$ASG_NAME \
      --start-time $(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 60 \
      --statistics Average \
      --region $REGION \
      --query 'Datapoints[0].Average' \
      --output text 2>/dev/null || echo "N/A")
    
    TIMESTAMP=$(date +%Y-%m-%d\ %H:%M:%S)
    echo "$TIMESTAMP,$CAPACITY,$RUNNING,$CPU" >> $MONITOR_LOG
    echo -e "${GREEN}$(date +%H:%M:%S)${NC} - Capacity: $CAPACITY, Running: $RUNNING, CPU: ${CPU}%"
    sleep 30
  done
) &
MONITOR_PID=$!

# Ensure monitoring stops on script exit
trap "kill $MONITOR_PID 2>/dev/null" EXIT

# 4. Run load test
echo -e "\n${YELLOW}=== Step 4: Starting Load Test ===${NC}"
echo "Test Configuration:"
echo "  - Duration: ${TEST_DURATION} seconds ($(($TEST_DURATION / 60)) minutes)"
echo "  - Concurrent Users: $CONCURRENT_USERS"
echo "  - Target: http://$ALB_DNS/"
echo ""

AB_RESULTS="ab-results-$(date +%Y%m%d-%H%M%S).txt"
AB_GNUPLOT="ab-results-$(date +%Y%m%d-%H%M%S).tsv"

echo "Running Apache Bench test..."
ab -t $TEST_DURATION -c $CONCURRENT_USERS -g $AB_GNUPLOT http://$ALB_DNS/ > $AB_RESULTS 2>&1

echo -e "${GREEN}Load test completed${NC}"
echo "Results saved to: $AB_RESULTS"

# 5. Wait for scaling to stabilize
echo -e "\n${YELLOW}=== Step 5: Waiting for Auto Scaling to Stabilize ===${NC}"
echo "Waiting 2 minutes for scaling activities to complete..."
sleep 120

# 6. Check final state
echo -e "\n${YELLOW}=== Step 6: Final State ===${NC}"
echo "Final ASG Configuration:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $REGION \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' \
  --output table

echo -e "\nFinal Instances:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $REGION \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
  --output table

# 7. Show scaling activities
echo -e "\n${YELLOW}=== Step 7: Recent Scaling Activities ===${NC}"
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name $ASG_NAME \
  --region $REGION \
  --max-records 10 \
  --query 'Activities[*].[StartTime,Description,StatusCode]' \
  --output table

# 8. Show load test summary
echo -e "\n${YELLOW}=== Step 8: Load Test Summary ===${NC}"
echo "Apache Bench Results:"
grep -A 20 "Server Software:" $AB_RESULTS | head -25

# 9. Stop monitoring
kill $MONITOR_PID 2>/dev/null
trap - EXIT

# 10. Generate summary
echo -e "\n${GREEN}=== Load Test Complete ===${NC}"
echo -e "\nGenerated Files:"
echo "  - Load test results: $AB_RESULTS"
echo "  - Gnuplot data: $AB_GNUPLOT"
echo "  - Monitoring log: $MONITOR_LOG"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Review the Apache Bench results in $AB_RESULTS"
echo "2. Check CloudWatch dashboard for detailed metrics"
echo "3. Verify scaling activities in AWS Console"
echo "4. Monitor for scale-in after cooldown period (10-15 minutes)"

echo -e "\n${GREEN}To view monitoring data:${NC}"
echo "  cat $MONITOR_LOG"

echo -e "\n${GREEN}To check current CPU utilization:${NC}"
echo "  aws cloudwatch get-metric-statistics \\"
echo "    --namespace AWS/EC2 \\"
echo "    --metric-name CPUUtilization \\"
echo "    --dimensions Name=AutoScalingGroupName,Value=$ASG_NAME \\"
echo "    --start-time \$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \\"
echo "    --end-time \$(date -u +%Y-%m-%dT%H:%M:%S) \\"
echo "    --period 60 \\"
echo "    --statistics Average \\"
echo "    --region $REGION"
