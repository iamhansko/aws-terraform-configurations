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
# No kubectl provider, and no helm provider. That absence is the point of this project.
# ---------------------------------------------------------------------------------------------------
#
# The cluster's API server endpoint is private only - endpoint_public_access is false and its validation pins it
# there. A provider configured against it would run on the machine executing terraform apply, which is outside
# both VPCs, so it could not reach the API server at all. rules.md E-9 is the rule, and this is the one project
# here that is about that constraint rather than working around it.
#
# What replaces them: nothing, because this project creates no Kubernetes objects. The three addons are
# aws_eks_addon resources, which the AWS provider creates through the EKS API rather than through the cluster's
# API server, so they work with a private endpoint (rules.md D-4 makes the same distinction for destroy
# ordering). Anything else would have to be applied from the workbench through an SSM Association, which is the
# form rules.md E-9 prescribes.
#
# The workbench itself does reach the API server - it is in the client VPC, and the whole VPC Lattice
# arrangement exists so that it can. That is a client inside a VPC, which is exactly what a private endpoint
# allows; it is not a Terraform provider.
#
# No random provider. The _monolithic template generated a uuid to stand in for AWS::StackId so it could slice a
# suffix out of it for the key pair's name; the key pair is named from cluster_name here.
#
# No archive provider either, which the original needed for a Lambda that has been removed entirely - see
# modules/lattice_client_endpoint for what replaced it.
