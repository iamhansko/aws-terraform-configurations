variable "namespace" {
  type        = string
  default     = "big-data"
  description = "Namespace EMR on EKS runs jobs in, as the _monolithic template's virtual cluster named it - and which that template never created"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether this module creates the namespace. False when something else owns it (rules.md B-4)"
}

variable "role_name" {
  type        = string
  default     = "emr-containers"
  description = "Name of the Role granting EMR on EKS its permissions in the namespace, as eksctl names it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.role_name))
    error_message = "role_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "role_binding_name" {
  type        = string
  default     = "emr-containers"
  description = "Name of the RoleBinding tying the Role to the Kubernetes user the service-linked role maps to"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.role_binding_name))
    error_message = "role_binding_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "emr_user_name" {
  type        = string
  default     = "emr-containers"
  description = "Kubernetes user name the service-linked role is mapped to in aws-auth, and the subject of the RoleBinding. One value on both sides, so the binding cannot miss its subject (rules.md B-5)"

  validation {
    condition     = length(var.emr_user_name) > 0
    error_message = "emr_user_name must not be empty."
  }
}

variable "service_linked_role_name" {
  type        = string
  default     = "AWSServiceRoleForAmazonEMRContainers"
  description = <<-DESC
    Name of the EMR on EKS service-linked role, without its path.

    The real role lives at role/aws-service-role/emr-containers.amazonaws.com/<name>, but the AWS IAM
    Authenticator does not permit a path in an aws-auth rolearn - so the ConfigMap entry names it without
    one. The opposite of what aws_eks_access_entry requires, and it only comes up here because a
    service-linked role cannot be an access entry principal at all (rules.md E-6).

    AWS creates this role the first time EMR on EKS is used in the account. If it does not exist yet,
    `aws iam create-service-linked-role --aws-service-name emr-containers.amazonaws.com` creates it -
    the mapping below is accepted either way, since aws-auth is text.
  DESC

  validation {
    condition     = !strcontains(var.service_linked_role_name, "/")
    error_message = "service_linked_role_name must be a bare role name with no path. The AWS IAM Authenticator rejects a rolearn containing a path, which is why the path is stripped here (rules.md E-6)."
  }
}
