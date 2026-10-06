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
# Both Kubernetes-facing providers authenticate with the same "aws eks
# get-token" flow the _monolithic bastion used after "aws eks
# update-kubeconfig". The _monolithic design went much further than that: an SSM
# association ran "eksctl create cluster" on the bastion to build the cluster
# itself, then a cloned shell script installed Karpenter. Here the cluster is
# aws_eks_cluster and Karpenter is helm_release plus kubectl_manifest, so all of
# it is in Terraform state and visible to terraform plan (rules.md E-1).
#
# helm needs no API server access at plan time, only at apply time, so
# hashicorp/helm works even though its configuration depends on a cluster
# created in this same apply.
provider "helm" {
  # Isolates chart resolution from whatever Helm state happens to exist on the
  # machine running Terraform. Without these, the provider uses Helm's own
  # defaults - repositories.yaml under %APPDATA%\helm (or ~/.config/helm) and the
  # index cache under %TEMP%\helm\repository. If that repositories.yaml already
  # has a named entry whose URL matches a chart_repository here (a leftover
  # "helm repo add eks https://aws.github.io/eks-charts", say), the provider
  # resolves the chart through that name and reads <cache>/<name>-index.yaml -
  # a file only "helm repo update" creates, and one that %TEMP% cleanup removes.
  # When it is missing the plan fails with "Unable to locate chart <chart>: no
  # cached repo found. (try 'helm repo update')", naming an index file that can
  # even belong to a different repository than the one being resolved.
  #
  # Pointing both at an empty project-local directory means no named entry ever
  # matches, so the index is fetched straight from the chart_repository URL and
  # the result no longer depends on the operator's machine having run
  # "helm repo update". Living under .terraform keeps it out of git and lets
  # deleting .terraform reset it.
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
# Karpenter's NodePool and EC2NodeClass are custom resources, and
# hashicorp/kubernetes's kubernetes_manifest needs a live API server at plan
# time to resolve a CRD's schema - impossible when the cluster and the CRDs are
# created in the same apply. alekc/kubectl's lazy_load defers building the
# client until first use (rules.md E-3/E-2).
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
