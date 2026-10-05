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
# alekc/kubectl rather than hashicorp/kubernetes, and here for two reasons rather than one. The
# cluster is created in this same apply, so hashicorp/kubernetes - configured during plan, when
# module.eks_cluster.cluster_endpoint is still unknown - fails with "Failed to construct REST client
# ... no client config". And the NetworkAttachmentDefinition is a custom resource whose CRD is
# installed by another module in this same apply, which hashicorp/kubernetes cannot handle at all:
# it resolves a custom resource's schema at plan time (rules.md E-2/E-3).
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
# No helm provider: nothing here installs a chart. The _monolithic template installed the AWS Load
# Balancer Controller from user data and created a Pod Identity association and an IAM role granting
# it ec2:* and elasticloadbalancing:*, while nothing in the project creates a Service of type
# LoadBalancer or an Ingress. The controller, its role, its association and the
# eks-pod-identity-agent addon that existed only to serve that association are all dropped rather
# than carried over (rules.md A-5).
