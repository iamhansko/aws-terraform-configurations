# Generated from 120_codepipeline_asg/inplace.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
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
  default     = "inplace"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
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
variable "vs_code_version" {
  type    = string
  default = "4.108.2"
}
# Added by hand rather than by the converter. These configure the things CloudFormation used to do
# itself - seed the repository, and signal that the bootstrap had finished (rules.md B-3).
variable "source_branch_name" {
  type        = string
  default     = "main"
  description = "Branch the pipeline reads. One value feeds the three places that have to agree - the source action's BranchName, the EventBridge rule's referenceName, and the branch the first push creates - rather than the same literal written three times (rules.md B-5)"

  validation {
    condition     = length(var.source_branch_name) > 0 && can(regex("^[A-Za-z0-9._/-]+$", var.source_branch_name))
    error_message = "source_branch_name must be a non-empty branch name of letters, digits, dots, underscores, slashes or hyphens."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the VS Code instance where the bootstrap drops its completion marker. The association that seeds the repository waits on that file rather than trusting depends_on or wait_for_success_timeout_seconds (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with a slash."
  }
}
variable "git_prepare_timeout_seconds" {
  type        = number
  default     = 1200
  description = "How long the apply waits for the first commit to reach CodeCommit. It has to cover the whole bootstrap, because the association's first statement blocks until the marker file appears - the CreationPolicy this replaces allowed 15 minutes for the same work"

  validation {
    condition     = var.git_prepare_timeout_seconds >= 300 && var.git_prepare_timeout_seconds <= 3600
    error_message = "git_prepare_timeout_seconds must be between 300 and 3600."
  }
}
# --- Mappings / Conditions ---
locals {
  mappings = {
    AzMapping = {
      a = {
        PublicSubnetCidr  = "10.0.0.0/24"
        PrivateSubnetCidr = "10.0.1.0/24"
      }
      b = {
        PublicSubnetCidr  = "10.0.2.0/24"
        PrivateSubnetCidr = "10.0.3.0/24"
      }
      c = {
        PublicSubnetCidr  = "10.0.4.0/24"
        PrivateSubnetCidr = "10.0.5.0/24"
      }
    }
  }
  stack_id                                  = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  cond_security_group_inbound_from_anywhere = (var.inbound_from_anywhere == "True")
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
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "code_build_iam_role" {
  role       = aws_iam_role.code_build_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
resource "aws_iam_role_policy" "code_deploy_iam_role" {
  name = "custom-launch-template"
  role = aws_iam_role.code_deploy_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:RunInstances", "ec2:CreateTags", "iam:PassRole"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "code_deploy_iam_role" {
  role       = aws_iam_role.code_deploy_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}
resource "aws_iam_role_policy_attachment" "app_ec2_iam_role" {
  role       = aws_iam_role.app_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
resource "aws_iam_role_policy_attachment" "code_pipeline_iam_role" {
  role       = aws_iam_role.code_pipeline_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
resource "aws_cloudwatch_event_target" "cloud_watch_event_rule" {
  rule      = aws_cloudwatch_event_rule.cloud_watch_event_rule.name
  arn       = "arn:aws:codepipeline:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_codepipeline.code_pipeline.name}"
  target_id = "codepipeline-codepipeline"
  role_arn  = aws_iam_role.cloud_watch_event_rule_iam_role.arn
}
resource "aws_iam_role_policy" "cloud_watch_event_rule_iam_role" {
  name = "start-pipeline-execution"
  role = aws_iam_role.cloud_watch_event_rule_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codepipeline:StartPipelineExecution"]
      Resource = ["arn:aws:codepipeline:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_codepipeline.code_pipeline.name}"]
    }]
  })
}
# --- Resources ---
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
resource "aws_subnet" "public_subneta" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = local.mappings["AzMapping"]["a"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subneta_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subneta.id
}
resource "aws_subnet" "public_subnetc" {
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = local.mappings["AzMapping"]["c"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-c"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnetc_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnetc.id
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
resource "aws_subnet" "private_subneta" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["a"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "private-subnet-a"
  }
}
resource "aws_eip" "natgateway_elastic_ipa" {}
resource "aws_route_table_association" "private_subneta_route_table_association" {
  route_table_id = aws_route_table.private_subnet_route_table.id
  subnet_id      = aws_subnet.private_subneta.id
}
resource "aws_subnet" "private_subnetc" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["c"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}c"
  tags = {
    Name = "private-subnet-c"
  }
}
resource "aws_eip" "natgateway_elastic_ipc" {}
resource "aws_route_table_association" "private_subnetc_route_table_association" {
  route_table_id = aws_route_table.private_subnet_route_table.id
  subnet_id      = aws_subnet.private_subnetc.id
}
resource "aws_route_table" "private_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "private-rt"
  }
}
resource "aws_route" "private_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
  route_table_id         = aws_route_table.private_subnet_route_table.id
}
resource "aws_nat_gateway" "nat_gateway" {
  vpc_id            = aws_vpc.vpc.id
  availability_mode = "regional"
  availability_zone_address {
    availability_zone = "${data.aws_region.current.region}a"
    allocation_ids    = [aws_eip.natgateway_elastic_ipa.allocation_id]
  }
  availability_zone_address {
    availability_zone = "${data.aws_region.current.region}c"
    allocation_ids    = [aws_eip.natgateway_elastic_ipc.allocation_id]
  }
  tags = {
    Name = "regional-natgw"
  }
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "vs_code_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t3.medium"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "vscode"
  }
  iam_instance_profile = aws_iam_instance_profile.vs_code_ec2_instance_profile.name
  user_data            = <<EOT
