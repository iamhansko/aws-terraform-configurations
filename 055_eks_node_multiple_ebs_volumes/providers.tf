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
# No kubectl or helm provider here, and nothing to configure for one.
#
# Every other EKS project in this repository declares at least one, because it creates
# objects inside the cluster. This one does not: what it demonstrates happens entirely
# below Kubernetes, in the launch template that gives each node a second EBS volume and
# puts the container runtime's state on it. There is nothing to apply to the API server,
# so adding a provider would only mean configuring a client nothing uses.
#
# The _monolithic template did declare one implicitly, by installing the AWS Load
# Balancer Controller from a helm command in userdata - along with an IRSA role and a
# policy granting ec2:* and elasticloadbalancing:*. Nothing in the project created an
# Ingress or a Service of type LoadBalancer for it to act on, and the helm command sat
# after an "exec bash" line that replaced the shell, so it never ran either way. All of
# it is dropped rather than carried over (rules.md E-1/H-1).
