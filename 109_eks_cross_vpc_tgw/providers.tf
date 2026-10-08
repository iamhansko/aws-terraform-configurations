terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
    # alekc/kubectl rather than hashicorp/kubernetes. The workload manifests go into clusters this
    # same apply creates, and a typed Kubernetes provider is configured during plan - when the
    # cluster endpoints are still unknown - so it fails with "no client config" (rules.md E-2).
    # alekc/kubectl is the maintained fork of gavinbunney/kubectl.
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

# Two clusters means two of every cluster-scoped provider, distinguished by alias. A module that
# talks to a cluster is handed the right one through its providers argument; there is no default
# kubectl or helm provider on purpose, so a module that forgets to ask fails at init rather than
# writing into whichever cluster happened to be configured first.
#
# lazy_load is what makes a single apply possible: it lets a provider be declared with a host that
# is unknown at plan time and defers building the REST client until a kubectl_manifest resource is
# used, by which point the cluster exists (rules.md E-2).
#
# Declaring these providers at all is legitimate because both clusters keep a public API server
# endpoint - a provider runs wherever terraform runs (rules.md E-9). var.endpoint_public_access
# pins that decision.
provider "kubectl" {
  alias = "vpc_a"

  host                   = module.vpc_a_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.vpc_a_eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.vpc_a_eks_cluster.cluster_name]
  }
}

provider "kubectl" {
  alias = "vpc_b"

  host                   = module.vpc_b_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.vpc_b_eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.vpc_b_eks_cluster.cluster_name]
  }
}

# helm needs no equivalent workaround: it only connects during apply, so hashicorp/helm is used as
# is - but it still needs one configuration per cluster (rules.md E-2).
provider "helm" {
  alias = "vpc_a"

  kubernetes = {
    host                   = module.vpc_a_eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.vpc_a_eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.vpc_a_eks_cluster.cluster_name]
    }
  }
}

provider "helm" {
  alias = "vpc_b"

  kubernetes = {
    host                   = module.vpc_b_eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.vpc_b_eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.vpc_b_eks_cluster.cluster_name]
    }
  }
}
