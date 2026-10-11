terraform {
  # 1.14, above the repository's 1.9, for one feature: the aws_codebuild_start_build action that builds the
  # ComfyUI image during the apply and holds the Deployment until the image exists (main.tf). Nothing else
  # here needs more than 1.9.
  required_version = ">= 1.14"
  required_providers {
    # ~> 6.24 rather than the repository's ~> 6.0: the regional NAT gateway arrived in 6.24 and the
    # aws_codebuild_start_build action in 6.15, and an older 6.x fails on either with an error about an
    # unsupported argument or action type rather than about a version. Still major version 6.
    aws     = { source = "hashicorp/aws", version = "~> 6.24" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    # alekc/kubectl rather than hashicorp/kubernetes. The Karpenter pool, the Mountpoint volumes and the
    # ComfyUI objects are applied in the same terraform apply that creates the cluster, and a typed provider
    # would need the cluster endpoint - and for the Karpenter CRDs, their schemas - at plan time
    # (rules.md E-2/E-3).
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

# What this configuration is, after the change.
#
# It used to build a workbench and nothing else: an Ubuntu instance that cloned aws-samples/comfyui-on-eks and
# ran the blueprint's own auto_deploy scripts, so the cluster, the GPU pool, the buckets, the image and the
# CloudFront distribution came from a CDK application whose state lived in CloudFormation stacks this
# configuration never saw. Every one of those is a resource here now, and nothing is cloned at apply time -
# the parts of the blueprint that are not infrastructure (the Dockerfile and its custom nodes, the model
# download script, the sync Lambda's code) are kept in this directory and shipped from it.
#
# The kubectl and helm providers below run on the machine executing terraform, which is what
# var.endpoint_public_access pins (rules.md E-9).
#
# lazy_load is what makes a single apply possible: the provider is declared with a host that is unknown at
# plan time, and the REST client is built only when a kubectl_manifest is first used, by which point the
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

# helm needs no equivalent workaround: it only connects during apply (rules.md E-2).
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
