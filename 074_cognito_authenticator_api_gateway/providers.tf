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
# One root where the _monolithic template had two stacks, 1_vscode and 2_cognito, and none of the SAM stack it
# deployed from the workbench.
#
# The stacks were split by a cycle CloudFormation could only break across stacks: the app client's callback URL
# is the web app's address, and the web app was a SAM stack deployed from the workbench. So the first stack
# built the workbench and deployed the web app, and the second imported its callback URL (Fn::ImportValue
# cognito-webapp-CallbackUrl) and the instance ID, passed across by hand.
#
# The web app's SAM template is Terraform resources now (modules/cognito_web_app), and that is what removes the
# cycle: the web app's address is its REST API's, which exists before the function does, so the pool names it
# first. The build stays on the workbench - npm install, which Terraform cannot run.
#
# Also not reproduced from 1_vscode: three ECR repositories (server, client, image-generation) that nothing
# pushed to or pulled from, and the private subnets and NAT gateways described in the network module.
#
# random stays, for the hosted domain prefix, which has to be unique across every account in the region; the
# uuid that used to stand in for AWS::StackId supplied it. archive zips the function that waits for the web
# app's package (modules/s3_object_waiter).
