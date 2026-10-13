terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# Two clusters in one root module, so every Kubernetes-side provider is declared twice with an alias and
# each module block says which one it uses.
#
# One AWS provider is enough: both clusters are in the same region and the same VPC, which is what makes
# this a comparison of two cluster configurations rather than of two regions (rules.md I-3 applies to the
# region case, not this one).
#
# alekc/kubectl rather than hashicorp/kubernetes, for the usual reason: both clusters are created in this
# same apply, so a provider configured at plan time - when cluster_endpoint is still unknown - fails with
# "Failed to construct REST client ... no client config". lazy_load defers building the client until a
# resource is first used (rules.md E-2).
provider "kubectl" {
  alias                  = "nvidia"
  host                   = module.nvidia_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.nvidia_eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.nvidia_eks_cluster.cluster_name]
  }
}
provider "kubectl" {
  alias                  = "time_slicing"
  host                   = module.time_slicing_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.time_slicing_eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.time_slicing_eks_cluster.cluster_name]
  }
}
# Each helm provider gets its own repository cache.
#
# Both install the same chart from the same repository, and with one shared cache directory the two
# releases can download the index and the chart archive into it concurrently. On Windows that is a file
# lock conflict rather than a harmless duplicate write, and it surfaces as
# "Error: Error locating chart ... Access is denied." - which reads like a missing chart rather than two
# writers. The duplicate download is the cost, and it is a few hundred kilobytes.
provider "helm" {
  alias = "nvidia"

  repository_config_path = "${path.root}/.terraform/helm/nvidia/repositories.yaml"
  repository_cache       = "${path.root}/.terraform/helm/nvidia/cache"

  kubernetes = {
    host                   = module.nvidia_eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.nvidia_eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.nvidia_eks_cluster.cluster_name]
    }
  }
}
provider "helm" {
  alias = "time_slicing"

  # A separate cache from the other provider's, for the reason given above.
  repository_config_path = "${path.root}/.terraform/helm/time-slicing/repositories.yaml"
  repository_cache       = "${path.root}/.terraform/helm/time-slicing/cache"

  kubernetes = {
    host                   = module.time_slicing_eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.time_slicing_eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.time_slicing_eks_cluster.cluster_name]
    }
  }
}
# No AWS Load Balancer Controller. The _monolithic template installed it on both clusters and created an
# IAM role granting it ec2:* and elasticloadbalancing:* plus a Pod Identity association per cluster,
# while neither cluster creates a Service of type LoadBalancer or an Ingress - the application pod
# publishes a container port with nothing in front of it. The controller, the role and both associations
# are dropped, and the application's interface is reached with kubectl port-forward, which is what the
# original required too without saying so (rules.md A-5).
