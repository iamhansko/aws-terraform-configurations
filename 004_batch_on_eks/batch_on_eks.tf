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
  default     = "batch-on-eks"
  description = "Resource Name Prefix"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

variable "amazon_linux2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}

data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}

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
}

resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
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

resource "aws_iam_role_policy_attachment" "eks_cluster_iam_role" {
  role       = aws_iam_role.eks_cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_access_policy_association" "bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_iam_role" {
  role       = aws_iam_role.fargate_pod_execution_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_iam_role" {
  role       = aws_iam_role.karpenter_controller_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role_0" {
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role_1" {
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role_2" {
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role_3" {
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "batch_node_iam_role_0" {
  role       = aws_iam_role.batch_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "batch_node_iam_role_1" {
  role       = aws_iam_role.batch_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "batch_node_iam_role_2" {
  role       = aws_iam_role.batch_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "batch_node_iam_role_3" {
  role       = aws_iam_role.batch_node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc"
  }
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

resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "public-rt"
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
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

resource "aws_subnet" "public_subnetb" {
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = local.mappings["AzMapping"]["b"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-b"
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table_association" "public_subnetb_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnetb.id
}

resource "aws_subnet" "private_subneta" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["a"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "private-subnet-a"
  }
}

resource "aws_route_table" "private_subneta_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "private-rt-a"
  }
}

resource "aws_eip" "natgatewaya_elastic_ip" {}

resource "aws_nat_gateway" "nat_gatewaya" {
  allocation_id = aws_eip.natgatewaya_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subneta.id
  tags = {
    Name = "natgw-a"
  }
}

resource "aws_route_table_association" "private_subneta_route_table_association" {
  route_table_id = aws_route_table.private_subneta_route_table.id
  subnet_id      = aws_subnet.private_subneta.id
}

resource "aws_route" "private_subneta_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gatewaya.id
  route_table_id         = aws_route_table.private_subneta_route_table.id
}

resource "aws_subnet" "private_subnetb" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["b"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}b"
  tags = {
    Name = "private-subnet-b"
  }
}

resource "aws_route_table" "private_subnetb_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "private-rt-b"
  }
}

resource "aws_eip" "natgatewayb_elastic_ip" {}

resource "aws_nat_gateway" "nat_gatewayb" {
  allocation_id = aws_eip.natgatewayb_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnetb.id
  tags = {
    Name = "natgw-b"
  }
}

resource "aws_route_table_association" "private_subnetb_route_table_association" {
  route_table_id = aws_route_table.private_subnetb_route_table.id
  subnet_id      = aws_subnet.private_subnetb.id
}

resource "aws_route" "private_subnetb_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gatewayb.id
  route_table_id         = aws_route_table.private_subnetb_route_table.id
}

resource "aws_instance" "bastion_ec2" {
  instance_type        = "t3.medium"
  key_name             = aws_key_pair.key_pair.key_name
  ami                  = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  iam_instance_profile = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  tags = {
    Name = "bastion"
  }
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf groupinstall -yq "Development Tools"
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
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
}

resource "time_sleep" "wait_bastion_ec2" {
  depends_on = [aws_instance.bastion_ec2]
  create_duration = "300s"
}

resource "aws_security_group" "bastion_ec2_security_group" {
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
}

resource "aws_iam_role" "bastion_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  role = aws_iam_role.bastion_ec2_iam_role.name
}

resource "aws_key_pair" "key_pair" {
  key_name   = "${var.prefix}-key"
  public_key = tls_private_key.key_pair.public_key_openssh
}

resource "aws_eks_cluster" "eks_cluster" {
  version = "1.36"
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  }
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  upgrade_policy {
    support_type = "STANDARD"
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  name = "${var.prefix}-eks-cluster"
}
resource "aws_iam_role" "eks_cluster_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_eks_access_entry" "bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ec2_security_group_ingress" {
  security_group_id            = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  ip_protocol                  = -1
  referenced_security_group_id = aws_security_group.bastion_ec2_security_group.id
}

resource "aws_eks_fargate_profile" "kubesystem_fargate_profile" {
  cluster_name           = aws_eks_cluster.eks_cluster.name
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_iam_role.arn
  subnet_ids             = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  selector {
    namespace = "kube-system"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  fargate_profile_name = "${var.prefix}-kubesystem-fargate-profile"
}

resource "aws_iam_role" "fargate_pod_execution_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:fargateprofile/${aws_eks_cluster.eks_cluster.name}/*"
        }
      }
    }]
  })
}

resource "aws_ssm_association" "karpenter_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = <<EOT
dnf install -yq git
dnf install -yq docker
dnf install -yq bash-completion
systemctl enable --now docker
# usermod -aG docker ec2-user
# newgrp docker
chmod 666 /var/run/docker.sock

su - ec2-user << 'EOF'
export HOME=/home/ec2-user
cd $HOME
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.36.2/2026-07-05/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc

ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

aws eks update-kubeconfig --name ${aws_eks_cluster.eks_cluster.name}

echo $'#!/bin/bash
export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.14.0"
export K8S_VERSION="1.36"
export AWS_PARTITION="aws"
export CLUSTER_NAME="${aws_eks_cluster.eks_cluster.name}"
export AWS_DEFAULT_REGION="${data.aws_region.current.region}"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TEMPOUT="$(mktemp)"
helm registry logout public.ecr.aws
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
--version "$KARPENTER_VERSION" \
--namespace "$KARPENTER_NAMESPACE" --create-namespace \
--set "settings.clusterName=$CLUSTER_NAME" \
--set controller.resources.requests.cpu=1 \
--set controller.resources.requests.memory=1Gi \
--set controller.resources.limits.cpu=1 \
--set controller.resources.limits.memory=1Gi \
--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${aws_iam_role.karpenter_controller_iam_role.arn}" \
--wait' > install_karpenter.sh
chmod +x install_karpenter.sh

