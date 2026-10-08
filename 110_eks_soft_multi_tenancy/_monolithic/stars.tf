# Generated from 110_eks_soft_multi_tenancy/stars.yaml by tools/cfn2tf.
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
  default     = "stars"
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
variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "EKS Cluster Kubernetes Version (1.XX)"
  validation {
    condition     = contains(["1.32", "1.33", "1.34", "1.35", "1.36"], var.kubernetes_version)
    error_message = "KubernetesVersion must be one of: 1.32, 1.33, 1.34, 1.35, 1.36"
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
  mappings = {
    AzMapping = {
      a = {
        PublicSubnetCidr  = "10.0.0.0/24"
        PrivateSubnetCidr = "10.0.1.0/24"
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
resource "aws_eks_access_policy_association" "tenant_a_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.tenant_a_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  access_scope {
    type       = "namespace"
    namespaces = ["tenant-a"]
  }
}
resource "aws_eks_access_policy_association" "tenant_b_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.tenant_b_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  access_scope {
    type       = "namespace"
    namespaces = ["tenant-b"]
  }
}
resource "aws_iam_role_policy" "aws_load_balancer_controller_role" {
  name = "AWSLoadBalancerControllerPolicy"
  role = aws_iam_role.aws_load_balancer_controller_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:CreateServiceLinkedRole"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
        }
      }
      }, {
      Effect   = "Allow"
      Action   = ["ec2:*", "elasticloadbalancing:*"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["cognito-idp:DescribeUserPoolClient", "acm:ListCertificates", "acm:DescribeCertificate", "iam:ListServerCertificates", "iam:GetServerCertificate", "waf-regional:GetWebACL", "waf-regional:GetWebACLForResource", "waf-regional:AssociateWebACL", "waf-regional:DisassociateWebACL", "wafv2:GetWebACL", "wafv2:GetWebACLForResource", "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL", "shield:GetSubscriptionState", "shield:DescribeProtection", "shield:CreateProtection", "shield:DeleteProtection"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_eks_access_policy_association" "vs_code_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vs_code_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
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
resource "aws_eks_cluster" "eks_cluster" {
  version = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [aws_subnet.public_subneta.id, aws_subnet.public_subnetc.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "172.20.0.0/16"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-eks-cluster"
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
resource "aws_eks_addon" "vpc_cni_add_on" {
  addon_name           = "vpc-cni"
  cluster_name         = aws_eks_cluster.eks_cluster.name
  configuration_values = "enableNetworkPolicy: \"true\"\n"
}
resource "aws_eks_addon" "kube_proxy_add_on" {
  addon_name   = "kube-proxy"
  cluster_name = aws_eks_cluster.eks_cluster.name
}
resource "aws_eks_addon" "core_dns_add_on" {
  addon_name   = "coredns"
  cluster_name = aws_eks_cluster.eks_cluster.name
}
resource "aws_eks_addon" "pod_identity_agent_addon" {
  addon_name   = "eks-pod-identity-agent"
  cluster_name = aws_eks_cluster.eks_cluster.name
}
resource "aws_eks_node_group" "core_node_group" {
  node_group_name      = "core-nodegroup"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.medium"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.eks_cluster.name
  force_update_version = true
  node_role_arn        = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
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
resource "aws_iam_role" "tenant_a_role" {
  name = "tenant-a-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_eks_access_entry" "tenant_a_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.tenant_a_role.arn
  type          = "STANDARD"
}
resource "aws_iam_role" "tenant_b_role" {
  name = "tenant-b-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_eks_access_entry" "tenant_b_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.tenant_b_role.arn
  type          = "STANDARD"
}
resource "aws_lb" "management_ui_nlb" {
  load_balancer_type = "network"
  security_groups    = [aws_vpc.vpc.default_security_group_id]
  subnets            = [aws_subnet.public_subneta.id, aws_subnet.public_subnetc.id]
  tags = {
    "elbv2.k8s.aws/cluster"    = aws_eks_cluster.eks_cluster.name
    "service.k8s.aws/resource" = "LoadBalancer"
    "service.k8s.aws/stack"    = "management-ui/management-ui"
  }
  internal = false
}
resource "aws_security_group" "nlb_security_group" {
  description = "Security Group"
  name        = "nlb-sg"
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "nlb-sg"
  }
}
resource "aws_iam_role" "aws_load_balancer_controller_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
resource "aws_eks_pod_identity_association" "aws_load_balancer_controller_role_pod_identity_association" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  namespace       = "kube-system"
  role_arn        = aws_iam_role.aws_load_balancer_controller_role.arn
  service_account = "aws-load-balancer-controller"
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
  iam_instance_profile        = aws_iam_instance_profile.vs_code_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf install -yq git
dnf groupinstall -yq "Development Tools"

export VSC_VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | jq -r '.tag_name | ltrimstr("v")')
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
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.3/2025-08-03/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl /home/ec2-user/bin/kubectl
export PATH=/home/ec2-user/bin:$PATH
echo "export PATH=/home/ec2-user/bin:$PATH" >> ~/.bashrc
echo "alias k=kubectl" >> ~/.bashrc
echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
echo "source <(kubectl completion bash)" >> ~/.bashrc
exec bash
aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.eks_cluster.name}

curl -fsSL -o /home/ec2-user/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 /home/ec2-user/get_helm.sh
/home/ec2-user/get_helm.sh
rm /home/ec2-user/get_helm.sh

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
--set clusterName=${aws_eks_cluster.eks_cluster.name} \
--set serviceAccount.name=aws-load-balancer-controller \
--set region=${data.aws_region.current.region} \
--set vpcId=${aws_vpc.vpc.id} \
--wait
sleep 60
EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id, aws_security_group.vs_code_ec2_security_group.id]
  depends_on                  = [aws_eks_node_group.core_node_group]
}
resource "aws_security_group" "vs_code_ec2_security_group" {
  description = "Security Group"
  name        = "vscode-sg"
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
    Name = "vscode-sg"
  }
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
  role = jsonencode([aws_iam_role.vs_code_ec2_iam_role.name])
}
resource "aws_eks_access_entry" "vs_code_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vs_code_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_ssm_association" "ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user && cd $HOME\nmkdir -p /home/ec2-user/manifests\ncd manifests\n\ncat << 'EOF' > namespaces.yaml\napiVersion: v1\nkind: Namespace\nmetadata:\n  name: tenant-a\n  labels:\n    tenant: a\n---\napiVersion: v1\nkind: Namespace\nmetadata:\n  name: tenant-b\n  labels:\n    tenant: b\n---\napiVersion: v1\nkind: Namespace\nmetadata:\n  name: management-ui\n  labels:\n    role: management-ui\nEOF\nkubectl apply -f namespaces.yaml\n\ncat << 'EOF' > quotas.yaml\napiVersion: v1\nkind: ResourceQuota\nmetadata:\n  name: tenant-quota\n  namespace: tenant-a\nspec:\n  hard:\n    pods: \"20\"\n    requests.cpu: \"4\"\n    requests.memory: 4Gi\n    limits.cpu: \"8\"\n    limits.memory: 8Gi\n---\napiVersion: v1\nkind: LimitRange\nmetadata:\n  name: tenant-limitrange\n  namespace: tenant-a\nspec:\n  limits:\n    - type: Container\n      default:\n        cpu: 200m\n        memory: 256Mi\n      defaultRequest:\n        cpu: 100m\n        memory: 128Mi\n---\napiVersion: v1\nkind: ResourceQuota\nmetadata:\n  name: tenant-quota\n  namespace: tenant-b\nspec:\n  hard:\n    pods: \"20\"\n    requests.cpu: \"4\"\n    requests.memory: 4Gi\n    limits.cpu: \"8\"\n    limits.memory: 8Gi\n---\napiVersion: v1\nkind: LimitRange\nmetadata:\n  name: tenant-limitrange\n  namespace: tenant-b\nspec:\n  limits:\n    - type: Container\n      default:\n        cpu: 200m\n        memory: 256Mi\n      defaultRequest:\n        cpu: 100m\n        memory: 128Mi\nEOF\nkubectl apply -f quotas.yaml\n\nfor TENANT in tenant-a tenant-b; do\ncat <<EOF > $${TENANT}-backend.yaml\napiVersion: v1\nkind: Service\nmetadata:\n  name: backend\n  namespace: $${TENANT}\n  labels:\n    role: backend\nspec:\n  ports:\n  - port: 6379\n  selector:\n    role: backend\n---\napiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: backend\n  namespace: $${TENANT}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      role: backend\n  template:\n    metadata:\n      labels:\n        role: backend\n    spec:\n      containers:\n      - name: backend\n        image: calico/star-probe:v0.1.0\n        command:\n        - probe\n        - --http-port=6379\n        - --urls=http://frontend.tenant-a.svc.cluster.local:6379/status,http://frontend.tenant-b.svc.cluster.local:6379/status\n        ports:\n        - containerPort: 6379\nEOF\ncat <<EOF > $${TENANT}-frontend.yaml\napiVersion: v1\nkind: Service\nmetadata:\n  name: frontend\n  namespace: $${TENANT}\n  labels:\n    role: frontend\nspec:\n  ports:\n  - port: 80\n  selector:\n    role: frontend\n---\napiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: frontend\n  namespace: $${TENANT}\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      role: frontend\n  template:\n    metadata:\n      labels:\n        role: frontend\n    spec:\n      containers:\n      - name: frontend\n        image: calico/star-probe:v0.1.0\n        command:\n        - probe\n        - --http-port=80\n        - --urls=http://backend.tenant-a.svc.cluster.local:6379/status,http://backend.tenant-b.svc.cluster.local:6379/status\n        ports:\n        - containerPort: 80\nEOF\nkubectl apply -f $${TENANT}-backend.yaml\nkubectl apply -f $${TENANT}-frontend.yaml\ndone\n\ncat <<EOF > management-ui.yaml\napiVersion: v1\nkind: Service\nmetadata:\n  name: management-ui\n  namespace: management-ui\n  annotations:\n    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing\n    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip\n    service.beta.kubernetes.io/aws-load-balancer-security-groups: ${aws_security_group.nlb_security_group.id}, ${aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id}\nspec:\n  type: LoadBalancer\n  ports:\n  - port: 80\n    targetPort: 9001\n  selector:\n    role: management-ui\n---\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: probes\n  namespace: management-ui\ndata:\n  probes.json: |\n    [\n      {\"id\": \"FA\", \"url\": \"http://frontend.tenant-a.svc.cluster.local:80/status\"},\n      {\"id\": \"BA\", \"url\": \"http://backend.tenant-a.svc.cluster.local:6379/status\"},\n      {\"id\": \"FB\", \"url\": \"http://frontend.tenant-b.svc.cluster.local:80/status\"},\n      {\"id\": \"BB\", \"url\": \"http://backend.tenant-b.svc.cluster.local:6379/status\"}\n    ]\n---\napiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: management-ui\n  namespace: management-ui\nspec:\n  replicas: 1\n  selector:\n    matchLabels:\n      role: management-ui\n  template:\n    metadata:\n      labels:\n        role: management-ui\n    spec:\n      containers:\n      - name: management-ui\n        image: calico/star-collect:v0.1.0\n        imagePullPolicy: Always\n        ports:\n        - containerPort: 9001\n        volumeMounts:\n        - name: probes-json\n          mountPath: /star/probes.json\n          subPath: probes.json\n          readOnly: true\n      volumes:\n      - name: probes-json\n        configMap:\n          name: probes\nEOF\nkubectl apply -f management-ui.yaml\n\nfor TENANT in tenant-a tenant-b; do\necho 'kind: NetworkPolicy\napiVersion: networking.k8s.io/v1\nmetadata:\n  name: default-deny\nspec:\n  podSelector:\n    matchLabels: {}' | kubectl apply -n $${TENANT} -f -\n\necho 'kind: NetworkPolicy\napiVersion: networking.k8s.io/v1\nmetadata:\n  name: allow-ui\nspec:\n  podSelector:\n    matchLabels: {}\n  ingress:\n    - from:\n        - namespaceSelector:\n            matchLabels:\n              role: management-ui' | kubectl apply -n $${TENANT} -f -\n\necho 'kind: NetworkPolicy\napiVersion: networking.k8s.io/v1\nmetadata:\n  name: backend-policy\nspec:\n  podSelector:\n    matchLabels:\n      role: backend\n  ingress:\n    - from:\n        - podSelector:\n            matchLabels:\n              role: frontend\n      ports:\n        - protocol: TCP\n          port: 6379' | kubectl apply -n $${TENANT} -f -\ndone\n\necho \"# EKS Soft Multi-tenancy\n\n## tenant-a frontend -> tenant-a backend (expected: allowed)\nFRONTENT_A=$(kubectl get pod -n tenant-a -l role=frontend -o jsonpath='{.items[*].metadata.name}')\nkubectl exec -n tenant-a $FRONTENT_A -- probe --http-port=81 --urls=http://backend.tenant-a.svc.cluster.local:6379/status\n\n## tenant-a frontend -> tenant-b backend (expected: blocked/timeout)\nFRONTENT_A=$(kubectl get pod -n tenant-a -l role=frontend -o jsonpath='{.items[*].metadata.name}')\nkubectl exec -n tenant-a $FRONTENT_A -- probe --http-port=82 --urls=http://backend.tenant-b.svc.cluster.local:6379/status\n\n## tenant-b frontend -> tenant-b backend (expected: allowed)\nFRONTENT_B=$(kubectl get pod -n tenant-b -l role=frontend -o jsonpath='{.items[*].metadata.name}')\nkubectl exec -n tenant-b $FRONTENT_B -- probe --http-port=81 --urls=http://backend.tenant-b.svc.cluster.local:6379/status\n\n## tenant-b frontend -> tenant-a backend (expected: blocked/timeout)\nFRONTENT_B=$(kubectl get pod -n tenant-b -l role=frontend -o jsonpath='{.items[*].metadata.name}')\nkubectl exec -n tenant-b $FRONTENT_B -- probe --http-port=82 --urls=http://backend.tenant-a.svc.cluster.local:6379/status\n\n## management-ui service\ncurl http://${aws_lb.management_ui_nlb.dns_name}\n\n\" > /home/ec2-user/README.md\nSSMEOF\n"])
  }
  depends_on = [aws_instance.vs_code_ec2]
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
# CloudFormation output: ManagementUiNlb
output "management_ui_nlb" {
  value       = "http://${aws_lb.management_ui_nlb.dns_name}"
  description = "Stars Demo - Management UI NLB DNS Name"
}
