terraform {
  required_providers {
    # Three, because this module is one component with three halves that reference each
    # other: the IAM role the controller assumes, the chart that annotates its service
    # account with that role, and the ClusterIssuer that tells it which hosted zone to
    # write DNS-01 challenge records into. Splitting them would mean passing an ARN and a
    # namespace across module boundaries for no gain (rules.md C-2).
    aws     = { source = "hashicorp/aws" }
    helm    = { source = "hashicorp/helm" }
    kubectl = { source = "alekc/kubectl" }
  }
}
