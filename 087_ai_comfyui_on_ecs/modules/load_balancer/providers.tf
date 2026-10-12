terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
    tls = { source = "hashicorp/tls" }
    # One resource, and only because nothing else expresses it - see time_sleep.certificate_valid in main.tf,
    # which holds the ACM import back until the certificate it generated is valid by AWS's clock as well.
    time = { source = "hashicorp/time" }
  }
}
