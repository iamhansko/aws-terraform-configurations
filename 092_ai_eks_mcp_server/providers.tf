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
# No kubectl or helm provider, and that is worth saying because every other EKS root here has at least one.
#
# Nothing in this project applies a Kubernetes object. The cluster exists so that the Amazon Q CLI on the
# workbench - and the EKS MCP server it is configured with - has something to talk to; the demo is asking Q to
# inspect and change the cluster, so anything Terraform created in it would be pre-empting the exercise.
#
# The consequence is the one rules.md E-9 describes for its own case: whatever Q creates is not in Terraform
# state, so a destroy removes the cluster and takes those objects with it rather than removing them in order.
# For a demo cluster that is the right trade; for anything else it is the reason to be careful about what the
# MCP server is allowed to write.
#
# No random provider. The _monolithic template generated a uuid to stand in for AWS::StackId so it could slice
# a suffix out of it for the key pair's name; the key pair is named from cluster_name here.
