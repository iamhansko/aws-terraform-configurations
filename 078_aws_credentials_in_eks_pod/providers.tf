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
# Three clusters in one root module, so the kubectl provider is declared three times with an alias and
# each module block says which one it uses.
#
# One AWS provider is enough: all three clusters are in the same region and the same VPC, which is what
# makes this a comparison of three credential mechanisms rather than of three environments
# (rules.md I-3 applies to the cross-region case, not this one).
#
# alekc/kubectl rather than hashicorp/kubernetes, for the usual reason: the clusters are created in this
# same apply, so a provider configured at plan time - when cluster_endpoint is still unknown - fails with
# "Failed to construct REST client ... no client config". lazy_load defers building the client until a
# resource is first used (rules.md E-2).
provider "kubectl" {
  alias                  = "imds"
  host                   = module.imds_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.imds_eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.imds_eks_cluster.cluster_name]
  }
}
provider "kubectl" {
  alias                  = "irsa"
  host                   = module.irsa_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.irsa_eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.irsa_eks_cluster.cluster_name]
  }
}
provider "kubectl" {
  alias                  = "pod_identity"
  host                   = module.pod_identity_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.pod_identity_eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.pod_identity_eks_cluster.cluster_name]
  }
}
# No helm provider: nothing here installs a chart. The whole project is three clusters, one pod each and
# the IAM around them.
