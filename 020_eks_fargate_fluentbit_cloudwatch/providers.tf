terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# Kubernetes objects use alekc/kubectl rather than hashicorp/kubernetes:
# hashicorp/kubernetes fails at plan time with "cannot create REST client: no
# client config" when its host/CA come from a cluster that does not exist yet.
# lazy_load defers building the real client until a kubectl_manifest resource is
# first used, by which point the cluster exists (rules.md E-2).
#
# This provider is why the cluster's API server endpoint is public here, unlike
# 019_eks_fargate which needed no Kubernetes provider at all: the provider runs
# on the machine executing terraform apply, not inside the VPC, so a private-only
# endpoint would make every kubectl_manifest unreachable. Narrow
# public_access_cidrs to your own address rather than leaving the default.
provider "kubectl" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
  }
}
