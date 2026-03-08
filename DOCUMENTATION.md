# Scalable and Fault-Tolerant WordPress on AWS

## Project Overview

This project deploys a highly available, scalable WordPress application on AWS using Terraform. The infrastructure spans multiple availability zones in the us-east-1 region, providing fault tolerance and automatic scaling capabilities.

## Architecture

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud (us-east-1)                          │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                    VPC (10.0.0.0/16)                                  │ │
│  │                                                                       │ │
│  │  ┌─────────────────────────────┐  ┌─────────────────────────────┐   │ │
│  │  │   Availability Zone 1a      │  │   Availability Zone 1b      │   │ │
│  │  │                             │  │                             │   │ │
│  │  │  ┌───────────────────────┐  │  │  ┌───────────────────────┐  │   │ │
│  │  │  │ Public Subnet         │  │  │  │ Public Subnet         │  │   │ │
│  │  │  │ 10.0.1.0/24           │  │  │  │ 10.0.3.0/24           │  │   │ │
│  │  │  │                       │  │  │  │                       │  │   │ │
│  │  │  │  ┌─────────────────┐  │  │  │  │  ┌─────────────────┐  │  │   │ │
│  │  │  │  │ EC2 Instance    │  │  │  │  │  │ ASG Instance    │  │  │   │ │
│  │  │  │  │ (t3.micro)      │  │  │  │  │  │ (t2.micro)      │  │  │   │ │
│  │  │  │  │ WordPress       │  │  │  │  │  │ WordPress       │  │  │   │ │
│  │  │  │  └────────┬────────┘  │  │  │  │  └────────┬────────┘  │  │   │ │
│  │  │  │           │           │  │  │  │           │           │  │   │ │
│  │  │  │  ┌────────▼────────┐  │  │  │  │  ┌────────▼────────┐  │  │   │ │
│  │  │  │  │ NAT Gateway     │  │  │  │  │  │ ASG Instance    │  │  │   │ │
│  │  │  │  │ (Elastic IP)    │  │  │  │  │  │ (t2.micro)      │  │  │   │ │
│  │  │  │  └─────────────────┘  │  │  │  │  └─────────────────┘  │  │   │ │
│  │  │  └───────────┬───────────┘  │  │  └───────────┬───────────┘  │   │ │
│  │  │              │               │  │              │               │   │ │
│  │  │  ┌───────────▼───────────┐  │  │  ┌───────────▼───────────┐  │   │ │
│  │  │  │ Private Subnet        │  │  │  │ Private Subnet        │  │   │ │
│  │  │  │ 10.0.2.0/24           │  │  │  │ 10.0.4.0/24           │  │   │ │
│  │  │  │                       │  │  │  │                       │  │   │ │
│  │  │  │  ┌─────────────────┐  │  │  │  │  ┌─────────────────┐  │  │   │ │
│  │  │  │  │ Aurora Instance │  │  │  │  │  │ Aurora Instance │  │  │   │ │
│  │  │  │  │ (db.t3.small)   │  │  │  │  │  │ (db.t3.small)   │  │  │   │ │
│  │  │  │  │ Writer          │◄─┼──┼──┼──┼─►│ Reader          │  │  │   │ │
│  │  │  │  └─────────────────┘  │  │  │  │  └─────────────────┘  │  │   │ │
│  │  │  └───────────────────────┘  │  │  └───────────────────────┘  │   │ │
│  │  └─────────────────────────────┘  └─────────────────────────────┘   │ │
│  │                                                                       │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │ │
│  │  │              Application Load Balancer (ALB)                    │ │ │
│  │  │              HTTP:80 → Target Group                             │ │ │
│  │  └──────────────────────────────┬──────────────────────────────────┘ │ │
│  │                                 │                                     │ │
│  │  ┌──────────────────────────────▼──────────────────────────────────┐ │ │
│  │  │              Internet Gateway (IGW)                             │ │ │
│  │  └─────────────────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                    S3 Bucket: deham9alblogs                           │ │
│  │                    (ALB Access Logs + Versioning)                     │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                    S3 Bucket: restartproject                          │ │
│  │                    (WordPress Content Source)                         │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                              ┌───────────────┐
                              │   Internet    │
                              │   Users       │
                              └───────────────┘

Traffic Flow:
─────────────
1. User → ALB (HTTP:80)
2. ALB → EC2/ASG Instances (Health Check + Load Distribution)
3. EC2/ASG → Aurora MySQL (Port 3306 via Private Subnets)
4. EC2/ASG → S3 (WordPress Content Sync via IAM Role)
5. Private Subnets → NAT Gateway → Internet (Outbound only)
6. Public Subnets → Internet Gateway → Internet (Bidirectional)

