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
# Three providers, and no credential beyond the AWS one. The source this pipeline reads is a CodeCommit
# repository in this account, so the source stage is authorised by an IAM policy and the workbench pushes
# with its instance role - there is nothing here that needs a token, and nothing that can expire.

# hashicorp/helm for the AWS Load Balancer Controller, which is what turns the pipeline's Service into the
# NLB. It needs no workaround for being configured from a cluster created in the same apply, because it
# does not contact the API server during plan (rules.md E-2).
#
# Declaring helm in required_providers is not enough: without this block the provider initialises with an
# empty configuration, looks for a kubeconfig, and fails at apply with "Kubernetes cluster unreachable:
# invalid configuration: no configuration has been provided". init, validate and plan all pass, because
# nothing reads the cluster until the helm_release is created.
provider "helm" {
  kubernetes = {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      # --region is passed explicitly rather than left to the CLI's own default chain. get-token presigns a
      # regional STS call, and the cluster rejects a token signed for a different region - so if the AWS
      # provider takes its region from var.aws_region while the CLI resolves a different one from the
      # environment, this release fails with Unauthorized rather than anything that names the cause.
      args = ["eks", "get-token", "--region", data.aws_region.current.region, "--cluster-name", module.eks_cluster.cluster_name]
    }
  }
}
# No kubectl provider, and that is worth stating because every other EKS root in this repository has one.
# The workload here is not applied by Terraform at all: the pipeline's deploy stage applies the manifest,
# which is the thing being demonstrated. Terraform declares what the pipeline renders - the Deployment and
# Service are built as typed objects in modules/eks_deploy_pipeline and serialised into the buildspec - so
# the manifest is still reviewable in plan, but the object in the cluster belongs to the pipeline.
#
# The consequence is the one rules.md E-9 describes for its own case: those Kubernetes objects are not in
# Terraform state, so a destroy does not remove them. It does remove the cluster, which takes them with it,
# and the pre-created load balancer is a Terraform resource (rules.md G-3) - so the load balancer is not
# orphaned the way it would be if the Service alone owned it.
