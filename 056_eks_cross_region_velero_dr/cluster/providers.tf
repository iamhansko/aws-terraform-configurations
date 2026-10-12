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
# What this variant is, and what it is not.
#
# The project's name says cross-region, and that is what primary_account/ and secondary_account/ do:
# two roots, two accounts, two regions, with S3 replication carrying the backups between them. This
# variant is the rehearsal that comes before it - two clusters in one account and one region, sharing
# one VPC and one backup bucket, so a backup taken on one cluster can be restored onto the other
# without any cross-account machinery in the way.
#
# That is deliberately what the _monolithic template built, and it is worth saying so plainly because
# the resource names invite the opposite reading: it called its clusters primary_cluster and
# secondary_cluster while giving both the same subnet list, the same region and the same bucket
# (rules.md I-3 is about exactly that - a name that implies a region boundary that is not there).
# Nothing here is cross-region. The value of the rehearsal is that everything except the region
# boundary is real: two clusters, two Velero installations, a volume with data in it, and a restore
# that has to recreate that volume from a snapshot in a cluster that never saw it.
#
# Two AWS providers are not needed for that, so there are none - a second provider alias would be the
# right way to split regions inside one account (rules.md I-3), and adding one without a second
# network would only look like cross-region without being it.
#
# Two helm providers and two kubectl providers are needed, because each cluster has its own API
# server endpoint and its own credentials. Both authenticate the same way the _monolithic bastion did
# after "aws eks update-kubeconfig": an exec credential plugin calling "aws eks get-token". The
# difference is where the calls come from - that template ran one SSM-less user data script that
# installed the load balancer controller with helm, applied the storage classes and the StatefulSet
# with kubectl, and ran a velero.sh it had just written, once per cluster (rules.md E-1). None of it
# was in state.
#
# One bug in that script is worth recording because it produces no error at all: the second helm
# install, the one aimed at the secondary cluster, still passed --set clusterName=<primary cluster>.
# See modules/aws_load_balancer_controller.
provider "helm" {
  alias = "primary"
  # Isolates chart resolution from whatever Helm state exists on the machine running Terraform.
  # Without these the provider uses Helm's own repositories.yaml and index cache, and a leftover
  # named repository whose URL matches a chart_repository here makes the plan fail with "no cached
  # repo found. (try 'helm repo update')". An empty project-local directory means no named entry ever
  # matches.
  #
  # A cache directory per provider, not one shared between them. Both providers install the same two
  # charts, and with one cache they race to download them: each writes a temporary file and renames it
  # into place, and the second rename fails because the first provider still holds the target. On
  # Windows that surfaces during plan as
  #
  #   Error: Error locating chart
  #   Unable to locate chart aws-load-balancer-controller: link error: cannot rename
  #   ...aws-load-balancer-controller-1.14.1.tgz3335701678 to ...tgz: Access is denied.
  #
  # which reads like a missing chart rather than two writers. The duplicate download is the cost, and
  # it is a few hundred kilobytes.
  repository_config_path = "${path.root}/.terraform/helm/primary/repositories.yaml"
  repository_cache       = "${path.root}/.terraform/helm/primary/cache"

  kubernetes = {
    host                   = module.primary_eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.primary_eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.primary_eks_cluster.cluster_name]
    }
  }
}
provider "helm" {
  alias = "secondary"

  # A separate cache from the primary provider's, for the reason given above.
  repository_config_path = "${path.root}/.terraform/helm/secondary/repositories.yaml"
  repository_cache       = "${path.root}/.terraform/helm/secondary/cache"

  kubernetes = {
    host                   = module.secondary_eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.secondary_eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.secondary_eks_cluster.cluster_name]
    }
  }
}
# alekc/kubectl rather than hashicorp/kubernetes for the storage classes and the workload.
# VolumeSnapshotClass is a custom resource whose CRD the snapshot-controller addon installs in this
# same apply, and hashicorp/kubernetes needs the CRD present at plan time to resolve its schema -
# which is impossible here. lazy_load defers building the client until a resource is first used,
# during apply, after both the cluster and the CRDs exist (rules.md E-2/E-3).
#
# Both aliases are named, including the primary one: an unaliased default provider would be inherited
# by any module that forgot its providers argument, and that module would then apply to the primary
# cluster silently. With no default, forgetting it is a configuration error instead (rules.md I-3).
provider "kubectl" {
  alias                  = "primary"
  host                   = module.primary_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.primary_eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.primary_eks_cluster.cluster_name]
  }
}
provider "kubectl" {
  alias                  = "secondary"
  host                   = module.secondary_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.secondary_eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.secondary_eks_cluster.cluster_name]
  }
}
