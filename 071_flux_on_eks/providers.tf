terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    github  = { source = "integrations/github", version = "~> 6.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# alekc/kubectl rather than hashicorp/kubernetes. The StorageClass and Flux's own GitRepository
# and Kustomization go into a cluster this same apply creates, and hashicorp/kubernetes is
# configured during plan - when module.eks_cluster.cluster_endpoint is still unknown - so it
# fails with "Failed to construct REST client ... no client config". The two Flux objects make
# the case twice over: they are custom resources whose CRDs are installed by a Helm release in
# this same apply, and hashicorp/kubernetes needs a CRD present at plan time to resolve its
# schema (rules.md E-2/E-3).
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
# hashicorp/helm needs no such workaround: it does not contact the API server during plan, only
# during apply (rules.md E-2). Used here for the Flux controllers.
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
# Creates the GitOps repository Flux is pointed at. Both arguments come from variables rather than
# from the environment: the provider also reads GITHUB_TOKEN and GITHUB_OWNER, and letting it fall
# back to those would mean a plan whose target account depends on the shell it ran in - the same
# trap as a provider region taken from the environment chain.
#
# Configured at plan time from variables, which is why this provider raises none of the problems
# the kubectl comment above describes: nothing it needs is an unknown value.
provider "github" {
  owner = var.github_owner
  token = var.github_token
}
# No fluxcd/flux provider. Its flux_bootstrap_git resource would put Flux's self-management under
# Terraform, which is a different thing from what this project does - here the controllers are
# installed by the chart and Flux is pointed at a repository, rather than keeping its own
# manifests in one. Flux's own guidance now argues against installing Flux from Terraform at all,
# because every object Terraform applies becomes one Flux also wants to reconcile:
# https://fluxcd.io/blog/2026/04/terraform-flux-operator-bootstrap/
