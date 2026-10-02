terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# alekc/kubectl for the one raw manifest in this project: the default gp3 StorageClass every one of
# Sentry's eight volume claims resolves through. Everything else here is a Helm chart.
#
# alekc/kubectl rather than hashicorp/kubernetes because the cluster is created in this same apply,
# so module.eks_cluster.cluster_endpoint is unknown while Terraform configures providers during
# plan. lazy_load defers building the client to first use, which is during apply, after the cluster
# exists (rules.md E-2).
#
# load_config_file = false is not cosmetic, and this project learned that the hard way. Left at its
# default of true the provider falls back to ~/.kube/config, and since nothing in that fallback path
# involves module.eks_cluster, it silently talks to whatever cluster the operator's current context
# happens to name. The first apply after the StorageClass was added failed with:
#
#   Error: gp3 failed to create kubernetes rest client for update of resource:
#     Get "https://99A0CF44....sk1.ap-northeast-2.eks.amazonaws.com/api?timeout=32s":
#     dial tcp: lookup ...: no such host
#
# - a host belonging to a different, already deleted cluster in a different region, which was simply
# the current context at the time. The error looks like a networking or endpoint-access problem
# (rules.md E-9) and is neither. Worth noting what the good outcome would have been: had that
# context pointed at a live cluster, the manifest would have been applied to the wrong cluster and
# recorded in this project's state as a success.
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
# hashicorp/helm needs no such workaround: unlike hashicorp/kubernetes it does not contact the API
# server during plan, only during apply (rules.md E-2).
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
