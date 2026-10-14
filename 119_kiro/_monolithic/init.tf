# Generated from 119_kiro/init.yaml by tools/cfn2tf.
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
  default     = "init"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_ssoadmin_instances" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "inbound_from_anywhere" {
  type        = string
  default     = "True"
  description = "SecurityGroup Inbound Rule (Source 0.0.0.0/0)"
  validation {
    condition     = contains(["True", "False"], var.inbound_from_anywhere)
    error_message = "InboundFromAnywhere must be one of: True, False"
  }
}
variable "ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id
}
# --- Mappings / Conditions ---
locals {
  stack_id                                  = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  cond_security_group_inbound_from_anywhere = (var.inbound_from_anywhere == "True")
}
# --- Resources split out of composite CloudFormation resources ---
data "archive_file" "get_parameter_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/get_parameter_lambda_function/index.py"
  output_path = "${path.module}/build/get_parameter_lambda_function.zip"
}
resource "aws_iam_role_policy" "get_parameter_lambda_iam_role" {
  name = "GetParameterLambdaIamPolicy"
  role = aws_iam_role.get_parameter_lambda_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "get_parameter_lambda_iam_role" {
  role       = aws_iam_role.get_parameter_lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
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
resource "aws_iam_role_policy" "ec2_iam_role" {
  name = "KiroIamPolicy"
  role = aws_iam_role.ec2_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["q:*", "codewhisperer:*", "user-subscriptions:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ec2_iam_role_0" {
  role       = aws_iam_role.ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "ec2_iam_role_1" {
  role       = aws_iam_role.ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonQDeveloperAccess"
}
data "archive_file" "terminate_instance_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/terminate_instance_lambda_function/index.py"
  output_path = "${path.module}/build/terminate_instance_lambda_function.zip"
}
resource "aws_iam_role_policy" "terminate_instance_lambda_iam_role" {
  name = "TerminateInstanceLambdaIamPolicy"
  role = aws_iam_role.terminate_instance_lambda_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:TerminateInstances", "ec2:DescribeInstances"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "terminate_instance_lambda_iam_role" {
  role       = aws_iam_role.terminate_instance_lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
# === IamIdentityCenterInstance (AWS::SSO::Instance) NOT CONVERTED ===
# IAM Identity Center instances cannot be created by the AWS provider; read an existing one with the aws_ssoadmin_instances data source.
# Original CloudFormation definition:
# # {
# #   "Type": "AWS::SSO::Instance"
# # }
resource "aws_lambda_invocation" "kiro_username" {
  function_name = aws_lambda_function.get_parameter_lambda_function.arn
  input = jsonencode({
    ParameterName = "/kiro/user/name"
  })
  depends_on = [aws_instance.ec2]
}
resource "aws_lambda_invocation" "kiro_password" {
  function_name = aws_lambda_function.get_parameter_lambda_function.arn
  input = jsonencode({
    ParameterName = "/kiro/user/password"
  })
  depends_on = [aws_instance.ec2]
}
resource "aws_lambda_function" "get_parameter_lambda_function" {
  function_name    = "GetParameterStoreValue"
  runtime          = "python3.13"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.get_parameter_lambda_iam_role.arn
  timeout          = 30
  filename         = data.archive_file.get_parameter_lambda_function.output_path
  source_code_hash = data.archive_file.get_parameter_lambda_function.output_base64sha256
}
resource "aws_iam_role" "get_parameter_lambda_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc"
  }
}
resource "aws_subnet" "public_subnet_a" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "public-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
  depends_on             = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT7M"
# #   }
# # }
resource "aws_instance" "ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t3.large"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "ec2"
  }
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
set -x

dnf update -yq
dnf install -yq git
dnf groupinstall -yq "Development Tools"

export VSC_VERSION="4.102.3"
wget https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
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

IMDS_TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
if [ -z "$IMDS_TOKEN" ]; then
  echo "Failed to get IMDSv2 token"
  exit 1
fi
export ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)
export CREDENTIALS=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME)
export AWS_DEFAULT_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.Token')

echo "AwsDefaultRegion : $AWS_DEFAULT_REGION"
echo "AwsSecretAccessKey : $AWS_SECRET_ACCESS_KEY"
echo "AwsSessionToken : $AWS_SESSION_TOKEN"
aws sts get-caller-identity

