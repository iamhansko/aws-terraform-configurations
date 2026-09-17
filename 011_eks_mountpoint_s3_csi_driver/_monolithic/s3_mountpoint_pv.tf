# Generated from 011_eks_mountpoint_s3_csi_driver/s3_mountpoint_pv.yaml by tools/cfn2tf.
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
  default     = "s3-mountpoint-pv"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "amazon_linux2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
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
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
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
resource "aws_iam_role_policy_attachment" "mountpoint_s3_csi_driver_iam_role" {
  role       = aws_iam_role.mountpoint_s3_csi_driver_iam_role.name
  policy_arn = aws_iam_policy.amazon_s3_cs_idriver_policy.arn
}
# --- Resources ---
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
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT30M"
# #   }
# # }
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

sudo -Eu ec2-user bash << 'EOF'
cd /home/ec2-user
mkdir -p /home/ec2-user/bin
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl
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

mkdir -p /home/ec2-user/manifests
echo $'apiVersion: v1
kind: PersistentVolume
metadata:
  name: s3-pv
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  claimRef:
    namespace: default
    name: s3-pvc
  mountOptions:
    - allow-delete
    - region ${data.aws_region.current.region}
    - prefix pod/
  csi:
    driver: s3.csi.aws.com
    volumeHandle: s3-csi-driver-volume
    volumeAttributes:
      bucketName: ${aws_s3_bucket.s3_bucket.id}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 20Gi
  volumeName: s3-pv
---
apiVersion: v1
kind: Pod
metadata:
  name: s3-app
spec:
  containers:
    - name: app
      image: ubuntu
      command: ["/bin/sh"]
      args: ["-c", "echo \'Hello from the container!\' >> /data/$(date -u).txt; tail -f /dev/null"]
      volumeMounts:
        - name: persistent-storage
          mountPath: /data
  volumes:
    - name: persistent-storage
      persistentVolumeClaim:
        claimName: s3-pvc' > /home/ec2-user/manifests/pod.yaml
EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id, aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
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
  role = jsonencode([aws_iam_role.bastion_ec2_iam_role.name])
}
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_eks_cluster" "eks_cluster" {
  version = "1.32"
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
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-eks-cluster"
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
resource "aws_eks_access_entry" "bastion_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.bastion_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_eks_addon" "vpc_cni_addon" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "kube_proxy_addon" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "coredns_addon" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_node_group" "managed_node_group" {
  cluster_name   = aws_eks_cluster.eks_cluster.name
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  node_role_arn  = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 2
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.launch_template.id
    version = aws_launch_template.launch_template.latest_version
  }
  node_repair_config {
    enabled = true
  }
}
resource "aws_launch_template" "launch_template" {
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "eks-node"
    }
  }
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
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_addon" "mountpoint_s3_csi_driver_addon" {
  addon_name                  = "aws-mountpoint-s3-csi-driver"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.mountpoint_s3_csi_driver_iam_role.arn
}
resource "aws_iam_role" "mountpoint_s3_csi_driver_iam_role" {
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
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:sub": "system:serviceaccount:kube-system:s3-csi-driver-sa",
                  "${element(split("//", aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer), 1)}:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOT
}
resource "aws_iam_policy" "amazon_s3_cs_idriver_policy" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = ["${aws_s3_bucket.s3_bucket.arn}"]
      }, {
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:DeleteObject"]
      Resource = ["${aws_s3_bucket.s3_bucket.arn}/*"]
    }]
  })
}
resource "aws_s3_bucket" "s3_bucket" {}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.bastion_ec2.public_ip}:8000"
  description = "VsCode on BastionEC2"
}
