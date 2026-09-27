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
# No kubectl provider and no helm provider, and that is what distinguishes this
# variant from its siblings. CoreDNS autoscaling here is a property of the EKS
# addon, set through configuration_values, so there is no Kubernetes object to
# create and nothing to install into the cluster (rules.md E-5).
#
# The cpa_coredns variant next door achieves the same outcome with a
# cluster-proportional-autoscaler Helm release, and needs a helm provider for it -
# comparing the two root modules is the point of having both.
