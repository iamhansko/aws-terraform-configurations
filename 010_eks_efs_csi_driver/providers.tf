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
# Authenticates to the EKS cluster with the same "aws eks get-token" flow the
# _monolithic bastion relied on after "aws eks update-kubeconfig", so the
# StorageClass and demo workload can be applied without a kubeconfig file or a
# shell session on an EC2 instance (rules.md E-1).
#
# Uses alekc/kubectl instead of hashicorp/kubernetes: this root module creates
# the cluster and its Kubernetes objects in a single apply, and
# hashicorp/kubernetes fails at plan time with "cannot create REST client: no
# client config" because module.eks_cluster's endpoint and CA are still unknown
# when providers are configured. lazy_load defers building the real client until
# a kubectl_manifest resource is first used, by which point the cluster exists
# (rules.md E-2).
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
