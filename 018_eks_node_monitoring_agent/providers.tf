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
# No helm or kubectl provider, and no Karpenter - which is a consequence of this
# project having six clusters rather than one.
#
# A provider block is singular: it is configured with one host, one CA and one
# get-token invocation. The six clusters here are a for_each map, so there is no single
# cluster for a helm provider to point at, and "install Karpenter into each cluster"
# cannot be expressed as for_each over that map - every release would land on whichever
# cluster the one provider happened to name. Expressing it properly would mean six
# aliased helm providers written out by hand, which is exactly the repetition for_each
# removed from the rest of this configuration.
#
# The _monolithic template did not install Karpenter either. It created a Karpenter
# IRSA role per cluster and had an SSM association stage an install_karpenter.sh script
# in the bastion's home directory with the invocation commented out - six roles with
# nothing assuming them, and a script an operator was expected to run by hand. Those
# roles are dropped here rather than recreated: rules.md E-1 says not to install charts
# from a shell script, not to add an install the original deliberately left manual.
#
# Everything this project actually demonstrates - the Node Monitoring Agent, the
# conditions it reports, and node_repair_config acting on them - is an AWS API call, so
# the whole configuration applies with the AWS provider alone. That is also why the
# cluster endpoints need nothing special: nothing here talks to a Kubernetes API server
# at apply time.
