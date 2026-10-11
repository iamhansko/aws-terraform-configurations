terraform {
  required_providers {
    # aws and helm because the IAM role and the release reference each other: the release
    # annotates Teleport's service accounts with the role's ARN, and the role's policy is
    # scoped to the DynamoDB tables the release tells Teleport to create. Neither half is
    # useful alone (rules.md C-2).
    #
    # kubectl for the ClusterRoleBinding that gives Teleport's users a Kubernetes identity.
    # The group it binds is the one the add-user command writes into each user, so the two
    # are defined together here rather than split across modules.
    aws     = { source = "hashicorp/aws" }
    helm    = { source = "hashicorp/helm" }
    kubectl = { source = "alekc/kubectl" }
  }
}
