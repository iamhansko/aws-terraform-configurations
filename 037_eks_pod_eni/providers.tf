terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
  }
}

provider "aws" {
  region = var.aws_region
}

# Authenticates to the EKS cluster with the same aws eks get-token flow that
# the previous "aws eks update-kubeconfig" + kubectl userdata step relied on,
# so the SecurityGroupPolicy CRD can be applied without a kubeconfig file or
# a dedicated EC2 instance (rules.md E-1). Uses alekc/kubectl instead of
# hashicorp/kubernetes: kubectl_manifest doesn't need a live API server at
# plan time to resolve a resource's schema, and lazy_load defers building
# the actual client until first use, so this cluster (whose outputs
# configure this provider) and its SecurityGroupPolicy/demo pod manifests
# can be created together in a single `terraform apply` (rules.md E-2).
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
