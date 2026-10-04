# Generated from 123_kubernetes_on_ec2/template.yaml by tools/cfn2tf.
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
  default     = "template"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "kubernetes_ingress_host_name" {
  type        = string
  default     = "example.com"
  description = "Kubernetes Ingress Host"
}
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
  mappings = {
    AzMapping = {
      a = {
        PublicSubnetCidr  = "10.0.0.0/24"
        PrivateSubnetCidr = "10.0.1.0/24"
      }
      c = {
        PublicSubnetCidr  = "10.0.2.0/24"
        PrivateSubnetCidr = "10.0.3.0/24"
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
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/lambda_function/index.py"
  output_path = "${path.module}/build/lambda_function.zip"
}
resource "aws_iam_role_policy_attachment" "lambda_function_iam_role_0" {
  role       = aws_iam_role.lambda_function_iam_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_function_iam_role_1" {
  role       = aws_iam_role.lambda_function_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "control_plane_iam_role_0" {
  role       = aws_iam_role.control_plane_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "control_plane_iam_role_1" {
  role       = aws_iam_role.control_plane_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
resource "aws_iam_role_policy_attachment" "node_iam_role_0" {
  role       = aws_iam_role.node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "node_iam_role_1" {
  role       = aws_iam_role.node_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
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
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
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
resource "aws_s3_bucket" "s3_bucket" {}
resource "aws_lambda_invocation" "empty_s3_bucket" {
  function_name = aws_lambda_function.lambda_function.arn
  input = jsonencode({
    S3Bucket = aws_s3_bucket.s3_bucket.id
  })
}
resource "aws_lambda_function" "lambda_function" {
  runtime          = "python3.14"
  handler          = "index.handler"
  role             = aws_iam_role.lambda_function_iam_role.arn
  timeout          = 900
  memory_size      = 256
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-lambda-function"
}
resource "aws_iam_role" "lambda_function_iam_role" {
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
set -x
dnf update -yq
dnf install -yq git unzip
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

mkdir -p /home/ec2-user/.kube
aws s3 cp s3://${aws_s3_bucket.s3_bucket.id}/kubeconfig /home/ec2-user/.kube/config
aws s3 cp s3://${aws_s3_bucket.s3_bucket.id}/kubeconfig /root/.kube/config

mkdir -p /home/ec2-user/bin
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.35.3/2026-04-08/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl /home/ec2-user/bin/kubectl
export PATH=/home/ec2-user/bin:$PATH
echo "export PATH=/home/ec2-user/bin:$PATH" >> ~/.bashrc
echo "alias k=kubectl" >> ~/.bashrc
echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
echo "source <(kubectl completion bash)" >> ~/.bashrc
exec bash

curl -fsSL -o /home/ec2-user/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 /home/ec2-user/get_helm.sh
/home/ec2-user/get_helm.sh
rm /home/ec2-user/get_helm.sh

helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo update traefik
mkdir -p /home/ec2-user/traefik
echo 'deployment:
  kind: DaemonSet
nodeSelector:
  kubernetes.io/hostname: ${aws_instance.node.private_dns}
  kubernetes.io/os: linux
updateStrategy:
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 0
ports:
  web:
    port: 8000
    hostPort: 80
  websecure:
    port: 8443
    hostPort: 443
securityContext:
  capabilities:
    drop: [ALL]
    add: [NET_BIND_SERVICE]
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
service:
  spec:
    type: ClusterIP' > /home/ec2-user/traefik/values.yaml
helm upgrade --install traefik traefik/traefik --namespace traefik --create-namespace --values /home/ec2-user/traefik/values.yaml --wait --timeout 300s

mkdir -p /home/ec2-user/manifests
echo 'apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  labels:
    app: whoami
spec:
  replicas: 2
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
        - name: whoami
          image: traefik/whoami
          ports:
            - name: http
              containerPort: 80
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
spec:
  selector:
    app: whoami
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: ${var.kubernetes_ingress_host_name}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: whoami
                port:
                  name: http
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: whoami
                port:
                  name: http' > /home/ec2-user/manifests/web.yaml
kubectl apply -f /home/ec2-user/manifests/web.yaml
echo '# Kubernetes on EC2

curl ${var.kubernetes_ingress_host_name}

curl ${var.kubernetes_ingress_host_name}/api' > README.md
EOF

echo '${aws_eip.kubernetes_ingress_ip.public_ip} ${var.kubernetes_ingress_host_name}' >> /etc/hosts

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.kubernetes_default_security_group.id, aws_security_group.vs_code_ec2_security_group.id]
  depends_on                  = [aws_eip_association.kubernetes_ingress_ip_association]
}
resource "aws_security_group" "vs_code_ec2_security_group" {
  description = "Security Group for the VS Code"
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
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "vs_code_ec2_instance_profile" {
  role = jsonencode([aws_iam_role.vs_code_ec2_iam_role.name])
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "control_plane" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t3.medium"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "k8s-controlplane"
  }
  iam_instance_profile        = aws_iam_instance_profile.control_plane_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
set -x

dnf update -yq

swapoff -a
sed -ri '/\sswap\s/s/^/#/' /etc/fstab

cat <<EOF | tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl -p /etc/sysctl.d/99-kubernetes-cri.conf > /dev/null

dnf install -yq containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

K8S_LATEST_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
K8S_MINOR_VERSION=$(echo "$K8S_LATEST_VERSION" | grep -oE '^v[0-9]+\.[0-9]+')
echo "$K8S_LATEST_VERSION - $K8S_MINOR_VERSION"

cat << EOF | tee /etc/yum.repos.d/kubernetes.repo > /dev/null
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$K8S_MINOR_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$K8S_MINOR_VERSION/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf install -yq kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

POD_NETWORK_CIDR="192.168.0.0/16" # Calico Default Pod CIDR

kubeadm init \
--pod-network-cidr="$POD_NETWORK_CIDR" \
--apiserver-advertise-address="$PRIVATE_IP" \
--node-name="$(hostname -f)"

mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

mkdir -p /home/ec2-user/.kube
cp -f /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
chown ec2-user:ec2-user /home/ec2-user/.kube/config

aws s3 cp /root/.kube/config s3://${aws_s3_bucket.s3_bucket.id}/kubeconfig

kubeadm token create --print-join-command > /home/ec2-user/join.sh

aws s3 cp /home/ec2-user/join.sh s3://${aws_s3_bucket.s3_bucket.id}/join.sh

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource ControlPlane --region ${data.aws_region.current.region}

export KUBECONFIG=/root/.kube/config

CALICO_VERSION=$(curl -s https://api.github.com/repos/projectcalico/calico/releases/latest | grep '"tag_name"' | head -n1 | cut -d '"' -f4)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/tigera-operator.yaml --validate=false
kubectl -n tigera-operator wait --for=condition=Available deployment/tigera-operator --timeout=180s
curl -sL -o /tmp/custom-resources.yaml https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/custom-resources.yaml
sed -i "s#cidr: 192.168.0.0/16#cidr: $POD_NETWORK_CIDR#" /tmp/custom-resources.yaml
sleep 30
kubectl create -f /tmp/custom-resources.yaml
kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=180s
EOT
  subnet_id                   = aws_subnet.private_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.kubernetes_default_security_group.id]
}
resource "aws_iam_role" "control_plane_iam_role" {
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
resource "aws_iam_instance_profile" "control_plane_instance_profile" {
  role = jsonencode([aws_iam_role.control_plane_iam_role.name])
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT5M"
# #   }
# # }
resource "aws_instance" "node" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t3.medium"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "k8s-node"
  }
  iam_instance_profile        = aws_iam_instance_profile.node_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
set -x

dnf update -yq

swapoff -a
sed -ri '/\sswap\s/s/^/#/' /etc/fstab

cat <<EOF | tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl -p /etc/sysctl.d/99-kubernetes-cri.conf > /dev/null

dnf install -yq containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

K8S_LATEST_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
K8S_MINOR_VERSION=$(echo "$K8S_LATEST_VERSION" | grep -oE '^v[0-9]+\.[0-9]+')
echo "$K8S_LATEST_VERSION - $K8S_MINOR_VERSION"

cat << EOF | tee /etc/yum.repos.d/kubernetes.repo > /dev/null
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$K8S_MINOR_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$K8S_MINOR_VERSION/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf install -yq kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

aws s3 cp s3://${aws_s3_bucket.s3_bucket.id}/join.sh /home/ec2-user/join.sh
chmod +x /home/ec2-user/join.sh
/home/ec2-user/join.sh

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource Node --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subnetc.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.kubernetes_default_security_group.id, aws_security_group.kubernetes_ingress_security_group.id]
  depends_on                  = [aws_instance.control_plane, aws_vpc_security_group_ingress_rule.kubernetes_default_security_group_ingress]
}
resource "aws_iam_role" "node_iam_role" {
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
resource "aws_iam_instance_profile" "node_instance_profile" {
  role = jsonencode([aws_iam_role.node_iam_role.name])
}
resource "aws_security_group" "kubernetes_default_security_group" {
  description = "Default Security Group for the Kubernetes Cluster"
  name        = "k8s-default-sg"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = "k8s-default-sg"
  }
}
resource "aws_vpc_security_group_ingress_rule" "kubernetes_default_security_group_ingress" {
  security_group_id            = aws_security_group.kubernetes_default_security_group.id
  ip_protocol                  = -1
  referenced_security_group_id = aws_security_group.kubernetes_default_security_group.id
  depends_on                   = [aws_nat_gateway.nat_gateway]
}
resource "aws_security_group" "kubernetes_ingress_security_group" {
  description = "Security Group for the Kubernetes Ingress"
  name        = "k8s-ingress-sg"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "k8s-ingress-sg"
  }
}
resource "aws_eip" "kubernetes_ingress_ip" {}
resource "aws_eip_association" "kubernetes_ingress_ip_association" {
  allocation_id = aws_eip.kubernetes_ingress_ip.allocation_id
  instance_id   = aws_instance.node.id
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
