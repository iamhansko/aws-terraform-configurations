terraform {
  required_version = ">= 1.9"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 6.0" }
    tls  = { source = "hashicorp/tls", version = "~> 4.0" }
    helm = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# hashicorp/helm for the AWS Load Balancer Controller. It needs no workaround for being configured from a
# cluster created in the same apply, because it does not contact the API server during plan (rules.md E-2).
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
# No kubectl provider: nothing here applies a raw manifest. The GPU workload is left for the user to write,
# which is the exercise - the project is about whether a node with reserved GPU capacity comes up at all.
#
# The NVIDIA device plugin is a helm_release for the same reason, and the reason is worth stating because the
# obvious alternative is not available. Its time-slicing configuration lives in a ConfigMap, and declaring
# one would need the kubectl provider (rules.md E-2) - so a variant that wants time slicing has to add that
# provider here. This one does not: one GPU advertised as one GPU is the whole point of a project about
# whether reserved capacity materialises. 030_emr_on_eks is where the time-slicing form of this module lives.
#
# No random provider. The _monolithic template generated a uuid to stand in for AWS::StackId so it could slice
# a suffix out of it for the key pair's name; the key pair is named from cluster_name here.
