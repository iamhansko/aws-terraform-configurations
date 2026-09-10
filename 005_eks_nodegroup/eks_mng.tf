terraform {
  required_version = ">= 1.5"
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

variable "prefix" {
  type        = string
  default     = "eks-mng"
  description = "Resource Name Prefix"
}

data "aws_region" "current" {}

variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "EKS Cluster Kubernetes Version (1.XX)"
  validation {
    condition     = contains(["1.34", "1.35", "1.36"], var.kubernetes_version)
    error_message = "KubernetesVersion must be 1.34+"
  }
}

variable "amazon_linux2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Resolved by the aws_ssm_parameter data source"
}

data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}

locals {
  mappings = {
    ResourceMap = {
      Vpc = {
        Name      = "stem-vpc"
        CidrBlock = "10.0.0.0/16"
      }
      PublicSubnet = {
        Name = "stem-public"
      }
      PrivateSubnet = {
        Name = "stem-private"
      }
      InternetGateway = {
        Name = "stem-igw"
      }
      NatGateway = {
        Name = "stem-natgw"
      }
      VsCodeEc2 = {
        Name         = "vscode"
        InstanceType = "t3.small"
      }
    }
  }
  is_windows = can(regex("^[A-Za-z]:", abspath(path.root)))
}

resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}

resource "aws_key_pair" "key_pair" {
  key_name   = "${var.prefix}-key"
  public_key = tls_private_key.key_pair.public_key_openssh
}

resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_iam_role" {
  role       = aws_iam_role.eks_cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_iam_role_0" {
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_iam_role_1" {
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_node_iam_role_2" {
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_iam_role_3" {
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_eks_access_policy_association" "eks_cluster_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vscode_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

resource "aws_vpc" "vpc" {
  enable_dns_hostnames = true
  cidr_block           = local.mappings["ResourceMap"]["Vpc"]["CidrBlock"]
  tags = {
    Name = local.mappings["ResourceMap"]["Vpc"]["Name"]
  }
}

resource "aws_subnet" "private_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  tags = {
    Name                              = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "a"])
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "private_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 1)
  tags = {
    Name                              = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "b"])
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "private_subnet_c" {
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 2)
  tags = {
    Name                              = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "c"])
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 3)
  tags = {
    Name                     = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "a"])
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 4)
  tags = {
    Name                     = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "b"])
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public_subnet_c" {
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 5)
  tags = {
    Name                     = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "c"])
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = local.mappings["ResourceMap"]["InternetGateway"]["Name"]
  }
}

resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}

resource "aws_eip" "nat_gateway_a_elastic_ip" {}

resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["NatGateway"]["Name"], "a"])
  }
}

resource "aws_eip" "nat_gateway_b_elastic_ip" {}

resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["NatGateway"]["Name"], "b"])
  }
}

resource "aws_eip" "nat_gateway_c_elastic_ip" {}

resource "aws_nat_gateway" "nat_gateway_c" {
  allocation_id = aws_eip.nat_gateway_c_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_c.id
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["NatGateway"]["Name"], "c"])
  }
}

resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "rt"])
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}

resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}

resource "aws_route_table_association" "public_subnet_c_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_c.id
}

resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}

resource "aws_route_table" "private_subnet_a_route_table" {
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "a", "rt"])
  }
  vpc_id = aws_vpc.vpc.id
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
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "b", "rt"])
  }
  vpc_id = aws_vpc.vpc.id
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

resource "aws_route_table" "private_subnet_c_route_table" {
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "c", "rt"])
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table_association" "private_subnet_c_route_table_association" {
  route_table_id = aws_route_table.private_subnet_c_route_table.id
  subnet_id      = aws_subnet.private_subnet_c.id
}

resource "aws_route" "private_subnet_c_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_c.id
  route_table_id         = aws_route_table.private_subnet_c_route_table.id
}

resource "aws_instance" "vscode_ec2" {
  ami           = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  instance_type = local.mappings["ResourceMap"]["VsCodeEc2"]["InstanceType"]
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = local.mappings["ResourceMap"]["VsCodeEc2"]["Name"]
  }
  iam_instance_profile        = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  user_data                   = <<-EOT
    #!/bin/bash
    set -x
    dnf update -y
    dnf install -y git
    dnf groupinstall -y "Development Tools"
    dnf install -yq python3.13
    ln -sf /usr/bin/python3.13 /usr/bin/python
    python -m ensurepip --upgrade

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

    sudo -Eu ec2-user bash << 'EOF'
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.0/2024-05-12/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo "export PATH=/home/ec2-user/bin:$PATH" >> ~/.bashrc
    echo "alias k=kubectl" >> ~/.bashrc
    echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
    echo "source <(kubectl completion bash)" >> ~/.bashrc

    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.eks_cluster.name}

    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin

    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > /home/ec2-user/get_helm.sh
    chmod 700 /home/ec2-user/get_helm.sh
    /home/ec2-user/get_helm.sh

    mkdir -p /home/ec2-user/userdata
    touch /home/ec2-user/userdata/complete
    EOF
    EOT
  subnet_id                   = aws_subnet.public_subnet_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vscode_ec2_security_group.id, aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
}

