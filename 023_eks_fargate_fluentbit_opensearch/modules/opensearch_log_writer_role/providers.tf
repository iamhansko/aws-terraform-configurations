terraform {
  required_version = ">= 1.9"
  required_providers {
    # The security plugin's role and rolesmapping APIs live inside the domain, not
    # in the AWS control plane, so the AWS provider cannot express them - it can
    # only set the domain's IAM-side access policy. This is the same reasoning that
    # sends Kubernetes objects to a provider that talks to the API server rather
    # than to EKS (rules.md E-1).
    opensearch = { source = "opensearch-project/opensearch", version = "~> 2.3" }
  }
}
