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

# No kubectl, helm or kubernetes provider here, and that absence is deliberate -
# it is the only thing that distinguishes this root from the other EKS roots in
# this repository, and an absence cannot be found by grep, so it is written down.
#
# This cluster's API server has no public endpoint (var.endpoint_public_access is
# false and pinned false). A Terraform provider runs on the machine executing
# terraform apply, which is outside the VPC, so it cannot reach that endpoint at
# all. Declaring one would pass plan and then fail mid-apply with a dial timeout
# that looks exactly like the destroy-ordering problem rules.md D-4 describes.
#
# So the one Kubernetes-side thing this project installs - the AWS Load Balancer
# Controller chart - is installed by an SSM Association running helm on the
# workbench instance, which is inside the VPC. That is the exception rules.md E-9
# allows to rules.md E-1, and rules.md E-9 also lists what it costs: the release is
# not in Terraform state, nothing detects drift on it, and a failure arrives as
# "unexpected state 'Failed'" from SSM rather than as a Helm error.
#
# The same constraint is why modules/aws_load_balancer_controller_iam_role holds
# only the IAM role and its Pod Identity association. A module that declared a helm
# provider in its required_providers would make Terraform demand a helm provider
# configuration this root does not have - which is why the toggle approach
# ("install_chart = false" on a shared module) does not work either.
