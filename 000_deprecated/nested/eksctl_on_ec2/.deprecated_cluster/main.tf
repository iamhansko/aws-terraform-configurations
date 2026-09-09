# Generated from 000_deprecated/nested/eksctl_on_ec2/.deprecated_cluster.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
variable "aws_region" {
  type = string
  default = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}
variable "stack_name" {
  type = string
  default = "deprecated-cluster"
  description = "Stands in for AWS::StackName."
}
data "aws_region" "current" {}
# --- Parameters ---
variable "eks_cluster_name" {
  type = string
  default = "eks-cluster"
}
variable "eks_cluster_version" {
  type = string
  default = 1.31
  validation {
    condition = contains([1.31, 1.3, 1.29, 1.28, 1.27, 1.26, 1.25], var.eks_cluster_version)
    error_message = "EksClusterVersion must be one of: 1.31, 1.3, 1.29, 1.28, 1.27, 1.26, 1.25"
  }
}
variable "eks_mng_ami_family" {
  type = string
  default = "AmazonLinux2023"
  validation {
    condition = contains(["AmazonLinux2023", "AmazonLinux2", "UbuntuPro2204", "Ubuntu2204", "Ubuntu2004", "Ubuntu1804", "Bottlerocket", "WindowsServer2022CoreContainer", "WindowsServer2022FullContainer", "WindowsServer2019CoreContainer", "WindowsServer2019FullContainer"], var.eks_mng_ami_family)
    error_message = "EksMngAmiFamily must be one of: AmazonLinux2023, AmazonLinux2, UbuntuPro2204, Ubuntu2204, Ubuntu2004, Ubuntu1804, Bottlerocket, WindowsServer2022CoreContainer, WindowsServer2022FullContainer, WindowsServer2019CoreContainer, WindowsServer2019FullContainer"
  }
}
variable "eks_mng_instance_type" {
  type = string
  default = "t3.xlarge"
  validation {
    condition = contains(["t1.micro", "t2.2xlarge", "t2.large", "t2.medium", "t2.micro", "t2.nano", "t2.small", "t2.xlarge", "t3.2xlarge", "t3.large", "t3.medium", "t3.micro", "t3.nano", "t3.small", "t3.xlarge", "t3a.2xlarge", "t3a.large", "t3a.medium", "t3a.micro", "t3a.nano", "t3a.small", "t3a.xlarge", "t4g.2xlarge", "t4g.large", "t4g.medium", "t4g.micro", "t4g.nano", "t4g.small", "t4g.xlarge"], var.eks_mng_instance_type)
    error_message = "EksMngInstanceType must be one of: t1.micro, t2.2xlarge, t2.large, t2.medium, t2.micro, t2.nano, t2.small, t2.xlarge, t3.2xlarge, t3.large, t3.medium, t3.micro, t3.nano, t3.small, t3.xlarge, t3a.2xlarge, t3a.large, t3a.medium, t3a.micro, t3a.nano, t3a.small, t3a.xlarge, t4g.2xlarge, t4g.large, t4g.medium, t4g.micro, t4g.nano, t4g.small, t4g.xlarge"
  }
}
variable "eks_mng_desired_capacity" {
  type = number
  default = 3
}
variable "eks_mng_enable_spot" {
  type = string
  default = "true"
  validation {
    condition = contains(["true", "false"], var.eks_mng_enable_spot)
    error_message = "EksMngEnableSpot must be one of: true, false"
  }
}
# --- Resources ---
resource "aws_cloudformation_stack" "network_stack" {
  template_url = "https://iamhanskogithub.s3.ap-southeast-2.amazonaws.com/nested/vpc_and_more.yaml"
  parameters = {
    Prefix = "eks"
    VpcCidrBlock = "10.0.0.0/16"
    NumberOfPublicSubnets = 3
    NumberOfPrivateSubnets = 3
    EnableDnsHostnamesOption = true
    EnableDnsResolutionOption = true
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-network-stack"
}
resource "aws_cloudformation_stack" "vscode_on_ec2_stack" {
  template_url = "https://iamhanskogithub.s3.ap-southeast-2.amazonaws.com/nested/deprecated_vscode_on_ec2.yaml"
  parameters = {
    VpcId = aws_cloudformation_stack.network_stack.outputs["VpcId"]
    PublicSubnetId = aws_cloudformation_stack.network_stack.outputs["PublicSubnet1Id"]
    AmiId = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
    InstanceType = "t3.small"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-vscode-on-ec2-stack"
}
resource "aws_s3_bucket" "ssm_run_command_s3_bucket" {}
resource "aws_ssm_association" "ssm_association" {
  name = "AWS-RunShellScript"
  targets {
    key = "InstanceIds"
    values = [aws_cloudformation_stack.vscode_on_ec2_stack.outputs["Ec2InstanceId"]]
  }
  output_location {
    s3_bucket_name = aws_s3_bucket.ssm_run_command_s3_bucket.id
    s3_key_prefix = "logs/"
  }
  parameters = {
    commands = join("\n", ["su - ec2-user <<'EOF'\nmkdir -p /home/ec2-user/bin\ncurl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.31.2/2024-11-15/bin/linux/amd64/kubectl\nchmod +x kubectl\nmv kubectl /home/ec2-user/bin/kubectl\nexport PATH=/home/ec2-user/bin:$PATH\necho \"export PATH=/home/ec2-user/bin:$PATH\" >> ~/.bashrc\necho \"alias k=kubectl\" >> ~/.bashrc\necho \"complete -o default -F __start_kubectl k\" >> ~/.bashrc\necho \"source <(kubectl completion bash)\" >> ~/.bashrc\n\ncurl --silent --location \"https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz\" | tar xz -C /tmp\nsudo mv /tmp/eksctl /usr/local/bin\naws configure set region ${data.aws_region.current.region}\n\ncurl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > /home/ec2-user/get_helm.sh\nchmod 700 /home/ec2-user/get_helm.sh\n/home/ec2-user/get_helm.sh\nEOF\n\nsu - ec2-user <<'EOF'\nmkdir -p /home/ec2-user/eksctl\ncat <<EOF > /home/ec2-user/eksctl/cluster.yaml\napiVersion: eksctl.io/v1alpha5\nkind: ClusterConfig\nmetadata:\n  name: ${var.eks_cluster_name}\n  region: ${data.aws_region.current.region}\n  version: ${var.eks_cluster_version}\nvpc:\n  id: ${aws_cloudformation_stack.network_stack.outputs["VpcId"]}\n  subnets:\n    public:\n      public1:\n        id: ${aws_cloudformation_stack.network_stack.outputs["PublicSubnet1Id"]}\n      public2:\n        id: ${aws_cloudformation_stack.network_stack.outputs["PublicSubnet2Id"]}\n      public3:\n        id: ${aws_cloudformation_stack.network_stack.outputs["PublicSubnet3Id"]}\n    private:\n      private1:\n        id: ${aws_cloudformation_stack.network_stack.outputs["PrivateSubnet1Id"]}\n      private2:\n        id: ${aws_cloudformation_stack.network_stack.outputs["PrivateSubnet2Id"]}\n      private3:\n        id: ${aws_cloudformation_stack.network_stack.outputs["PrivateSubnet3Id"]}\nmanagedNodeGroups:\n  - name: nodegroup\n    amiFamily: ${var.eks_mng_ami_family}\n    spot: ${var.eks_mng_enable_spot}\n    instanceType: ${var.eks_mng_instance_type}\n    desiredCapacity: ${var.eks_mng_desired_capacity}\n    privateNetworking: true\n    disableIMDSv1: true\n    iam:\n      attachPolicyARNs:\n        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy\n        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy\n        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly\n        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore\n        - arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy\nEOF\neksctl create cluster -f /home/ec2-user/eksctl/cluster.yaml\nEOF\n"])
  }
}
# --- Outputs ---
# CloudFormation output: CloudFrontDomainName
output "cloud_front_domain_name" {
  value = aws_cloudformation_stack.vscode_on_ec2_stack.outputs["CloudFrontDomainName"]
}
# CloudFormation output: EksClusterName
output "eks_cluster_name" {
  value = var.eks_cluster_name
}
# CloudFormation output: Ec2InstanceId
output "ec2_instance_id" {
  value = aws_cloudformation_stack.vscode_on_ec2_stack.outputs["Ec2InstanceId"]
}
# CloudFormation output: Ec2IamRoleArn
output "ec2_iam_role_arn" {
  value = aws_cloudformation_stack.vscode_on_ec2_stack.outputs["Ec2IamRoleArn"]
}
# CloudFormation output: Ec2PublicIp
output "ec2_public_ip" {
  value = aws_cloudformation_stack.vscode_on_ec2_stack.outputs["Ec2PublicIp"]
}
# CloudFormation output: Ec2PublicDnsName
output "ec2_public_dns_name" {
  value = aws_cloudformation_stack.vscode_on_ec2_stack.outputs["Ec2PublicDnsName"]
}
# CloudFormation output: Ec2SecurityGroup
output "ec2_security_group" {
  value = aws_cloudformation_stack.vscode_on_ec2_stack.outputs["Ec2SecurityGroup"]
}
# CloudFormation output: VpcId
output "vpc_id" {
  value = aws_cloudformation_stack.network_stack.outputs["VpcId"]
}
# CloudFormation output: PublicSubnet1Id
output "public_subnet1_id" {
  value = aws_cloudformation_stack.network_stack.outputs["PublicSubnet1Id"]
}
# CloudFormation output: PublicSubnet2Id
output "public_subnet2_id" {
  value = aws_cloudformation_stack.network_stack.outputs["PublicSubnet2Id"]
}
# CloudFormation output: PublicSubnet3Id
output "public_subnet3_id" {
  value = aws_cloudformation_stack.network_stack.outputs["PublicSubnet3Id"]
}
# CloudFormation output: PrivateSubnet1Id
output "private_subnet1_id" {
  value = aws_cloudformation_stack.network_stack.outputs["PrivateSubnet1Id"]
}
# CloudFormation output: PrivateSubnet2Id
output "private_subnet2_id" {
  value = aws_cloudformation_stack.network_stack.outputs["PrivateSubnet2Id"]
}
# CloudFormation output: PrivateSubnet3Id
output "private_subnet3_id" {
  value = aws_cloudformation_stack.network_stack.outputs["PrivateSubnet3Id"]
}
