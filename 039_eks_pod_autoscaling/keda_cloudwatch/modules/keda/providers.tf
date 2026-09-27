terraform {
  required_providers {
    # Both, because this module owns an IAM role and the chart that consumes it. The
    # release reads the role's ARN straight off the aws_iam_role resource next to it
    # rather than taking it as a variable: IRSA is one component, and splitting the
    # role from the chart that annotates its service account with it would only make
    # the pair harder to keep in agreement (rules.md C-2).
    aws  = { source = "hashicorp/aws" }
    helm = { source = "hashicorp/helm" }
  }
}
