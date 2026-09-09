# Generated from 000_deprecated/eks/argo-rollouts/canary.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
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
variable "stack_name" {
  type        = string
  default     = "canary"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "eks_cluster_name" {
  type    = string
  default = "eks-cluster"
}
variable "eks_cluster_version" {
  type    = string
  default = 1.32
  validation {
    condition     = contains([1.32, 1.31, 1.3, 1.29, 1.28, 1.27, 1.26, 1.25], var.eks_cluster_version)
    error_message = "EksClusterVersion must be one of: 1.32, 1.31, 1.3, 1.29, 1.28, 1.27, 1.26, 1.25"
  }
}
variable "eks_mng_ami_family" {
  type    = string
  default = "AmazonLinux2023"
  validation {
    condition     = contains(["AmazonLinux2023", "AmazonLinux2", "UbuntuPro2204", "Ubuntu2204", "Ubuntu2004", "Ubuntu1804", "Bottlerocket", "WindowsServer2022CoreContainer", "WindowsServer2022FullContainer", "WindowsServer2019CoreContainer", "WindowsServer2019FullContainer"], var.eks_mng_ami_family)
    error_message = "EksMngAmiFamily must be one of: AmazonLinux2023, AmazonLinux2, UbuntuPro2204, Ubuntu2204, Ubuntu2004, Ubuntu1804, Bottlerocket, WindowsServer2022CoreContainer, WindowsServer2022FullContainer, WindowsServer2019CoreContainer, WindowsServer2019FullContainer"
  }
}
variable "eks_mng_instance_type" {
  type    = string
  default = "t3.large"
  validation {
    condition     = contains(["t1.micro", "t2.2xlarge", "t2.large", "t2.medium", "t2.micro", "t2.nano", "t2.small", "t2.xlarge", "t3.2xlarge", "t3.large", "t3.medium", "t3.micro", "t3.nano", "t3.small", "t3.xlarge", "t3a.2xlarge", "t3a.large", "t3a.medium", "t3a.micro", "t3a.nano", "t3a.small", "t3a.xlarge", "t4g.2xlarge", "t4g.large", "t4g.medium", "t4g.micro", "t4g.nano", "t4g.small", "t4g.xlarge"], var.eks_mng_instance_type)
    error_message = "EksMngInstanceType must be one of: t1.micro, t2.2xlarge, t2.large, t2.medium, t2.micro, t2.nano, t2.small, t2.xlarge, t3.2xlarge, t3.large, t3.medium, t3.micro, t3.nano, t3.small, t3.xlarge, t3a.2xlarge, t3a.large, t3a.medium, t3a.micro, t3a.nano, t3a.small, t3a.xlarge, t4g.2xlarge, t4g.large, t4g.medium, t4g.micro, t4g.nano, t4g.small, t4g.xlarge"
  }
}
variable "eks_mng_desired_capacity" {
  type    = number
  default = 2
}
variable "prefix" {
  type        = string
  default     = "eks"
  description = "Name Tag Auto-generation (\"project\" -> project-vpc, project-igw, ...)"
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR Block for the VPC to Create (ex 10.0.0.0/16)"
}
variable "enable_dns_hostnames_option" {
  type    = string
  default = true
  validation {
    condition     = contains([true, false], var.enable_dns_hostnames_option)
    error_message = "EnableDnsHostnamesOption must be one of: True, False"
  }
}
variable "enable_dns_resolution_option" {
  type    = string
  default = true
  validation {
    condition     = contains([true, false], var.enable_dns_resolution_option)
    error_message = "EnableDnsResolutionOption must be one of: True, False"
  }
}
variable "ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "EC2 AMI Id(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 Instance Type"
  validation {
    condition     = contains(["t1.micro", "t2.2xlarge", "t2.large", "t2.medium", "t2.micro", "t2.nano", "t2.small", "t2.xlarge", "t3.2xlarge", "t3.large", "t3.medium", "t3.micro", "t3.nano", "t3.small", "t3.xlarge", "t3a.2xlarge", "t3a.large", "t3a.medium", "t3a.micro", "t3a.nano", "t3a.small", "t3a.xlarge", "t4g.2xlarge", "t4g.large", "t4g.medium", "t4g.micro", "t4g.nano", "t4g.small", "t4g.xlarge"], var.instance_type)
    error_message = "InstanceType must be one of: t1.micro, t2.2xlarge, t2.large, t2.medium, t2.micro, t2.nano, t2.small, t2.xlarge, t3.2xlarge, t3.large, t3.medium, t3.micro, t3.nano, t3.small, t3.xlarge, t3a.2xlarge, t3a.large, t3a.medium, t3a.micro, t3a.nano, t3a.small, t3a.xlarge, t4g.2xlarge, t4g.large, t4g.medium, t4g.micro, t4g.nano, t4g.small, t4g.xlarge"
  }
}
# --- Mappings / Conditions ---
locals {
  mappings = {
    AWSRegions2PrefixListID = {
      "ap-northeast-1" = {
        PrefixList = "pl-58a04531"
      }
      "ap-northeast-2" = {
        PrefixList = "pl-22a6434b"
      }
      "ap-northeast-3" = {
        PrefixList = "pl-31a14458"
      }
      "ap-south-1" = {
        PrefixList = "pl-9aa247f3"
      }
      "ap-southeast-1" = {
        PrefixList = "pl-31a34658"
      }
      "ap-southeast-2" = {
        PrefixList = "pl-b8a742d1"
      }
      "ca-central-1" = {
        PrefixList = "pl-38a64351"
      }
      "eu-central-1" = {
        PrefixList = "pl-a3a144ca"
      }
      "eu-north-1" = {
        PrefixList = "pl-fab65393"
      }
      "eu-west-1" = {
        PrefixList = "pl-4fa04526"
      }
      "eu-west-2" = {
        PrefixList = "pl-93a247fa"
      }
      "eu-west-3" = {
        PrefixList = "pl-75b1541c"
      }
      "sa-east-1" = {
        PrefixList = "pl-5da64334"
      }
      "us-east-1" = {
        PrefixList = "pl-3b927c52"
      }
      "us-east-2" = {
        PrefixList = "pl-b6a144df"
      }
      "us-west-1" = {
        PrefixList = "pl-4ea04527"
      }
      "us-west-2" = {
        PrefixList = "pl-82a045eb"
      }
    }
  }
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
resource "aws_iam_role_policy_attachment" "vs_code_on_ec2_iam_role" {
  role       = aws_iam_role.vs_code_on_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = var.enable_dns_resolution_option
  enable_dns_hostnames = var.enable_dns_hostnames_option
  tags = {
    Name = var.prefix
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "${var.prefix}-igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "${var.prefix}-rtb-public"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
resource "aws_subnet" "public_subnet1" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${var.prefix}-subnet-public1-${data.aws_region.current.region}a"
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet1_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet1.id
}
resource "aws_subnet" "public_subnet2" {
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 1)
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${var.prefix}-subnet-public2-${data.aws_region.current.region}b"
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet2_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet2.id
}
resource "aws_subnet" "private_subnet1" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 3)
  tags = {
    Name                              = "${var.prefix}-subnet-private1-${data.aws_region.current.region}a"
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_eip" "nat_gateway1_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway1" {
  allocation_id = aws_eip.nat_gateway1_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet1.id
  tags = {
    Name = "${var.prefix}-nat-public1-${data.aws_region.current.region}a"
  }
}
resource "aws_route_table" "private_subnet1_route_table" {
  tags = {
    Name = "${var.prefix}-rtb-private1-${data.aws_region.current.region}a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet1_route_table_association" {
  route_table_id = aws_route_table.private_subnet1_route_table.id
  subnet_id      = aws_subnet.private_subnet1.id
}
resource "aws_route" "private_subnet1_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway1.id
  route_table_id         = aws_route_table.private_subnet1_route_table.id
}
resource "aws_subnet" "private_subnet2" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 4)
  tags = {
    Name                              = "${var.prefix}-subnet-private2-${data.aws_region.current.region}b"
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_eip" "nat_gateway2_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway2" {
  allocation_id = aws_eip.nat_gateway2_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet2.id
  tags = {
    Name = "${var.prefix}-nat-public2-${data.aws_region.current.region}b"
  }
}
resource "aws_route_table" "private_subnet2_route_table" {
  tags = {
    Name = "${var.prefix}-rtb-private2-${data.aws_region.current.region}b"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet2_route_table_association" {
  route_table_id = aws_route_table.private_subnet2_route_table.id
  subnet_id      = aws_subnet.private_subnet2.id
}
resource "aws_route" "private_subnet2_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway2.id
  route_table_id         = aws_route_table.private_subnet2_route_table.id
}
resource "aws_key_pair" "key_pair" {
  key_name   = join("-", ["key", element(split("-", element(split("/", local.stack_id), 2)), 4)])
  public_key = tls_private_key.key_pair.public_key_openssh
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT10M"
# #   }
# # }
resource "aws_instance" "vs_code_on_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = var.instance_type
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "vscode"
  }
  iam_instance_profile        = aws_iam_instance_profile.vs_code_on_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash

dnf update -y
dnf install -y -q git
dnf groupinstall -y -q "Development Tools"
dnf install -y -q python3.12
python3.12 -m ensurepip --upgrade
python3.12 -m pip install --upgrade pip
ln -sf /usr/bin/python3.12 /usr/bin/python
echo "alias pip=pip3" >> ~/.bashrc

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeOnEc2 --region ${data.aws_region.current.region}

export CODE_SERVER_VERSION="4.96.4"
wget -q https://github.com/coder/code-server/releases/download/v$CODE_SERVER_VERSION/code-server-$CODE_SERVER_VERSION-linux-amd64.tar.gz
tar -xzf code-server-$CODE_SERVER_VERSION-linux-amd64.tar.gz
mv code-server-$CODE_SERVER_VERSION-linux-amd64 /usr/local/lib/code-server
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
systemctl enable --now code-server

dnf install -y -q docker
systemctl enable --now docker
# usermod -aG docker ec2-user
# newgrp docker
# VS Code Server Terminal(Bash) Deletes "docker" group...
chmod 666 /var/run/docker.sock
EOT
  subnet_id                   = aws_subnet.public_subnet1.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vs_code_on_ec2_security_group.id]
}
resource "aws_security_group" "vs_code_on_ec2_security_group" {
  description = "Security Group for VS Code EC2 SSH Connection"
  name        = join("-", ["vscode-ec2-sg", element(split("-", element(split("/", local.stack_id), 2)), 4)])
  vpc_id      = aws_vpc.vpc.id
  ingress {
    description     = "com.amazonaws.global.cloudfront.origin-facing"
    protocol        = "tcp"
    from_port       = 8000
    to_port         = 8000
    prefix_list_ids = [local.mappings["AWSRegions2PrefixListID"][data.aws_region.current.region]["PrefixList"]]
  }
}
resource "aws_iam_role" "vs_code_on_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "vs_code_on_ec2_instance_profile" {
  role = jsonencode([aws_iam_role.vs_code_on_ec2_iam_role.name])
}
resource "aws_cloudfront_distribution" "cloud_front_distribution" {
  origin {
    domain_name = aws_instance.vs_code_on_ec2.public_dns
    origin_id   = aws_instance.vs_code_on_ec2.public_dns
    custom_origin_config {
      http_port              = 8000
      origin_protocol_policy = "http-only"
      # cfn2tf: 'https_port' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      https_port = 443
      # cfn2tf: 'origin_ssl_protocols' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }
  enabled = true
  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    forwarded_values {
      query_string = false
      # cfn2tf: 'cookies' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
      cookies {
        forward = "none"
      }
    }
    compress                 = false
    target_origin_id         = aws_instance.vs_code_on_ec2.public_dns
    viewer_protocol_policy   = "allow-all"
    cache_policy_id          = aws_cloudfront_cache_policy.cloud_front_cache_policy.id
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    # cfn2tf: 'cached_methods' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
    cached_methods = ["GET", "HEAD"]
  }
  # cfn2tf: 'restrictions' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  # cfn2tf: 'viewer_certificate' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "aws_cloudfront_cache_policy" "cloud_front_cache_policy" {
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 1
  name        = join("-", ["VSCode", element(split("-", element(split("/", local.stack_id), 2)), 4)])
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "all"
    }
    enable_accept_encoding_gzip = false
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Accept-Charset", "Authorization", "Origin", "Accept", "Referer", "Host", "Accept-Language", "Accept-Encoding", "Accept-Datetime"]
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}
resource "aws_ssm_association" "ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 1800
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_on_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << EOF\nmkdir -p /home/ec2-user/bin\ncurl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.31.2/2024-11-15/bin/linux/amd64/kubectl\nchmod +x kubectl\nmv kubectl /home/ec2-user/bin/kubectl\nexport PATH=/home/ec2-user/bin:$PATH\necho \"export PATH=/home/ec2-user/bin:$PATH\" >> ~/.bashrc\necho \"alias k=kubectl\" >> ~/.bashrc\necho \"complete -o default -F __start_kubectl k\" >> ~/.bashrc\necho \"source <(kubectl completion bash)\" >> ~/.bashrc\n\ncurl --silent --location \"https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz\" | tar xz -C /tmp\nsudo mv /tmp/eksctl /usr/local/bin\naws configure set default.region ${data.aws_region.current.region}\n\ncurl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > /home/ec2-user/get_helm.sh\nchmod 700 /home/ec2-user/get_helm.sh\n/home/ec2-user/get_helm.sh\n\nmkdir -p /home/ec2-user/eksctl\n\necho '#!/bin/bash\ncluster_name=\"${var.eks_cluster_name}\"\nbastion_id=\\$(ec2-metadata -i | cut -d \" \" -f 2)\ncluster_sg=\\$(aws eks describe-cluster --name \\$cluster_name --query \"cluster.resourcesVpcConfig.clusterSecurityGroupId\" --output text)\nbastion_sg=\\$(aws ec2 describe-instances --instance-ids \\$bastion_id --query \"Reservations[].Instances[].SecurityGroups[].GroupId\" --output text)\naws ec2 modify-instance-attribute --instance-id \\$bastion_id --groups \\$bastion_sg \\$cluster_sg' > /home/ec2-user/eksctl/security_group.sh\n\necho '# eksctl create cluster -f /home/ec2-user/eksctl/cluster.yaml\napiVersion: eksctl.io/v1alpha5\nkind: ClusterConfig\nmetadata:\n  name: ${var.eks_cluster_name}\n  region: ${data.aws_region.current.region}\n  version: \"${var.eks_cluster_version}\"\nvpc:\n  id: ${aws_vpc.vpc.id}\n  subnets:\n    public:\n      public1:\n        id: ${aws_subnet.public_subnet1.id}\n      public2:\n        id: ${aws_subnet.public_subnet2.id}\n    private:\n      private1:\n        id: ${aws_subnet.private_subnet1.id}\n      private2:\n        id: ${aws_subnet.private_subnet2.id}\nmanagedNodeGroups:\n  - name: nodegroup\n    amiFamily: ${var.eks_mng_ami_family}\n    instanceType: ${var.eks_mng_instance_type}\n    desiredCapacity: ${var.eks_mng_desired_capacity}\n    privateNetworking: true\n    iam:\n      attachPolicyARNs:\n        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy\n        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy\n        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly\n        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore\naddons:\n  - name: coredns\n    resolveConflicts: overwrite\n  - name: kube-proxy\n    resolveConflicts: overwrite\n  - name: vpc-cni\n    resolveConflicts: overwrite\n  - name: eks-pod-identity-agent\n    resolveConflicts: overwrite\n  - name: metrics-server\n    resolveConflicts: overwrite\niam:\n  withOIDC: true # eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve' > /home/ec2-user/eksctl/cluster.yaml\n\neksctl create cluster -f /home/ec2-user/eksctl/cluster.yaml\n\ncd /home/ec2-user\ngit clone https://github.com/AWS-Skills/eks-deepdive.git\n\nmkdir -p /home/ec2-user/karpenter\nmv /home/ec2-user/eks-deepdive/karpenter /home/ec2-user/\nsed -i 's/export CLUSTER_NAME=\"\"/export CLUSTER_NAME=\"${var.eks_cluster_name}\"/g' /home/ec2-user/karpenter/00_install_karpenter.sh\nsed -i 's/export AWS_REGION=\"\"/export AWS_REGION=\"${data.aws_region.current.region}\"/g' /home/ec2-user/karpenter/00_install_karpenter.sh\nsed -i 's/role: KarpenterNodeRole-/role: KarpenterNodeRole-${var.eks_cluster_name}/g' /home/ec2-user/karpenter/01_nodepool.yaml\nsed -i 's/aws:eks:cluster-name:/aws:eks:cluster-name: ${var.eks_cluster_name}/g' /home/ec2-user/karpenter/01_nodepool.yaml\nchmod +x /home/ec2-user/karpenter/00_install_karpenter.sh\n/home/ec2-user/karpenter/00_install_karpenter.sh\n\nmkdir -p /home/ec2-user/lbc\nmv /home/ec2-user/eks-deepdive/aws-load-balancer-controller/* /home/ec2-user/lbc/\nsed -i 's/export CLUSTER_NAME=\"\"/export CLUSTER_NAME=\"${var.eks_cluster_name}\"/g' /home/ec2-user/lbc/00_install_lbc.sh\nsed -i 's/export AWS_REGION=\"\"/export AWS_REGION=\"${data.aws_region.current.region}\"/g' /home/ec2-user/lbc/00_install_lbc.sh\nchmod +x /home/ec2-user/lbc/00_install_lbc.sh\n/home/ec2-user/lbc/00_install_lbc.sh\n\nmkdir -p /home/ec2-user/argo-rollouts\nmv /home/ec2-user/eks-deepdive/argo-rollouts /home/ec2-user/\nsed -i 's/export AWS_REGION=\"\"/export AWS_REGION=\"${data.aws_region.current.region}\"/g' /home/ec2-user/argo-rollouts/00_install_argorollouts.sh\nchmod +x /home/ec2-user/argo-rollouts/00_install_argorollouts.sh\n/home/ec2-user/argo-rollouts/00_install_argorollouts.sh\n\nCLUSTER_SG=$(aws eks describe-cluster --name ${var.eks_cluster_name} --query \"cluster.resourcesVpcConfig.clusterSecurityGroupId\" --output text)\nTARGETGROUP_ARN=$(aws elbv2 create-target-group --name active-tg --protocol HTTP --port 80 --vpc-id ${aws_vpc.vpc.id} --target-type ip --query 'TargetGroups[0].TargetGroupArn' --output text)\nALB_ARN=$(aws elbv2 create-load-balancer --name alb --subnets ${aws_subnet.private_subnet1.id} ${aws_subnet.private_subnet2.id} --security-groups $CLUSTER_SG --query 'LoadBalancers[0].LoadBalancerArn' --output text)\naws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TARGETGROUP_ARN\nsed -i \"s|ALB_TARGETGROUP_ARN|$TARGETGROUP_ARN|g\" /home/ec2-user/argo-rollouts/01_canary_rollouts.yaml\n\n# kubectl apply -f /home/ec2-user/argo-rollouts/01_canary_rollouts.yaml\n\nEOF\n"])
  }
}
# --- Outputs ---
# CloudFormation output: CloudFrontDomainName
output "cloud_front_domain_name" {
  value = "https://${aws_cloudfront_distribution.cloud_front_distribution.domain_name}"
}