Security Groups:
────────────────
• sg_vpc: HTTP(80), HTTPS(443), SSH(22) → EC2/ASG/ALB
• allow_ssh: SSH(22) → EC2 instances
• allow_aurora_access: All traffic → Aurora cluster
• allow_ec2_aurora: Outbound MySQL(3306) from EC2
```

### Network Architecture

The infrastructure uses a multi-AZ VPC design:

- **VPC CIDR**: 10.0.0.0/16 (65,536 IP addresses)
- **Availability Zones**: us-east-1a and us-east-1b
- **Subnets**:
  - Public Subnet 1 (10.0.1.0/24) - us-east-1a
  - Private Subnet 1 (10.0.2.0/24) - us-east-1a
  - Public Subnet 2 (10.0.3.0/24) - us-east-1b
  - Private Subnet 2 (10.0.4.0/24) - us-east-1b

### Components

#### 1. Compute Resources

**EC2 Instance** (`ec2.tf`)
- Instance Type: t3.micro
- AMI: Amazon Linux 2023
- Location: Public Subnet 1 (us-east-1a)
- IAM Role: deham10_ec2 (for S3 access)
- Key Pair: deham9-iam

**Auto Scaling Group** (`auto_scaling.tf`)
- Instance Type: t2.micro
- Min/Max/Desired: 2/2/2 instances
- Distribution: Across both public subnets
- Scaling Policy: Target tracking based on CPU utilization (70% target)
- Health Check: ELB-based with 300s grace period

#### 2. Load Balancing

**Application Load Balancer** (`elb.tf`)
- Type: Internet-facing ALB
- Subnets: Both public subnets
- Protocol: HTTP (port 80)
- Health Check:
  - Interval: 10 seconds
  - Timeout: 5 seconds
  - Healthy threshold: 2
  - Unhealthy threshold: 2
  - Path: /

#### 3. Database

**Aurora MySQL Cluster** (`rds.tf`)
- Engine: Aurora MySQL 5.7.mysql_aurora.2.11.1
- Cluster: 2 instances across both AZs
- Instance Class: db.t3.small
- Database Name: auroradb
- Master Username: admin
- Location: Private subnets

#### 4. Storage

**S3 Bucket** (`s3.tf`)
- Bucket Name: deham9alblogs
- Purpose: ALB access logs
- Versioning: Enabled

**WordPress Content**
- Source Bucket: restartproject
- Synced to: /var/www/html on EC2 instances

#### 5. Security Groups

**sg_vpc** (`sg.tf`)
- Inbound: HTTP (80), HTTPS (443), SSH (22)
- Outbound: All traffic
- Applied to: EC2 instances and ALB

**allow_ssh**
- Inbound: SSH (22)
- Applied to: EC2 instances

**allow_aurora_access**
- Inbound: All traffic (port 0-65535)
- Applied to: Aurora cluster

#### 6. Networking

**Internet Gateway**
- Provides internet access for public subnets

**NAT Gateway**
- Elastic IP attached
- Located in Public Subnet 1
- Provides outbound internet access for private subnets

**Route Tables**
- Public Route Table: Routes 0.0.0.0/0 to Internet Gateway
- Private Route Table: Routes 0.0.0.0/0 to NAT Gateway

## File Structure

```
.
├── main.tf                      # VPC, subnets, IGW, NAT, route tables
├── ec2.tf                       # EC2 instance configuration
├── auto_scaling.tf              # Launch template and ASG
├── elb.tf                       # Application Load Balancer
├── rds.tf                       # Aurora MySQL cluster
├── s3.tf                        # S3 bucket for logs
├── sg.tf                        # Security groups
├── vars.tf                      # Variable definitions
├── providers.tf                 # Terraform and AWS provider config
├── userdata.tpl                 # User data script for EC2
├── userdatalaunchtemplate.tpl   # User data for ASG instances
└── README.md                    # Project description
```

## Prerequisites

### Required Software

1. **Terraform**
   - Version: 1.0.0 or higher (compatible with AWS provider ~> 5.0)
   - Installation:
     ```bash
     # Windows (using Chocolatey)
     choco install terraform
     
     # macOS (using Homebrew)
     brew install terraform
     
     # Linux (using package manager)
     wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
     unzip terraform_1.6.0_linux_amd64.zip
     sudo mv terraform /usr/local/bin/
     ```
   - Verify installation:
     ```bash
     terraform version
     ```

2. **AWS CLI**
   - Version: 2.x or higher
   - Installation:
     ```bash
     # Windows
     msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
     
     # macOS
     curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
     sudo installer -pkg AWSCLIV2.pkg -target /
     
     # Linux
     curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
     unzip awscliv2.zip
     sudo ./aws/install
     ```
   - Verify installation:
     ```bash
     aws --version
     ```

3. **Git** (for version control)
   ```bash
   git --version
   ```

### AWS Account Requirements

1. **AWS Account**
   - Active AWS account with billing enabled
   - Access to us-east-1 region

2. **IAM User Credentials**
   - IAM user with programmatic access
   - Required permissions:
     - EC2 (full access)
     - VPC (full access)
     - RDS (full access)
     - S3 (full access)
     - ELB (full access)
     - Auto Scaling (full access)
     - IAM (read access for roles)
   
   - Recommended: Use AWS managed policies:
     - `AmazonEC2FullAccess`
     - `AmazonVPCFullAccess`
     - `AmazonRDSFullAccess`
     - `AmazonS3FullAccess`
     - `ElasticLoadBalancingFullAccess`
     - `AutoScalingFullAccess`

3. **Configure AWS CLI**
   ```bash
   aws configure
   ```
   
   Enter the following when prompted:
   ```
   AWS Access Key ID: [Your Access Key]
   AWS Secret Access Key: [Your Secret Key]
   Default region name: us-east-1
   Default output format: json
   ```
   
   Verify configuration:
   ```bash
   aws sts get-caller-identity
   ```

### AWS Resources to Create Before Deployment

#### 1. Create SSH Key Pair

**Option A: Using AWS Console**
1. Navigate to EC2 → Key Pairs
2. Click "Create key pair"
3. Name: `deham9-iam`
4. Key pair type: RSA
5. Private key format: .pem
6. Click "Create key pair"
7. Save the downloaded .pem file securely

**Option B: Using AWS CLI**
```bash
aws ec2 create-key-pair \
  --key-name deham9-iam \
  --query 'KeyMaterial' \
  --output text > deham9-iam.pem

# Set proper permissions (Linux/macOS)
chmod 400 deham9-iam.pem
```

#### 2. Create IAM Instance Profile for S3 Access

**Step 1: Create IAM Policy**
```bash
# Create policy document
cat > ec2-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::restartproject",
        "arn:aws:s3:::restartproject/*"
      ]
    }
  ]
}
EOF

# Create the policy
aws iam create-policy \
  --policy-name EC2-S3-ReadAccess \
  --policy-document file://ec2-s3-policy.json
```

**Step 2: Create IAM Role**
```bash
# Create trust policy
cat > ec2-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name deham10-ec2-role \
  --assume-role-policy-document file://ec2-trust-policy.json

# Attach the policy to the role
aws iam attach-role-policy \
  --role-name deham10-ec2-role \
  --policy-arn arn:aws:iam::[YOUR-ACCOUNT-ID]:policy/EC2-S3-ReadAccess
```

**Step 3: Create Instance Profile**
```bash
# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name deham10_ec2

# Add role to instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name deham10_ec2 \
  --role-name deham10-ec2-role
```

#### 3. Create S3 Bucket for WordPress Content

```bash
# Create the bucket
aws s3 mb s3://restartproject --region us-east-1

# Upload WordPress files (if you have them locally)
# First, download WordPress
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz

# Upload to S3
aws s3 sync wordpress/ s3://restartproject/

# Verify upload
aws s3 ls s3://restartproject/
```

**Alternative: Prepare WordPress with Database Configuration**

If you want to pre-configure WordPress:

```bash
# Download WordPress
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cd wordpress

# Create wp-config.php from sample
cp wp-config-sample.php wp-config.php

# Edit wp-config.php with your database details
# (You'll need to update this after Aurora is created)
nano wp-config.php

