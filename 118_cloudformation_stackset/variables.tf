variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.). This is where the StackSet itself is created; where it deploys is stack_instance_regions"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "stack_set_name" {
  type        = string
  default     = "AccessPolicy"
  description = "Name of the StackSet, as the _monolithic template named it. It also names every stack it creates, as StackSet-<name>-<id>"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,127}$", var.stack_set_name))
    error_message = "stack_set_name must start with a letter and be up to 128 characters of letters, digits and hyphens."
  }
}
variable "template_path" {
  type        = string
  default     = "templates/iam_policy.yaml"
  description = "Path to the CloudFormation template the StackSet deploys, relative to this root. A file rather than the escaped one-line string the _monolithic template embedded in template_body - which made the document unreadable and an edit a re-escaping exercise"

  validation {
    condition     = can(regex("\\.(ya?ml|json)$", var.template_path))
    error_message = "template_path must point at a .yaml, .yml or .json file."
  }
}
variable "managed_policy_name" {
  type        = string
  default     = "DenyAll"
  description = "Name the deployed template gives its managed policy, as the _monolithic template hardcoded it. A parameter here rather than a literal in the template, so the StackSet can be deployed into an account that already has a policy by this name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.managed_policy_name))
    error_message = "managed_policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
variable "allowed_source_ip_addresses" {
  type        = list(string)
  default     = ["100.0.0.11", "100.0.0.12", "100.0.0.13", "100.0.0.14"]
  description = <<-DESC
    Addresses exempt from the deny in the policy the StackSet deploys. The four from the _monolithic
    template's per-instance ParameterOverrides, which is the interesting half of the feature: the template's
    own default is two addresses, and the instance overrides it.

    These are documentation addresses and match nobody, which is what makes the demo safe. The policy is
    created attached to nothing, so it has no effect regardless - see the outputs.
  DESC

  validation {
    condition     = length(var.allowed_source_ip_addresses) > 0
    error_message = "allowed_source_ip_addresses must contain at least one address - a policy with an empty NotIpAddress condition denies everything unconditionally."
  }
  validation {
    condition = alltrue([
      for address in var.allowed_source_ip_addresses :
      can(cidrhost(strcontains(address, "/") ? address : "${address}/32", 0))
    ])
    error_message = "allowed_source_ip_addresses must each be a valid IPv4 address or CIDR block."
  }
}
variable "stack_instance_account_ids" {
  type        = list(string)
  default     = null
  description = "Accounts the StackSet deploys into. Null uses the account this root is applied to, which is what the _monolithic template's DeploymentTargets did with a Ref to AWS::AccountId. Naming other accounts requires an execution role of the agreed name to already exist in each of them"

  validation {
    condition     = var.stack_instance_account_ids == null || alltrue([for id in coalesce(var.stack_instance_account_ids, []) : can(regex("^[0-9]{12}$", id))])
    error_message = "stack_instance_account_ids must contain 12-digit AWS account IDs, or be null to use the current account."
  }
}
variable "stack_instance_regions" {
  type        = list(string)
  default     = null
  description = "Regions the StackSet deploys into. Null uses the region this root is applied to, as the original did. Note that the template creates an IAM managed policy, which is global - deploying it to two regions in one account fails the second time with a name collision"

  validation {
    condition     = var.stack_instance_regions == null || alltrue([for region in coalesce(var.stack_instance_regions, []) : can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", region))])
    error_message = "stack_instance_regions must contain valid regions, or be null to use the current region."
  }
}
variable "administration_role_name" {
  type        = string
  default     = "AWSCloudFormationStackSetAdministrationRole"
  description = "Name of the role CloudFormation assumes to drive the StackSet, as the _monolithic template named it. It is the name AWS's own setup templates use, so an account that already runs a self-managed StackSet has this role and this project would collide with it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.administration_role_name))
    error_message = "administration_role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "execution_role_name" {
  type        = string
  default     = "AWSCloudFormationStackSetExecutionRole"
  description = "Name of the role assumed inside each target account, as the _monolithic template named it. A StackSet names it by name rather than by ARN, so every target account needs a role called exactly this"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.execution_role_name))
    error_message = "execution_role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "scope_execution_role_to_iam_policies" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether to replace the execution role's AdministratorAccess with permissions for just the managed policy
    the template creates.

    False by default, which is the _monolithic template's behaviour and AWS's own documented setup. The
    reason to keep administrator as the default is that it is what a StackSet needs in general: the role has
    to be able to create whatever any template deployed through it contains, and it does not know that in
    advance. Narrowing it to this template's needs is correct for this project and wrong the moment the
    template changes - which is a trap worth naming rather than a default worth having.

    Set true to see the narrow version, and expect it to break if the template gains a resource.
  DESC
}
variable "failure_tolerance_count" {
  type        = number
  default     = 0
  description = "How many target accounts may fail before the operation stops. Zero, which is CloudFormation's default stated explicitly"

  validation {
    condition     = var.failure_tolerance_count >= 0
    error_message = "failure_tolerance_count must be zero or greater."
  }
}
variable "max_concurrent_count" {
  type        = number
  default     = 1
  description = "How many accounts are operated on at once. CloudFormation requires it to be at most failure_tolerance_count + 1"

  validation {
    condition     = var.max_concurrent_count >= 1
    error_message = "max_concurrent_count must be at least 1."
  }
  validation {
    condition     = var.max_concurrent_count <= var.failure_tolerance_count + 1
    error_message = "max_concurrent_count must be no greater than failure_tolerance_count + 1, which is CloudFormation's own constraint."
  }
}
variable "stack_set_tags" {
  type = map(string)
  default = {
    foo = "bar"
  }
  description = "Tags on the StackSet, which CloudFormation also applies to every resource each stack creates. The default is the _monolithic template's, kept so the demo shows the same thing in the console"

  validation {
    condition     = alltrue([for key in keys(var.stack_set_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "stack_set_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
