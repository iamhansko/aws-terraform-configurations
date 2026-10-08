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
# The only non-AWS target in this repository, and the one the conversion asked for by name: the _monolithic
# template created the repository with AWS::CodeStar::GitHubRepository, and cfn2tf left "Use the GitHub
# provider" where the resource had been. Without it the repository the runners register with does not exist,
# the controller gets a 404 asking for a registration token, and no listener is ever created - with nothing in
# the apply reporting it (see modules/github_repository).
#
# Same token as the runners use, and it needs more than they do: a classic token needs repo scope to create a
# repository, a fine-grained one needs Administration: write plus Contents: write on the owner.
provider "github" {
  owner = var.github_owner
  token = var.github_token
}
# alekc/kubectl rather than hashicorp/kubernetes. The cluster is created in this same apply, so
# hashicorp/kubernetes - configured during plan, when module.eks_cluster.cluster_endpoint is still unknown -
# fails with "Failed to construct REST client ... no client config". lazy_load defers the client until the
# resource is first used, which is after the cluster exists (rules.md E-2).
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
# hashicorp/helm needs no workaround: it does not contact the API server during plan (rules.md E-2).
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
# Both providers reach the cluster from the machine running terraform, so endpoint_public_access has to stay
# true here - which its validation pins (rules.md E-9).
#
# No random provider. The _monolithic template generated a uuid to stand in for AWS::StackId so it could slice
# a suffix out of it for the key pair's name; the key pair is named from cluster_name here.
