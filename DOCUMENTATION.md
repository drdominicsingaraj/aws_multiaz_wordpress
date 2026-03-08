# Scalable and Fault-Tolerant WordPress on AWS

## Project Overview

This project deploys a highly available, scalable WordPress application on AWS using Terraform. The infrastructure spans multiple availability zones in the us-east-1 region, providing fault tolerance and automatic scaling capabilities.

## Architecture

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

1. **AWS Account** with appropriate permissions
2. **Terraform** installed (version compatible with AWS provider ~> 5.0)
3. **AWS CLI** configured with credentials
4. **SSH Key Pair** named "deham9-iam" created in us-east-1
5. **IAM Instance Profile** named "deham10_ec2" with S3 read permissions
6. **S3 Bucket** named "restartproject" with WordPress content

## Deployment Instructions

### 1. Initialize Terraform

```bash
terraform init
```

This downloads the required providers (AWS, Template).

### 2. Review the Plan

```bash
terraform plan
```

Review the resources that will be created.

### 3. Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm.

### 4. Deployment Time

Expected deployment time: 10-15 minutes
- VPC and networking: ~2 minutes
- NAT Gateway: ~2 minutes
- Aurora cluster: ~5-10 minutes
- EC2 and ASG: ~3 minutes

### 5. Access the Application

After deployment completes:

1. Get the ALB DNS name:
   ```bash
   terraform output
   ```

2. Access WordPress:
   ```
   http://<alb-dns-name>
   ```

3. SSH to EC2 instance:
   ```bash
   ssh -i deham9-iam.pem ec2-user@<public-ip>
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

Monthly cost estimate (us-east-1):

- EC2 t3.micro (1 instance): ~$7.50
- EC2 t2.micro (2 ASG instances): ~$15.00
- Aurora db.t3.small (2 instances): ~$73.00
- ALB: ~$16.20
- NAT Gateway: ~$32.40
- Data transfer: Variable
- S3 storage: Minimal

**Total estimated monthly cost**: ~$144-150 (excluding data transfer)

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
