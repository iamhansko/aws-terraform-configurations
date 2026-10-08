variable "cluster_name" {
  type        = string
  description = "Cluster the access entries are created on. Passed in from the module that created it (rules.md B-5)"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "tenants" {
  type        = map(string)
  description = <<-DESC
    Tenants, as a map of a caller-chosen label to the namespace that tenant's role may edit.

    A map rather than a list because the keys become resource addresses, and they are labels defined in the
    configuration rather than values discovered at apply time (rules.md B-8). The namespace is the value
    because that is the whole point of the module: one IAM role per tenant, each scoped to one namespace.
  DESC

  validation {
    condition     = length(var.tenants) > 0
    error_message = "tenants must name at least one tenant - a soft multi-tenancy demo with no tenants has nothing to demonstrate."
  }
  validation {
    condition     = alltrue([for label in keys(var.tenants) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "tenants keys are labels used in resource addresses and role names, so each must be letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for namespace in values(var.tenants) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", namespace))])
    error_message = "tenants values must be valid lowercase RFC 1123 DNS labels - they are Kubernetes namespace names."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix for each tenant's role name; the tenant label is appended. The _monolithic template used tenant-a-role-<stack> and tenant-b-role-<stack>, which is the same shape"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,40}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-40 characters from the set IAM accepts for a role name, leaving room for the tenant label."
  }
}
variable "trusted_principal_arns" {
  type        = list(string)
  description = <<-DESC
    Principals allowed to assume the tenant roles.

    The _monolithic template trusted arn:aws:iam::<account>:root - the whole account - which means any
    principal in it with sts:AssumeRole permission can become either tenant. For a demo where the point is to
    switch between tenants from the workbench that is workable, but it makes the roles a weaker boundary than
    they look: the isolation being demonstrated is Kubernetes-side, not IAM-side.

    Naming the workbench's role here instead is tighter and still lets the demo work, which is what the caller
    does.
  DESC

  validation {
    condition     = length(var.trusted_principal_arns) > 0
    error_message = "trusted_principal_arns must name at least one principal - a role nobody can assume cannot be used to demonstrate anything."
  }
  validation {
    condition     = alltrue([for arn in var.trusted_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(root|role/|user/)", arn))])
    error_message = "trusted_principal_arns must contain IAM principal ARNs - an account root, a role or a user."
  }
}
variable "access_policy_arn" {
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  description = <<-DESC
    Access policy each tenant's role is granted, scoped to that tenant's namespace. Edit as the _monolithic
    template granted it: create, update and delete workloads, but not RBAC and not cluster-scoped objects.

    The scoping is what makes this soft multi-tenancy rather than shared admin - the same policy with a cluster
    scope would let either tenant read the other's Secrets.
  DESC

  validation {
    condition     = can(regex("^arn:aws:eks::aws:cluster-access-policy/", var.access_policy_arn))
    error_message = "access_policy_arn must be an EKS cluster access policy ARN."
  }
}
variable "session_duration" {
  type        = number
  default     = 3600
  description = "How long an assumed tenant session lasts. One hour, IAM's default stated explicitly"

  validation {
    condition     = var.session_duration >= 3600 && var.session_duration <= 43200
    error_message = "session_duration must be between 3600 and 43200 seconds - IAM's own range."
  }
}
