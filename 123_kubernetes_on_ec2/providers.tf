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

# No kubectl, helm or kubernetes provider here, and unlike the EKS roots in this
# repository that is not a choice - it is not possible.
#
# rules.md E-1 says Kubernetes objects belong in provider resources, and rules.md E-2
# says alekc/kubectl is what makes that work when the cluster is created by the same
# apply. Both assume the cluster has an endpoint and a CA certificate Terraform can
# learn: for an EKS cluster those are attributes of aws_eks_cluster. This cluster is
# built by kubeadm on an EC2 instance, so its API server address is a private VPC
# address and its CA is generated during boot, inside the instance. Nothing in the
# Terraform graph ever holds either value.
#
# So every Kubernetes object here - Calico, Traefik, the whoami Deployment, Service
# and Ingress - is applied by an SSM Association running kubectl and helm on the
# workbench, which downloaded the admin kubeconfig from the handoff bucket. That is
# the shape rules.md E-9 defines for a private EKS endpoint, applied for a stronger
# reason, and it carries the same costs rules.md E-9 lists:
#
#   - none of those objects is in Terraform state, so nothing detects drift on them
#     and terraform destroy removes none of them;
#   - every value passes through a shell, so quoting, newlines and "$" are all
#     surfaces;
#   - a failure arrives as "unexpected state 'Failed'" from SSM, and the real cause
#     has to be dug out with describe-association-executions,
#     describe-association-execution-targets and get-command-invocation
#     (rules.md A-4 documents that sequence).
#
# What is kept from rules.md E-3 is the manifests themselves: they are HCL objects
# rendered with yamlencode, not YAML pasted into a shell script, so the pod CIDR that
# kubeadm is given and the pod CIDR Calico is configured with come from one variable.
