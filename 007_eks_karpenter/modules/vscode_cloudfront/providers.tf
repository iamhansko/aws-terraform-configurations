terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
    # For the suffix that keeps the cache policy name unique in the account. It needs no configuration, so
    # there is no provider block for it in the root - a module may use such a provider through its implicit
    # default configuration (rules.md A-2).
    random = { source = "hashicorp/random" }
  }
}
