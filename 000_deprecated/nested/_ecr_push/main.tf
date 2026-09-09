# Generated from 000_deprecated/nested/_ecr_push.yaml by tools/cfn2tf.
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
  default     = "ecr-push"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
# --- Resources ---
resource "aws_ecr_repository" "golang_ecr" {
  force_delete = true
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-golang-ecr"
}
resource "aws_cloudformation_stack" "network_stack" {
  template_url = "https://iamhanskogithub.s3.ap-southeast-2.amazonaws.com/nested/vpc_and_more.yaml"
  parameters = {
    Prefix                    = "ops"
    VpcCidrBlock              = "10.0.0.0/16"
    NumberOfPublicSubnets     = 1
    NumberOfPrivateSubnets    = 0
    EnableDnsHostnamesOption  = true
    EnableDnsResolutionOption = true
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-network-stack"
}
resource "aws_cloudformation_stack" "vscode_on_ec2_stack" {
  template_url = "https://iamhanskogithub.s3.ap-southeast-2.amazonaws.com/nested/vscode_on_ec2.yaml"
  parameters = {
    VpcId                                  = aws_cloudformation_stack.network_stack.outputs["VpcId"]
    PublicSubnetId                         = aws_cloudformation_stack.network_stack.outputs["PublicSubnet1Id"]
    AmiId                                  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
    InstanceType                           = "t3.small"
    SsmCommandWaitForSuccessTimeoutSeconds = 420
    SsmRunCommandShellScript               = "su - ec2-user <<'EOF'\nmkdir -p /home/ec2-user/api\n\necho 'package main\nimport (\n    \"fmt\"\n    \"net/http\"\n)\nfunc healthcheck(w http.ResponseWriter, req *http.Request) {\n    fmt.Fprint(w, \"OK\")\n}\nfunc main() {\n    http.HandleFunc(\"/healthcheck\", healthcheck)\n    http.ListenAndServe(\":8080\", nil)\n}' > /home/ec2-user/api/main.go\n\nsudo dnf install -y golang\nmkdir -p /home/ec2-user/.cache/go-build\nchown -R ec2-user:ec2-user /home/ec2-user/.cache\nCGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOCACHE=/home/ec2-user/.cache/go-build go build -o /home/ec2-user/api/golang-api-amd64 /home/ec2-user/api/main.go\n\necho 'FROM alpine\nWORKDIR /app\nCOPY golang-api-amd64 .\nRUN apk add --no-cache curl\nRUN apk --no-cache add ca-certificates && apk --no-cache upgrade\nRUN adduser -D appuser\nRUN chown appuser:appuser ./golang-api-amd64\nRUN chmod +x ./golang-api-amd64\nUSER appuser\nEXPOSE 8080\nCMD [\"./golang-api-amd64\"]' > /home/ec2-user/api/Dockerfile\n\nIMAGE_TAG=${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/${aws_ecr_repository.golang_ecr.name}:latest\n\naws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com\ndocker build -t $IMAGE_TAG /home/ec2-user/api\ndocker push $IMAGE_TAG\nEOF\n"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-vscode-on-ec2-stack"
}
# --- Outputs ---
# CloudFormation output: CloudFrontDomainName
output "cloud_front_domain_name" {
  value = aws_cloudformation_stack.vscode_on_ec2_stack.outputs["CloudFrontDomainName"]
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
