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
# Both Kubernetes-facing providers authenticate the same way the _monolithic bastion did after
# "aws eks update-kubeconfig": an exec credential plugin calling "aws eks get-token". What
# changes is where the calls come from. That template ran an SSM association which shelled into
# the bastion and, inside a single here-document, helm-installed the termination handler and
# kubectl-applied the demo Deployment - so neither was in Terraform state: no diff in plan,
# nothing removed on destroy, and a YAML error would have surfaced only in the association's
# output (rules.md E-1). It also shipped a Lambda-backed CloudFormation custom resource whose
# only job was to look up the Auto Scaling group behind each node group; the provider exposes
# that field directly, so the Lambda, its IAM role, its policy and its Python source are deleted
# rather than converted (see modules/asg_lifecycle_hooks).
#
# helm needs no API server access at plan time, only at apply time, so hashicorp/helm works
# even though its configuration depends on a cluster this same apply creates (rules.md E-2).
provider "helm" {
  # Isolates chart resolution from whatever Helm state exists on the machine running Terraform.
  # Without these the provider uses Helm's own repositories.yaml and index cache, and a leftover
  # named repository whose URL matches a chart here makes the plan fail with "no cached repo
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
# alekc/kubectl rather than hashicorp/kubernetes for the demo Deployment and its disruption
# budget. hashicorp/kubernetes is configured during plan, when module.eks_cluster.cluster_endpoint
# is still unknown, so it fails with "Failed to construct REST client ... no client config".
# lazy_load defers building the client until a resource is first used, which is during apply,
# after the cluster exists (rules.md E-2).
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
