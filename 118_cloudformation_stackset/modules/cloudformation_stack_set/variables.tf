variable "name" {
  type        = string
  description = "Name of the StackSet, which also names every stack it creates: a stack instance is called StackSet-<name>-<id>"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,127}$", var.name))
    error_message = "name must start with a letter and be up to 128 characters of letters, digits and hyphens - CloudFormation's own limit."
  }
}
variable "description" {
  type        = string
  default     = null
  description = "Description shown in the CloudFormation console. Null leaves it unset, as the _monolithic template did - which leaves a StackSet whose purpose is nowhere recorded"

  validation {
    condition     = var.description == null || (length(var.description) >= 1 && length(var.description) <= 1024)
    error_message = "description must be 1-1024 characters, or null."
  }
}
variable "template_body" {
  type        = string
  description = "The CloudFormation template to deploy. Read from a file by the caller rather than written inline: the _monolithic template carried it as a single escaped string with every newline as \\n, which made the document unreadable and an edit a re-escaping exercise"

  validation {
    condition     = length(var.template_body) > 0
    error_message = "template_body must not be empty."
  }
  validation {
    condition     = length(var.template_body) <= 51200
    error_message = "template_body must be 51200 bytes or fewer, which is CloudFormation's limit for a template passed inline. A larger template has to go to S3 and be referenced by template_url."
  }
  validation {
    # A template with no Resources section is accepted by this API call and fails when a stack instance is
    # created, several minutes later and in a different resource (rules.md B-1).
    condition     = can(regex("(?m)^Resources:", var.template_body))
    error_message = "template_body must contain a Resources section. CloudFormation accepts a StackSet whose template has none and only fails when a stack instance is created from it."
  }
}
variable "administration_role_arn" {
  type        = string
  description = "Role CloudFormation assumes to drive this StackSet. Passed in from the module that created it, so the StackSet and the role cannot name different things (rules.md B-5)"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/", var.administration_role_arn))
    error_message = "administration_role_arn must be an IAM role ARN."
  }
}
variable "execution_role_name" {
  type        = string
  description = "Name of the role to assume in each target account. A name rather than an ARN because that is what the API takes - the account is supplied per stack instance"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.execution_role_name))
    error_message = "execution_role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "capabilities" {
  type        = list(string)
  default     = ["CAPABILITY_NAMED_IAM"]
  description = <<-DESC
    Capabilities the template is acknowledged to need. The _monolithic template declared all three;
    CAPABILITY_NAMED_IAM alone covers this template, which creates a managed policy with a name of its own.

    What each one acknowledges:
      CAPABILITY_IAM        - the template creates IAM resources
      CAPABILITY_NAMED_IAM  - and names them, which is the stronger claim and implies the first
      CAPABILITY_AUTO_EXPAND - the template contains transforms or nested stacks that expand at deploy time

    Declaring one that is not needed costs nothing but says the template does something it does not.
  DESC

  validation {
    condition     = length(setsubtract(var.capabilities, ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"])) == 0
    error_message = "capabilities must be drawn from CAPABILITY_IAM, CAPABILITY_NAMED_IAM and CAPABILITY_AUTO_EXPAND."
  }
}
variable "parameters" {
  type        = map(string)
  default     = {}
  description = "StackSet-level parameter values, which every stack instance inherits unless it overrides them. The _monolithic template passed an empty map and put the values in a per-instance override instead - so the StackSet's own defaults were the template's"
}
variable "tags" {
  type = map(string)
  default = {
    foo = "bar"
  }
  description = "Tags on the StackSet, which CloudFormation also applies to every resource each stack creates. The default is the _monolithic template's, kept because changing it would change what the demo shows in the console - a real StackSet would carry something meaningful"

  validation {
    condition     = alltrue([for key in keys(var.tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
variable "stack_instances" {
  type = map(object({
    accounts           = list(string)
    regions            = list(string)
    parameter_override = optional(map(string), {})
  }))
  default     = {}
  description = <<-DESC
    Where to deploy, keyed by a caller-chosen label. This is the part the _monolithic template left behind
    entirely: StackInstancesGroup came through the conversion as a commented-out TODO, so the StackSet was
    created and never deployed anywhere. Nothing failed - a StackSet with no instances is valid and does
    nothing.

    A map rather than a list because the keys become resource addresses, and they are labels defined in the
    configuration rather than values discovered at apply time (rules.md B-8).
  DESC

  validation {
    condition     = alltrue([for label in keys(var.stack_instances) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "stack_instances keys are labels used in resource addresses, so each must be letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition = alltrue([
      for instance in values(var.stack_instances) :
      length(instance.accounts) > 0 && alltrue([for id in instance.accounts : can(regex("^[0-9]{12}$", id))])
    ])
    error_message = "every stack_instances entry must name at least one 12-digit AWS account ID."
  }
  validation {
    condition = alltrue([
      for instance in values(var.stack_instances) :
      length(instance.regions) > 0 && alltrue([for region in instance.regions : can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", region))])
    ])
    error_message = "every stack_instances entry must name at least one valid region."
  }
}
variable "failure_tolerance_count" {
  type        = number
  default     = 0
  description = "How many target accounts may fail before the operation stops. Zero, which is CloudFormation's default stated explicitly: a demo wants to know about the first failure rather than push through it"

  validation {
    condition     = var.failure_tolerance_count >= 0
    error_message = "failure_tolerance_count must be zero or greater."
  }
}
variable "max_concurrent_count" {
  type        = number
  default     = 1
  description = "How many accounts are operated on at once. One, and CloudFormation requires it to be at most failure_tolerance_count + 1 - so raising this means raising the tolerance too"

  validation {
    condition     = var.max_concurrent_count >= 1
    error_message = "max_concurrent_count must be at least 1."
  }
  validation {
    # CloudFormation rejects the combination rather than either value, which is exactly the shape a
    # cross-variable validation is for (rules.md B-1).
    condition     = var.max_concurrent_count <= var.failure_tolerance_count + 1
    error_message = "max_concurrent_count must be no greater than failure_tolerance_count + 1, which is CloudFormation's own constraint - raise the tolerance to raise the concurrency."
  }
}
variable "retain_stacks_on_destroy" {
  type        = bool
  default     = false
  description = "Whether removing a stack instance leaves its stack in place. False, so a destroy removes what it created. True is for handing a stack over to the account that owns it, and it means terraform destroy leaves resources behind with nothing tracking them"
}
