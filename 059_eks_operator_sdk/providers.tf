terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# No kubectl or helm provider, and that is a deliberate exception to rules.md E-1 rather
# than an oversight. It is worth being explicit about, because an absent provider cannot
# be found with grep.
#
# E-1 says Kubernetes objects belong in Terraform resources instead of shell commands, and
# every other EKS project here follows it. This one cannot, because the objects do not
# exist as anything Terraform could declare until a code generator has run:
#
#   operator-sdk init / create api  scaffolds a Go project - source files, a Makefile, a
#                                   CRD, a controller. There is no Terraform resource for
#                                   "generate a repository".
#   make docker-build / docker-push builds a container image from that source, which needs
#                                   a Docker daemon (rules.md H-1).
#   make deploy                     applies the manifests kustomize renders from that
#                                   generated tree. They are an output of the scaffolding,
#                                   so they cannot be written here in advance.
#
# So the three SSM Association steps in main.tf are the work, not a shortcut around it -
# the same exception 049_eks_argocd_vault makes for "vault operator init". What Terraform
# does own is everything those steps need: the cluster, the nodes, the registry, and the
# instance's access to all three.
#
# The cost is the one rules.md E-9 lists: the operator, its CRD and the sample custom
# resource are not in state, so plan shows no diff for them and destroy does not remove
# them. Destroying the cluster takes them with it, which is why nothing here depends on
# that ordering.
