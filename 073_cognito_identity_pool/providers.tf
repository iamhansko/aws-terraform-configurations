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
# One root where the _monolithic template had two stacks, 1_vscode and 2_cognito, and none of the SAM stacks it
# deployed from the workbench.
#
# The stacks were split by a cycle CloudFormation could only break across stacks: the app client's callback URL
# is the web app's address, the web app was a SAM stack deployed from the workbench, and the web app's
# configuration is the user pool's IDs. So the first stack deployed the web app unconfigured, the second
# imported its URL (Fn::ImportValue cognito-webapp-Url), and the web app was deployed a second time with the
# IDs.
#
# Both SAM templates are Terraform resources now - cognito-web in modules/cognito_web_app, cognito-lambdas in
# modules/cognito_trigger_lambda - and that is what removes the cycle. The web app's address is its REST API's,
# which exists before the function does, so the pool names it first and the web app is built once, already
# configured. The build itself stays on the workbench: npm install and an esbuild bundle, which Terraform
# cannot run.
#
# random stays, for the hosted domain prefix, which has to be unique across every account in the region; the
# uuid that used to stand in for AWS::StackId supplied it. archive zips the pre token generation function.
