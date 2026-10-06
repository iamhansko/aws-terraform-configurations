terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
    # alekc/kubectl rather than hashicorp/kubernetes. The workload's objects go into a
    # cluster this same apply creates, and a typed Kubernetes provider is configured during
    # plan - when the cluster endpoint is still unknown - so it fails with "no client
    # config" (rules.md E-2). alekc/kubectl is the maintained fork of gavinbunney/kubectl.
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

# lazy_load is what makes a single apply possible: it lets the provider be declared with a
# host that is unknown at plan time and defers building the REST client until a
# kubectl_manifest resource is used, by which point the cluster exists (rules.md E-2).
#
# Declaring this provider at all is legitimate because this cluster keeps a public API
# server endpoint - the provider runs wherever terraform runs (rules.md E-9).
# var.endpoint_public_access pins that decision.
#
# Aimed at the primary cluster only. The secondary one is the restore target: AWS Backup
# populates it, and Terraform deliberately puts nothing in it - an object created here would
# be a second owner of something a restore is about to write.
provider "kubectl" {
  host                   = module.primary_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.primary_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.primary_cluster.cluster_name]
  }
}

# helm needs no equivalent workaround: it only connects during apply, so hashicorp/helm is
# used as is (rules.md E-2).
provider "helm" {
  kubernetes = {
    host                   = module.primary_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.primary_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.primary_cluster.cluster_name]
    }
  }
}
