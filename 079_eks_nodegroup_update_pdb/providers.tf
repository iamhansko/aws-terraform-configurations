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
# alekc/kubectl rather than hashicorp/kubernetes. The Deployment and the
# PodDisruptionBudget go into a cluster this same apply creates, and
# hashicorp/kubernetes is configured during plan - when
# module.eks_cluster.cluster_endpoint is still unknown - so it fails with
# "Failed to construct REST client ... no client config". lazy_load defers building the
# client until a resource is first used, which is during apply, after the cluster exists
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
# No helm provider: nothing here installs a chart. The _monolithic template created an
# IRSA role for the AWS Load Balancer Controller and then never installed the controller,
# so the role, its trust policy and its inline policy - which granted ec2:* and
# elasticloadbalancing:* - existed for nothing. It is dropped rather than carried over
# (rules.md A-5).
