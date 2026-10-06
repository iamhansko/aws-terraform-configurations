terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
    # alekc/kubectl, not hashicorp/kubernetes: the cluster these objects go into is created by the
    # same terraform apply, and a typed Kubernetes provider cannot be configured at plan time
    # against an endpoint that does not exist yet (rules.md E-2). The aws-auth patch also needs
    # server-side apply on a field of an object something else owns, which is a kubectl_manifest
    # argument rather than a typed resource's (rules.md E-6).
    kubectl = { source = "alekc/kubectl" }
  }
}