SERVICE="sso"
HOST="sso.$AWS_DEFAULT_REGION.amazonaws.com"
ENDPOINT="https://$HOST/control/"
REQUEST_METHOD="POST"
CONTENT_TYPE="application/x-amz-json-1.1"
AMZ_TARGET="SWBService.UpdateSsoConfiguration"
AMZ_USER_AGENT="aws-sdk-js/2.1467.0 promise"
IAM_IDENTITY_CENTER_INSTANCE_ARN="${tolist(data.aws_ssoadmin_instances.current.arns)[0]}"
REQUEST_BODY='{"instanceArn":"'"$IAM_IDENTITY_CENTER_INSTANCE_ARN"'","configurationType":"APP_AUTHENTICATION_CONFIGURATION","ssoConfiguration":{"mfaMode":"DISABLED"}}'
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
DATESTAMP=$(date -u +"%Y%m%d")
function hash_sha256 {
  echo -n "$1" | openssl dgst -sha256 -binary | xxd -p -c 256
}
function hmac_sha256 {
  key="$1"
  data="$2"
  echo -n "$data" | openssl dgst -sha256 -mac HMAC -macopt "$key" -binary
}
PAYLOAD_HASH=$(hash_sha256 "$REQUEST_BODY")
CANONICAL_URI="/control/"
CANONICAL_QUERYSTRING=""
CANONICAL_HEADERS="host:$HOST
x-amz-content-sha256:$PAYLOAD_HASH
x-amz-date:$TIMESTAMP
x-amz-security-token:$AWS_SESSION_TOKEN
x-amz-target:$AMZ_TARGET
x-amz-user-agent:$AMZ_USER_AGENT"
SIGNED_HEADERS="host;x-amz-content-sha256;x-amz-date;x-amz-security-token;x-amz-target;x-amz-user-agent"
CANONICAL_REQUEST="$REQUEST_METHOD
$CANONICAL_URI
$CANONICAL_QUERYSTRING
$CANONICAL_HEADERS

