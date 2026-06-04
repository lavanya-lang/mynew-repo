# Creates a production-oriented single-AZ VPC (3 public + 3 private subnets) with a single NAT Gateway and an S3 Gateway VPC endpoint, an encrypted EC2 instance in the private subnet, an encrypted S3 bucket with ownership enforcement and public access blocking, an IAM role with an S3 read/write policy scoped to the bucket, a CloudWatch dashboard and alarms targeting an SNS FIFO topic for alerts.
# Generated Terraform code for AWS in us-east-1

terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.25.0"
    }
  }
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "Name tag for the VPC"
  type        = string
  default     = "networking"
}

variable "availability_zone" {
  description = "Availability Zone to use (single-AZ design)"
  type        = string
  default     = "us-east-1a"
}

variable "public_subnet_count" {
  description = "Number of public subnets to create in the single AZ"
  type        = number
  default     = 3
  validation {
    condition     = var.public_subnet_count == 3
    error_message = "This plan is authored for exactly 3 public subnets."
  }
}

variable "private_subnet_count" {
  description = "Number of private subnets to create in the single AZ"
  type        = number
  default     = 3
  validation {
    condition     = var.private_subnet_count == 3
    error_message = "This plan is authored for exactly 3 private subnets."
  }
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-0abcdef1234567890"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "gr-prod-key"
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IP to the instance"
  type        = bool
  default     = false
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Root EBS volume type"
  type        = string
  default     = "gp3"
}

variable "bucket_name" {
  description = "S3 bucket name"
  type        = string
  default     = "my-s3-bucket"
}

variable "sns_topic_name" {
  description = "SNS topic name for alerts"
  type        = string
  default     = "my-sns-topic.fifo"
}

variable "assume_role_policy_json" {
  description = "Assume role policy JSON for the IAM role"
  type        = string
  default     = "{\"Version\":\"2012-10-10\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"s3.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Project     = "networking"
  }
}

provider "aws" {
  region = var.region

  {{block_to_replace_cred}}
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  private_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 8, 10),
    cidrsubnet(var.vpc_cidr, 8, 11),
    cidrsubnet(var.vpc_cidr, 8, 12)
  ]
  public_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 8, 0),
    cidrsubnet(var.vpc_cidr, 8, 1),
    cidrsubnet(var.vpc_cidr, 8, 2)
  ]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = var.vpc_name
  })
}

resource "aws_internet_gateway" "main" {
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-igw"
  })

  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  count = var.public_subnet_count

  availability_zone       = var.availability_zone
  cidr_block              = local.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = var.private_subnet_count

  availability_zone = var.availability_zone
  cidr_block        = local.private_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_route_table" "public" {
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-public-rt"
  })

  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_default" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
  route_table_id         = aws_route_table.public.id
}

resource "aws_route_table_association" "public" {
  count = var.public_subnet_count

  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-rt"
  })

  vpc_id = aws_vpc.main.id
}

resource "aws_route" "private_default" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
  route_table_id         = aws_route_table.private.id
}

resource "aws_route_table_association" "private" {
  count = var.private_subnet_count

  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private[count.index].id
}

resource "aws_security_group" "ec2" {
  description = "EC2 instance security group"
  name        = "${var.vpc_name}-ec2-sg"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-ec2-sg"
  })
}

resource "aws_vpc_endpoint" "s3" {
  service_name    = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  vpc_id          = aws_vpc.main.id

  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.public.id
  ]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-s3-endpoint"
  })
}

resource "aws_instance" "main" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  associate_public_ip_address = var.associate_public_ip_address
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.ec2.id]

  root_block_device {
    encrypted   = true
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
  }

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-ec2"
  })
}

resource "aws_s3_bucket" "main" {
  bucket = var.bucket_name

  tags = merge(var.tags, {
    Name = var.bucket_name
  })
}

resource "aws_s3_bucket_ownership_controls" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "s3_access" {
  assume_role_policy = var.assume_role_policy_json
  name               = "${var.vpc_name}-s3-access-role"

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-s3-access-role"
  })
}

resource "aws_iam_policy" "s3_rw" {
  name        = "${var.vpc_name}-s3-rw"
  description = "Read/write access to the S3 bucket ${var.bucket_name}"

  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "${aws_s3_bucket.main.arn}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": [
        "${aws_s3_bucket.main.arn}/*"
      ]
    }
  ]
}
EOF

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_rw" {
  policy_arn = aws_iam_policy.s3_rw.arn
  role       = aws_iam_role.s3_access.name
}

resource "aws_sns_topic" "alerts" {
  fifo_topic = true
  name       = var.sns_topic_name

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  alarm_description   = "EC2 CPU utilization is high"
  alarm_name          = "${var.vpc_name}-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  alarm_actions = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_status_check_failed" {
  alarm_description   = "EC2 instance status check failed"
  alarm_name          = "${var.vpc_name}-ec2-statuscheck-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  alarm_actions = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.vpc_name}-dashboard"

  dashboard_body = <<-EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "region": "${data.aws_region.current.name}",
        "title": "EC2 CPUUtilization",
        "metrics": [
          [ "AWS/EC2", "CPUUtilization", "InstanceId", "${aws_instance.main.id}" ]
        ],
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "region": "${data.aws_region.current.name}",
        "title": "EC2 Network In/Out",
        "metrics": [
          [ "AWS/EC2", "NetworkIn", "InstanceId", "${aws_instance.main.id}", { "stat": "Sum" } ],
          [ ".", "NetworkOut", ".", ".", { "stat": "Sum" } ]
        ],
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "region": "${data.aws_region.current.name}",
        "title": "S3 Bucket Metrics (RequestCount / BytesDownloaded / BytesUploaded)",
        "metrics": [
          [ "AWS/S3", "NumberOfObjects", "BucketName", "${aws_s3_bucket.main.bucket}", "StorageType", "AllStorageTypes" ],
          [ "AWS/S3", "BucketSizeBytes", "BucketName", "${aws_s3_bucket.main.bucket}", "StorageType", "StandardStorage" ]
        ],
        "view": "timeSeries",
        "period": 86400,
        "stat": "Average"
      }
    }
  ]
}
EOF
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.main.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.main.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role for S3 access"
  value       = aws_iam_role.s3_access.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for alerts"
  value       = aws_sns_topic.alerts.arn
}