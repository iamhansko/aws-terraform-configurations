terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    github  = { source = "integrations/github", version = "~> 6.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# The repository Argo CD syncs from is created here rather than assumed to exist. Nothing created it
# before, so following this project produced an Argo CD application pointing at a 404.
#
# owner and token come from the same two variables the CodeBuild source credential already uses, so
# the account this writes to is the account that variable names - there is no second place to
# configure. The token needs the repo scope; with delete_repo in scope as well, terraform destroy
# removes the repository.
provider "github" {
  owner = var.github_user
  token = var.github_token
}
# alekc/kubectl rather than hashicorp/kubernetes. The Role and RoleBinding that let Argo CD's
# repo-server read the Vault Secret go into a cluster this same apply creates, and
# hashicorp/kubernetes is configured during plan - when module.eks_cluster.cluster_endpoint is
# still unknown - so it fails with "Failed to construct REST client ... no client config".
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
# hashicorp/helm needs no such workaround: it does not contact the API server during plan, only
# during apply (rules.md E-2).
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
# No vault provider. It would be the obvious way to enable a secrets engine and write the demo
# secret, but every vault provider resource needs an address and a token - and the token only
# exists after "vault operator init", which runs inside the cluster during this same apply. That
# is circular, so those steps live in the bootstrap SSM Association in main.tf instead. It is the
# one documented exception to rules.md E-1 in this project.
