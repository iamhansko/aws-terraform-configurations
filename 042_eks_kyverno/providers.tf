terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# The Grafana and GrafanaDatasource custom resources are raw manifests against CRDs
# the grafana-operator installs. alekc/kubectl rather than hashicorp/kubernetes:
# kubernetes_manifest resolves a resource schema from the API server during plan,
# which fails both for a cluster that does not exist yet and for a CRD that has not
# been installed yet. lazy_load defers building the client until first use
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