# Update these lines:
# define('DB_NAME', 'auroradb');
# define('DB_USER', 'admin');
# define('DB_PASSWORD', 'wWkTAeM3n3ZQUlOBQzh0');
# define('DB_HOST', 'your-aurora-endpoint');

# Upload to S3
cd ..
aws s3 sync wordpress/ s3://restartproject/
```

### Verify Prerequisites

Run this checklist before deployment:

```bash
# 1. Check Terraform
terraform version

# 2. Check AWS CLI
aws --version

# 3. Verify AWS credentials
aws sts get-caller-identity

# 4. Verify key pair exists
aws ec2 describe-key-pairs --key-names deham9-iam

# 5. Verify IAM instance profile exists
aws iam get-instance-profile --instance-profile-name deham10_ec2

# 6. Verify S3 bucket exists
aws s3 ls s3://restartproject/

# 7. Check available regions
aws ec2 describe-regions --query 'Regions[?RegionName==`us-east-1`]'
```

All commands should return successful responses before proceeding with deployment.

## Setup and Deployment Guide

### Step 1: Clone or Download the Project

```bash
# If using Git
git clone <repository-url>
cd aws_multiaz_wordpress

# Or download and extract the ZIP file
# Then navigate to the project directory
```

### Step 2: Review and Customize Configuration

Before deploying, review and customize the following files:

**1. Update `vars.tf` (if needed)**
```bash
# Edit variables if you want to change defaults
nano vars.tf
```

**2. Review `main.tf`**
- Verify VPC CIDR blocks match your requirements
- Check subnet configurations
- Confirm availability zones (us-east-1a, us-east-1b)

**3. Update `rds.tf`**
⚠️ **Important**: Change the hard-coded database password
```hcl
# Line 18 in rds.tf
master_password = "YOUR-SECURE-PASSWORD-HERE"
```

**4. Update `ec2.tf` and `auto_scaling.tf`**
- Verify key pair name matches yours: `deham9-iam`
- Verify IAM instance profile name: `deham10_ec2`
- Update AMI IDs if needed (current: Amazon Linux 2023)

**5. Update `userdata.tpl` and `userdatalaunchtemplate.tpl`**
- Verify S3 bucket name: `restartproject`
- Customize WordPress installation steps if needed

### Step 3: Initialize Terraform

Initialize the Terraform working directory:

```bash
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/template versions...
- Installing hashicorp/aws v5.x.x...
- Installing hashicorp/template v2.2.0...

Terraform has been successfully initialized!
```

### Step 4: Validate Configuration

Validate the Terraform configuration files:

```bash
terraform validate
```

Expected output:
```
Success! The configuration is valid.
```

### Step 5: Format Code (Optional)

Format Terraform files for consistency:

```bash
terraform fmt
```

### Step 6: Review Deployment Plan

Generate and review the execution plan:

```bash
terraform plan
```

This will show:
- Resources to be created (should be ~30+ resources)
- VPC, subnets, route tables
- EC2 instances, Auto Scaling Group
- Load Balancer and target groups
- Aurora cluster and instances
- Security groups
- S3 bucket

Review the plan carefully to ensure everything looks correct.

**Save the plan (optional):**
```bash
terraform plan -out=tfplan
```

### Step 7: Deploy Infrastructure

Apply the Terraform configuration:

```bash
terraform apply
```

Or if you saved the plan:
```bash
terraform apply tfplan
```

When prompted, type `yes` to confirm.

### Step 8: Monitor Deployment Progress

The deployment will take approximately 10-15 minutes:

```
Deployment Timeline:
├─ 0-2 min:   VPC, Subnets, Route Tables, Internet Gateway
├─ 2-4 min:   NAT Gateway (with Elastic IP)
├─ 4-6 min:   Security Groups
├─ 6-8 min:   S3 Bucket, EC2 Instance
├─ 8-10 min:  Load Balancer, Target Groups
├─ 10-15 min: Aurora Cluster (longest component)
└─ 15+ min:   Auto Scaling Group, Final configurations
```

Watch for any errors during deployment. Common issues:
- Insufficient IAM permissions
- Resource limits exceeded
- Availability zone capacity issues

### Step 9: Retrieve Outputs

After successful deployment, retrieve important information:

```bash
# Get all outputs
terraform output

# Get specific output
terraform output public_ip
```

**Important Endpoints:**

```bash
# Get ALB DNS name
aws elbv2 describe-load-balancers \
  --names nit-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text

# Get Aurora cluster endpoint
aws rds describe-db-clusters \
  --db-cluster-identifier auroracluster \
  --query 'DBClusters[0].Endpoint' \
  --output text

# Get EC2 public IP
terraform output public_ip
```

### Step 10: Verify Deployment

**1. Check VPC and Networking**
```bash
# Verify VPC
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=deham9-vpc"

# Verify subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>"

# Verify Internet Gateway
aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=deham9-igw"

# Verify NAT Gateway
aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=deham9-nat-gateway"
```

**2. Check EC2 Instances**
```bash
# List EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=awsrestartproject" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress]' \
  --output table

# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names awsrestart-autoscaling-group
```

**3. Check Load Balancer**
```bash
# Verify ALB
aws elbv2 describe-load-balancers --names nit-alb

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>
```

**4. Check Aurora Database**
```bash
# Verify Aurora cluster
aws rds describe-db-clusters --db-cluster-identifier auroracluster

# Check cluster instances
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=auroracluster"
```

**5. Check S3 Bucket**
```bash
# Verify S3 bucket
aws s3 ls s3://deham9alblogs/

# Check versioning
aws s3api get-bucket-versioning --bucket deham9alblogs
```

### Step 11: Access and Configure WordPress

**1. Access WordPress via Load Balancer**

```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names nit-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "Access WordPress at: http://$ALB_DNS"
```

Open the URL in your browser. You should see:
- WordPress installation page (if fresh install)
- WordPress site (if content was pre-configured in S3)

**2. SSH to EC2 Instance**

```bash
# Get EC2 public IP
EC2_IP=$(terraform output -raw public_ip)

# SSH to instance
ssh -i deham9-iam.pem ec2-user@$EC2_IP
```

**3. Verify Services on EC2**

Once connected via SSH:

```bash
# Check Apache status
sudo systemctl status httpd

# Check MariaDB status
sudo systemctl status mariadb

# Verify WordPress files
ls -la /var/www/html/

