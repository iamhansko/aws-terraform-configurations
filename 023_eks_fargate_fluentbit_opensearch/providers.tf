terraform {
  required_version = ">= 1.9"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    tls        = { source = "hashicorp/tls", version = "~> 4.0" }
    kubectl    = { source = "alekc/kubectl", version = "~> 2.4" }
    opensearch = { source = "opensearch-project/opensearch", version = "~> 2.3" }
  }
}
provider "aws" {
  region = var.aws_region
}
# Fine-grained access control is configured through the domain's own HTTP API, not
# through the AWS control plane, so the AWS provider cannot reach it. This provider
# is what turns the _monolithic template's src/client.py - a script someone ran by
# hand against a live domain - into declared resources (rules.md E-1).
#
# Unlike hashicorp/kubernetes, this provider is safe to point at a domain created
# in the same apply (rules.md E-2). Terraform defers configuring a provider whose
# arguments are still unknown at plan time, and none of this provider's resources
# do plan-time reads - which is precisely what kubernetes_manifest does, and why
# that one fails here. Verified by planning a roles mapping against an endpoint
# derived from a not-yet-created resource: the plan succeeds.
#
# Basic auth as the master user, because the domain has an internal user database.
# sign_aws_requests has to be off for that: left at its default the provider signs
# with SigV4 and ignores these credentials, and the domain answers 403.
provider "opensearch" {
  url               = "https://${module.opensearch_domain.endpoint}"
  username          = var.opensearch_master_user_name
  password          = var.opensearch_master_user_password
  sign_aws_requests = false
  # Health checking and sniffing both probe individual nodes, which a managed
  # domain does not expose - it publishes one endpoint in front of them. Left on,
  # the client decides it has no reachable node and fails before sending anything.
  healthcheck = false
  sniff       = false
}
# Kubernetes objects use alekc/kubectl rather than hashicorp/kubernetes:
# hashicorp/kubernetes fails at plan time with "cannot create REST client: no
# client config" when its host/CA come from a cluster that does not exist yet.
# lazy_load defers building the real client until a kubectl_manifest resource is
# first used, by which point the cluster exists (rules.md E-2).
#
# This provider is why the cluster's API server endpoint is public here, unlike
# 019_eks_fargate which needed no Kubernetes provider at all: the provider runs
# on the machine executing terraform apply, not inside the VPC, so a private-only
# endpoint would make every kubectl_manifest unreachable. Narrow
# public_access_cidrs to your own address rather than leaving the default.
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
