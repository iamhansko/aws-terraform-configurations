variable "name" {
  type        = string
  default     = "cli"
  description = "Name of the pod, cli as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the pod and its service account live in, as the _monolithic template had it. It is not incidental: both the IRSA trust policy's sub condition and the Pod Identity association name this namespace, so changing it here without changing them leaves the pod with no credentials of its own and falling back to the node's"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_account_name" {
  type        = string
  default     = "cli-sa"
  description = "Name of the service account the pod runs as, cli-sa as the _monolithic template had it. The same string appears in the IRSA trust policy's sub condition and in the Pod Identity association, so all three have to agree - and when they do not, the pod still starts and still has credentials, just the node's rather than its own"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "role_arn_annotation" {
  type        = string
  default     = null
  description = "IAM role ARN written into the service account's eks.amazonaws.com/role-arn annotation, which is how IRSA binds a role to a service account. Null leaves the annotation off - which is correct for the IMDS cluster, where the pod is meant to fall back to the node's credentials, and for the Pod Identity cluster, where the binding is an AWS-side association instead. The _monolithic template added it with a kubectl annotate call after applying the account (rules.md B-4)"

  validation {
    condition     = var.role_arn_annotation == null || can(regex("^arn:aws:iam::[0-9]{12}:role/", var.role_arn_annotation))
    error_message = "role_arn_annotation must be an IAM role ARN, or null to leave the annotation off."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/aws-cli/aws-cli:2.32.9"
  description = "Container image. The AWS CLI, which is all this pod is for - it runs nothing and exists to be exec'd into so \"aws sts get-caller-identity\" can be run from inside it. Pinned and from ECR Public, where the _monolithic template used amazon/aws-cli: docker.io's floating latest, from a registry that rate-limits anonymous pulls per source address, pulled three times over because there are three clusters"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must carry an explicit tag or a digest."
  }
}
variable "credential_mechanism" {
  type        = string
  description = "Which of the three mechanisms this pod is meant to get its credentials from: imds, irsa or pod_identity. No default. It changes nothing about the pod - that is the point, and it is worth stating in one place - but it is written onto the pod as a label so a cluster can be told apart from its siblings at a glance, and it is what this module validates the other inputs against"

  validation {
    condition     = contains(["imds", "irsa", "pod_identity"], var.credential_mechanism)
    error_message = "credential_mechanism must be imds, irsa or pod_identity."
  }
}
variable "automount_service_account_token" {
  type        = bool
  default     = true
  description = "Whether the pod gets its service account token mounted. True, which is the default and which both IRSA and Pod Identity need - IRSA exchanges a projected token for role credentials, and the Pod Identity agent does the same with a different token. Setting it false is a quick way to watch both mechanisms fall back to the node's credentials without any error appearing"
}
