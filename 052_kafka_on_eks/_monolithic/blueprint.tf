# Generated from 052_kafka_on_eks/blueprint.yaml by tools/cfn2tf.
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
  default     = "blueprint"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "vpc" {
  type        = string
  description = "VsCode EC2 Instance - VPC"
}
variable "subnet" {
  type        = string
  description = "VsCode EC2 Instance - Subnet"
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
  stack_id                                  = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  cond_security_group_inbound_from_anywhere = (var.inbound_from_anywhere == "True")
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
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
# --- Resources ---
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT50M"
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

sudo yum install -yq yum-utils shadow-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum install -yq terraform

export VSC_VERSION="4.104.1"
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

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > /home/ec2-user/get_helm.sh
chmod 700 /home/ec2-user/get_helm.sh
/home/ec2-user/get_helm.sh

export AWS_REGION=${data.aws_region.current.region}
export AWS_DEFAULT_REGION=${data.aws_region.current.region}

git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/streaming/kafka
sed -i 's/\/dev\/tty/\/dev\/null/g' ./install.sh
chmod +x install.sh
./install.sh

sleep 30
kubectl create namespace kafka
kubectl apply -f kafka-manifests/
kubectl apply -f monitoring-manifests/

echo '# Create Kafka Topic and Run Sample Test

## Create a Kafka Topic
kubectl apply -f examples/kafka-topics.yaml
kubectl exec -it cluster-broker-0 -c kafka -n kafka -- /bin/bash -c "/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092"

## Execute Sample Kafka Producer
kubectl -n kafka run kafka-producer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic

## Execute Sample Kafka Consumer
kubectl -n kafka run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic --from-beginning

## Grafana Dashboard for Kafka
export GRAFANA_SECRET_NAME=$(terraform output -json | jq -r ".grafana_secret_name.value")
aws secretsmanager get-secret-value --secret-id $GRAFANA_SECRET_NAME --region ${data.aws_region.current.region} --query "SecretString" --output text
' > /home/ec2-user/README.md
EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = var.subnet
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vs_code_ec2_security_group.id]
}
resource "aws_security_group" "vs_code_ec2_security_group" {
  description = "Security Group"
  name        = "vscode-sg"
  vpc_id      = var.vpc
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
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_ssm_association" "ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user && cd $HOME\n\ncd data-on-eks/streaming/kafka\nexport EKS_CLUSTER_NAME=$(terraform output -json | jq -r \".cluster_name.value\")\naws eks update-kubeconfig --name $EKS_CLUSTER_NAME\ncurl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.4/docs/install/iam_policy.json\naws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json\neksctl create iamserviceaccount \\\n--cluster=$EKS_CLUSTER_NAME \\\n--namespace=kube-system \\\n--name=aws-load-balancer-controller \\\n--attach-policy-arn=arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AWSLoadBalancerControllerIAMPolicy \\\n--override-existing-serviceaccounts \\\n--region ${data.aws_region.current.region} \\\n--approve\nhelm repo add eks https://aws.github.io/eks-charts\nhelm repo update eks\nhelm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --wait \\\n--set clusterName=$EKS_CLUSTER_NAME \\\n--set serviceAccount.create=false \\\n--set serviceAccount.name=aws-load-balancer-controller\nsleep 30\nmkdir -p /home/ec2-user/manifests\necho 'apiVersion: networking.k8s.io/v1\nkind: Ingress\nmetadata:\n  name: grafana\n  namespace: kube-prometheus-stack\n  annotations:\n    alb.ingress.kubernetes.io/scheme: internet-facing\n    alb.ingress.kubernetes.io/target-type: ip\nspec:\n  ingressClassName: alb\n  rules:\n    - http:\n        paths:\n          - path: /\n            pathType: Prefix\n            backend:\n              service:\n                name: kube-prometheus-stack-grafana\n                port:\n                  number: 80' > /home/ec2-user/manifests/grafana_ingress.yaml\nkubectl apply -f /home/ec2-user/manifests/grafana_ingress.yaml\n\nwget -O eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/v0.7.4/eks-node-viewer_Linux_x86_64\nchmod +x eks-node-viewer\nsudo mv -v eks-node-viewer /usr/local/bin\nSSMEOF\n"])
  }
  depends_on = [aws_instance.vs_code_ec2]
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
