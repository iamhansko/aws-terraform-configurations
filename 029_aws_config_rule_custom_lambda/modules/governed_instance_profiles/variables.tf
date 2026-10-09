variable "profiles" {
  type = map(object({
    instance_profile_name = string
    role_name             = string
    policy_arns           = list(string)
    demonstrates          = string
  }))
  description = <<-DESC
    The instance profiles the Config rule is meant to find, keyed by what each one demonstrates.

    Each entry becomes a role, an instance profile holding that role, and one attachment per policy
    ARN. The _monolithic template wrote that out twice - two roles, two profiles, one attachment -
    and the two copies differed only in which policies were attached, which is what makes this a
    for_each rather than N blocks (rules.md B-7).

    demonstrates is rendered into the workbench README by the caller. It is part of the data rather
    than a comment because the fixtures are useless without knowing which one is supposed to fail and
    why, and the person who needs that is reading a README on an instance, not this file.
  DESC

  validation {
    condition     = alltrue([for key in keys(var.profiles) : can(regex("^[a-zA-Z0-9_-]+$", key))])
    error_message = "profiles keys become resource addresses and the stem of each attachment's key, so each must be letters, digits, underscores or hyphens."
  }
  validation {
    condition = alltrue([for profile in values(var.profiles) :
      can(regex("^[\\w+=,.@-]{1,64}$", profile.role_name)) && can(regex("^[\\w+=,.@-]{1,128}$", profile.instance_profile_name))
    ])
    error_message = "role_name must be 1-64 and instance_profile_name 1-128 characters from the set IAM accepts for names (letters, digits and _+=,.@-)."
  }
  validation {
    condition = alltrue(flatten([for profile in values(var.profiles) :
      [for arn in profile.policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))]
    ]))
    error_message = "policy_arns must contain IAM policy ARNs."
  }
  validation {
    # Profile names and role names are checked as two separate sets. IAM keeps roles and instance
    # profiles in different namespaces, so a role and a profile sharing a name is legal - it is what
    # the defaults do, after the _monolithic template, and what the console does when it creates a
    # profile for a role. Pooling both names into one list rejected exactly those defaults, so this
    # root could not get through plan at all.
    condition = alltrue([
      length(distinct([for profile in values(var.profiles) : profile.instance_profile_name])) == length(var.profiles),
      length(distinct([for profile in values(var.profiles) : profile.role_name])) == length(var.profiles),
    ])
    error_message = "instance_profile_name must be unique across entries, and so must role_name. IAM names are per-account, so a duplicate fails at apply with EntityAlreadyExists after some of the fixtures already exist - and a role shared between two profiles would make the handler's \"exactly one role\" check pass for both while the demo intended them to differ. A role and a profile may share a name; they are different IAM namespaces."
  }
}
variable "assume_role_services" {
  type        = list(string)
  default     = ["ec2.amazonaws.com"]
  description = "Service principals allowed to assume the fixture roles. ec2.amazonaws.com, because a role reached through an instance profile is assumed by EC2 on an instance's behalf - a role trusting anything else can be put in an instance profile and silently never works"

  validation {
    condition     = length(var.assume_role_services) > 0 && alltrue([for service in var.assume_role_services : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", service))])
    error_message = "assume_role_services must be a non-empty list of AWS service principals (e.g. ec2.amazonaws.com)."
  }
  validation {
    condition     = contains(var.assume_role_services, "ec2.amazonaws.com")
    error_message = "assume_role_services must include ec2.amazonaws.com. These roles exist to be carried by EC2 instances through an instance profile; without that principal, launching an instance with the profile succeeds and the instance has no credentials, which is not what the rule is demonstrating."
  }
}