# Check Apache logs
sudo tail -f /var/log/httpd/access_log
sudo tail -f /var/log/httpd/error_log
```

**4. Configure WordPress Database Connection**

If WordPress is not yet configured:

```bash
# SSH to EC2 instance
ssh -i deham9-iam.pem ec2-user@$EC2_IP

# Navigate to WordPress directory
cd /var/www/html

# Get Aurora endpoint
AURORA_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier auroracluster \
  --query 'DBClusters[0].Endpoint' \
  --output text)

# Edit wp-config.php
sudo nano wp-config.php

# Update these values:
# define('DB_NAME', 'auroradb');
# define('DB_USER', 'admin');
# define('DB_PASSWORD', 'wWkTAeM3n3ZQUlOBQzh0');
# define('DB_HOST', '<aurora-endpoint>');

# Set proper permissions
sudo chown -R apache:apache /var/www/html/
sudo chmod -R 755 /var/www/html/

# Restart Apache
sudo systemctl restart httpd
```

**5. Complete WordPress Installation**

Access the WordPress installation wizard:
```
http://<alb-dns-name>/wp-admin/install.php
```

Follow the on-screen instructions:
1. Select language
2. Enter site title
3. Create admin username and password
4. Enter admin email
5. Click "Install WordPress"

### Step 12: Test High Availability and Auto Scaling

**1. Test Load Balancer Distribution**

```bash
# Make multiple requests to see load balancing
for i in {1..10}; do
  curl -s http://$ALB_DNS | grep -o "Instance.*"
  sleep 1
done
```

**2. Test Auto Scaling with Stress Testing**

#### Option A: Using Apache Bench (ab) - Simple Load Testing

**Install Apache Bench:**
```bash
# On Amazon Linux / RHEL / CentOS
sudo yum install httpd-tools -y

# On Ubuntu / Debian
sudo apt-get install apache2-utils -y

# On macOS
brew install httpd
```

**Run Basic Load Test:**
```bash
# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names nit-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Test with 1000 requests, 50 concurrent connections
ab -n 1000 -c 50 http://$ALB_DNS/

# More aggressive test: 10,000 requests, 100 concurrent
ab -n 10000 -c 100 http://$ALB_DNS/

# Sustained load test (5 minutes)
ab -t 300 -c 50 http://$ALB_DNS/
```

**Expected Output:**
```
Concurrency Level:      50
Time taken for tests:   45.123 seconds
Complete requests:      1000
Failed requests:        0
Requests per second:    22.16 [#/sec] (mean)
Time per request:       2256.150 [ms] (mean)
```

#### Option B: Using Apache JMeter - Advanced Load Testing

**Install JMeter:**
```bash
# Download JMeter
wget https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.tgz
tar -xzf apache-jmeter-5.6.3.tgz
cd apache-jmeter-5.6.3/bin

# Run JMeter GUI
./jmeter
```

**Create JMeter Test Plan:**
1. Add Thread Group: Right-click Test Plan → Add → Threads → Thread Group
   - Number of Threads: 100
   - Ramp-up Period: 60 seconds
   - Loop Count: 10

2. Add HTTP Request: Right-click Thread Group → Add → Sampler → HTTP Request
   - Server Name: `<alb-dns-name>`
   - Port: 80
   - Path: /

3. Add Listeners:
   - View Results Tree
   - Summary Report
   - Graph Results

4. Run Test: Click green "Start" button

**Run JMeter in CLI Mode (Recommended for load testing):**
```bash
./jmeter -n -t test-plan.jmx -l results.jtl -e -o report/

# Parameters:
# -n: Non-GUI mode
# -t: Test plan file
# -l: Results file
# -e: Generate report
# -o: Output folder
```

#### Option C: Using stress-ng - CPU Stress Testing

**SSH to EC2 Instance and Generate CPU Load:**
```bash
# SSH to one of the ASG instances
ssh -i deham9-iam.pem ec2-user@<instance-ip>

# Install stress-ng
sudo yum install stress-ng -y

# Generate CPU load (all cores, 5 minutes)
stress-ng --cpu 0 --timeout 300s --metrics-brief

# Generate specific CPU load (80% for 10 minutes)
stress-ng --cpu 2 --cpu-load 80 --timeout 600s
```

#### Option D: Using Locust - Python-based Load Testing

**Install Locust:**
```bash
# Install Python and pip (if not already installed)
sudo yum install python3 python3-pip -y

# Install Locust
pip3 install locust
```

**Create Locust Test File (locustfile.py):**
```python
from locust import HttpUser, task, between

class WordPressUser(HttpUser):
    wait_time = between(1, 3)  # Wait 1-3 seconds between requests
    
    @task(3)
    def view_homepage(self):
        self.client.get("/")
    
    @task(1)
    def view_post(self):
        self.client.get("/sample-post/")
    
    @task(1)
    def view_about(self):
        self.client.get("/about/")

# Run with:
# locust -f locustfile.py --host=http://<alb-dns> --users 100 --spawn-rate 10
```

**Run Locust Test:**
```bash
# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names nit-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Run headless (no web UI)
locust -f locustfile.py \
  --host=http://$ALB_DNS \
  --users 100 \
  --spawn-rate 10 \
  --run-time 10m \
  --headless

# Or run with web UI (access at http://localhost:8089)
locust -f locustfile.py --host=http://$ALB_DNS
```

#### Option E: Using AWS CloudWatch Synthetics - Continuous Testing

**Create Canary Script:**
```bash
# Create canary via AWS Console
# Navigate to: CloudWatch → Application Monitoring → Synthetics Canaries
# Or use AWS CLI:

aws synthetics create-canary \
  --name wordpress-load-test \
  --artifact-s3-location s3://deham9alblogs/canary/ \
  --execution-role-arn arn:aws:iam::<account-id>:role/CloudWatchSyntheticsRole \
  --schedule Expression="rate(5 minutes)" \
  --runtime-version syn-nodejs-puppeteer-3.9 \
  --code Handler="index.handler",S3Bucket="<bucket>",S3Key="canary.zip"
```

### Monitoring Auto Scaling During Load Tests

**1. Monitor Auto Scaling Activity in Real-Time**

```bash
# Watch Auto Scaling activities
watch -n 5 'aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name awsrestart-autoscaling-group \
  --max-records 5 \
  --query "Activities[*].[StartTime,Description,StatusCode]" \
  --output table'
```

**2. Monitor CloudWatch Metrics**

```bash
# Get CPU utilization for ASG
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=awsrestart-autoscaling-group \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average \
  --query 'Datapoints[*].[Timestamp,Average]' \
  --output table

# Monitor ALB request count
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=app/nit-alb/<id> \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --output table
```

**3. Create CloudWatch Dashboard for Live Monitoring**

```bash
# Create dashboard JSON
cat > dashboard.json <<'EOF'
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/EC2", "CPUUtilization", {"stat": "Average"}]
        ],
        "period": 60,
        "stat": "Average",
        "region": "us-east-1",
        "title": "ASG CPU Utilization"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", {"stat": "Sum"}]
        ],
        "period": 60,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "ALB Request Count"
      }
    }
  ]
}
EOF

# Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name WordPress-LoadTest \
  --dashboard-body file://dashboard.json
```

**4. Monitor Target Health**

```bash
# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
  --names nit-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Watch target health
watch -n 5 "aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table"
```

### Complete Load Testing Workflow

**Step-by-Step Load Test Procedure:**

```bash
#!/bin/bash
# load-test.sh - Complete load testing script

# 1. Get initial state
echo "=== Initial State ==="
ASG_NAME="awsrestart-autoscaling-group"
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names nit-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB DNS: $ALB_DNS"
echo "Current ASG capacity:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize,Instances[*].InstanceId]' \
  --output table

# 2. Start monitoring in background
echo -e "\n=== Starting Monitoring ==="
(
  while true; do
    CAPACITY=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names $ASG_NAME \
      --query 'AutoScalingGroups[0].DesiredCapacity' \
      --output text)
    CPU=$(aws cloudwatch get-metric-statistics \
      --namespace AWS/EC2 \
      --metric-name CPUUtilization \
      --dimensions Name=AutoScalingGroupName,Value=$ASG_NAME \
      --start-time $(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 60 \
      --statistics Average \
      --query 'Datapoints[0].Average' \
      --output text)
    echo "$(date +%H:%M:%S) - Capacity: $CAPACITY, CPU: ${CPU}%"
    sleep 30
  done
) &
MONITOR_PID=$!

# 3. Run load test
echo -e "\n=== Starting Load Test ==="
echo "Running Apache Bench test for 5 minutes..."
ab -t 300 -c 100 -g results.tsv http://$ALB_DNS/ > ab-results.txt 2>&1

# 4. Wait for scaling to complete
echo -e "\n=== Waiting for Auto Scaling ==="
sleep 120

# 5. Check final state
echo -e "\n=== Final State ==="
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize,Instances[*].InstanceId]' \
  --output table

# 6. Show scaling activities
echo -e "\n=== Scaling Activities ==="
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name $ASG_NAME \
  --max-records 5 \
  --query 'Activities[*].[StartTime,Description,StatusCode]' \
  --output table

# 7. Stop monitoring
kill $MONITOR_PID

echo -e "\n=== Load Test Complete ==="
echo "Results saved to: ab-results.txt"
```

**Run the script:**
```bash
chmod +x load-test.sh
./load-test.sh
```

### Expected Auto Scaling Behavior

**Timeline of Events:**

```
T+0:00  - Load test starts (100 concurrent users)
T+0:30  - CPU utilization begins to rise
T+1:00  - CPU reaches 70% threshold
T+1:30  - CloudWatch alarm triggers
T+2:00  - Auto Scaling initiates scale-out
T+2:30  - New instance launches
T+3:00  - New instance passes health checks
T+3:30  - New instance added to target group
T+4:00  - Load distributed across instances
T+5:00  - Load test ends
T+7:00  - CPU drops below 70%
T+12:00 - Scale-in cooldown period ends
T+15:00 - Auto Scaling may scale in (if CPU remains low)
```

### Interpreting Load Test Results

**Apache Bench Metrics:**
```
Key Metrics to Monitor:
├─ Requests per second: Should increase with scaling
├─ Time per request: Should decrease with scaling
├─ Failed requests: Should remain at 0
├─ 50th percentile: Median response time
├─ 95th percentile: Response time for 95% of requests
└─ 99th percentile: Worst-case response time
```

**Success Criteria:**
- ✅ CPU utilization triggers scaling at ~70%
- ✅ New instances launch within 2-3 minutes
- ✅ No failed requests during scaling
- ✅ Response times remain acceptable (<2 seconds)
- ✅ All instances pass health checks
- ✅ Load is distributed evenly across instances

**3. Test Database Failover**

```bash
# Connect to Aurora cluster
mysql -h <aurora-endpoint> -u admin -p

# Check cluster status
SHOW STATUS LIKE 'wsrep_cluster_status';
```

### Step 13: Stress Testing and Auto Scaling Validation

This section provides comprehensive stress testing procedures to validate that your Auto Scaling Group responds correctly to increased load.

#### Quick Start: Using load-test.sh

The project includes `load-test.sh` - an automated bash script with monitoring.

**Run the load test:**
```bash
# Make the script executable
chmod +x load-test.sh

# Run the load test
./load-test.sh
```

**What it does:**
1. Retrieves initial ASG state
2. Starts background monitoring (capacity, CPU every 30 seconds)
3. Runs Apache Bench load test (100 concurrent users, 5 minutes)
4. Waits for Auto Scaling to stabilize
5. Shows final state and scaling activities
6. Generates detailed reports

**Output files:**
- `ab-results-TIMESTAMP.txt` - Detailed results
- `ab-results-TIMESTAMP.tsv` - Gnuplot data
- `monitor-TIMESTAMP.log` - CSV metrics log

#### Using Locust for Advanced Testing

The project includes `locustfile.py` for realistic user simulation.

**Install Locust:**
```bash
pip3 install locust
```

**Run Locust tests:**
```bash
# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names nit-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Run with Web UI
locust -f locustfile.py --host=http://$ALB_DNS
# Open http://localhost:8089

# Run headless (100 users, 10 minutes)
locust -f locustfile.py \
  --host=http://$ALB_DNS \
  --users 100 \
  --spawn-rate 10 \
  --run-time 10m \
  --headless

# Generate HTML report
locust -f locustfile.py \
  --host=http://$ALB_DNS \
  --users 100 \
  --spawn-rate 10 \
  --run-time 10m \
  --headless \
  --html report.html
```

**Locust features:**
- WordPressUser: Simulates typical visitor (homepage, posts, pages)
- HeavyUser: Aggressive load generation
- StepLoadShape: Gradual load increase (20→200 users over 10 min)

#### Alternative: Apache Bench (Quick Testing)

```bash
# Install Apache Bench
sudo yum install httpd-tools -y

# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names nit-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Run 5-minute sustained load test
ab -t 300 -c 100 http://$ALB_DNS/

# More aggressive test
ab -n 10000 -c 100 http://$ALB_DNS/
```

#### Monitoring During Tests

**Monitor Auto Scaling activities:**
```bash
# Watch scaling activities (updates every 5 seconds)
watch -n 5 'aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name awsrestart-autoscaling-group \
  --max-records 5 \
  --query "Activities[*].[StartTime,Description,StatusCode]" \
  --output table'
```

**Monitor CPU utilization:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=awsrestart-autoscaling-group \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average,Maximum \
  --output table
```

**Monitor target health:**
```bash
TG_ARN=$(aws elbv2 describe-target-groups \
  --names nit-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

watch -n 5 "aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table"
```

#### Expected Auto Scaling Timeline

```
T+0:00  - Load test starts (100 concurrent users)
T+0:30  - CPU utilization rises (20% → 45%)
T+1:00  - CPU reaches 70% threshold
T+1:30  - CloudWatch alarm triggers
T+2:00  - Auto Scaling initiates scale-out
T+2:30  - New instance launches
T+3:00  - New instance passes health checks
T+3:30  - New instance added to target group
T+4:00  - Load distributed across instances
T+5:00  - Load test ends
T+7:00  - CPU drops below 70%
T+12:00 - Scale-in cooldown period ends
T+15:00 - Auto Scaling may scale in
```

#### Success Criteria

✅ CPU utilization reaches 70% during load test  
✅ CloudWatch alarm triggers within 1-2 minutes  
✅ New instances launch successfully  
✅ All instances show "Healthy" in target group  
✅ Zero failed requests during scaling  
✅ Response times remain < 2 seconds (95th percentile)  
✅ Instances terminate after cooldown period

#### Load Testing Checklist

Before testing:
- [ ] Verify ASG min/max/desired capacity
- [ ] Confirm scaling policy is active (70% CPU)
- [ ] Check CloudWatch alarms enabled
- [ ] Ensure sufficient EC2 limits
- [ ] Set up monitoring dashboard

After testing:
- [ ] Review scaling activities
- [ ] Analyze CloudWatch metrics
- [ ] Check for failed requests
- [ ] Verify scale-in behavior
- [ ] Document results

For detailed stress testing documentation, see the complete guide in the "Stress Testing and Auto Scaling Validation" section.

### Step 14: Configure Monitoring (Optional)

**1. Enable CloudWatch Logs**

```bash
# Install CloudWatch agent on EC2
sudo yum install amazon-cloudwatch-agent -y

# Configure log collection
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
```

**2. Create CloudWatch Dashboard**

```bash
# Create dashboard via AWS Console
# Navigate to CloudWatch → Dashboards → Create dashboard
# Add widgets for:
# - EC2 CPU utilization
# - ALB request count
# - Aurora connections
# - Auto Scaling group metrics
```

### Step 14: Backup Configuration

Save your Terraform state and configuration:

```bash
# Backup terraform.tfstate
cp terraform.tfstate terraform.tfstate.backup

# Backup .terraform directory
tar -czf terraform-backup.tar.gz .terraform/

# Store securely (DO NOT commit to public repositories)
```

### Post-Deployment Checklist

- [ ] WordPress is accessible via ALB DNS
- [ ] All EC2 instances are healthy in target group
- [ ] Auto Scaling Group has 2 running instances
- [ ] Aurora cluster has 2 instances (writer + reader)
- [ ] Database connection is working
- [ ] S3 bucket is receiving ALB logs
- [ ] SSH access to EC2 instances works
- [ ] Security groups are properly configured
- [ ] CloudWatch monitoring is enabled (optional)
- [ ] Backup strategy is in place

### Troubleshooting Deployment Issues

**Issue: Terraform init fails**
```bash
# Clear Terraform cache
rm -rf .terraform .terraform.lock.hcl

# Re-initialize
terraform init
```

**Issue: Insufficient IAM permissions**
```bash
# Check current IAM permissions
aws iam get-user
aws iam list-attached-user-policies --user-name <your-username>

# Contact AWS administrator to grant required permissions
```

**Issue: Resource already exists**
```bash
# Import existing resource
terraform import aws_vpc.dev_vpc <vpc-id>

# Or destroy and recreate
terraform destroy
terraform apply
```

**Issue: Aurora cluster creation timeout**
```bash
# Check Aurora cluster status
aws rds describe-db-clusters --db-cluster-identifier auroracluster

# Wait for status to be 'available'
# This can take 10-15 minutes
```

**Issue: EC2 instances not healthy**
```bash
# Check instance status
aws ec2 describe-instance-status --instance-ids <instance-id>

# Check system logs
aws ec2 get-console-output --instance-id <instance-id>

# SSH and check services
ssh -i deham9-iam.pem ec2-user@<public-ip>
sudo systemctl status httpd
```

## Instance Initialization

Both EC2 and ASG instances run user data scripts that:

1. Update the system: `sudo yum update -y`
2. Install Apache web server: `sudo yum install -y httpd`
3. Install PHP and MariaDB client: `sudo yum install -y mariadb105-server php php-mysqlnd unzip`
4. Start and enable Apache: `sudo systemctl start httpd && sudo systemctl enable httpd`
5. Start and enable MariaDB: `sudo systemctl start mariadb && sudo systemctl enable mariadb`
6. Sync WordPress content from S3: `aws s3 sync s3://restartproject/ /var/www/html`

## Database Connection

To connect to Aurora from an EC2 instance:

```bash
# Install MariaDB client (if not already installed)
sudo yum install mariadb -y

# Connect to the writer instance
mysql -h <cluster-endpoint> -P 3306 -u admin -p
# Password: wWkTAeM3n3ZQUlOBQzh0
```

Cluster endpoints can be found in the AWS RDS console or via:
```bash
aws rds describe-db-clusters --db-cluster-identifier auroracluster
```

## Monitoring and Maintenance

### Auto Scaling

The ASG automatically scales based on CPU utilization:
- Target: 70% average CPU
- Scale up: When CPU > 70% for sustained period
- Scale down: When CPU < 70% for sustained period

### Health Checks

- ALB performs health checks every 10 seconds
- Unhealthy instances are automatically replaced
- Grace period: 300 seconds for new instances

### Logs

