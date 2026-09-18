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
# No kubernetes, kubectl or helm provider here, unlike the other EKS projects in
# this repository. Everything this project declares is an AWS API call: the
# CoreDNS placement that a Fargate-only cluster needs is expressed as addon
# configuration (modules/eks_coredns_addon) rather than as a manifest or a
# rollout restart, so nothing has to reach the cluster's API server at apply
# time. That is also what lets the cluster keep the _monolithic template's
# endpoint_public_access = false: the API server is only reachable from inside
# the VPC, which is where the bastion is.
