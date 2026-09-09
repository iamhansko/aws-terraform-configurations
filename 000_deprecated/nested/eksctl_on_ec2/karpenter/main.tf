# Generated from 000_deprecated/nested/eksctl_on_ec2/karpenter.yaml by tools/cfn2tf.
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
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}
variable "stack_name" {
  type        = string
  default     = "karpenter"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
# --- Resources ---
resource "aws_cloudformation_stack" "eks_cluster_stack" {
  template_url = "https://iamhanskogithub.s3.ap-southeast-2.amazonaws.com/nested/eksctl_on_ec2/cluster.yaml"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-eks-cluster-stack"
}
resource "aws_ssm_association" "karpenter_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 1800
  targets {
    key    = "InstanceIds"
    values = [aws_cloudformation_stack.eks_cluster_stack.outputs["Ec2InstanceId"]]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user <<'EOF'\nexport HOME=\"/home/ec2-user\"\nexport CLUSTER_NAME=${aws_cloudformation_stack.eks_cluster_stack.outputs["EksClusterName"]}\nexport AWS_REGION=${data.aws_region.current.region}\nexport AWS_ACCOUNT_ID=${data.aws_caller_identity.current.account_id}\nexport CLUSTER_ENDPOINT=\"$(aws eks describe-cluster --name $CLUSTER_NAME --query \"cluster.endpoint\" --output text)\"\nexport KARPENTER_NAMESPACE=\"kube-system\"\necho Cluster Name:$CLUSTER_NAME AWS Region:$AWS_REGION Account ID:$AWS_ACCOUNT_ID Cluster Endpoint:$CLUSTER_ENDPOINT Karpenter Namespace:$KARPENTER_NAMESPACE\n\nKARPENTER_VERSION_V=$(curl -sL \"https://api.github.com/repos/aws/karpenter/releases/latest\" | jq -r \".tag_name\")\nexport KARPENTER_VERSION=$(echo $KARPENTER_VERSION_V | sed \"s/^v//\")\necho \"Karpenter's Latest release version: $KARPENTER_VERSION\"\n\nexport TEMPOUT=$(mktemp)\ncurl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v\"$KARPENTER_VERSION\"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml  > \"$TEMPOUT\" \\\n&& aws cloudformation deploy \\\n  --stack-name \"Karpenter-$CLUSTER_NAME\" \\\n  --template-file \"$TEMPOUT\" \\\n  --capabilities CAPABILITY_NAMED_IAM \\\n  --parameter-overrides \"ClusterName=$CLUSTER_NAME\"\n\neksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve\n\neksctl create iamserviceaccount \\\n  --cluster \"$CLUSTER_NAME\" --name karpenter --namespace $KARPENTER_NAMESPACE \\\n  --role-name \"$CLUSTER_NAME-karpenter\" \\\n  --attach-policy-arn \"arn:aws:iam::$AWS_ACCOUNT_ID:policy/KarpenterControllerPolicy-$CLUSTER_NAME\" \\\n  --role-only \\\n  --approve\nexport KARPENTER_IAM_ROLE_ARN=\"arn:aws:iam::$AWS_ACCOUNT_ID:role/$CLUSTER_NAME-karpenter\"\n\naws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true\n\nhelm registry logout public.ecr.aws\nhelm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version \"$KARPENTER_VERSION\" \\\n  --namespace \"$KARPENTER_NAMESPACE\" --create-namespace \\\n  --set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=$KARPENTER_IAM_ROLE_ARN \\\n  --set settings.clusterName=$CLUSTER_NAME \\\n  --set settings.clusterEndpoint=$CLUSTER_ENDPOINT \\\n  --set settings.featureGates.spotToSpotConsolidation=true \\\n  --set settings.interruptionQueue=$CLUSTER_NAME \\\n  --set controller.resources.requests.cpu=1 \\\n  --set controller.resources.requests.memory=1Gi \\\n  --set controller.resources.limits.cpu=1 \\\n  --set controller.resources.limits.memory=1Gi \\\n  --wait\n\nwget -O eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/v0.7.1/eks-node-viewer_Linux_x86_64\nchmod +x eks-node-viewer\nsudo mv -v eks-node-viewer /usr/local/bin\n\ncurl -sS https://webinstall.dev/k9s | bash\\\" | tee -a  /home/ec2-user/.bash_profile\nEOF\n"])
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
