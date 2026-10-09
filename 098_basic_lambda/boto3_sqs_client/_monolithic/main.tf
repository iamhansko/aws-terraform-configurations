# Generated from 098_basic_lambda/boto3_sqs_client.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}
variable "stack_name" {
  type        = string
  default     = "boto3-sqs-client"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "al2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "al2023_ami_id" {
  name = var.al2023_ami_id
}
# --- Load generator sizing ---
# These were literals inside the message-app.py heredoc below (rules.md B-3). They
# are variables because one of them, load_test_concurrency, is the whole reason the
# original run returned 429 for 45% of its requests, and that number has to be set
# against a ceiling this configuration cannot raise.
#
# A Lambda function URL invokes synchronously, so every in-flight HTTP request holds
# one concurrent execution. The account's limit is 1000, but a workshop guardrail
# function reserves 890 of it, leaving UnreservedConcurrentExecutions = 110 for every
# function without its own reservation - which is what queue-lambda uses. Offering
# 200 simultaneous requests against 110 slots throttles the excess instantly:
# 100 batches x 90 rejected = 9000, and the run measured 8929 Throttles against
# 11071 Invocations with ConcurrentExecutions pinned at 110.
#
# Raising memory_size does not change that arithmetic. All 200 requests of a batch
# arrive within a few milliseconds of each other, so shortening a 26 ms invocation
# changes how fast the 110 accepted ones finish, not how many are accepted.
variable "load_test_concurrency" {
  type        = number
  default     = 100
  description = "Simultaneous in-flight requests the generator keeps open. Must stay at or below the Lambda concurrency available to this function, because a function URL holds one concurrent execution per in-flight request and Lambda returns 429 for the excess"

  validation {
    condition     = var.load_test_concurrency >= 1 && var.load_test_concurrency <= 110
    error_message = "load_test_concurrency must be between 1 and 110. 110 is this account's UnreservedConcurrentExecutions - a guardrail function reserves 890 of the 1000 limit, and reserved_concurrent_executions cannot buy headroom here because AWS refuses any reservation that drops the unreserved pool below 100, capping it at 10. To drive more than 110 concurrent requests, the burst has to reach SQS through something that is not a synchronous Lambda invocation, such as an API Gateway SQS integration (10000 rps, 5000 burst)."
  }
}
variable "load_test_total_requests" {
  type        = number
  default     = 20000
  description = "Total requests the generator sends"

  validation {
    condition     = var.load_test_total_requests >= 1
    error_message = "load_test_total_requests must be at least 1."
  }
}
variable "load_test_batch_delay_seconds" {
  type        = number
  default     = 0.1
  description = "Pause between batches. The original 1 second was the run's actual rate limiter: it held throughput to roughly 110 requests per second while the 110 concurrent slots can retire about 4000 per second at the measured 26 ms duration"

  validation {
    condition     = var.load_test_batch_delay_seconds >= 0
    error_message = "load_test_batch_delay_seconds must not be negative."
  }
}
variable "message_app_timeout_seconds" {
  type        = number
  default     = 300
  description = "How long to wait for the SSM Association that writes message-app.py to report Success"

  validation {
    condition     = var.message_app_timeout_seconds >= 15
    error_message = "message_app_timeout_seconds must be at least 15, the minimum AWS accepts for wait_for_success_timeout_seconds."
  }
}
variable "load_test_max_retries" {
  type        = number
  default     = 5
  description = "Retries per request when Lambda answers 429. A 429 is backpressure rather than a failure, so the generator backs off and resends instead of dropping the message, which is what makes the success count reach load_test_total_requests"

  validation {
    condition     = var.load_test_max_retries >= 0
    error_message = "load_test_max_retries must not be negative."
  }
}
# --- Mappings / Conditions ---
locals {
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  # Rendered once and consumed twice: the bastion's user data writes it on first
  # boot, and aws_ssm_association.bastion_message_app rewrites it on every apply
  # whose rendering changed (rules.md B-5). Keeping the body in one place matters
  # here because user_data only runs once per instance - editing the script inline
  # produced a plan that said "updated in-place" while the file on the running
  # instance stayed at its first-boot contents.
  message_app_py = templatefile("${path.module}/scripts/message_app.py.tftpl", {
    total_requests = var.load_test_total_requests
    concurrency    = var.load_test_concurrency
    batch_delay    = var.load_test_batch_delay_seconds
    max_retries    = var.load_test_max_retries
  })
}
# --- Resources split out of composite CloudFormation resources ---
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# CloudFormation stores the generated private key in SSM at /ec2/keypair/<key-pair-id>; mirrored below.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "queue_ec2_iam_role" {
  role       = aws_iam_role.queue_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/lambda_function/index.py"
  output_path = "${path.module}/build/lambda_function.zip"
}
resource "aws_iam_role_policy" "lambda_role" {
  name = "SQSAccess"
  role = aws_iam_role.lambda_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = aws_sqs_queue.sqs_queue.arn
    }]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block           = "10.102.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "queue-vpc"
  }
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  availability_zone       = "${data.aws_region.current.region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "queue-pub-a"
  }
}
resource "aws_internet_gateway" "igw" {
  tags = {
    Name = "queue-igw"
  }
}
resource "aws_internet_gateway_attachment" "igw_attachment" {
  vpc_id              = aws_vpc.vpc.id
  internet_gateway_id = aws_internet_gateway.igw.id
}
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "queue-pub-rt"
  }
}
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT5M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  instance_type          = "t3.small"
  key_name               = aws_key_pair.key_pair.key_name
  subnet_id              = aws_subnet.public_subnet_a.id
  ami                    = data.aws_ssm_parameter.al2023_ami_id.insecure_value
  iam_instance_profile   = aws_iam_instance_profile.bastion_instance_profile.name
  vpc_security_group_ids = [aws_security_group.bastion_ec2_security_group.id]
  tags = {
    Name = "queue-bastion"
  }
  metadata_options {
    http_tokens = "optional"
  }
  user_data = <<EOT
