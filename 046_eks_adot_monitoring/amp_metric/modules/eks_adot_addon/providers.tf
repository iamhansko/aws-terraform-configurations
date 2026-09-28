terraform {
  required_providers {
    # Both, because the IRSA roles and the add-on reference each other: the add-on's
    # configuration annotates each collector's service account with a role's ARN, and each
    # role's trust policy names the service account the add-on will create. Neither half is
    # useful alone (rules.md C-2).
    aws = { source = "hashicorp/aws" }
  }
}
