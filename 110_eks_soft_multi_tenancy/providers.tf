terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# alekc/kubectl rather than hashicorp/kubernetes. The cluster is created in this same apply, so
# hashicorp/kubernetes - configured during plan, when module.eks_cluster.cluster_endpoint is still unknown -
# fails with "Failed to construct REST client ... no client config". lazy_load defers the client until a
# resource is first used, which is after the cluster exists (rules.md E-2).
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
# hashicorp/helm for the AWS Load Balancer Controller, which needs no workaround: it does not contact the API
# server during plan (rules.md E-2).
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
# Both providers reach the cluster from the machine running terraform, so endpoint_public_access has to stay
# true here - which its validation pins (rules.md E-9).
#
# No random provider. The _monolithic template generated a uuid to stand in for AWS::StackId so it could slice a
# suffix out of it for the key pair's name; the key pair is named from cluster_name here.