$SIGNED_HEADERS
$PAYLOAD_HASH"
CANONICAL_REQUEST_HASH=$(hash_sha256 "$CANONICAL_REQUEST")
ALGORITHM="AWS4-HMAC-SHA256"
CREDENTIAL_SCOPE="$DATESTAMP/$AWS_DEFAULT_REGION/$SERVICE/aws4_request"
STRING_TO_SIGN="$ALGORITHM
$TIMESTAMP
$CREDENTIAL_SCOPE
$CANONICAL_REQUEST_HASH"
kDate=$(echo -n "$DATESTAMP" | openssl dgst -sha256 -mac HMAC -macopt "key:AWS4$AWS_SECRET_ACCESS_KEY" -binary | xxd -p -c 256)
kRegion=$(echo -n "$AWS_DEFAULT_REGION" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$kDate" -binary | xxd -p -c 256)
kService=$(echo -n "$SERVICE" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$kRegion" -binary | xxd -p -c 256)
kSigning=$(echo -n "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$kService" -binary | xxd -p -c 256)
SIGNATURE=$(echo -n "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$kSigning" | sed 's/^.* //')
AUTHORIZATION_HEADER="$ALGORITHM Credential=$AWS_ACCESS_KEY_ID/$CREDENTIAL_SCOPE, SignedHeaders=$SIGNED_HEADERS, Signature=$SIGNATURE"
curl -X POST "$ENDPOINT" \
-H "Content-Type: $CONTENT_TYPE" \
-H "X-Amz-User-Agent: $AMZ_USER_AGENT" \
-H "X-Amz-Target: $AMZ_TARGET" \
-H "X-Amz-Content-Sha256: $PAYLOAD_HASH" \
-H "X-Amz-Date: $TIMESTAMP" \
-H "X-Amz-Security-Token: $AWS_SESSION_TOKEN" \
-H "Authorization: $AUTHORIZATION_HEADER" \
--data-raw "$REQUEST_BODY"

export IDENTITY_STORE_ID="${tolist(data.aws_ssoadmin_instances.current.identity_store_ids)[0]}"
export USER_ID=$(aws identitystore create-user \
--identity-store-id $IDENTITY_STORE_ID \
--user-name kiro \
--name "GivenName=Kiro,FamilyName=User" \
--display-name "Kiro User" \
--emails "Type=work,Value=pro@kiro.com" \
--query "UserId" | tr -d '"')

SERVICE="userpool"
HOST="identitystore.$AWS_DEFAULT_REGION.amazonaws.com"
ENDPOINT="https://$HOST/"
REQUEST_METHOD="POST"
CONTENT_TYPE="application/x-amz-json-1.0"
AMZ_TARGET="SWBUPService.UpdatePassword"
AMZ_USER_AGENT="aws-sdk-js/2.1467.0 promise"
REQUEST_BODY='{"UserId":"'$USER_ID'","PasswordMode":"OTP"}'

TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
DATESTAMP=$(date -u +"%Y%m%d")
function hash_sha256 {
  echo -n "$1" | openssl dgst -sha256 -binary | xxd -p -c 256
}
function hmac_sha256 {
  key="$1"
  data="$2"
  echo -n "$data" | openssl dgst -sha256 -mac HMAC -macopt "$key" -binary
}
PAYLOAD_HASH=$(hash_sha256 "$REQUEST_BODY")
CANONICAL_URI="/"
CANONICAL_QUERYSTRING=""
CANONICAL_HEADERS="host:$HOST
x-amz-content-sha256:$PAYLOAD_HASH
x-amz-date:$TIMESTAMP
x-amz-security-token:$AWS_SESSION_TOKEN
x-amz-target:$AMZ_TARGET
x-amz-user-agent:$AMZ_USER_AGENT"
SIGNED_HEADERS="host;x-amz-content-sha256;x-amz-date;x-amz-security-token;x-amz-target;x-amz-user-agent"
CANONICAL_REQUEST="$REQUEST_METHOD
$CANONICAL_URI
$CANONICAL_QUERYSTRING
$CANONICAL_HEADERS

$SIGNED_HEADERS
$PAYLOAD_HASH"
CANONICAL_REQUEST_HASH=$(hash_sha256 "$CANONICAL_REQUEST")
ALGORITHM="AWS4-HMAC-SHA256"
CREDENTIAL_SCOPE="$DATESTAMP/$AWS_DEFAULT_REGION/$SERVICE/aws4_request"
STRING_TO_SIGN="$ALGORITHM
$TIMESTAMP
$CREDENTIAL_SCOPE
$CANONICAL_REQUEST_HASH"
kDate=$(echo -n "$DATESTAMP" | openssl dgst -sha256 -mac HMAC -macopt "key:AWS4$AWS_SECRET_ACCESS_KEY" -binary | xxd -p -c 256)
kRegion=$(echo -n "$AWS_DEFAULT_REGION" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$kDate" -binary | xxd -p -c 256)
kService=$(echo -n "$SERVICE" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$kRegion" -binary | xxd -p -c 256)
kSigning=$(echo -n "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$kService" -binary | xxd -p -c 256)
SIGNATURE=$(echo -n "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$kSigning" | sed 's/^.* //')
AUTHORIZATION_HEADER="$ALGORITHM Credential=$AWS_ACCESS_KEY_ID/$CREDENTIAL_SCOPE, SignedHeaders=$SIGNED_HEADERS, Signature=$SIGNATURE"
export OTP=$(curl -X $REQUEST_METHOD "$ENDPOINT" \
-s \
-H "Content-Type: $CONTENT_TYPE" \
-H "X-Amz-User-Agent: $AMZ_USER_AGENT" \
-H "X-Amz-Target: $AMZ_TARGET" \
-H "X-Amz-Content-Sha256: $PAYLOAD_HASH" \
-H "X-Amz-Date: $TIMESTAMP" \
-H "X-Amz-Security-Token: $AWS_SESSION_TOKEN" \
-H "Authorization: $AUTHORIZATION_HEADER" \
--data-raw "$REQUEST_BODY" | jq ".Password" | tr -d '"')

echo "UserID : $USER_ID"
echo "OneTimePassword : $OTP"

aws ssm put-parameter --name "/kiro/user/password" --value $OTP --type String
aws ssm put-parameter --name "/kiro/user/name" --value "kiro" --type String

su - ec2-user << EOF
set -x
curl -L -O https://github.com/iamhansko/kiroctl/releases/download/v0.0/kiroctl
chmod +x ./kiroctl
mkdir -p /home/ec2-user/bin && cp ./kiroctl /home/ec2-user/bin/kiroctl && export PATH=/home/ec2-user/bin:\$PATH
echo 'export PATH=/home/ec2-user/bin:\$PATH' >> ~/.bashrc
rm -f ./kiroctl
kiroctl profile create --region us-east-1
sleep 20
for i in {1..3}; do
  kiroctl user subscribe --region us-east-1 --plan Q_DEVELOPER_STANDALONE_PRO $USER_ID
  sleep 5
done
EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource Ec2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subnet_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ec2_security_group.id]
}
resource "aws_security_group" "ec2_security_group" {
  description = "Security Group"
  name        = "ec2-sg"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 8000
      to_port     = 8000
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "ec2-sg"
  }
}
resource "aws_iam_role" "ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.ec2_iam_role.name
}
resource "aws_lambda_invocation" "terminate_instance" {
  function_name = aws_lambda_function.terminate_instance_lambda_function.arn
  input = jsonencode({
    InstanceId = aws_instance.ec2.id
  })
}
resource "aws_lambda_function" "terminate_instance_lambda_function" {
  runtime          = "python3.13"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.terminate_instance_lambda_iam_role.arn
  timeout          = 60
  filename         = data.archive_file.terminate_instance_lambda_function.output_path
  source_code_hash = data.archive_file.terminate_instance_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-terminate-instance-lambda-function"
}
resource "aws_iam_role" "terminate_instance_lambda_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# --- Outputs ---
# CloudFormation output: 01KiroLoginUrl
output "out_01_kiro_login_url" {
  value       = "https://${tolist(data.aws_ssoadmin_instances.current.identity_store_ids)[0]}.awsapps.com/start"
  description = "Kiro Login URL"
}
# CloudFormation output: 02KiroUsername
output "out_02_kiro_username" {
  value       = jsondecode(aws_lambda_invocation.kiro_username.result)["Value"]
  description = "Kiro Username"
}
# CloudFormation output: 03KiroPassword
output "out_03_kiro_password" {
  value       = jsondecode(aws_lambda_invocation.kiro_password.result)["Value"]
  description = "Kiro Password"
}
