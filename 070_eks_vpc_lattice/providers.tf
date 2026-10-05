terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# alekc/kubectl rather than hashicorp/kubernetes, and here the second reason matters more than the
# first. The cluster is created in this same apply, so hashicorp/kubernetes - configured during plan,
# when module.eks_cluster.cluster_endpoint is still unknown - fails with "Failed to construct REST
# client ... no client config". And almost every Kubernetes object in this project is a custom resource
# whose CRD is installed by another module in the same run: GatewayClass, Gateway and HTTPRoute all come
# from the Gateway API bundle. hashicorp/kubernetes resolves a custom resource's schema at plan time and
# cannot do that for a CRD that does not exist yet (rules.md E-2/E-3).
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
# apply (rules.md E-2). Used here for the AWS Gateway API Controller.
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
# hashicorp/http fetches the pinned Gateway API CRD bundle at plan time, so its documents - and
# therefore the resource addresses they become - are known before apply. It is the one provider here
# that makes terraform plan need network access to something other than AWS, which is a real cost and
# the reason the URL is overridable (see modules/gateway_api_crds).