#!/bin/bash
dnf update -y
dnf groupinstall -y "Development Tools"
dnf install -y python3.13
ln -s /usr/bin/python3.13 /usr/bin/python3

wget https://github.com/coder/code-server/releases/download/v4.100.3/code-server-4.100.3-linux-amd64.tar.gz
tar -xzf code-server-4.100.3-linux-amd64.tar.gz
mv code-server-4.100.3-linux-amd64 /usr/local/lib/code-server
ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

mkdir -p /home/ec2-user/.config/code-server
cat <<EOF > /home/ec2-user/.config/code-server/config.yaml
bind-addr: 0.0.0.0:8000
auth: none
cert: false
EOF
chown -R ec2-user:ec2-user /home/ec2-user/.config

cat <<EOF > /etc/systemd/system/code-server.service
[Unit]
Description=VS Code Server
After=network.target
[Service]
Type=simple
User=ec2-user
ExecStart=/usr/local/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml /home/ec2-user
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable code-server
systemctl start code-server

python3 -m ensurepip --upgrade
python3 -m pip install aiohttp boto3 requests

# Quoted heredoc rather than echo '...': the body is interpolated from
# local.message_app_py, and a single quote anywhere in it would otherwise
# terminate the echo string early (rules.md A-4 applies too - a CRLF .tf file
# makes the terminator PYAPP\r and the whole script stops parsing).
cat > /home/ec2-user/message-app.py << 'PYAPP'
${local.message_app_py}
PYAPP
chown ec2-user:ec2-user /home/ec2-user/message-app.py

