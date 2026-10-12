terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
    # alekc/kubectl rather than hashicorp/kubernetes. The Kubernetes objects this root
    # declares are Karpenter's EC2NodeClass and NodePool - custom resources whose CRDs are
    # installed by a Helm release in this same apply, so a typed provider would need both
    # the cluster endpoint and those schemas at plan time and fails with "no client
    # config" (rules.md E-2/E-3). alekc/kubectl is the maintained fork of
    # gavinbunney/kubectl.
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

# One thing in this project is deliberately NOT a provider resource: Kubeflow itself.
#
# rules.md E-1 says Kubernetes objects belong in provider resources, and rules.md E-2 says
# alekc/kubectl is how that works when the cluster is created by the same apply. Every
# other Kubernetes object here follows that - the Karpenter pools, the device plugin, the
# load balancer controller. Kubeflow does not, and the reason is what it is rather than
# where the cluster is:
#
#   - it is installed by building a kustomization out of a git repository, which no
#     Terraform data source can do - data.http can fetch a URL (070_eks_gateway_api does
#     exactly that for the Gateway API CRD bundle), but it cannot run kustomize;
#   - the build produces on the order of a thousand objects, including CRDs and the custom
#     resources that use them, so it is not a set anyone can enumerate as resources;
#   - the bundle is applied repeatedly on purpose, because the first pass always fails on
#     kinds whose CRDs the same pass is installing.
#
# So the install is an SSM Association running kubectl on the bastion, which is the shape
# rules.md E-9 defines for a private endpoint, used here for a different reason. The costs
# rules.md E-9 lists apply unchanged: nothing Kubeflow creates is in Terraform state,
# nothing detects drift on it, terraform destroy removes none of it, and a failure arrives
# as "unexpected state 'Failed'" from SSM rather than as a kubectl error.
#
# What is fixed relative to the _monolithic template is the part that could be: the git ref
# is pinned to a release tag instead of tracking the default branch, and the retry loop is
# bounded instead of running until the association's own timeout.
