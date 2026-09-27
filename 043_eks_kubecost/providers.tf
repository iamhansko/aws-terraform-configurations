terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# The StorageClass, the basic-auth Secret and the dashboard Ingress are raw
# manifests. alekc/kubectl rather than hashicorp/kubernetes: the latter fails at
# plan time with "cannot create REST client: no client config" when its host comes
# from a cluster that does not exist yet, because kubernetes_manifest fetches a
# resource schema during plan. lazy_load defers building the client until a
# manifest is first used, by which point the cluster exists (rules.md E-2).
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
# hashicorp/helm needs no workaround: it does not contact the cluster during plan,
# so the cluster and its releases apply together (rules.md E-2).
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
