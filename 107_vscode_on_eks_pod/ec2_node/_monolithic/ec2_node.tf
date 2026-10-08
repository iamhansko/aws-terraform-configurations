# Generated from 107_vscode_on_eks_pod/ec2_node.yaml by tools/cfn2tf.
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
  default     = "ec2-node"
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
  default     = "1.34"
  description = "EKS Cluster Kubernetes Version (1.XX)"
  validation {
    condition     = contains(["1.32", "1.33", "1.34"], var.kubernetes_version)
    error_message = "KubernetesVersion must be one of: 1.32, 1.33, 1.34"
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
  default = "4.108.1"
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
resource "aws_eks_access_policy_association" "vs_code_ec2_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vs_code_ec2_iam_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_iam_role_policy_attachment" "eks_cluster_iam_role" {
  role       = aws_iam_role.eks_cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role_policy_attachment" "ebs_csi_driver_addon_iam_role" {
  role       = aws_iam_role.ebs_csi_driver_addon_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
resource "aws_iam_role_policy_attachment" "efs_csi_driver_addon_iam_role" {
  role       = aws_iam_role.efs_csi_driver_addon_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}
resource "aws_iam_role_policy" "mountpoint_s3_csi_driver_iam_role" {
  name = "MountpointS3Policy"
  role = aws_iam_role.mountpoint_s3_csi_driver_iam_role.name
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
resource "aws_s3_bucket_versioning" "s3_bucket_versioning" {
  bucket = aws_s3_bucket.s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "s3_bucket_lifecycle" {
  bucket = aws_s3_bucket.s3_bucket.id
  rule {
    id     = "GlacierRule"
    status = "Enabled"
    filter {
      prefix = "glacier"
    }
    expiration {
      days = 365
    }
    transition {
      days          = 14
      storage_class = "GLACIER"
    }
  }
}
resource "aws_iam_role_policy_attachment" "vs_code_pod_role" {
  role       = aws_iam_role.vs_code_pod_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
resource "aws_eks_access_policy_association" "vs_code_pod_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vs_code_pod_role.arn
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

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

curl -fsSL -o /home/ec2-user/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 /home/ec2-user/get_helm.sh
/home/ec2-user/get_helm.sh
rm /home/ec2-user/get_helm.sh

aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.eks_cluster.name}
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --wait \
--set clusterName=${aws_eks_cluster.eks_cluster.name} \
--set serviceAccount.name=aws-load-balancer-controller \
--set region=${data.aws_region.current.region} \
--set vpcId=${aws_vpc.vpc.id}
sleep 60

mkdir -p /home/ec2-user/manifests

echo 'kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${aws_efs_file_system.efs_file_system.id}
  directoryPerms: "700"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: efs
spec:
  replicas: 2
  selector:
    matchLabels:
      app: efs
  template:
    metadata:
      labels:
        app: efs
    spec:
      containers:
      - name: app
        image: rockylinux:8
        command: ["/bin/sh"]
        args: ["-c", "while true; do echo $(date -u) >> /data/out; sleep 5; done"]
        volumeMounts:
        - name: persistent-storage
          mountPath: /data
      volumes:
      - name: persistent-storage
        persistentVolumeClaim:
          claimName: efs-pvc' > /home/ec2-user/manifests/deployment_efs.yaml
kubectl apply -f /home/ec2-user/manifests/deployment_efs.yaml

echo 'apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  csi.storage.k8s.io/fstype: xfs
  type: io1
  iopsPerGB: "50"
  encrypted: "true"
allowedTopologies:
- matchLabelExpressions:
  - key: topology.kubernetes.io/zone
    values:
    - ${data.aws_region.current.region}a
    - ${data.aws_region.current.region}c
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-sc
  resources:
    requests:
      storage: 4Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ebs
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ebs
  template:
    metadata:
      labels:
        app: ebs
    spec:
      containers:
      - name: app
        image: public.ecr.aws/amazonlinux/amazonlinux
        command: ["/bin/sh"]
        args: ["-c", "while true; do echo $(date -u) >> /data/out.txt; sleep 5; done"]
        volumeMounts:
        - name: persistent-storage
          mountPath: /data
      volumes:
      - name: persistent-storage
        persistentVolumeClaim:
          claimName: ebs-pvc' > /home/ec2-user/manifests/deployment_ebs.yaml
kubectl apply -f /home/ec2-user/manifests/deployment_ebs.yaml

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
    - prefix /
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
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s3
spec:
  replicas: 2
  selector:
    matchLabels:
      app: s3
  template:
    metadata:
      labels:
        app: s3
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
            claimName: s3-pvc' > /home/ec2-user/manifests/deployment_s3.yaml
kubectl apply -f /home/ec2-user/manifests/deployment_s3.yaml

echo 'apiVersion: v1
kind: Pod
metadata:
  name: pod-app
spec:
  containers:
  - name: nginx
    image: nginx' > /home/ec2-user/manifests/pod_app.yaml
kubectl apply -f /home/ec2-user/manifests/pod_app.yaml

echo 'apiVersion: apps/v1
kind: Deployment
metadata:
  name: deployment-app
spec:
  replicas: 4
  selector:
    matchLabels:
      deployment: app
  template:
    metadata:
      labels:
        deployment: app
    spec:
      nodeSelector:
        nodegroup: app
      containers:
      - name: nginx
        image: nginx' > /home/ec2-user/manifests/deployment_app.yaml
kubectl apply -f /home/ec2-user/manifests/deployment_app.yaml

EOF

aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id, aws_security_group.vs_code_ec2_security_group.id]
  depends_on                  = [aws_eks_node_group.app_node_group, aws_eks_addon.ebs_csi_driver_addon, aws_eks_addon.efs_csi_driver_addon, aws_eks_addon.mountpoint_s3_csi_driver_addon]
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
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_addon" "vpc_cni_add_on" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "kube_proxy_add_on" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "core_dns_add_on" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "pod_identity_agent_addon" {
  addon_name                  = "eks-pod-identity-agent"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "ebs_csi_driver_addon" {
  addon_name                  = "aws-ebs-csi-driver"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi_driver_addon_iam_role.arn
    service_account = "ebs-csi-controller-sa"
  }
}
resource "aws_iam_role" "ebs_csi_driver_addon_iam_role" {
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
resource "aws_eks_addon" "efs_csi_driver_addon" {
  addon_name                  = "aws-efs-csi-driver"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi_driver_addon_iam_role.arn
    service_account = "efs-csi-controller-sa"
  }
}
resource "aws_iam_role" "efs_csi_driver_addon_iam_role" {
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
resource "aws_eks_addon" "mountpoint_s3_csi_driver_addon" {
  addon_name                  = "aws-mountpoint-s3-csi-driver"
  cluster_name                = aws_eks_cluster.eks_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  pod_identity_association {
    role_arn        = aws_iam_role.mountpoint_s3_csi_driver_iam_role.arn
    service_account = "s3-csi-driver-sa"
  }
}
resource "aws_iam_role" "mountpoint_s3_csi_driver_iam_role" {
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
resource "aws_eks_node_group" "app_node_group" {
  node_group_name      = "app-mng"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.xlarge"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.eks_cluster.name
  force_update_version = true
  labels = {
    nodegroup = "app"
  }
  node_role_arn = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
  launch_template {
    id      = aws_launch_template.app_launch_template.id
    version = aws_launch_template.app_launch_template.latest_version
  }
}
resource "aws_launch_template" "app_launch_template" {
  name     = "app-nodegroup-launchtemplate"
  key_name = aws_key_pair.key_pair.key_name
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "app-mng"
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
resource "aws_efs_file_system" "efs_file_system" {
  performance_mode = "generalPurpose"
}
resource "aws_efs_mount_target" "fargate_efs_mount_target_private_subneta" {
  file_system_id  = aws_efs_file_system.efs_file_system.id
  security_groups = [aws_security_group.efs_security_group.id]
  subnet_id       = aws_subnet.private_subneta.id
}
resource "aws_efs_mount_target" "fargate_efs_mount_target_private_subnetc" {
  file_system_id  = aws_efs_file_system.efs_file_system.id
  security_groups = [aws_security_group.efs_security_group.id]
  subnet_id       = aws_subnet.private_subnetc.id
}
resource "aws_security_group" "efs_security_group" {
  description = "Security Group"
  name        = "efs-sg"
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "efs-sg"
  }
}
resource "aws_s3_bucket" "s3_bucket" {}
resource "aws_ssm_association" "vs_code_pod" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 3600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    commands = join("\n", ["sleep 180\n\nsu - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user\ncd $HOME\n\necho 'apiVersion: apps/v1\nkind: StatefulSet\nmetadata:\n  name: vscode\nspec:\n  selector:\n    matchLabels:\n      statefulset: vscode\n  replicas: 1\n  template:\n    metadata:\n      labels:\n        statefulset: vscode\n    spec:\n      serviceAccountName: vscode\n      containers:\n      - name: code-server\n        image: codercom/code-server:4.108.2-39\n        ports:\n        - containerPort: 8080\n          name: vscode\n        resources:\n          requests:\n            cpu: 3\n            memory: 12Gi\n        volumeMounts:\n        - name: config\n          mountPath: \"/home/coder/.config/code-server\"\n          readOnly: true\n      volumes:\n        - name: config\n          configMap:\n            name: vscode\n            items:\n              - key: config.yaml\n                path: config.yaml\n---\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: vscode\ndata:\n  config.yaml: |\n    auth: none\n    cert: false\n---\napiVersion: v1\nkind: ServiceAccount\nmetadata:\n  name: vscode\n---\napiVersion: v1\nkind: Service\nmetadata:\n  name: vscode\n  labels:\n    statefulset: vscode\nspec:\n  ports:\n  - port: 8080\n    name: vscode\n  selector:\n    statefulset: vscode\n---\napiVersion: networking.k8s.io/v1\nkind: Ingress\nmetadata:\n  name: vscode\n  annotations:\n    alb.ingress.kubernetes.io/scheme: internet-facing\n    alb.ingress.kubernetes.io/target-type: ip\n    alb.ingress.kubernetes.io/security-groups: ${aws_security_group.alb_security_group.id}\n    alb.ingress.kubernetes.io/manage-backend-security-group-rules: \"true\"\nspec:\n  ingressClassName: alb\n  rules:\n  - http:\n      paths:\n      - path: /\n        pathType: Prefix\n        backend:\n          service:\n            name: vscode\n            port:\n              number: 8080' > /home/ec2-user/manifests/vscode.yaml\n\nkubectl apply -f /home/ec2-user/manifests/vscode.yaml\nkubectl rollout status statefulset vscode\nsleep 30\nkubectl exec -i vscode-0 -- sh << EOF\necho '#!/bin/bash\nsudo dnf update -yq\nsudo dnf groupinstall -yq \"Development Tools\"\nsudo dnf install -yq openssl\ncurl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\"\nunzip awscliv2.zip\nsudo ./aws/install\nsudo yum install -yq yum-utils shadow-utils\nsudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo\nsudo yum install -yq terraform\ncurl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.34.2/2025-11-13/bin/linux/amd64/kubectl\nchmod +x /home/coder/kubectl\nmkdir -p /home/coder/bin\ncp /home/coder/kubectl /home/coder/bin/kubectl\nexport PATH=/home/coder/bin:$PATH\necho 'export PATH=/home/coder/bin:$PATH' >> ~/.bashrc\necho \"alias k=kubectl\" >> ~/.bashrc\necho \"complete -o default -F __start_kubectl k\" >> ~/.bashrc\necho \"source <(kubectl completion bash)\" >> ~/.bashrc\ncurl --silent --location \"https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz\" | tar xz -C /tmp\nsudo mv /tmp/eksctl /usr/local/bin\ncurl -fsSL -o /home/coder/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4\nchmod 700 /home/coder/get_helm.sh\n/home/coder/get_helm.sh\nrm /home/coder/get_helm.sh\naws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.eks_cluster.name}' > init.sh\nEOF\nsleep 10\nkubectl exec vscode-0 -- sh -c \"chmod +x /home/coder/init.sh\"\nsleep 10\nkubectl exec vscode-0 -- sh -c \"/home/coder/init.sh\"\n\ncat << 'EOF' > /home/ec2-user/README.md\n# VSCode on Pod\nEOF\n\nSSMEOF\n"])
  }
  depends_on = [aws_instance.vs_code_ec2]
}
resource "aws_iam_role" "vs_code_pod_role" {
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
resource "aws_eks_pod_identity_association" "vs_code_pod_role_pod_identity_association" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  namespace       = "default"
  role_arn        = aws_iam_role.vs_code_pod_role.arn
  service_account = "vscode"
}
resource "aws_eks_access_entry" "vs_code_pod_iam_access_entry" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = aws_iam_role.vs_code_pod_role.arn
  type          = "STANDARD"
}
resource "aws_lb" "alb" {
  name               = "vscode"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subneta.id, aws_subnet.public_subnetc.id]
  security_groups    = [aws_vpc.vpc.default_security_group_id]
  tags = {
    "elbv2.k8s.aws/cluster"    = aws_eks_cluster.eks_cluster.name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = "default/vscode"
  }
  internal = false
}
resource "aws_lb_listener" "alb_listener" {
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn
  }
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
}
resource "aws_lb_target_group" "alb_target_group" {
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    "elbv2.k8s.aws/cluster"    = aws_eks_cluster.eks_cluster.name
    "ingress.k8s.aws/resource" = "default/vscode-vscode:8080"
    "ingress.k8s.aws/stack"    = "default/vscode"
  }
  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = 8080
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    enabled             = true
    matcher             = "200-399"
  }
}
resource "aws_security_group" "alb_security_group" {
  description = "Security Group"
  name        = "alb-sg"
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
    Name = "alb-sg"
  }
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