timedatectl set-timezone Asia/Seoul

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
}
# user_data runs once per instance, so changing the generator's sizing in the
# heredoc above updates Terraform state and leaves the file on a running bastion
# untouched. This association rewrites it: aws_ssm_association re-runs whenever
# its parameters change, and cat > is a truncating write, so an apply that changes
# load_test_concurrency lands on the instance without replacing it (rules.md H-2
# uses the same mechanism to keep a generated README in step with outputs).
resource "aws_ssm_association" "bastion_message_app" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.message_app_timeout_seconds

  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }

  parameters = {
    commands = <<-EOT
      cat > /home/ec2-user/message-app.py << 'PYAPP'
      ${local.message_app_py}
      PYAPP
      chown ec2-user:ec2-user /home/ec2-user/message-app.py
      EOT
  }
}
resource "aws_eip" "bastion_elastic_ip" {}
resource "aws_eip_association" "bastion_elastic_ip_association" {
  allocation_id = aws_eip.bastion_elastic_ip.allocation_id
  instance_id   = aws_instance.bastion_ec2.id
}
resource "aws_security_group" "bastion_ec2_security_group" {
  vpc_id      = aws_vpc.vpc.id
  description = "Security Group"
  tags = {
    Name = "bastion-ec2-sg"
  }
}
# Standalone rule resources rather than the inline ingress blocks the conversion
# produced (rules.md F-2). The egress rule below is the reason this group had to
# be touched at all: a VPC security group gets a default allow-all egress rule,
# and CloudFormation removes it only if the template specifies SecurityGroupEgress
# - this one never did, so the original instances had outbound access. Terraform
# always drops that default rule on create, and inline blocks are authoritative
# over the whole group, so converting the ingress blocks without adding an egress
# rule left the group with zero egress. The instance then boots with no route out,
# and every dnf/wget/pip line in its user data fails silently - the apply succeeds,
# the instance reports running, and code-server is simply never installed.
resource "aws_vpc_security_group_egress_rule" "bastion_ec2_egress" {
  security_group_id = aws_security_group.bastion_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "bastion_ec2_code_server_ingress" {
  security_group_id = aws_security_group.bastion_ec2_security_group.id
  description       = "code-server web UI"
  ip_protocol       = "tcp"
  from_port         = 8000
  to_port           = 8000
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "bastion_ec2_ssh_ingress" {
  security_group_id = aws_security_group.bastion_ec2_security_group.id
  description       = "SSH on the alternate port the original template opened"
  ip_protocol       = "tcp"
  from_port         = 2222
  to_port           = 2222
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "bastion_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "bastion_instance_profile" {
  # A single role name, not the CloudFormation Roles list: an instance profile
  # takes at most one role, so aws_iam_instance_profile.role is a string. The
  # jsonencode([...]) the conversion left here passes '["terraform-..."]' to
  # AddRoleToInstanceProfile, which IAM rejects as an invalid roleName at apply
  # time - validate and plan both pass (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
resource "aws_instance" "queue_ec2" {
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.key_pair.key_name
  subnet_id              = aws_subnet.public_subnet_a.id
  ami                    = data.aws_ssm_parameter.al2023_ami_id.insecure_value
  iam_instance_profile   = aws_iam_instance_profile.queue_instance_profile.name
  vpc_security_group_ids = [aws_security_group.queue_ec2_security_group.id]
  tags = {
    Name = "queue-ec2"
  }
  user_data = <<EOT
#!/bin/bash
dnf update -y
dnf groupinstall -y "Development Tools"
dnf install -y python3.13
ln -s /usr/bin/python3.13 /usr/bin/python3

dnf install -y amazon-cloudwatch-agent
echo '{
  "agent": {
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/Gwangju_queue.log",
            "log_group_name": "queue-log-group",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}' > /opt/aws/amazon-cloudwatch-agent/bin/config.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
-a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json

python3 -m ensurepip --upgrade
python3 -m pip install boto3

cat > /home/ec2-user/worker.py << EOF
import boto3
import concurrent.futures
import logging
queue_url = "${aws_sqs_queue.sqs_queue.id}"
log_file = "/var/log/Gwangju_queue.log"
logging.basicConfig(filename=log_file, format="%(asctime)s %(message)s")
sqs = boto3.client("sqs", region_name="${data.aws_region.current.region}")
def worker(message):
  try:
    logging.info("처리성공")
    sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=message["ReceiptHandle"])
  except Exception as e:
    logging.error(e)
def sqs_process(max_workers=10, wait_time=10, max_messages=10):
  with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
    while True:
      response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=max_messages, # max 10
        WaitTimeSeconds=wait_time, # max 20
        VisibilityTimeout=30
      )
      if "Messages" in response:
        messages = response["Messages"]
        futures = [executor.submit(worker, message) for message in messages]
        concurrent.futures.wait(futures)
if __name__ == "__main__":
  sqs_process(max_workers=200, wait_time=5, max_messages=10)
EOF
chown ec2-user:ec2-user /home/ec2-user/worker.py
touch /var/log/Gwangju_queue.log
chown ec2-user:ec2-user /var/log/Gwangju_queue.log

# python3 /home/ec2-user/worker.py

timedatectl set-timezone Asia/Seoul

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource QueueEc2 --region ${data.aws_region.current.region}
EOT
}
resource "aws_security_group" "queue_ec2_security_group" {
  vpc_id      = aws_vpc.vpc.id
  description = "Security Group"
  tags = {
    Name = "queue-ec2-sg"
  }
}
# Same conversion defect as the bastion group above: no egress rule meant no
# outbound at all, so this instance could not install python/boto3 or reach SQS
# (rules.md F-2).
resource "aws_vpc_security_group_egress_rule" "queue_ec2_egress" {
  security_group_id = aws_security_group.queue_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "queue_ec2_ssh_ingress" {
  security_group_id            = aws_security_group.queue_ec2_security_group.id
  description                  = "SSH from the bastion security group"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion_ec2_security_group.id
}
resource "aws_iam_role" "queue_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "queue_instance_profile" {
  # Same list-to-string reduction as bastion_instance_profile (rules.md A-3),
  # and the role it names is corrected too: the conversion pointed this profile
  # at bastion_ec2_iam_role, which left queue_ec2_iam_role created and granted a
  # policy but attached to nothing, while queue_ec2 ran as the bastion's role.
  role = aws_iam_role.queue_ec2_iam_role.name
}
resource "aws_sqs_queue" "sqs_queue" {
  name                      = "queue"
  message_retention_seconds = 3600
}
resource "aws_lambda_function" "lambda_function" {
  function_name = "queue-lambda"
  runtime       = "python3.13"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  timeout       = 300
  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.sqs_queue.id
    }
  }
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
}
resource "aws_iam_role" "lambda_role" {
  name = "queue-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_lambda_function_url" "lambda_url" {
  authorization_type = "NONE"
  function_name      = aws_lambda_function.lambda_function.function_name
}
resource "aws_lambda_permission" "lambda_permission" {
  function_name          = aws_lambda_function.lambda_function.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}
resource "aws_cloudwatch_log_group" "cloud_watch_log_group" {
  name = "queue-log-group"
}
resource "aws_cloudwatch_log_metric_filter" "cloud_watch_metric_filter" {
  name                      = "queue-filter"
  pattern                   = "\"처리성공\""
  log_group_name            = aws_cloudwatch_log_group.cloud_watch_log_group.name
  apply_on_transformed_logs = false
  metric_transformation {
    name      = "queue-metric"
    namespace = "queue"
    value     = "1"
  }
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  # public_ip, not id. CloudFormation's Ref on an AWS::EC2::EIP returns the IP
  # address, but aws_eip.id is the allocation ID, so the conversion's blanket
  # Ref -> .id mapping produced http://eipalloc-...:8000 here. The allocation ID
  # is what Fn::GetAtt AllocationId returns, which this template never asked for.
  value       = "http://${aws_eip.bastion_elastic_ip.public_ip}:8000"
  description = "VsCode on BastionEC2"
}
# CloudFormation output: KeyPairValue
output "key_pair_value" {
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/systems-manager/parameters/%252Fec2%252Fkeypair%252F${aws_key_pair.key_pair.key_pair_id}"
  description = "KeyPair Value"
}
