# Generated from 105_eks_backup/karpenter_nodegroup.yaml by tools/cfn2tf.
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
  default     = "karpenter-nodegroup"
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
  cluster_name  = aws_eks_cluster.primary_cluster.name
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
resource "aws_iam_role_policy_attachment" "karpenter_controller_iam_role" {
  role       = aws_iam_role.karpenter_controller_iam_role.name
  policy_arn = aws_iam_policy.karpenter_controller_policy.arn
}
resource "aws_cloudwatch_event_target" "scheduled_change_rule" {
  rule      = aws_cloudwatch_event_rule.scheduled_change_rule.name
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
  target_id = "KarpenterInterruptionQueueTarget"
}
resource "aws_cloudwatch_event_target" "spot_interruption_rule" {
  rule      = aws_cloudwatch_event_rule.spot_interruption_rule.name
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
  target_id = "KarpenterInterruptionQueueTarget"
}
resource "aws_cloudwatch_event_target" "rebalance_rule" {
  rule      = aws_cloudwatch_event_rule.rebalance_rule.name
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
  target_id = "KarpenterInterruptionQueueTarget"
}
resource "aws_cloudwatch_event_target" "instance_state_change_rule" {
  rule      = aws_cloudwatch_event_rule.instance_state_change_rule.name
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
  target_id = "KarpenterInterruptionQueueTarget"
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
resource "aws_backup_vault_notifications" "eks_backup_vault" {
  backup_vault_name   = aws_backup_vault.eks_backup_vault.name
  sns_topic_arn       = aws_sns_topic.eks_sns_topic.arn
  backup_vault_events = ["EKS_RESTORE_OBJECT_FAILED", "EKS_RESTORE_OBJECT_SKIPPED"]
}
resource "aws_sns_topic_subscription" "eks_sns_topic" {
  topic_arn = aws_sns_topic.eks_sns_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.eks_queue.arn
}
resource "aws_iam_role_policy_attachment" "eks_backup_iam_role_0" {
  role       = aws_iam_role.eks_backup_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
resource "aws_iam_role_policy_attachment" "eks_backup_iam_role_1" {
  role       = aws_iam_role.eks_backup_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}
resource "aws_iam_role_policy_attachment" "eks_backup_iam_role_2" {
  role       = aws_iam_role.eks_backup_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}
resource "aws_iam_role_policy_attachment" "eks_backup_iam_role_3" {
  role       = aws_iam_role.eks_backup_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
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

aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.primary_cluster.name}
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --wait \
--set clusterName=${aws_eks_cluster.primary_cluster.name} \
--set serviceAccount.name=aws-load-balancer-controller \
--set region=${data.aws_region.current.region} \
--set vpcId=${aws_vpc.vpc.id} \
--set tolerations[0].key=nodegroup \
--set tolerations[0].value=addon \
--set tolerations[0].operator=Equal \
--set tolerations[0].effect=NoSchedule \
--set nodeSelector.nodegroup=addon
sleep 60

helm registry logout public.ecr.aws
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version 1.8.6 --namespace kube-system \
--set settings.clusterName=${aws_eks_cluster.primary_cluster.name} \
--set controller.resources.requests.cpu=1 \
--set controller.resources.requests.memory=1Gi \
--set controller.resources.limits.cpu=1 \
--set controller.resources.limits.memory=1Gi \
--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${aws_iam_role.karpenter_controller_iam_role.arn}" \
--set controller.resources.limits.memory=1Gi \
--set nodeSelector.nodegroup=addon \
--set tolerations[0].key=CriticalAddonsOnly \
--set tolerations[0].operator=Exists \
--set tolerations[1].effect=NoSchedule \
--set tolerations[1].key=nodegroup \
--set tolerations[1].operator=Equal \
--set tolerations[1].value=addon \
--wait

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
  name: pod-ec2
spec:
  containers:
  - name: nginx
    image: nginx' > /home/ec2-user/manifests/pod_ec2.yaml
kubectl apply -f /home/ec2-user/manifests/pod_ec2.yaml

echo 'apiVersion: apps/v1
kind: Deployment
metadata:
  name: deployment-ec2
spec:
  replicas: 4
  selector:
    matchLabels:
      deployment: ec2
  template:
    metadata:
      labels:
        deployment: ec2
    spec:
      containers:
      - name: nginx
        image: nginx' > /home/ec2-user/manifests/deployment_ec2.yaml
kubectl apply -f /home/ec2-user/manifests/deployment_ec2.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.0/docs/examples/2048/2048_full.yaml

echo 'apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: ${aws_iam_role.eks_node_iam_role.name}
  amiSelectorTerms:
    - alias: al2023@latest
  subnetSelectorTerms:
    - tags:
        Name: "private-subnet-*"
  securityGroupSelectorTerms:
    - tags:
        aws:eks:cluster-name: "*Cluster-*"
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t", "m", "c"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 10m' > /home/ec2-user/manifests/nodepool_default.yaml
kubectl apply -f /home/ec2-user/manifests/nodepool_default.yaml

EOF

aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_eks_cluster.primary_cluster.vpc_config[0].cluster_security_group_id, aws_eks_cluster.secondary_cluster.vpc_config[0].cluster_security_group_id, aws_security_group.vs_code_ec2_security_group.id]
  depends_on                  = [aws_eks_node_group.add_on_node_group, aws_eks_pod_identity_association.aws_load_balancer_controller_role_pod_identity_association, aws_eks_pod_identity_association.karpenter_controller_iam_role_pod_identity_association]
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
  cluster_name  = aws_eks_cluster.primary_cluster.name
  principal_arn = aws_iam_role.vs_code_ec2_iam_role.arn
  type          = "STANDARD"
}
resource "aws_eks_cluster" "primary_cluster" {
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
  name = "${var.stack_name}-primary-cluster"
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
resource "aws_iam_openid_connect_provider" "primary_cluster_oidc_provider" {
  url            = aws_eks_cluster.primary_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_eks_addon" "vpc_cni_add_on" {
  addon_name                  = "vpc-cni"
  cluster_name                = aws_eks_cluster.primary_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "kube_proxy_add_on" {
  addon_name                  = "kube-proxy"
  cluster_name                = aws_eks_cluster.primary_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "core_dns_add_on" {
  addon_name                  = "coredns"
  cluster_name                = aws_eks_cluster.primary_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values        = "nodeSelector:\n  nodegroup: addon\ntolerations:\n  - effect: NoSchedule\n    key: nodegroup\n    operator: Equal\n    value: addon\n"
}
resource "aws_eks_addon" "pod_identity_agent_addon" {
  addon_name                  = "eks-pod-identity-agent"
  cluster_name                = aws_eks_cluster.primary_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
}
resource "aws_eks_addon" "ebs_csi_driver_addon" {
  addon_name                  = "aws-ebs-csi-driver"
  cluster_name                = aws_eks_cluster.primary_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values        = "controller:\n  nodeSelector:\n    nodegroup: addon\n  tolerations:\n    - effect: NoSchedule\n      key: nodegroup\n      operator: Equal\n      value: addon\n"
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
  cluster_name                = aws_eks_cluster.primary_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values        = "controller:\n  nodeSelector:\n    nodegroup: addon\n  tolerations:\n    - effect: NoSchedule\n      key: nodegroup\n      operator: Equal\n      value: addon\n"
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
  cluster_name                = aws_eks_cluster.primary_cluster.name
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values        = "controller:\n  nodeSelector:\n    nodegroup: addon\n  tolerations:\n    - effect: NoSchedule\n      key: nodegroup\n      operator: Equal\n      value: addon\n"
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
  cluster_name    = aws_eks_cluster.primary_cluster.name
  namespace       = "kube-system"
  role_arn        = aws_iam_role.aws_load_balancer_controller_role.arn
  service_account = "aws-load-balancer-controller"
}
resource "aws_iam_role" "karpenter_controller_iam_role" {
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
resource "aws_iam_policy" "karpenter_controller_policy" {
  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowScopedEC2InstanceAccessActions",
      "Effect": "Allow",
      "Resource": [
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}::image/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}::snapshot/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:security-group/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:subnet/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:capacity-reservation/*"
      ],
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet"
      ]
    },
    {
      "Sid": "AllowScopedEC2LaunchTemplateAccessActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedEC2InstanceActionsWithTags",
      "Effect": "Allow",
      "Resource": [
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:fleet/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:volume/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:network-interface/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:spot-instances-request/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:capacity-reservation/*"
      ],
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet",
        "ec2:CreateLaunchTemplate"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedResourceCreationTagging",
      "Effect": "Allow",
      "Resource": [
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:fleet/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:volume/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:network-interface/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:spot-instances-request/*"
      ],
      "Action": "ec2:CreateTags",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedResourceTagging",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
      "Action": "ec2:CreateTags",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/karpenter.sh/nodepool": "*"
        },
        "ForAllValues:StringEquals": {
          "aws:TagKeys": [
            "eks:eks-cluster-name",
            "karpenter.sh/nodeclaim",
            "Name"
          ]
        }
      }
    },
    {
      "Sid": "AllowScopedDeletion",
      "Effect": "Allow",
      "Resource": [
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*"
      ],
      "Action": [
        "ec2:TerminateInstances",
        "ec2:DeleteLaunchTemplate"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowRegionalReadActions",
      "Effect": "Allow",
      "Resource": "*",
      "Action": [
        "ec2:DescribeCapacityReservations",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${data.aws_region.current.region}"
        }
      }
    },
    {
      "Sid": "AllowSSMReadActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}::parameter/aws/service/*",
      "Action": "ssm:GetParameter"
    },
    {
      "Sid": "AllowPricingReadActions",
      "Effect": "Allow",
      "Resource": "*",
      "Action": "pricing:GetProducts"
    },
    {
      "Sid": "AllowInterruptionQueueActions",
      "Effect": "Allow",
      "Resource": "${aws_sqs_queue.karpenter_interruption_queue.arn}",
      "Action": [
        "sqs:DeleteMessage",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage"
      ]
    },
    {
      "Sid": "AllowPassingInstanceRole",
      "Effect": "Allow",
      "Resource": "${aws_iam_role.eks_node_iam_role.arn}",
      "Action": "iam:PassRole",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "ec2.amazonaws.com",
            "ec2.amazonaws.com.cn"
          ]
        }
      }
    },
    {
      "Sid": "AllowScopedInstanceProfileCreationActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
      "Action": [
        "iam:CreateInstanceProfile"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/topology.kubernetes.io/region": "${data.aws_region.current.region}"
        },
        "StringLike": {
          "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedInstanceProfileTagActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
      "Action": [
        "iam:TagInstanceProfile"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/topology.kubernetes.io/region": "${data.aws_region.current.region}",
          "aws:RequestTag/topology.kubernetes.io/region": "${data.aws_region.current.region}"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*",
          "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedInstanceProfileActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
      "Action": [
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:DeleteInstanceProfile"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/topology.kubernetes.io/region": "${data.aws_region.current.region}"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*"
        }
      }
    },
    {
      "Sid": "AllowInstanceProfileReadActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
      "Action": "iam:GetInstanceProfile"
    },
    {
      "Sid": "AllowUnscopedInstanceProfileListAction",
      "Effect": "Allow",
      "Resource": "*",
      "Action": "iam:ListInstanceProfiles"
    },
    {
      "Sid": "AllowAPIServerEndpointDiscovery",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/*",
      "Action": "eks:DescribeCluster"
    }
  ]
}
EOT
}
resource "aws_eks_pod_identity_association" "karpenter_controller_iam_role_pod_identity_association" {
  cluster_name    = aws_eks_cluster.primary_cluster.name
  namespace       = "kube-system"
  role_arn        = aws_iam_role.karpenter_controller_iam_role.arn
  service_account = "karpenter"
}
resource "aws_sqs_queue" "karpenter_interruption_queue" {
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue_policy" "karpenter_interruption_queue_policy" {
  queue_url = jsonencode([aws_sqs_queue.karpenter_interruption_queue.id])
  policy = jsonencode({
    Id = "EC2InterruptionPolicy"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com", "sqs.amazonaws.com"]
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.karpenter_interruption_queue.arn
      }, {
      Sid      = "DenyHTTP"
      Effect   = "Deny"
      Action   = "sqs:*"
      Resource = aws_sqs_queue.karpenter_interruption_queue.arn
      Condition = {
        Bool = {
          "aws:SecureTransport" = false
        }
      }
      Principal = "*"
    }]
  })
}
resource "aws_cloudwatch_event_rule" "scheduled_change_rule" {
  event_pattern = jsonencode({
    source        = ["aws.health"]
    "detail-type" = ["AWS Health Event"]
  })
}
resource "aws_cloudwatch_event_rule" "spot_interruption_rule" {
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Spot Instance Interruption Warning"]
  })
}
resource "aws_cloudwatch_event_rule" "rebalance_rule" {
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance Rebalance Recommendation"]
  })
}
resource "aws_cloudwatch_event_rule" "instance_state_change_rule" {
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
  })
}
resource "aws_eks_node_group" "add_on_node_group" {
  node_group_name      = "addon-mng"
  ami_type             = "AL2023_x86_64_STANDARD"
  instance_types       = ["t3.large"]
  capacity_type        = "ON_DEMAND"
  cluster_name         = aws_eks_cluster.primary_cluster.name
  force_update_version = true
  labels = {
    nodegroup = "addon"
  }
  taint {
    effect = "NO_SCHEDULE"
    key    = "nodegroup"
    value  = "addon"
  }
  node_role_arn = aws_iam_role.eks_node_iam_role.arn
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  subnet_ids = [aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
  launch_template {
    id      = aws_launch_template.add_on_launch_template.id
    version = aws_launch_template.add_on_launch_template.latest_version
  }
}
resource "aws_launch_template" "add_on_launch_template" {
  name     = "addon-nodegroup-launchtemplate"
  key_name = aws_key_pair.key_pair.key_name
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "addon-mng"
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
resource "aws_backup_vault" "eks_backup_vault" {
  name = "eks"
}
resource "aws_sns_topic" "eks_sns_topic" {}
resource "aws_sqs_queue" "eks_queue" {
  message_retention_seconds = 3600
}
resource "aws_iam_role" "eks_backup_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["backup.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_eks_cluster" "secondary_cluster" {
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
  name = "${var.stack_name}-secondary-cluster"
}
resource "aws_iam_openid_connect_provider" "secondary_cluster_oidc_provider" {
  url            = aws_eks_cluster.secondary_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_ssm_association" "ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    commands = join("\n", ["sleep 180\n\nsu - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user\ncd $HOME\naws backup start-backup-job --backup-vault-name ${aws_backup_vault.eks_backup_vault.id} --resource-arn ${aws_eks_cluster.primary_cluster.arn} --iam-role-arn ${aws_iam_role.eks_backup_iam_role.arn}\n\ncat << 'EOF' >> /home/ec2-user/README.md\n# EKS Backup / Restore\n\nBackup\n```\naws backup start-backup-job \\\n--backup-vault-name ${aws_backup_vault.eks_backup_vault.id} \\\n--resource-arn ${aws_eks_cluster.primary_cluster.arn} \\\n--iam-role-arn ${aws_iam_role.eks_backup_iam_role.arn}\n```\n\nComposite Recovery Points\n```\naws backup list-recovery-points-by-resource \\\n--resource-arn ${aws_eks_cluster.primary_cluster.arn} \\\n--query \"RecoveryPoints[*].RecoveryPointArn\" | grep composite:eks\n```\n\nExisting Cluster Restore\n```\naws backup start-restore-job \\\n--recovery-point-arn \"⚠️\" \\\n--iam-role-arn ${aws_iam_role.eks_backup_iam_role.arn} \\\n--metadata '⚠️' \\\n--resource-type \"EKS\"\n```\n\nNew Cluster Restore\n```\naws backup start-restore-job \\\n--recovery-point-arn \"⚠️\" \\\n--iam-role-arn ${aws_iam_role.eks_backup_iam_role.arn} \\\n--metadata '⚠️' \\\n--resource-type \"EKS\"\n\nIAM Accss Entry - Access Policy\n```\naws eks create-access-entry --type STANDARD \\\n--cluster-name ${aws_eks_cluster.secondary_cluster.name} \\\n--principal-arn ${aws_iam_role.eks_backup_iam_role.arn}\n\naws eks associate-access-policy --access-scope type=cluster \\\n--cluster-name ${aws_eks_cluster.secondary_cluster.name} \\\n--principal-arn ${aws_iam_role.eks_backup_iam_role.arn} \\\n--policy-arn arn:aws:eks::aws:cluster-access-policy/AWSBackupFullAccessPolicyForRestore\n```\nEOF\n\nSSMEOF\n"])
  }
  depends_on = [aws_instance.vs_code_ec2]
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
