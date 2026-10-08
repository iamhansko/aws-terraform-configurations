terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
    # Only for one resource, and only because nothing else here can express what it expresses - see
    # time_sleep.role_propagation in main.tf, which closes the gap between CreateRole returning and
    # the trust policy being visible to the EKS capabilities service.
    time = { source = "hashicorp/time", version = "~> 0.12" }
  }
}