ALB access logs are stored in the S3 bucket: `s3://deham9alblogs/`

## Cost Estimation

### Detailed Cost Breakdown (us-east-1 Region)

#### Compute Resources

| Resource | Specification | Hourly Rate | Daily Cost | Monthly Cost |
|----------|--------------|-------------|------------|--------------|
| EC2 t3.micro (1 instance) | 2 vCPU, 1 GB RAM | $0.0104 | $0.25 | $7.59 |
| EC2 t2.micro (2 ASG instances) | 1 vCPU, 1 GB RAM each | $0.0116 × 2 | $0.56 | $16.70 |
| **Compute Subtotal** | | | **$0.81** | **$24.29** |

#### Database

| Resource | Specification | Hourly Rate | Daily Cost | Monthly Cost |
|----------|--------------|-------------|------------|--------------|
| Aurora MySQL db.t3.small (Writer) | 2 vCPU, 2 GB RAM | $0.041 | $0.98 | $29.93 |
| Aurora MySQL db.t3.small (Reader) | 2 vCPU, 2 GB RAM | $0.041 | $0.98 | $29.93 |
| Aurora Storage (10 GB) | First 10 GB | $0.10/GB-month | $0.03 | $1.00 |
| Aurora I/O (1M requests) | Per 1M requests | $0.20 | $0.20 | $6.00 |
| **Database Subtotal** | | | **$2.19** | **$66.86** |

#### Networking

| Resource | Specification | Hourly Rate | Daily Cost | Monthly Cost |
|----------|--------------|-------------|------------|--------------|
| Application Load Balancer | ALB hours | $0.0225 | $0.54 | $16.43 |
| ALB LCU (Load Balancer Capacity Units) | ~5 LCUs average | $0.008 × 5 | $0.96 | $29.20 |
| NAT Gateway | Data processing | $0.045 | $1.08 | $32.85 |
| NAT Gateway Data Transfer | 10 GB/day | $0.045/GB | $0.45 | $13.50 |
| Elastic IP (NAT Gateway) | Associated with NAT | $0.00 | $0.00 | $0.00 |
| Data Transfer Out (Internet) | 10 GB/day to internet | $0.09/GB | $0.90 | $27.00 |
| **Networking Subtotal** | | | **$3.93** | **$119.98** |

#### Storage

| Resource | Specification | Daily Rate | Daily Cost | Monthly Cost |
|----------|--------------|------------|------------|--------------|
| S3 Standard Storage (deham9alblogs) | 1 GB ALB logs | $0.023/GB-month | $0.001 | $0.02 |
| S3 Standard Storage (restartproject) | 500 MB WordPress | $0.023/GB-month | $0.0004 | $0.01 |
| S3 PUT/COPY/POST Requests | 1,000 requests/day | $0.005/1000 | $0.005 | $0.15 |
| S3 GET Requests | 10,000 requests/day | $0.0004/1000 | $0.004 | $0.12 |
| **Storage Subtotal** | | | **$0.01** | **$0.30** |

#### Additional Costs

| Resource | Specification | Daily Cost | Monthly Cost |
|----------|--------------|------------|--------------|
| EBS Volumes (3 instances × 8 GB) | gp3 volumes | $0.03 | $0.96 |
| CloudWatch Logs (optional) | 1 GB ingestion | $0.02 | $0.50 |
| CloudWatch Metrics (optional) | Custom metrics | $0.01 | $0.30 |
| Route 53 (if used) | Hosted zone | $0.02 | $0.50 |
| **Additional Subtotal** | | **$0.08** | **$2.26** |

### Total Cost Summary

| Period | Cost (USD) | Notes |
|--------|-----------|-------|
| **Hourly** | **$0.29** | Average per hour |
| **Daily** | **$7.02** | 24-hour period |
| **Weekly** | **$49.14** | 7-day period |
| **Monthly** | **$213.69** | 30-day period (730 hours) |
| **Yearly** | **$2,564.28** | 365-day period |

### Cost Breakdown by Category

```
Daily Cost Distribution:
├─ Networking:     $3.93 (56%)  ████████████████████████████
├─ Database:       $2.19 (31%)  ███████████████
├─ Compute:        $0.81 (12%)  ██████
├─ Additional:     $0.08 (1%)   █
└─ Storage:        $0.01 (<1%)  █
                   ─────
Total:             $7.02/day
```

### Cost Optimization Strategies

#### Immediate Savings (Can reduce daily cost to ~$4.50)

1. **Remove Duplicate EC2 Instance** (-$0.25/day)
   - Currently running both standalone EC2 and ASG
   - Remove standalone instance, use only ASG
   ```bash
   # Comment out or remove in ec2.tf
   # resource "aws_instance" "instance" { ... }
   ```

2. **Reduce ASG to 1 Instance During Low Traffic** (-$0.28/day)
   - Change min_size from 2 to 1 in auto_scaling.tf
   - Scales up automatically when needed
   ```hcl
   min_size = 1
   desired_capacity = 1
   ```

3. **Use Aurora Serverless v2** (-$1.50/day)
   - Automatically scales based on demand
   - Minimum ACUs: 0.5 (~$0.12/hour)
   - Only pay for actual usage

4. **Schedule Resources for Non-Production** (-$2.00/day)
   - Stop instances during off-hours (e.g., nights, weekends)
   - Use AWS Instance Scheduler or Lambda
   - Example: Run only 12 hours/day = 50% savings

#### Long-Term Savings (Can reduce monthly cost by 40-60%)

1. **Reserved Instances** (1-year commitment)
   - EC2 Reserved Instances: 30-40% discount
   - RDS Reserved Instances: 35-45% discount
   - Savings: ~$60-80/month

2. **Savings Plans** (1 or 3-year commitment)
   - Compute Savings Plans: Up to 66% discount
   - More flexible than Reserved Instances
   - Savings: ~$70-100/month

3. **Use Spot Instances for ASG** (for non-critical workloads)
   - Up to 90% discount vs On-Demand
   - Risk: Can be interrupted
   - Savings: ~$0.50/day on ASG instances

4. **Optimize Data Transfer**
   - Use CloudFront CDN to reduce data transfer costs
   - Enable S3 Transfer Acceleration
   - Compress content (gzip)
   - Savings: ~$0.50-1.00/day

5. **Right-Size Resources**
   - Monitor actual usage with CloudWatch
   - Downgrade instance types if underutilized
   - Example: t3.micro → t3.nano = 50% savings
   - Savings: ~$0.40/day

