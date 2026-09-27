terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    helm   = { source = "hashicorp/helm", version = "~> 3.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# helm, and no kubectl provider: the one thing this variant installs is a chart, and
# the autoscaler's configuration travels as chart values rather than as a Kubernetes
# object of its own. hashicorp/helm is used directly because it does not need to
# reach the API server during plan, so it works in the same apply that creates the
# cluster - which is the constraint that forces alekc/kubectl on Kubernetes
# resources elsewhere in this repository (rules.md E-2).
#
# The sibling addon_autoscaling_coredns variant gets the same CoreDNS scaling from
# the coredns addon's own autoScaling configuration and so declares no helm provider
# at all. Comparing the two root modules is the point of having both.
provider "helm" {
  kubernetes = {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
    }
  }
}
