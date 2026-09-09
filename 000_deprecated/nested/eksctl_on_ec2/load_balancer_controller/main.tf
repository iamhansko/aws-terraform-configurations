# Generated from 000_deprecated/nested/eksctl_on_ec2/load_balancer_controller.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
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
  default     = "load-balancer-controller"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Mappings / Conditions ---
locals {
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
}
# --- Resources ---
resource "aws_cloudformation_stack" "eks_cluster_stack" {
  template_url = "https://iamhanskogithub.s3.ap-southeast-2.amazonaws.com/nested/eksctl_on_ec2/cluster.yaml"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-eks-cluster-stack"
}
resource "aws_ssm_association" "lbc_ssm_association" {
  name = "AWS-RunShellScript"
  targets {
    key    = "InstanceIds"
    values = [aws_cloudformation_stack.eks_cluster_stack.outputs["Ec2InstanceId"]]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << EOF\n\nexport oidc_id=$(aws eks describe-cluster --name ${aws_cloudformation_stack.eks_cluster_stack.outputs["EksClusterName"]} --query \"cluster.identity.oidc.issuer\" --output text | cut -d '/' -f 5)\necho $oidc_id\neksctl utils associate-iam-oidc-provider --region ${data.aws_region.current.region} --cluster ${aws_cloudformation_stack.eks_cluster_stack.outputs["EksClusterName"]} --approve\naws iam list-open-id-connect-providers | grep $oidc_id | cut -d \"/\" -f4\n\ncurl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/docs/install/iam_policy.json\naws iam create-policy \\\n--policy-name AWSLoadBalancerControllerIAMPolicy-${element(split("-", element(split("/", local.stack_id), 2)), 4)} \\\n--policy-document file://iam_policy.json\nrm iam_policy.json\n\neksctl create iamserviceaccount \\\n--cluster=${aws_cloudformation_stack.eks_cluster_stack.outputs["EksClusterName"]} \\\n--namespace=kube-system \\\n--name=aws-load-balancer-controller \\\n--role-name AmazonEKSLoadBalancerControllerRole-${element(split("-", element(split("/", local.stack_id), 2)), 4)} \\\n--attach-policy-arn=\"arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AWSLoadBalancerControllerIAMPolicy-${element(split("-", element(split("/", local.stack_id), 2)), 4)}\" \\\n--approve --region ${data.aws_region.current.region}\nhelm repo add eks https://aws.github.io/eks-charts\nhelm repo update eks\nhelm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \\\n--set clusterName=${aws_cloudformation_stack.eks_cluster_stack.outputs["EksClusterName"]} \\\n--set serviceAccount.create=false \\\n--set serviceAccount.name=aws-load-balancer-controller \\\n--set region=${data.aws_region.current.region} \\\n--set vpcId=${aws_cloudformation_stack.eks_cluster_stack.outputs["VpcId"]}\nkubectl rollout status -n kube-system deploy aws-load-balancer-controller\n\ngit clone https://codeberg.org/hjacobs/kube-ops-view.git\ncd kube-ops-view/\nkubectl apply -k deploy\nkubectl patch svc kube-ops-view -p \"{\\\"spec\\\": {\\\"type\\\": \\\"LoadBalancer\\\"}}\"\nEOF\n"])
  }
}
# --- Outputs ---
# CloudFormation output: CloudFrontDomainName
output "cloud_front_domain_name" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["CloudFrontDomainName"]
}
# CloudFormation output: EksClusterName
output "eks_cluster_name" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["EksClusterName"]
}
# CloudFormation output: Ec2InstanceId
output "ec2_instance_id" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["Ec2InstanceId"]
}
# CloudFormation output: Ec2IamRoleArn
output "ec2_iam_role_arn" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["Ec2IamRoleArn"]
}
# CloudFormation output: Ec2PublicIp
output "ec2_public_ip" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["Ec2PublicIp"]
}
# CloudFormation output: Ec2PublicDnsName
output "ec2_public_dns_name" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["Ec2PublicDnsName"]
}
# CloudFormation output: Ec2SecurityGroup
output "ec2_security_group" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["Ec2SecurityGroup"]
}
# CloudFormation output: VpcId
output "vpc_id" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["VpcId"]
}
# CloudFormation output: PublicSubnet1Id
output "public_subnet1_id" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["PublicSubnet1Id"]
}
# CloudFormation output: PublicSubnet2Id
output "public_subnet2_id" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["PublicSubnet2Id"]
}
# CloudFormation output: PublicSubnet3Id
output "public_subnet3_id" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["PublicSubnet3Id"]
}
# CloudFormation output: PrivateSubnet1Id
output "private_subnet1_id" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["PrivateSubnet1Id"]
}
# CloudFormation output: PrivateSubnet2Id
output "private_subnet2_id" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["PrivateSubnet2Id"]
}
# CloudFormation output: PrivateSubnet3Id
output "private_subnet3_id" {
  value = aws_cloudformation_stack.eks_cluster_stack.outputs["PrivateSubnet3Id"]
}