#!/bin/bash
dnf update -yq
dnf install -yq git
dnf groupinstall -yq "Development Tools"

export VSC_VERSION="${var.vs_code_version}"
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

sudo -Eu ec2-user bash << 'EOF'
cd /home/ec2-user
mkdir -p /home/ec2-user/python
echo 'FROM python:3.14
WORKDIR /code
COPY ./requirements.txt /code/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt
COPY ./main.py .
CMD ["fastapi", "run", "main.py", "--port", "80"]' > /home/ec2-user/python/Dockerfile
echo 'fastapi[standard]' > /home/ec2-user/python/requirements.txt
echo 'from fastapi import FastAPI
app = FastAPI()
@app.get("/")
def get():
  return {"Deployment": "In-place"}' > /home/ec2-user/python/main.py
# The region every CLI call on this instance needs, the CodeCommit credential helper included. The
# association that seeds the repository exports it as well, but setting it here is what makes the
# same push work from a terminal inside the IDE.
aws configure set default.region ${data.aws_region.current.region}

EOF

# What used to be here: a zip of the application uploaded to the bucket the converter named
# code_commit_s3_bucket, and a cfn-signal call. Both are gone, and so is the bucket - a heredoc is
# still a Terraform template, so even naming the bucket in this comment would be a reference to it.
#
# The zip fed the CloudFormation repository's Code property, which seeded the repository with a first
# commit on a branch. Terraform's aws_codecommit_repository has no equivalent, so the converted
# configuration uploaded a zip nothing ever read and created an empty repository - no commits, no
# branches - and the pipeline's source action failed with "no branch named main was found". The push
# in aws_ssm_association.git_prepare replaces it.
#
# cfn-signal answered a CreationPolicy that no longer exists, and aws-cfn-bootstrap is not installed
# on AL2023, so the call only ended the bootstrap on a non-zero exit.
#
# The marker file is deliberately the last thing this script does. The association waits for it, so
# touching it any earlier would let the push race the steps above (rules.md B-4/D-5).
mkdir -p ${var.marker_file_path}
touch ${var.marker_file_path}/userdata
EOT
  # user_data changes stop and start the instance by default, and cloud-init does not re-run its
  # script on a restart - the new bootstrap would never execute. Replacement is what runs it.
  user_data_replace_on_change = true
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vs_code_ec2_security_group.id]
}
# Terraform strips the allow-all egress rule AWS attaches to every new security group, and the
# conversion never re-created it: CloudFormation leaves that rule in place when a template declares no
# SecurityGroupEgress, so the original template had no reason to mention it. The result was three
# groups with zero egress rules, and nothing in this VPC could reach anything. The bootstrap died at
# its first dnf call, the SSM agent never registered, and the push that seeds CodeCommit had nowhere
# to go - which is why the repository was empty even before the missing Code property is counted.
#
# The rules are standalone resources, which is also why the inline blocks that used to be in this
# group are gone: inline ingress/egress own the group's entire rule set, so a group cannot hold both
# forms without producing permanent diffs (rules.md F-2).
resource "aws_security_group" "vs_code_ec2_security_group" {
  description = "Security Group"
  name        = "vscode-sg"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = "vscode-sg"
  }
}
resource "aws_vpc_security_group_ingress_rule" "vs_code_ec2_security_group_code_server_ingress" {
  count = local.cond_security_group_inbound_from_anywhere ? 1 : 0

  security_group_id = aws_security_group.vs_code_ec2_security_group.id
  description       = "code-server from anywhere"
  ip_protocol       = "tcp"
  from_port         = 8000
  to_port           = 8000
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_egress_rule" "vs_code_ec2_security_group_egress" {
  security_group_id = aws_security_group.vs_code_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "vs_code_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "vs_code_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply (rules.md A-3).
  role = aws_iam_role.vs_code_ec2_iam_role.name
}
# The repository the pipeline reads. Terraform creates it empty, and there is no argument that seeds
# it: CloudFormation's AWS::CodeCommit::Repository takes a Code property pointing at an S3 zip and
# makes a first commit from it, and aws_codecommit_repository has nothing equivalent. That is the
# whole of the reported failure - the source action looks for var.source_branch_name in a repository
# that has no commits and therefore no branches at all.
#
# aws_ssm_association.git_prepare at the end of this file is what seeds it, by pushing from the
# workbench. The dependency therefore runs the other way now than it did in the template: the
# repository has to exist before the instance can push to it, so the DependsOn the converter carried
# over from the Code property is gone.
#
# default_branch is not set here on purpose. AWS can only make a branch the default once that branch
# exists, and a repository Terraform has just created has none - setting it fails. The first push
# creates the branch and CodeCommit adopts it as the default.
resource "aws_codecommit_repository" "code_commit" {
  repository_name = "python-app-repo"
}
resource "aws_codebuild_project" "code_build" {
  name = "python-app-build"
  artifacts {
    type = "CODEPIPELINE"
  }
  cache {
    type  = "LOCAL"
    modes = ["LOCAL_SOURCE_CACHE", "LOCAL_DOCKER_LAYER_CACHE"]
  }
  concurrent_build_limit = 6
  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    type                        = "LINUX_CONTAINER"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }
  service_role  = aws_iam_role.code_build_iam_role.arn
  build_timeout = 5
  source {
    type      = "CODEPIPELINE"
    buildspec = <<EOT
version: 0.2
env:
  variables:
    AWS_ACCOUNT_ID: ${data.aws_caller_identity.current.account_id}
    IMAGE_REPO_NAME: ${aws_ecr_repository.ecr.name}
    IMAGE_REPO_URI: ${aws_ecr_repository.ecr.repository_url}
phases:
  pre_build:
    commands:
      - ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
      - aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com
  build:
    commands:
      - BUILD_ID=$(echo $CODEBUILD_BUILD_ID | cut -d':' -f2)
      - NEW_TAG=$(date "+%Y%m%d%H%M%S")
      - |
        cat > BUILD.md << EOF
        codebuild: $BUILD_ID
        codepipeline: $EXECUTION_ID
        EOF
      - docker build -t $IMAGE_REPO_URI:$NEW_TAG .
      - docker push $IMAGE_REPO_URI:$NEW_TAG
  post_build:
    commands:
      - echo $CODEBUILD_BUILD_ID
      - echo $EXECUTION_ID
      - mkdir scripts
      - |
        cat > scripts/start_server.sh << EOF
        #!/bin/bash
        docker rm -f \$(docker ps -aq) &> /dev/null
        docker system prune -af
        aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com
        docker pull $IMAGE_REPO_URI:$NEW_TAG
        docker run -d -p 5000:80 $IMAGE_REPO_URI:$NEW_TAG
        EOF
      - |
        cat > appspec.yml << EOF
        version: 0.0
        os: linux
        hooks:
          ApplicationStart:
            - location: scripts/start_server.sh
        EOF
artifacts:
  files:
    - appspec.yml
    - scripts/start_server.sh
    - BUILD.md
  discard-paths: no
EOT
  }
}
resource "aws_iam_role" "code_build_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codebuild.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_codedeploy_deployment_group" "code_deploy_deployment_group" {
  app_name         = aws_codedeploy_app.code_deploy_application.name
  service_role_arn = aws_iam_role.code_deploy_iam_role.arn
  auto_rollback_configuration {
    enabled = false
  }
  deployment_config_name = "CodeDeployDefault.AllAtOnce"
  autoscaling_groups     = [aws_autoscaling_group.app_auto_scaling_group.name]
  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.alb_target_group.name
    }
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  deployment_group_name = "${var.stack_name}-code-deploy-deployment-group"
}
resource "aws_codedeploy_app" "code_deploy_application" {
  compute_platform = "Server"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-code-deploy-application"
}
resource "aws_iam_role" "code_deploy_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codedeploy.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_autoscaling_group" "app_auto_scaling_group" {
  min_size         = 3
  desired_capacity = 3
  max_size         = 6
  launch_template {
    id      = aws_launch_template.app_launch_template.id
    version = 1
  }
  vpc_zone_identifier     = [aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
  default_cooldown        = 60
  default_instance_warmup = 60
  target_group_arns       = [aws_lb_target_group.alb_target_group.arn]
}
resource "aws_launch_template" "app_launch_template" {
  image_id               = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type          = "t3.medium"
  vpc_security_group_ids = [aws_security_group.app_security_group.id]
  iam_instance_profile {
    arn = aws_iam_instance_profile.app_ec2_instance_profile.arn
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      delete_on_termination = true
    }
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "enabled"
  }
  key_name = aws_key_pair.key_pair.key_name
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "app"
    }
  }
  user_data = base64encode(<<EOT
#!/bin/bash
dnf update -yq
dnf install -yq git
dnf groupinstall -yq "Development Tools"

dnf install -yq git
dnf install -yq docker
systemctl enable --now docker
usermod -aG docker ec2-user
newgrp docker

dnf install -yq ruby
dnf install -yq wget
cd /home/ec2-user
wget https://aws-codedeploy-${data.aws_region.current.region}.s3.${data.aws_region.current.region}.amazonaws.com/latest/install
chmod +x ./install
./install auto
systemctl status codedeploy-agent
EOT
  )
}
# Egress matters most on this group. These instances install the CodeDeploy agent at boot and pull the
# image the build pushed to ECR, both through the NAT gateway, and a deployment to an instance whose
# agent never installed fails with no instances in the deployment group (rules.md F-2).
resource "aws_security_group" "app_security_group" {
  description = "Security Group"
  name        = "app-ec2-sg"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = "app-ec2-sg"
  }
}
resource "aws_vpc_security_group_ingress_rule" "app_security_group_alb_ingress" {
  security_group_id            = aws_security_group.app_security_group.id
  description                  = "Application port from the ALB security group"
  ip_protocol                  = "tcp"
  from_port                    = 5000
  to_port                      = 5000
  referenced_security_group_id = aws_security_group.alb_security_group.id
}
resource "aws_vpc_security_group_egress_rule" "app_security_group_egress" {
  security_group_id = aws_security_group.app_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "app_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "app_ec2_instance_profile" {
  # Single role name string, not a list (rules.md A-3).
  role = aws_iam_role.app_ec2_iam_role.name
}
resource "aws_lb" "alb" {
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subneta.id, aws_subnet.public_subnetc.id]
  security_groups    = [aws_security_group.alb_security_group.id]
  internal           = false
}
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn
  }
}
resource "aws_lb_target_group" "alb_target_group" {
  port        = 5000
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.vpc.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = 5000
    interval            = 60
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    enabled             = true
    matcher             = "200-399"
  }
  deregistration_delay = 30
}
resource "aws_security_group" "alb_security_group" {
  description = "Security Group"
  name        = "alb-sg"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = "alb-sg"
  }
}
resource "aws_vpc_security_group_ingress_rule" "alb_security_group_http_ingress" {
  count = local.cond_security_group_inbound_from_anywhere ? 1 : 0

  security_group_id = aws_security_group.alb_security_group.id
  description       = "Listener port from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}
# The egress the target group health check and the forwarded requests both travel on.
resource "aws_vpc_security_group_egress_rule" "alb_security_group_egress" {
  security_group_id = aws_security_group.alb_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_ecr_repository" "ecr" {
  force_delete = true
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ecr"
}
resource "aws_codepipeline" "code_pipeline" {
  pipeline_type  = "V2"
  execution_mode = "QUEUED"
  artifact_store {
    location = aws_s3_bucket.code_pipeline_artifact_store_s3_bucket.id
    type     = "S3"
  }
  role_arn = aws_iam_role.code_pipeline_iam_role.arn
  stage {
    name = "SourceStage"
    action {
      name = "SourceAction"
      configuration = {
        PollForSourceChanges = false
        RepositoryName       = aws_codecommit_repository.code_commit.repository_name
        # The same value the push creates and the EventBridge rule matches (rules.md B-5).
        BranchName           = var.source_branch_name
        OutputArtifactFormat = "CODE_ZIP"
      }
      output_artifacts = ["SourceArtifact"]
      namespace        = "SourceVariables"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = 1
    }
    on_failure {
      result = "RETRY"
    }
  }
  stage {
    name = "BuildStage"
    action {
      name = "BuildAction"
      configuration = {
        ProjectName = aws_codebuild_project.code_build.name
        # The buildspec above writes "codepipeline: $EXECUTION_ID" into BUILD.md, which travels in the
        # deploy artifact so the deployed instance can say which execution put it there. Nothing
        # defined that variable, so the line rendered empty. An undefined variable does not fail a
        # build, which is why this was invisible.
        EnvironmentVariables = jsonencode([{
          name  = "EXECUTION_ID"
          value = "#{codepipeline.PipelineExecutionId}"
          type  = "PLAINTEXT"
        }])
      }
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]
      namespace        = "BuildVariables"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = 1
    }
    on_failure {
      result = "RETRY"
    }
  }
  stage {
    name = "DeployStage"
    action {
      name = "DeployAction"
      configuration = {
        ApplicationName = aws_codedeploy_app.code_deploy_application.name
        # deployment_group_name, not id. This resource's id is CodeDeploy's own identifier for the
        # group - a UUID - and the action needs the name. The pipeline is created either way and the
        # deploy stage fails at run time saying the deployment group does not exist.
        DeploymentGroupName = aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name
      }
      input_artifacts = ["BuildArtifact"]
      namespace       = "DeployVariables"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = 1
    }
    on_failure {
      result = "RETRY"
    }
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-code-pipeline"
}
# force_destroy because the pipeline writes an artifact into this bucket on every execution and
# Terraform did not create those objects, so destroy fails with BucketNotEmpty once the pipeline has
# run even once - which it now does, where before the source stage failed and left the bucket empty.
# aws_ecr_repository.ecr already carries force_delete for the same reason.
resource "aws_s3_bucket" "code_pipeline_artifact_store_s3_bucket" {
  force_destroy = true
}
resource "aws_iam_role" "code_pipeline_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codepipeline.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_cloudwatch_event_rule" "cloud_watch_event_rule" {
  description    = "Amazon CloudWatch Events rule to automatically start your pipeline when a change occurs in the AWS CodeCommit source repository and branch. Deleting this may prevent changes from being detected in that pipeline. Read more: http://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-about-starting.html"
  event_bus_name = "default"
  event_pattern = jsonencode({
    source        = ["aws.codecommit"]
    "detail-type" = ["CodeCommit Repository State Change"]
    resources     = [aws_codecommit_repository.code_commit.arn]
    detail = {
      # referenceCreated is what fires on the very first push, when the branch does not exist yet;
      # referenceUpdated covers every push after it.
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = [var.source_branch_name]
    }
  })
  state = "ENABLED"
}
resource "aws_iam_role" "cloud_watch_event_rule_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}

# Commits the application the bootstrap wrote and pushes it to CodeCommit.
#
# This is what the CloudFormation Code property did, and it has to be done from inside AWS rather than
# by a local-exec on whoever runs Terraform. The workbench already holds the files, already has git,
# and already has an identity - so the push is an SSM association on it.
#
# It is also the whole of the credential story. The AWS CLI's CodeCommit credential helper signs each
# git request with whatever credentials the caller has, which on this instance is its instance role,
# so there is no token and no SSH key anywhere.
#
# The first push creates the branch. The EventBridge rule matches referenceCreated, the pipeline runs,
# and the apply returns with the application built and deployed rather than merely ready.
resource "aws_ssm_association" "git_prepare" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.git_prepare_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    # The until loop is what orders this after the bootstrap. depends_on would only observe that the
    # instance resource was created, and wait_for_success_timeout_seconds does not wait for the
    # remote command the way it reads as though it does (rules.md D-5).
    commands = <<-EOT
      until [ -f ${var.marker_file_path}/userdata ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export AWS_DEFAULT_REGION=${data.aws_region.current.region}
      cd /home/ec2-user/python
      # Guarded because an association re-runs whenever its parameters change, and git init cannot
      # rename the branch of a repository that already exists.
      if [ ! -d .git ]; then git init -q -b ${var.source_branch_name}; fi
      git config --local user.email workbench@example.invalid
      git config --local user.name "codepipeline workbench"
      git add -A
      # Nothing to commit is a normal outcome on a re-run, and git treats it as an error - which under
      # set -e would fail the whole step.
      if [ -n "$(git status --porcelain)" ]; then git commit -q -m "Application deployed by the ${var.stack_name} pipeline"; fi
      # UseHttpPath is required: CodeCommit scopes the credential to the repository path, and without
      # it git offers a credential for the host and the push is refused.
      #
      # "$@" carries no braces, so Terraform leaves it to the shell for the helper to consume.
      git config --local credential.helper '!aws codecommit credential-helper $@'
      git config --local credential.UseHttpPath true
      # set-url rather than add, because adding a remote that already exists is an error and this
      # step has to survive a re-run.
      if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin ${aws_codecommit_repository.code_commit.clone_url_http}
      else
        git remote add origin ${aws_codecommit_repository.code_commit.clone_url_http}
      fi
      # On a re-run with nothing new git reports "Everything up-to-date" and exits zero.
      git push -u origin ${var.source_branch_name}
      STEP
      touch ${var.marker_file_path}/git_prepare
      EOT
  }

  # The pipeline and its trigger both have to exist before the push, or the push lands in a repository
  # nothing is watching and the first run never happens (rules.md D-2).
  depends_on = [
    aws_codepipeline.code_pipeline,
    aws_cloudwatch_event_target.cloud_watch_event_rule,
    aws_iam_role_policy.cloud_watch_event_rule_iam_role,
  ]
}
