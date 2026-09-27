terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# Both providers, because this variant has both kinds of work: KEDA and the AWS Load
# Balancer Controller are charts, and the workload plus the KEDA custom resources are
# Kubernetes objects.
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
# alekc/kubectl, not hashicorp/kubernetes. This root module creates the cluster and the
# objects inside it in one apply, and hashicorp/kubernetes fails at plan time because
# host and cluster_ca_certificate are still unknown then ("cannot create REST client:
# no client config"). lazy_load defers building the client until a resource first needs
# it, which is during apply, after the cluster exists (rules.md E-2).
#
# It matters twice over here: ScaledObject and TriggerAuthentication are custom
# resources, and kubernetes_manifest reads their CRDs from the API server during plan -
# so it would fail even against an existing cluster, because those CRDs arrive with the
# KEDA release in this same apply (rules.md E-3).
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
