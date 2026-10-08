variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the capability is installed on"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "name" {
  type        = string
  description = "Name of the capability, unique within the cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.name))
    error_message = "name must be 1-63 characters of letters, digits and hyphens, starting with a letter or digit."
  }
}

variable "type" {
  type        = string
  description = "Which capability to install: ACK, KRO or ARGOCD"

  validation {
    # A fixed enum the EKS API defines, so contains() rather than a regex (rules.md B-2). A value
    # outside this set is rejected by the API at apply time, well after the cluster exists.
    condition     = contains(["ACK", "KRO", "ARGOCD"], var.type)
    error_message = "type must be one of ACK, KRO or ARGOCD."
  }
}

variable "delete_propagation_policy" {
  type        = string
  default     = "RETAIN"
  description = "What happens to the Kubernetes objects the capability created when the capability is deleted. RETAIN is currently the only value the EKS API accepts"

  validation {
    condition     = contains(["RETAIN"], var.delete_propagation_policy)
    error_message = "delete_propagation_policy must be RETAIN, which is the only value the EKS API accepts today."
  }
}

variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "IAM managed policy ARNs attached to the role AWS assumes to run the capability. AdministratorAccess by default because an ACK controller creates arbitrary AWS resources on demand and the set is not knowable in advance - narrow this to the services the demo actually uses before running it anywhere real"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "argo_cd_configuration" {
  type = object({
    namespace          = optional(string)
    idc_instance_arn   = optional(string)
    vpce_ids           = optional(list(string), [])
    rbac_role_mappings = optional(map(list(object({ id = string, type = string }))), {})
  })
  default     = null
  description = "Configuration for the ARGOCD capability type. Null for ACK and kro, which take no configuration - the block is then omitted entirely rather than emitted empty (rules.md B-4)"

  validation {
    condition     = var.argo_cd_configuration == null || var.type == "ARGOCD"
    error_message = "argo_cd_configuration is only valid when type is ARGOCD. ACK and kro capabilities take no configuration, and the EKS API rejects a configuration block for them."
  }

  validation {
    condition     = var.argo_cd_configuration == null || try(var.argo_cd_configuration.idc_instance_arn, null) == null || can(regex("^arn:aws:sso:::instance/", var.argo_cd_configuration.idc_instance_arn))
    error_message = "argo_cd_configuration.idc_instance_arn must be an IAM Identity Center instance ARN (e.g. arn:aws:sso:::instance/ssoins-0123456789abcdef), or null to leave single sign-on off."
  }

  validation {
    condition = var.argo_cd_configuration == null || alltrue([
      for identities in values(try(var.argo_cd_configuration.rbac_role_mappings, {})) :
      alltrue([for identity in identities : contains(["SSO_USER", "SSO_GROUP"], identity.type)])
    ])
    error_message = "each rbac_role_mappings identity type must be SSO_USER or SSO_GROUP; the identities come from IAM Identity Center, and the id is the store's user or group id rather than a name."
  }

  validation {
    # Argo CD's three built-in roles, uppercase. The API takes the string as given, so a
    # lowercase "admin" or an invented role name is accepted here and simply matches nothing -
    # leaving an Argo CD with single sign-on on and no one able to log in.
    condition = var.argo_cd_configuration == null || alltrue([
      for role in keys(try(var.argo_cd_configuration.rbac_role_mappings, {})) :
      contains(["ADMIN", "EDITOR", "VIEWER"], role)
    ])
    error_message = "rbac_role_mappings keys must be one of ADMIN, EDITOR or VIEWER, uppercase - those are Argo CD's built-in roles and the names are case sensitive."
  }

  validation {
    # An RBAC mapping without single sign-on configured has nothing to map: the identities named in
    # it come from Identity Center. The combination is about the pair, so it is checked here rather
    # than on either field alone (rules.md B-1).
    condition     = var.argo_cd_configuration == null || length(try(var.argo_cd_configuration.rbac_role_mappings, {})) == 0 || try(var.argo_cd_configuration.idc_instance_arn, null) != null
    error_message = "argo_cd_configuration.rbac_role_mappings needs idc_instance_arn set, because the identities it maps are IAM Identity Center users and groups. Either set idc_instance_arn or drop the mappings."
  }
}

variable "role_propagation_wait_seconds" {
  type        = number
  default     = 30
  description = <<-DESC
    How long to wait after creating the capability role before creating the capability, so the trust
    policy has propagated to the EKS capabilities service.

    Thirty seconds, which is generous against a race that CreateRole normally loses by well under
    one. The cost of it being too short is an apply that fails with InvalidParameterException naming
    the trust policy, on a trust policy that is exactly the documented one - see
    time_sleep.role_propagation in main.tf for why that message points at the wrong thing. The cost
    of it being too long is thirty seconds.

    Raise it rather than retrying the apply if that error comes back. Retrying does work, because the
    role from the failed apply is still there and has propagated by then, but it leaves a
    configuration that only ever succeeds on the second run.
  DESC

  validation {
    condition     = var.role_propagation_wait_seconds >= 0 && floor(var.role_propagation_wait_seconds) == var.role_propagation_wait_seconds
    error_message = "role_propagation_wait_seconds must be a whole number of seconds, zero or greater."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the capability"
}
