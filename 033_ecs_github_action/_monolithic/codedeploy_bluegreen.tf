# Generated from 033_ecs_github_action.yaml/codedeploy_bluegreen.yaml by tools/cfn2tf.
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
  default     = "codedeploy-bluegreen"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "git_hub_token" {
  type = string
}
variable "git_hub_user" {
  type = string
}
variable "git_hub_repo" {
  type    = string
  default = "ecs-repo"
}
variable "git_hub_branch" {
  type    = string
  default = "ecs-app"
}
variable "git_hub_action" {
  type    = string
  default = "ecs-cicd-action"
}
variable "code_build_project_name" {
  type    = string
  default = "GitHubRunner"
}
variable "bastion_ec2_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "bastion_ec2_ami_id" {
  name = var.bastion_ec2_ami_id
}
variable "ecs_ami_id" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ecs_ami_id" {
  name = var.ecs_ami_id
}
# --- Mappings / Conditions ---
locals {
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
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
resource "aws_iam_role_policy_attachment" "ecs_container_instance_iam_role_0" {
  role       = aws_iam_role.ecs_container_instance_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_role_policy_attachment" "ecs_container_instance_iam_role_1" {
  role       = aws_iam_role.ecs_container_instance_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_iam_role_0" {
  role       = aws_iam_role.ecs_task_execution_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_iam_role_1" {
  role       = aws_iam_role.ecs_task_execution_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}
resource "aws_iam_role_policy_attachment" "code_deploy_iam_role" {
  role       = aws_iam_role.code_deploy_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
resource "aws_iam_role_policy_attachment" "code_build_iam_role" {
  role       = aws_iam_role.code_build_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "ecs-cicd-vpc"
  }
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  availability_zone       = "${data.aws_region.current.region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "ecs-cicd-public-a"
  }
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 1)
  availability_zone       = "${data.aws_region.current.region}b"
  map_public_ip_on_launch = true
  tags = {
    Name = "ecs-cicd-public-b"
  }
}
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 2)
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "ecs-cicd-private-a"
  }
}
resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 3)
  availability_zone = "${data.aws_region.current.region}b"
  tags = {
    Name = "ecs-cicd-private-b"
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "ecs-cicd-igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  vpc_id              = aws_vpc.vpc.id
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
}
resource "aws_route_table" "public_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "ecs-cicd-public-rt"
  }
}
resource "aws_route" "public_subnet_route" {
  route_table_id         = aws_route_table.public_subnet_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_subnet_route_table.id
}
resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_subnet_route_table.id
}
resource "aws_route_table" "private_subnet_a_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "ecs-cicd-private-a-rt"
  }
}
resource "aws_eip" "natgateway_a_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.natgateway_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = "ecs-cicd-natgw-a"
  }
}
resource "aws_route_table_association" "private_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_subnet_a_route_table.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
resource "aws_route" "private_subnet_a_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
  route_table_id         = aws_route_table.private_subnet_a_route_table.id
}
resource "aws_route_table" "private_subnet_b_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "ecs-cicd-private-b-rt"
  }
}
resource "aws_eip" "natgateway_b_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.natgateway_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = "ecs-cicd-natgw-b"
  }
}
resource "aws_route_table_association" "private_subnet_b_route_table_association" {
  route_table_id = aws_route_table.private_subnet_b_route_table.id
  subnet_id      = aws_subnet.private_subnet_b.id
}
resource "aws_route" "private_subnet_b_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.id
  route_table_id         = aws_route_table.private_subnet_b_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT5M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  instance_type        = "t3.small"
  ami                  = data.aws_ssm_parameter.bastion_ec2_ami_id.insecure_value
  key_name             = aws_key_pair.key_pair.key_name
  iam_instance_profile = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  tags = {
    Name = "ecs-cicd-bastion"
  }
  user_data                   = <<EOT
#!/bin/bash
dnf update -y
dnf groupinstall -y "Development Tools"
dnf install -y python3.12
dnf install -y python3-pip
ln -s /usr/bin/python3.12 /usr/bin/python

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

sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
sudo systemctl restart sshd
# ssh -i key.pem -p 10100 ec2-user@public_ip

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subnet_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
}
resource "aws_eip" "bastion_elastic_ip" {}
resource "aws_eip_association" "bastion_elastic_ip_association" {
  allocation_id = aws_eip.bastion_elastic_ip.allocation_id
  instance_id   = aws_instance.bastion_ec2.id
}
resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol    = "tcp"
    from_port   = 2222
    to_port     = 2222
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 8000
    to_port     = 8000
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "bastion-ec2-sg"
  }
}
resource "aws_iam_role" "bastion_ec2_iam_role" {
  name = "bastion-ec2-role"
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
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
resource "aws_ecr_repository" "ecr" {
  name = "ecs-cicd-ecr"
}
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs-cicd-cluster"
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
}
resource "aws_ecs_capacity_provider" "ecs_ec2_capacity_provider" {
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    managed_draining       = "ENABLED"
    managed_scaling {
      instance_warmup_period    = 30
      maximum_scaling_step_size = 10000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
    managed_termination_protection = "DISABLED"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ecs-ec2-capacity-provider"
}
resource "aws_ecs_cluster_capacity_providers" "ecs_ec2_capacity_provider_association" {
  capacity_providers = [aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id, "FARGATE", "FARGATE_SPOT"]
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  default_capacity_provider_strategy {
    base              = 0
    capacity_provider = aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id
    weight            = 100
  }
}
resource "aws_autoscaling_group" "ecs_asg" {
  min_size            = 1
  desired_capacity    = 1
  max_size            = 1
  vpc_zone_identifier = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = aws_launch_template.ecs_lt.latest_version
  }
  availability_zone_distribution {
    capacity_distribution_strategy = "balanced-only"
  }
  depends_on = [aws_ecs_cluster.ecs_cluster]
}
resource "aws_launch_template" "ecs_lt" {
  image_id      = data.aws_ssm_parameter.ecs_ami_id.insecure_value
  instance_type = "t3.medium"
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_container_instance_profile.name
  }
  vpc_security_group_ids = [aws_security_group.ecs_container_instance_security_group.id]
  user_data = base64encode(<<EOT
#!/bin/bash -xe
echo ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name} >> /etc/ecs/ecs.config
dnf install -y aws-cfn-bootstrap
EOT
  )
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  key_name = aws_key_pair.key_pair.key_name
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ecs-container-instance"
    }
  }
}
resource "aws_security_group" "ecs_container_instance_security_group" {
  description = "Security Group"
  name        = "ecs-container-instance-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_iam_role" "ecs_container_instance_iam_role" {
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
resource "aws_iam_instance_profile" "ecs_container_instance_profile" {
  # Single role name string, not a list (rules.md A-3).
  role = aws_iam_role.ecs_container_instance_iam_role.name
}
resource "aws_iam_role" "ecs_task_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role" "ecs_task_execution_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_security_group" "ecs_service_security_group" {
  description = "Security Group"
  name        = "ecs-service-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  ingress {
    protocol        = "TCP"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.bastion_ec2_security_group.id]
  }
  ingress {
    protocol        = "TCP"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb_security_group.id]
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_ssm_association" "ecr_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 900
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["dnf install -yq docker\nsystemctl start docker\nsystemctl enable docker\n# usermod -aG docker ec2-user\n# newgrp docker\nchmod 666 /var/run/docker.sock\n\ndnf install -yq git\n\nsu - ec2-user << EOF\nmkdir -p /home/ec2-user/${var.git_hub_repo}\ncd /home/ec2-user/${var.git_hub_repo}\necho 'from flask import Flask\n\napp = Flask(__name__)\n\nTAG = \"ec2-v1.0.0\"\n\n@app.route(\"/\")\ndef home():\n    return f\"Hello Korea!\", 200\n\n@app.route(\"/health\")\ndef health():\n    return \"OK\", 200\n\n@app.route(\"/tag\")\ndef tag():\n    return TAG, 200\n\nif __name__ == \"__main__\":\n    app.run(host=\"0.0.0.0\", port=80)' > /home/ec2-user/${var.git_hub_repo}/cicd-app.py\n\naws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com\n\necho 'FROM python:3.13-slim\nWORKDIR /app\nCOPY cicd-app.py .\nRUN pip install --no-cache-dir Flask\nRUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*\nCMD [\"python\", \"cicd-app.py\"]' > /home/ec2-user/${var.git_hub_repo}/Dockerfile\ndocker build -t ${aws_ecr_repository.ecr.repository_url}:latest .\ndocker push ${aws_ecr_repository.ecr.repository_url}:latest\n\nEOF\n"])
  }
}
resource "aws_ssm_association" "git_hub_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 900
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << EOF\nmkdir -p /home/ec2-user/${var.git_hub_repo}/.github/workflows\ncd /home/ec2-user/${var.git_hub_repo}\n\necho $'name: ${var.git_hub_action}\non:\n  push:\n    branches: [ \"${var.git_hub_branch}\" ]\njobs:\n  codebuild:\n    runs-on:\n      - codebuild-${var.code_build_project_name}${element(split("-", element(split("/", local.stack_id), 2)), 3)}-\\$${{ github.run_id }}-\\$${{ github.run_attempt }}\n    steps:\n      - name: Repo Checkout\n        uses: actions/checkout@v4\n      - name: ECR Login\n        id: login-ecr\n        uses: aws-actions/amazon-ecr-login@v1\n      - name: Docker Build and Push\n        id: push-ecr\n        env:\n          ECR_REGISTRY: \\$${{ steps.login-ecr.outputs.registry }}\n          ECR_REPOSITORY: ${aws_ecr_repository.ecr.name}\n          IMAGE_TAG: \\$${{ github.sha }}\n        run: |\n          docker build -t \\$ECR_REGISTRY/\\$ECR_REPOSITORY:\\$IMAGE_TAG .\n          docker build -t \\$ECR_REGISTRY/\\$ECR_REPOSITORY:latest .\n          docker push \\$ECR_REGISTRY/\\$ECR_REPOSITORY:\\$IMAGE_TAG\n          docker push \\$ECR_REGISTRY/\\$ECR_REPOSITORY:latest\n          echo \"IMAGE=\\$ECR_REGISTRY/\\$ECR_REPOSITORY:\\$IMAGE_TAG\" >> \\$GITHUB_ENV\n      - name: ECS TaskDefinition\n        id: update-taskdef\n        uses: aws-actions/amazon-ecs-render-task-definition@v1\n        with:\n          task-definition: taskdef.json\n          container-name: python\n          image: \\$${{ env.IMAGE }}\n      - name: Fargate Check\n        uses: mikefarah/yq@master\n        with:\n          cmd: |\n            if grep -q \\'TAG = \"fargate\"\\' cicd-app.py; then\n              yq -i \\'.Resources[0].TargetService.Properties.CapacityProviderStrategy[0].CapacityProvider = \"FARGATE\"\\' appspec.yaml\n            else\n              yq -i \\'.Resources[0].TargetService.Properties.CapacityProviderStrategy[0].CapacityProvider = \"${aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id}\"\\' appspec.yaml\n            fi\n      - name: ECS Service Deployment\n        uses: aws-actions/amazon-ecs-deploy-task-definition@v1\n        with:\n          task-definition: \\$${{ steps.update-taskdef.outputs.task-definition }}\n          service: ${aws_ecs_service.ecs_service.name}\n          cluster: ${aws_ecs_cluster.ecs_cluster.name}\n          codedeploy-appspec: appspec.yaml\n          codedeploy-application: ${aws_codedeploy_app.code_deploy_application.name}\n          codedeploy-deployment-group: ${aws_codedeploy_deployment_group.code_deploy_deployment_group.id}\n          wait-for-service-stability: true\n' > ./.github/workflows/codebuild.yaml\n\necho 'version: 0.0\nResources:\n  - TargetService:\n      Type: AWS::ECS::Service\n      Properties:\n        TaskDefinition: <TASK_DEFINITION>\n        LoadBalancerInfo:\n          ContainerName: python\n          ContainerPort: 80\n        CapacityProviderStrategy:\n          - CapacityProvider: ${aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id}\n            Weight: 1' > ./appspec.yaml\n\nzip -r src.zip . -x \"*/.*\"\naws s3 cp src.zip s3://${aws_s3_bucket.source_s3_bucket.id}\nEOF\n"])
  }
}
resource "aws_s3_bucket" "source_s3_bucket" {
  bucket = "github-runner-bucket-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
}
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family = "ecs-task-def"
  cpu    = "512"
  memory = "1024"
  container_definitions = jsonencode([{
    Name      = "python"
    Image     = aws_ecr_repository.ecr.repository_url
    Essential = true
    HealthCheck = {
      Command     = ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      Interval    = 30
      Retries     = 5
      StartPeriod = 5
      Timeout     = 5
    }
    PortMappings = [{
      ContainerPort = 80
      HostPort      = 80
      Name          = "http"
    }]
  }])
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2", "FARGATE"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution_iam_role.arn
  depends_on         = [aws_ssm_association.ecr_ssm_association]
}
resource "aws_lb" "alb" {
  name            = "ecs-cicd-alb"
  subnets         = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  security_groups = [aws_security_group.alb_security_group.id]
  internal        = false
}
resource "aws_security_group" "alb_security_group" {
  description = "Security Group"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "alb-sg"
  }
}
resource "aws_lb_target_group" "blue_target_group" {
  name        = "cicd-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"
  health_check {
    path    = "/health"
    enabled = true
  }
}
resource "aws_lb_target_group" "green_target_group" {
  name        = "green-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"
  health_check {
    path    = "/health"
    enabled = true
  }
}
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  protocol          = "HTTP"
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_target_group.arn
  }
}
resource "aws_ecs_service" "ecs_service" {
  name            = "ecs-cicd-service"
  cluster         = aws_ecs_cluster.ecs_cluster.name
  launch_type     = "EC2"
  desired_count   = 1
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  network_configuration {
    subnets         = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
    security_groups = [aws_security_group.ecs_service_security_group.id]
  }
  load_balancer {
    container_name   = "python"
    container_port   = 80
    target_group_arn = aws_lb_target_group.blue_target_group.arn
  }
  depends_on = [aws_lb_listener.alb_listener]
}
resource "aws_codedeploy_app" "code_deploy_application" {
  name             = "ecs-codedeploy-app"
  compute_platform = "ECS"
}
resource "aws_codedeploy_deployment_group" "code_deploy_deployment_group" {
  deployment_group_name = "ecs-codedeploy-dg"
  app_name              = aws_codedeploy_app.code_deploy_application.name
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
  }
  service_role_arn       = aws_iam_role.code_deploy_iam_role.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  ecs_service {
    cluster_name = aws_ecs_cluster.ecs_cluster.name
    service_name = aws_ecs_service.ecs_service.name
  }
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.alb_listener.arn]
      }
      target_group {
        name = aws_lb_target_group.blue_target_group.name
      }
      target_group {
        name = aws_lb_target_group.green_target_group.name
      }
    }
  }
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 0
    }
  }
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
# === GitHubRepository (AWS::CodeStar::GitHubRepository) NOT CONVERTED ===
# Legacy CodeStar resource; the AWS provider has no equivalent. Use the GitHub provider.
# Original CloudFormation definition:
# # {
# #   "Type": "AWS::CodeStar::GitHubRepository",
# #   "DependsOn": [
# #     "GitHubSsmAssociation"
# #   ],
# #   "Properties": {
# #     "EnableIssues": true,
# #     "IsPrivate": false,
# #     "RepositoryAccessToken": {
# #       "Ref": "GitHubToken"
# #     },
# #     "RepositoryName": {
# #       "Ref": "GitHubRepo"
# #     },
# #     "RepositoryOwner": {
# #       "Ref": "GitHubUser"
# #     },
# #     "Code": {
# #       "S3": {
# #         "Bucket": {
# #           "Ref": "SourceS3Bucket"
# #         },
# #         "Key": "src.zip"
# #       }
# #     }
# #   }
# # }
resource "aws_codestarconnections_connection" "git_hub_connection" {
  name          = "github-connection"
  provider_type = "GitHub"
}
resource "aws_codebuild_source_credential" "git_hub_credential" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.git_hub_token
  user_name   = var.git_hub_user
}
resource "aws_codebuild_project" "code_build_project" {
  name         = "${var.code_build_project_name}${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  service_role = aws_iam_role.code_build_iam_role.arn
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
  }
  source {
    type     = "GITHUB"
    location = "https://github.com/${var.git_hub_user}/${var.git_hub_repo}.git"
    auth {
      type     = "OAUTH"
      resource = aws_codestarconnections_connection.git_hub_connection.id
    }
  }
  # TODO cfn2tf: unmapped CloudFormation property 'Triggers' of AWS::CodeBuild::Project
  # # {
  # #   "Webhook": true,
  # #   "FilterGroups": [
  # #     [
  # #       {
  # #         "Type": "EVENT",
  # #         "Pattern": "WORKFLOW_JOB_QUEUED"
  # #       },
  # #       {
  # #         "Type": "WORKFLOW_NAME",
  # #         "Pattern": {
  # #           "Ref": "GitHubAction"
  # #         }
  # #       }
  # #     ]
  # #   ]
  # # }
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
resource "aws_ssm_association" "cicd_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 900
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["dnf install -yq git\n\nsu - ec2-user << EOF\ncd /home/ec2-user/${var.git_hub_repo}\n\ngit init\ngit remote add origin https://${var.git_hub_token}@github.com/${var.git_hub_user}/${var.git_hub_repo}.git\ngit checkout -b ${var.git_hub_branch}\naws ecs describe-task-definition --task-definition ecs-task-def --query \"taskDefinition\" > /home/ec2-user/${var.git_hub_repo}/taskdef.json\ngit add cicd-app.py\ngit add Dockerfile\ngit add taskdef.json\ngit add appspec.yaml\ngit add .github/workflows/codebuild.yaml\ngit commit -m \"init\"\ngit push --set-upstream origin ${var.git_hub_branch}\n\nEOF\n"])
  }
  depends_on = [aws_codebuild_project.code_build_project, aws_codedeploy_deployment_group.code_deploy_deployment_group]
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
