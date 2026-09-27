terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# No kubectl provider and no helm provider here, and that is the point of this
# project.
#
# Every other EKS root module in this repository configures one or both, pointed at
# the cluster's API server, and sets endpoint_public_access = true so the provider -
# which runs on the machine executing terraform apply - can reach it. That is what
# rules.md E-1 and E-2 ask for, and it is the right default.
#
# This cluster's API server is private only. Making it public purely so Terraform
# could reach it would defeat what the project exists to demonstrate, so the
# Kubernetes objects are created the way the _monolithic template created them:
# by SSM Associations that run kubectl and helm on the bastion, which sits inside
# the VPC and already has cluster-admin through an EKS access entry.
#
# The trade is real and worth stating. What is given up:
#   - The manifests and the Helm release are not in Terraform state, so drift in
#     them is invisible and terraform destroy does not remove them. The cluster
#     going away takes them with it, which is why that is acceptable here.
#   - Ordering between those objects is enforced by marker files and until loops
#     rather than by the dependency graph (rules.md D-5).
#   - A failure surfaces as an SSM association that did not reach Success, so the
#     real error has to be read out of the command invocation (rules.md A-4 has the
#     procedure).
# What is kept: the API server is never exposed to the internet.
