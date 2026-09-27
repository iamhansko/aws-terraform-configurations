terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
    helm   = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# No kubectl provider here: every Kubernetes object in this project comes from a
# Helm chart, so there is no raw manifest to apply. hashicorp/helm needs no
# workaround for being pointed at a cluster created in the same apply - unlike
# hashicorp/kubernetes it does not contact the API server during plan
# (rules.md E-2).
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