sleep 10
kubectl -n kube-system rollout restart deployment coredns
EOF
EOT
  }
  depends_on = [aws_eks_fargate_profile.kubesystem_fargate_profile]
}

resource "aws_iam_role" "karpenter_controller_iam_role" {
  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "${aws_iam_openid_connect_provider.eks_oidc_provider.arn}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringEquals": {
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:karpenter",
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}

resource "aws_iam_role" "karpenter_node_iam_role" {
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

resource "aws_eks_access_entry" "karpenter_node_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}

resource "aws_ssm_association" "batch_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  depends_on = [aws_ssm_association.karpenter_association]
  parameters = {
    commands = <<EOT
su - ec2-user << 'SSMEOF'
set -euo pipefail
export DEFAULT_NAMESPACE=batch-default
export CUSTOM_NAMESPACE=batch-app
cat - <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $DEFAULT_NAMESPACE
  labels:
    name: $DEFAULT_NAMESPACE
---
apiVersion: v1
kind: Namespace
metadata:
  name: $CUSTOM_NAMESPACE
  labels:
    name: $CUSTOM_NAMESPACE
EOF
cat - <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: aws-batch-cluster-role
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["daemonsets", "deployments", "statefulsets", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["clusterroles", "clusterrolebindings"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: aws-batch-cluster-role-binding
subjects:
- kind: User
  name: aws-batch
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: aws-batch-cluster-role
  apiGroup: rbac.authorization.k8s.io
EOF

cat - <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: aws-batch-compute-environment-role
  namespace: $DEFAULT_NAMESPACE
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "get", "list", "watch", "delete", "patch"]
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["get", "list"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: aws-batch-compute-environment-role-binding
  namespace: $DEFAULT_NAMESPACE
subjects:
- kind: User
  name: aws-batch
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: aws-batch-compute-environment-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: aws-batch-compute-environment-role
  namespace: $CUSTOM_NAMESPACE
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "get", "list", "watch", "delete", "patch"]
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["get", "list"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: aws-batch-compute-environment-role-binding
  namespace: $CUSTOM_NAMESPACE
subjects:
- kind: User
  name: aws-batch
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: aws-batch-compute-environment-role
  apiGroup: rbac.authorization.k8s.io
EOF

eksctl create iamidentitymapping --region ${data.aws_region.current.region} \
--cluster ${aws_eks_cluster.eks_cluster.name} \
--arn "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSServiceRoleForBatch" \
--username aws-batch

# aws-auth ConfigMap changes take time to propagate to the EKS control plane's
# authenticator. Poll until the aws-batch identity can actually authorize against
# the namespace before reporting success, otherwise AWS Batch's CreateComputeEnvironment
# call can race ahead and fail with "Unable to validate Kubernetes Namespace".
rbac_ready=false
for i in $(seq 1 30); do
  if kubectl auth can-i get namespace/$DEFAULT_NAMESPACE --as=aws-batch >/dev/null 2>&1; then
    echo "aws-batch identity has access to $DEFAULT_NAMESPACE"
    rbac_ready=true
    break
  fi
  echo "Waiting for aws-auth RBAC mapping to propagate... ($i/30)"
  sleep 10
done
if [ "$rbac_ready" != "true" ]; then
  echo "aws-batch identity still lacks access to $DEFAULT_NAMESPACE after 5 minutes" >&2
  exit 1
fi
SSMEOF
EOT
  }
}

resource "aws_batch_compute_environment" "batch_compute_environment" {
  state = "ENABLED"
  eks_configuration {
    eks_cluster_arn      = aws_eks_cluster.eks_cluster.arn
    kubernetes_namespace = "batch-default"
  }
  compute_resources {
    subnets             = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_group_ids  = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
    min_vcpus           = 0
    max_vcpus           = 256
    type                = "EC2"
    allocation_strategy = "BEST_FIT_PROGRESSIVE"
    ec2_key_pair        = aws_key_pair.key_pair.key_name
    instance_role       = aws_iam_instance_profile.batch_node_instance_profile.arn
    instance_type       = ["optimal"]
    tags = {
      Name = "batch-node"
    }
  }
  update_policy {
    job_execution_timeout_minutes = 30
    terminate_jobs_on_update      = false
  }
  type       = "MANAGED"
  depends_on = [aws_ssm_association.batch_association]
}

resource "aws_iam_instance_profile" "batch_node_instance_profile" {
  role = aws_iam_role.batch_node_iam_role.name
}

resource "aws_iam_role" "batch_node_iam_role" {
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

resource "aws_eks_access_entry" "batch_node_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.batch_node_iam_role.arn
  type          = "EC2_LINUX"
}

resource "aws_batch_job_definition" "batch_job_definition" {
  type = "container"
  eks_properties {
    pod_properties {
      containers {
        name    = "sleep30s"
        image   = "public.ecr.aws/amazonlinux/amazonlinux:latest"
        command = ["sleep", "30"]
        resources {
          limits = {
            cpu    = "0.5"
            memory = "512Mi"
          }
          requests = {
            cpu    = "0.5"
            memory = "512Mi"
          }
        }
      }
    }
  }
  platform_capabilities = ["EC2"]
  timeout {
    attempt_duration_seconds = 120
  }
  name = "${var.prefix}-batch-job-definition"
}

resource "aws_batch_job_queue" "batch_job_queue" {
  state    = "ENABLED"
  priority = 1
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.batch_compute_environment.arn
  }
  name = "${var.prefix}-batch-job-queue"
}

output "vs_code" {
  value       = "http://${aws_instance.bastion_ec2.public_ip}:8000"
  description = "VsCode on BastionEC2"
}