### Free Tier Eligibility (First 12 Months)

If you're within AWS Free Tier (first 12 months):

| Service | Free Tier Allowance | Monthly Savings |
|---------|-------------------|-----------------|
| EC2 t2.micro | 750 hours/month | $7.59 |
| EBS gp2/gp3 | 30 GB | $0.96 |
| ALB | 750 hours + 15 LCUs | $16.43 |
| RDS | 750 hours db.t2.micro* | N/A (using Aurora) |
| S3 | 5 GB storage + requests | $0.30 |
| Data Transfer | 15 GB/month | $1.35 |

**Potential Free Tier Savings**: ~$26/month (~$0.87/day)

*Note: Aurora is not included in Free Tier, but RDS MySQL/PostgreSQL is.

### Cost Monitoring and Alerts

Set up billing alerts to avoid surprises:

```bash
# Create billing alarm (via AWS CLI)
aws cloudwatch put-metric-alarm \
  --alarm-name daily-cost-alert \
  --alarm-description "Alert when daily cost exceeds $10" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --evaluation-periods 1 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold

# Create budget (via AWS Console)
# Navigate to: AWS Billing → Budgets → Create budget
# Set daily budget: $7-10
# Set monthly budget: $200-250
```

### Cost Comparison: Alternative Architectures

| Architecture | Daily Cost | Monthly Cost | Trade-offs |
|--------------|-----------|--------------|------------|
| **Current (Multi-AZ HA)** | $7.02 | $213.69 | High availability, fault-tolerant |
| **Single AZ** | $4.50 | $137.00 | Lower cost, no HA |
| **Aurora Serverless** | $5.20 | $158.40 | Auto-scaling, pay-per-use |
| **RDS MySQL (t3.micro)** | $4.80 | $146.00 | Lower cost, less scalable |
| **Single EC2 + RDS** | $2.50 | $76.00 | Minimal cost, no HA/scaling |
| **Lightsail** | $1.67 | $50.00 | Simplest, limited features |

### Real-World Cost Example

**Scenario**: Small business WordPress site with moderate traffic
- 10,000 page views/day
- 50 GB data transfer/month
- Running 16 hours/day (business hours)

**Optimized Daily Cost**: ~$4.50
- EC2 t3.micro (1 instance, 16h): $0.17
- Aurora t3.small (1 instance, 16h): $1.31
- ALB (16h): $0.36
- NAT Gateway (16h): $0.72
- Data transfer: $1.50
- Storage: $0.01
- Other: $0.43

**Monthly Cost**: ~$137.00 (36% savings vs 24/7 operation)

## Security Considerations

### Current Security Posture

⚠️ **Security Issues to Address**:

1. **Database Password**: Hard-coded in `rds.tf`
   - Recommendation: Use AWS Secrets Manager or SSM Parameter Store

2. **Aurora Public Access**: Instances set to `publicly_accessible = true`
   - Recommendation: Set to `false` for production

3. **SSH Access**: Open to 0.0.0.0/0
   - Recommendation: Restrict to specific IP ranges or use AWS Systems Manager Session Manager

4. **Aurora Security Group**: Allows all traffic from anywhere
   - Recommendation: Restrict to port 3306 from EC2 security group only

5. **No HTTPS**: ALB only configured for HTTP
   - Recommendation: Add SSL/TLS certificate and HTTPS listener

### Recommended Security Improvements

```hcl
# Example: Restrict Aurora security group
resource "aws_security_group" "allow_aurora_access" {
  name        = "allow_aurora_access"
  description = "Allow access to Aurora MySQL database"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    description     = "MySQL from EC2 instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_vpc.id]
  }

  tags = {
    Name = "aurora-stack-allow-aurora-MySQL"
  }
}
```

## Troubleshooting

### Issue: Instances not healthy in target group

1. Check security group allows traffic from ALB
2. Verify Apache is running: `sudo systemctl status httpd`
3. Check health check path returns 200 OK
4. Review ALB target group health check settings

### Issue: Cannot connect to Aurora

1. Verify security group allows traffic from EC2
2. Check Aurora cluster status in RDS console
3. Verify endpoint address is correct
4. Ensure EC2 instance has network connectivity to private subnets

### Issue: WordPress not loading

1. Check S3 sync completed: `ls -la /var/www/html`
2. Verify Apache is serving files: `curl localhost`
3. Check Apache error logs: `sudo tail -f /var/log/httpd/error_log`
4. Verify wp-config.php has correct database credentials

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

Type `yes` when prompted. This will remove all AWS resources created by Terraform.

⚠️ **Warning**: This action is irreversible. Ensure you have backups of any important data.

## Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| AWS_REGION | AWS region for deployment | us-east-1 | No |
| CIDR_BLOCK | CIDR block for internet access | 0.0.0.0/0 | No |
| AMIs | Region-specific AMI IDs | See vars.tf | No |

## Outputs

| Output | Description |
|--------|-------------|
| public_ip | Public IP of the standalone EC2 instance |
| ec2rendered | Rendered user data script for debugging |

## Known Issues

1. **Duplicate Compute Resources**: Both standalone EC2 instance and ASG are deployed
   - Consider removing the standalone EC2 instance if using ASG

2. **Auto Scaling Tags**: Syntax error in `auto_scaling.tf` line 60
   - Tags format incompatible with current provider version

3. **Hard-coded Values**: Several values are hard-coded (key names, IAM roles, bucket names)
   - Consider parameterizing these values

## Future Enhancements

1. **HTTPS Support**: Add ACM certificate and HTTPS listener
2. **CloudFront**: Add CDN for static content delivery
3. **ElastiCache**: Add Redis/Memcached for WordPress caching
4. **Backup Strategy**: Implement automated RDS snapshots and S3 backups
5. **Monitoring**: Add CloudWatch dashboards and alarms
6. **WAF**: Add AWS WAF for application-layer protection
7. **Secrets Management**: Move credentials to AWS Secrets Manager
8. **Multi-Region**: Extend to multi-region deployment for DR
9. **CI/CD**: Integrate with GitHub Actions or AWS CodePipeline
10. **Infrastructure Testing**: Add Terratest or similar testing framework

## Support and Contribution

For issues or questions, please refer to the project repository or contact the infrastructure team.

## License

This project is part of the AWS Restart program capstone project.

---

**Last Updated**: March 8, 2026
**Terraform Version**: Compatible with AWS Provider ~> 5.0
**AWS Region**: us-east-1
