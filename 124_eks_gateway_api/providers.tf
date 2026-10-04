terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# ---------------------------------------------------------------------------------------------------
# No kubectl provider, and no helm provider. That absence is deliberate, and it is the single decision
# that shapes the rest of this root module.
# ---------------------------------------------------------------------------------------------------
#
# Every other EKS root module in this repository configures one or both, pointed at the cluster's API server,
# and sets endpoint_public_access = true so the provider - which runs on the machine executing terraform
# apply - can reach it. That is what rules.md E-1 and E-2 ask for, and it is the right default.
#
# This cluster's API server is private only. The _monolithic template set EndpointPublicAccess: false and
# EndpointPrivateAccess: true, and endpoint_public_access carries a validation pinning it there. Opening the
# endpoint purely so Terraform could reach it would change what the original did, so the Kubernetes objects are
# created the way that template created them: by SSM Associations running kubectl and helm on the workbench,
# which sits inside the VPC, holds the cluster security group, and has cluster-admin through an EKS access
# entry. rules.md E-9 is that form, and this is the second project in the repository to need it.
#
# What this project puts through that path, in order, each step waiting on the previous step's marker file
# rather than on depends_on (rules.md D-5):
#
#   1. The Gateway API CRDs - the standard channel bundle plus the AWS-vended ones. These come first because
#      the controller decides at startup which of its controllers to enable by looking for the CRDs; a
#      controller that starts before them never reconciles a Gateway, and says nothing about why.
#   2. The AWS Load Balancer Controller chart, with the IRSA role this root creates for it.
#   3. The demo: a GatewayClass, a Gateway, an HTTPRoute and the workload they front.
#
# The trade is real and worth stating. What is given up:
#   - None of those Kubernetes objects is in Terraform state, so drift in them is invisible, plan shows
#     nothing about them, and terraform destroy does not remove them.
#   - That last point has a consequence specific to this project: the ALB is created by the controller in
#     response to the Gateway, and destroy tears down the cluster without first deleting the Gateway - so the
#     load balancer and its target groups can outlive the apply that caused them. The teardown output says so
#     and gives the one command that avoids it; rules.md G-3 is the structural fix, and it is not applied here
#     because adoption is defined for Ingress and Service stacks rather than for Gateways.
#   - Ordering between the steps is enforced by marker files and until loops rather than by the dependency
#     graph (rules.md D-5).
#   - A failure surfaces as an SSM association that did not reach Success, so the real error has to be read out
#     of the command invocation (rules.md A-4 has the procedure, and the output map below repeats it).
# What is kept: the API server is never exposed to the internet.
#
# No random provider either. The _monolithic template generated a uuid to stand in for AWS::StackId so it could
# slice a suffix out of it for the key pair's name; the key pair is named from cluster_name here.
