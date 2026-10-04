terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}
# No helm provider here, deliberately. This module creates the controller's IAM role but not its Helm release,
# because the root module it belongs to has no helm provider to configure against a private API server
# (rules.md E-9). Declaring helm in required_providers - even without using it - would make Terraform demand
# that configuration anyway, which is why an "install_chart = false" toggle would not have worked either.
