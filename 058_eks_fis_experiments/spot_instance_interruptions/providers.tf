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
# Both Kubernetes-facing providers authenticate the same way the _monolithic bastion did
# after "aws eks update-kubeconfig": an exec credential plugin calling
# "aws eks get-token". The difference is where the calls come from. That template ran one
# SSM association that shelled into the bastion and, in a single here-document, installed
# the Node Termination Handler and Karpenter with helm, then applied a NodePool, an
# EC2NodeClass and a Deployment with kubectl - none of which Terraform knew about
# (rules.md E-1). Here every one of those objects is a helm_release or a
# kubectl_manifest, so they appear in plan and are destroyed in order.
#
# helm needs no API server access at plan time, only at apply time, so hashicorp/helm
# works even though its configuration depends on a cluster this same apply creates
# (rules.md E-2).
provider "helm" {
  # Isolates chart resolution from whatever Helm state exists on the machine running
  # Terraform. Without these the provider uses Helm's own repositories.yaml and index
  # cache, and a leftover named repository whose URL matches a chart_repository here
  # makes the plan fail with "no cached repo found. (try 'helm repo update')". An empty
  # project-local directory means no named entry ever matches, so the index is fetched
  # from the URL directly.
  repository_config_path = "${path.root}/.terraform/helm/repositories.yaml"
  repository_cache       = "${path.root}/.terraform/helm/cache"

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
# NodePool and EC2NodeClass are custom resources whose CRDs the Karpenter chart installs
# in this same apply, and hashicorp/kubernetes's kubernetes_manifest needs a live API
# server at plan time to resolve a CRD's schema. alekc/kubectl's lazy_load defers
# building the client until a resource is first used, which is during apply, after the
# cluster and the CRDs exist (rules.md E-2/E-3).
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
