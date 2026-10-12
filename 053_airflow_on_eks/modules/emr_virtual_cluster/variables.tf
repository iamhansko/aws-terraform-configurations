variable "cluster_name" {
  type        = string
  description = "EKS cluster the virtual cluster is backed by"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "namespace" {
  type        = string
  description = "Namespace the virtual cluster is bound to, taken from the module that authorised EMR in it rather than restated (rules.md B-5). CreateVirtualCluster reads this namespace as the service-linked role, and fails if the RBAC and the aws-auth mapping are not in place first (rules.md E-6)"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "account_id" {
  type        = string
  description = "Account the cluster is in. EMR puts it in the name of every job service account, so the trust policy's sub condition matches on it"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, the Federated principal in the job execution role's trust policy"
  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policy's condition keys"
  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
variable "name" {
  type        = string
  description = "Name of the EMR virtual cluster. Also the prefix of the job execution role's generated name, cut to 33 characters to stay within IAM's 38-character name_prefix limit"
  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9\\-_]{0,63}$", var.name))
    error_message = "name must be 1-64 characters, start with a letter or digit, and contain only letters, digits, hyphens and underscores."
  }
}
variable "log_group_name" {
  type        = string
  description = "CloudWatch log group a job's monitoringConfiguration writes to. The job execution role can write to this group and no other, so a DAG has to name exactly this - which is why the root renders it into the DAG rather than the DAG spelling it out (rules.md B-5)"
  validation {
    condition     = can(regex("^[\\.\\-_/#A-Za-z0-9]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and . - _ / #."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 7
  description = "Retention on the job log group. 7 days, the upstream module's default"
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention values CloudWatch Logs accepts."
  }
}
variable "additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies attached to the job execution role on top of its CloudWatch Logs policy. Everything the job may do with S3 comes from here"
  validation {
    condition     = alltrue([for arn in var.additional_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "additional_policy_arns must contain valid IAM policy ARNs."
  }
}
