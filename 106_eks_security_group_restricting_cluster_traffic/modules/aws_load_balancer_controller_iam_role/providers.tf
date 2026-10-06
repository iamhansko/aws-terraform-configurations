terraform {
  required_providers {
    # aws only, deliberately. The controller's chart is installed by an SSM
    # Association on the bastion rather than by a helm provider, because this
    # cluster's API server endpoint is private - so declaring helm here would make
    # Terraform require a helm provider configuration the root module does not have.
    aws = { source = "hashicorp/aws" }
  }
}
