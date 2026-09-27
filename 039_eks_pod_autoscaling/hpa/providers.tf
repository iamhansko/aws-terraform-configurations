terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# alekc/kubectl, not hashicorp/kubernetes. This root module creates the cluster and
# the Deployment, Service and HorizontalPodAutoscaler inside it in one apply, and
# hashicorp/kubernetes fails at plan time because host and cluster_ca_certificate are
# still unknown then ("cannot create REST client: no client config"). lazy_load makes
# this provider defer building its client until a resource first needs it, which is
# during apply, after the cluster exists (rules.md E-2).
#
# No helm provider: nothing here is a chart. metrics-server, which the HPA depends on
# for measurements, is an EKS addon rather than a Helm release.
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
