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
# This configuration builds what awslabs/data-on-eks's schedulers/terraform/managed-airflow-mwaa
# blueprint built, at the last commit that still had it (1b7906b8, before #1103 removed it as
# unmaintained): the VPC, the EKS cluster and its add-ons, the cluster autoscaler, the EMR on EKS
# virtual cluster and the Amazon MWAA environment with its DAGs - plus the workbench instance the
# _monolithic template wrapped around them.
#
# The _monolithic template did not build any of that itself. Its instance cloned the blueprint and
# ran the blueprint's install.sh, a second Terraform run whose state lived on the instance's disk, so
# terraform plan here showed one instance and terraform destroy left the whole environment running.
# That nested run is gone. Every resource the blueprint made is a resource in this state, rewritten
# in this repository's module conventions rather than through the registry modules the blueprint
# called; the module comments name what each one replaces and what changed.
#
# alekc/kubectl rather than hashicorp/kubernetes, which the blueprint used for its namespaces, RBAC
# and the aws-auth entries. Those objects go into a cluster this same apply creates, and
# hashicorp/kubernetes is configured during plan - when module.eks_cluster.cluster_endpoint is still
# unknown - so it fails with "Failed to construct REST client ... no client config". lazy_load
# defers building the client until a resource is first used, which is during apply, after the
# cluster exists (rules.md E-2).
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
# hashicorp/helm needs no such workaround: it does not contact the API server during plan, only during
# apply (rules.md E-2). Used for the cluster autoscaler, the one add-on that is a chart rather than an
# EKS add-on.
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