resource "null_resource" "vscode_ec2_wait_unix" {
  count = local.is_windows ? 0 : 1
  depends_on = [
    aws_instance.vscode_ec2,
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
  ]
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOF
      set -e
      for i in $(seq 1 60); do
        PING=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=${aws_instance.vscode_ec2.id}" \
        --region "${data.aws_region.current.region}" \
        --query "InstanceInformationList[0].PingStatus" \
        --output text 2>/dev/null || echo "None")
        if [ "$PING" = "Online" ]; then
          echo "SSM Online"
          break
        fi
        echo "SSM: $PING ($i/60)"
        sleep 10
      done
      if [ "$PING" != "Online" ]; then
        echo "SSM: Failed" >&2
        exit 1
      fi

      COMMAND=""
      while true; do
        if [ -z "$COMMAND" ]; then
          COMMAND=$(aws ssm send-command \
          --document-name "AWS-RunShellScript" \
          --parameters 'commands=["cat /home/ec2-user/userdata/complete"]' \
          --instance-ids "${aws_instance.vscode_ec2.id}" \
          --region "${data.aws_region.current.region}" \
          --query "Command.CommandId" --output text 2>/dev/null || echo "")
          if [ -z "$COMMAND" ]; then
            sleep 10
            continue
          fi
        fi

        STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND" \
        --instance-id "${aws_instance.vscode_ec2.id}" \
        --region "${data.aws_region.current.region}" \
        --query "Status" --output text 2>/dev/null || echo "Pending")
        echo "COMMAND: $STATUS"

        case "$STATUS" in Success) break;;esac
        sleep 10
      done
    EOF
  }
}

resource "null_resource" "vscode_ec2_wait_windows" {
  count = local.is_windows ? 1 : 0
  depends_on = [
    aws_instance.vscode_ec2,
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
  ]
  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-Command"]
    command     = <<-EOF
      $ErrorActionPreference = "Stop"
      $InstanceId = "${aws_instance.vscode_ec2.id}"
      $Region     = "${data.aws_region.current.region}"

      $Ping = "None"
      for ($i = 1; $i -le 60; $i++) {
        $Ping = aws ssm describe-instance-information `
        --filters "Key=InstanceIds,Values=$InstanceId" `
        --region $Region `
        --query "InstanceInformationList[0].PingStatus" `
        --output text 2>$null
        if (-not $Ping) { $Ping = "None" }
        if ($Ping -eq "Online") {
          Write-Host "SSM Online"
          break
        }
        Write-Host "SSM: $Ping ($i/60)"
        Start-Sleep -Seconds 10
      }
      if ($Ping -ne "Online") {
        Write-Error "SSM: Failed"
        exit 1
      }

      $CommandId = ""
      while ($true) {
        if (-not $CommandId) {
          $CommandId = aws ssm send-command `
          --document-name "AWS-RunShellScript" `
          --parameters 'commands=["cat /home/ec2-user/userdata/complete"]' `
          --instance-ids $InstanceId `
          --region $Region `
          --query "Command.CommandId" --output text 2>$null
          if (-not $CommandId) {
            Start-Sleep -Seconds 10
            continue
          }
        }

        $Status = aws ssm get-command-invocation `
        --command-id $CommandId `
        --instance-id $InstanceId `
        --region $Region `
        --query "Status" --output text 2>$null
        if (-not $Status) { $Status = "Pending" }
        Write-Host "COMMAND: $Status"

        if ($Status -eq "Success") { break }
        Start-Sleep -Seconds 10
      }
    EOF
  }
}

resource "aws_security_group" "vscode_ec2_security_group" {
  description = "Security Group for Bastion EC2 SSH Connection"
  name        = "bastion-sg"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8000
    protocol    = "tcp"
    to_port     = 8000
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "bastion-sg"
  }
}

resource "aws_iam_role" "vscode_ec2_iam_role" {
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

resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  role = aws_iam_role.vscode_ec2_iam_role.name
}

resource "aws_eks_cluster" "eks_cluster" {
  name    = "stem-cluster"
  version = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false
    subnet_ids              = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id, aws_subnet.public_subnet_c.id, aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id, aws_subnet.private_subnet_c.id]
  }
  role_arn                  = aws_iam_role.eks_cluster_iam_role.arn
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

resource "aws_eks_node_group" "app_node_group" {
  node_group_name      = "stem-app"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.medium"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.eks_cluster.name
  force_update_version = true
  labels = {
    "stem/dedicated" = "app"
  }
  node_role_arn = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id, aws_subnet.private_subnet_c.id]
  launch_template {
    id      = aws_launch_template.app_launch_template.id
    version = aws_launch_template.app_launch_template.latest_version
  }
}

resource "aws_launch_template" "app_launch_template" {
  name                   = "app-nodegroup-launchtemplate"
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "app-nodegroup-instance"
    }
  }
}

resource "aws_iam_role" "eks_cluster_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["eks.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role" "eks_node_iam_role" {
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

resource "aws_eks_access_entry" "eks_cluster_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vscode_ec2_iam_role.arn
  type          = "STANDARD"
}

resource "aws_ssm_association" "document_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vscode_ec2.id]
  }
  depends_on = [
    null_resource.vscode_ec2_wait_unix,
    null_resource.vscode_ec2_wait_windows,
  ]
  parameters = {
    commands = <<-EOT
      echo $'#EKS Managed Node Group' > /home/ec2-user/README.md
      EOT
  }
}

output "vscode" {
  value       = "http://${aws_instance.vscode_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code Server EC2 instance"
}
