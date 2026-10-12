terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
  }
}
# The destination half of the cross-region, cross-account pair: this root builds the cluster a backup is
# restored into, and the bucket the other account replicates into. primary_account/ is the source half,
# and cluster/ is the single-account rehearsal that comes before both.
#
# This root is applied first. Its bucket has to exist before the other account's replication
# configuration can name it - S3 rejects a configuration whose destination is missing. Its bucket
# policy can still be written before that account's replication role exists, but not by naming the
# absent role directly: S3 rejects that as an invalid principal. The policy names the source account's
# always-existing root principal and narrows it to the agreed future role with aws:PrincipalArn. That
# condition-based grant is what breaks the circularity between the two roots without broadening access
# (rules.md I-2/I-4).
#
# No profile and no assume_role here, deliberately. Which account this applies into is decided by the
# credentials of whoever runs it, not by the configuration - that is what keeps one root from owning
# resources in two accounts, and it is the whole of rules.md I-1. The guard against applying it into the
# wrong account is a check block comparing data.aws_caller_identity against var.secondary_account_id,
# which is in main.tf.
provider "aws" {
  region = var.aws_region
}
# One cluster here, so one helm provider and one kubectl provider, both unaliased. The cluster variant
# needs aliases because it has two clusters in one root; this one does not, and adding aliases would
# mean every module needed a providers argument for no benefit (rules.md I-3).
#
# Both authenticate the same way the _monolithic bastion did after "aws eks update-kubeconfig": an exec
# credential plugin calling "aws eks get-token". The difference is where the calls come from - that
# template installed the load balancer controller with helm, applied the storage classes with kubectl,
# and ran a velero.sh it had just written, all from user data on the bastion (rules.md E-1). None of it
# was in state.
#
# Note what this root does not create: the workload. It arrives through a restore, which is the whole
# demonstration - the StatefulSet, its claims and the data in its volumes all come from the other
# account's backup rather than from this configuration.
#
# helm needs no API server access at plan time, only at apply time, so hashicorp/helm works even though
# its configuration depends on a cluster this same apply creates (rules.md E-2).
provider "helm" {
  # Isolates chart resolution from whatever Helm state exists on the machine running Terraform. Without
  # these the provider uses Helm's own repositories.yaml and index cache, and a leftover named
  # repository whose URL matches a chart_repository here makes the plan fail with "no cached repo
  # found. (try 'helm repo update')". An empty project-local directory means no named entry ever
  # matches.
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
# alekc/kubectl rather than hashicorp/kubernetes for the storage classes and the workload.
# VolumeSnapshotClass is a custom resource whose CRD the snapshot-controller addon installs in this same
# apply, and hashicorp/kubernetes needs the CRD present at plan time to resolve its schema. lazy_load
# defers building the client until a resource is first used, during apply, after both the cluster and
# the CRDs exist (rules.md E-2/E-3).
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
