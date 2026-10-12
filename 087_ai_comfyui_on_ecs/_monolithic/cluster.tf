# Generated from 087_ai_comfyui_on_ecs/cluster.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
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
  default     = "cluster"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# --- Parameters ---
variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment name to use for deployment"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}
variable "notification_email_address" {
  type        = string
  description = "Email address to receive deployment notifications (Example: test@example.co.jp)"
}
variable "self_sign_up" {
  type        = string
  default     = false
  description = "Enable self-signup functionality (CAUTION Carefully consider when you allow public access)"
  validation {
    condition     = contains([true, false], var.self_sign_up)
    error_message = "SelfSignUp must be one of: True, False"
  }
}
variable "allowed_sign_up_email_domains" {
  type        = string
  default     = ""
  description = "Allowed email domains for signup (Example: example1.co.jp, example2.co.jp)"
}
variable "allowed_ip_v4_address_ranges" {
  type        = string
  default     = ""
  description = "Allowed IPv4 address ranges for access (Example: 10.0.0.100/32, 192.168.0.0/24). Find your current Public IP address here: https://checkip.amazonaws.com/"
}
variable "allowed_ip_v6_address_ranges" {
  type        = string
  default     = ""
  description = "Allowed IPv6 address ranges for access"
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy_attachment" "code_build_service_role" {
  role       = aws_iam_role.code_build_service_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy" "code_build_service_role_policy_role" {
  name = "CodeBuildServiceRolePolicy"
  role = aws_iam_role.code_build_service_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.comfy_u_ideployment_project.name}:*", "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.comfy_u_ideployment_project.name}"]
      }, {
      Action   = ["sns:Publish"]
      Effect   = "Allow"
      Resource = aws_sns_topic.deployment_notification_topic.arn
    }]
  })
}
data "archive_file" "trigger_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/trigger_function/index.js"
  output_path = "${path.module}/build/trigger_function.zip"
}
resource "aws_iam_role_policy" "trigger_function_role" {
  name = "CodeBuildStartPolicy"
  role = aws_iam_role.trigger_function_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "codebuild:StartBuild"
      Resource = aws_codebuild_project.comfy_u_ideployment_project.arn
    }]
  })
}
resource "aws_iam_role_policy_attachment" "trigger_function_role" {
  role       = aws_iam_role.trigger_function_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
resource "aws_sns_topic" "deployment_notification_topic" {
  display_name      = "ComfyUI Deployment Notifications"
  name              = "Notification-for-${var.stack_name}"
  kms_master_key_id = "alias/aws/sns"
}
resource "aws_sns_topic_subscription" "deployment_notification_subscription" {
  protocol  = "email"
  topic_arn = aws_sns_topic.deployment_notification_topic.arn
  endpoint  = var.notification_email_address
}
resource "aws_iam_role" "code_build_service_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_policy" "code_build_service_role_policy" {
  name = "CodeBuildServiceRolePolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.comfy_u_ideployment_project.name}:*", "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.comfy_u_ideployment_project.name}"]
      }, {
      Action   = ["sns:Publish"]
      Effect   = "Allow"
      Resource = aws_sns_topic.deployment_notification_topic.arn
    }]
  })
}
resource "aws_codebuild_project" "comfy_u_ideployment_project" {
  name         = "CodeBuild-for-${var.stack_name}"
  description  = "Deploys ComfyUI"
  service_role = aws_iam_role.code_build_service_role.arn
  artifacts {
    type = "NO_ARTIFACTS"
  }
  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }
  environment {
    type            = "LINUX_CONTAINER"
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    privileged_mode = false
    environment_variable {
      name  = "Environment"
      value = var.environment
    }
    environment_variable {
      name  = "SelfSignUp"
      value = var.self_sign_up
    }
    environment_variable {
      name  = "AllowedSignUpEmailDomains"
      value = var.allowed_sign_up_email_domains
    }
    environment_variable {
      name  = "AllowedIpV4AddressRanges"
      value = var.allowed_ip_v4_address_ranges
    }
    environment_variable {
      name  = "AllowedIpV6AddressRanges"
      value = var.allowed_ip_v6_address_ranges
    }
    environment_variable {
      name  = "SNSTopicArn"
      value = aws_sns_topic.deployment_notification_topic.arn
    }
  }
  source {
    type      = "NO_SOURCE"
    buildspec = "version: 0.2\n\nphases:\n  install:\n    runtime-versions:\n      nodejs: 22\n    commands:\n      - echo \"Starting ComfyUI deployment\"\n      - aws sns publish --topic-arn $SNSTopicArn --subject \"ComfyUI Deployment Started\" --message \"Deployment of ComfyUI has started. You will receive another notification when deployment is complete.\"\n      - git clone https://github.com/aws-samples/cost-effective-aws-deployment-of-comfyui.git\n\n  pre_build:\n    commands:\n      - cd $CODEBUILD_SRC_DIR/cost-effective-aws-deployment-of-comfyui\n      - cp app.py app.py.backup\n\n      # Create and run unified parameter script (updates app.py and creates JSON for Parameter Store)\n      - |\n        cat > update-params.py << EOF\n        import os\n        import json\n\n        # 1. Open app.py\n        file_path = 'app.py'\n        with open(file_path, 'r', encoding='utf-8') as f:\n            content = f.read()\n\n        # 2. Compose the string incrementally\n        # Process arrays first\n        self_sign_up = 'True' if os.environ.get('SelfSignUp') == 'true' else 'False'\n\n        allowed_sign_up_email_domains = None\n        if os.environ.get('AllowedSignUpEmailDomains'):\n            allowed_sign_up_email_domains = [d.strip() for d in os.environ.get('AllowedSignUpEmailDomains').split(',')]\n\n        allowed_ipv4_address_ranges = None\n        if os.environ.get('AllowedIpV4AddressRanges'):\n            allowed_ipv4_address_ranges = [r.strip() for r in os.environ.get('AllowedIpV4AddressRanges').split(',')]\n\n        allowed_ipv6_address_ranges = None\n        if os.environ.get('AllowedIpV6AddressRanges'):\n            allowed_ipv6_address_ranges = [r.strip() for r in os.environ.get('AllowedIpV6AddressRanges').split(',')]\n\n        # Build replacement parts\n        parts = [\n            f'self_sign_up_enabled={self_sign_up}',\n            f'allowed_sign_up_email_domains={allowed_sign_up_email_domains}',\n            f'allowed_ip_v4_address_ranges={allowed_ipv4_address_ranges}',\n            f'allowed_ip_v6_address_ranges={allowed_ipv6_address_ranges}'\n        ]\n\n        # Join with proper indentation\n        replacement = ',\\\\n    '.join(parts)\n\n        # 3. Replace # Override Parameters.*/ with the composed string\n        import re\n        content = re.sub(r'# Override Parameters.*', replacement, content)\n\n        # Write the updated content back to the file\n        with open(file_path, 'w', encoding='utf-8') as f:\n            f.write(content)\n        print(f'Successfully updated {file_path}')\n        EOF\n\n        python3 update-params.py\n\n  build:\n    commands:\n      - cd $CODEBUILD_SRC_DIR/cost-effective-aws-deployment-of-comfyui\n\n      # Deploy the stack\n      - make cdk-deploy-force\n\n      # Get the application URL\n      - cd $CODEBUILD_SRC_DIR/\n      - |\n        STACK_NAME=$(aws cloudformation describe-stacks --query \"Stacks[?contains(StackName, 'ComfyUIStack$Environment')].StackName\" --output text)\n        APP_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query \"Stacks[0].Outputs[?OutputKey=='Endpoint'].OutputValue\" --output text)\n        USER_POOL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query \"Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue\" --output text)\n        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)\n        USER_CREATION_URL=\"https://$AWS_ACCOUNT_ID.$AWS_DEFAULT_REGION.console.aws.amazon.com/cognito/v2/idp/user-pools/$USER_POOL/user-management/users?region=$AWS_DEFAULT_REGION\"\n\n        cat << EOF > deployment-info.txt\n        ComfyUI Deployment Completed Successfully!\n        Deployment Time: $(date '+%Y-%m-%d %H:%M:%S')\n\n        Login URL: $APP_URL\n\n        Important Next Steps:\n        1. Please create a user in the Cognito User Pool to access the application (if self-signup disabled):\n           $USER_CREATION_URL\n\n        Configuration:\n        Environment: $Environment\n        Self-Signup Enabled: $SelfSignUp\n        Allowed SignUp Email Domains: $AllowedSignUpEmailDomains\n        Allowed IpV4 Address Ranges: $AllowedIpV4AddressRanges\n        Allowed IpV6 Address Ranges: $AllowedIpV6AddressRanges\n\n        Stack Details:\n        Stack Name: $STACK_NAME\n        Region: $AWS_DEFAULT_REGION\n\n        EOF\n\n  post_build:\n    commands:\n      - cd $CODEBUILD_SRC_DIR/\n      - aws sns publish --topic-arn \"$SNSTopicArn\" --subject \"ComfyUI Deployment Complete\" --message file://deployment-info.txt\n      - rm -rf cost-effective-aws-deployment-of-comfyui\nartifacts:\n  files:\n    - deployment-info.txt\n"
  }
  build_timeout = 120
}
resource "aws_lambda_invocation" "deployment_trigger" {
  function_name = aws_lambda_function.trigger_function.arn
  input = jsonencode({
    ProjectName    = aws_codebuild_project.comfy_u_ideployment_project.name
    ServiceTimeout = 600
  })
}
resource "aws_lambda_function" "trigger_function" {
  handler          = "index.handler"
  role             = aws_iam_role.trigger_function_role.arn
  runtime          = "nodejs20.x"
  timeout          = 30
  filename         = data.archive_file.trigger_function.output_path
  source_code_hash = data.archive_file.trigger_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-trigger-function"
}
resource "aws_iam_role" "trigger_function_role" {
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
# --- Outputs ---
# CloudFormation output: NotificationTopicArn
output "notification_topic_arn" {
  value       = aws_sns_topic.deployment_notification_topic.arn
  description = "ARN of the SNS topic for deployment notifications"
}
# CloudFormation output: CodeBuildProjectName
output "code_build_project_name" {
  value       = aws_codebuild_project.comfy_u_ideployment_project.name
  description = "Name of the CodeBuild project"
}
# CloudFormation output: CodeBuildLogGroup
output "code_build_log_group" {
  value       = "/aws/codebuild/${aws_codebuild_project.comfy_u_ideployment_project.name}"
  description = "CloudWatch Logs group for CodeBuild logs"
}
# CloudFormation output: DeploymentStatus
output "deployment_status" {
  value       = "Deployment has been initiated. You will receive an email notification at ${var.notification_email_address} when the deployment is complete."
  description = "Deployment status information"
}
