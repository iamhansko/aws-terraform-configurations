variable "name" {
  type        = string
  default     = "kiro-bootstrap"
  description = "Instance Name tag and prefix for IAM, SSM document, and Association names"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,31}$", var.name))
    error_message = "name must be 1-32 characters of letters, digits, dots, underscores, or hyphens, and must start with a letter or digit."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC in which the bootstrap security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID, such as vpc-0123456789abcdef0."
  }
}

variable "subnet_id" {
  type        = string
  description = "Private subnet in which the bootstrap instance is launched; outbound access is supplied by the network module NAT gateway"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID, such as subnet-0123456789abcdef0."
  }
}

variable "security_group_name" {
  type        = string
  default     = "kiro-bootstrap-sg"
  description = "Name of the outbound-only bootstrap security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the EC2 security-group character set, contain no apostrophe, and not start with sg- (rules.md F-1)."
  }
}

variable "ami_id" {
  type        = string
  description = "Amazon Linux 2023 x86_64 AMI ID resolved by the caller"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a syntactically valid AMI ID, such as ami-0123456789abcdef0."
  }
}

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the one-shot bootstrap"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type, such as t3.small."
  }
}

variable "aws_region" {
  type        = string
  description = "Infrastructure and IAM Identity Center region used by SSM, the Terraform waiters, and the workforce-subscription list endpoint/signing scope"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z0-9]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as us-east-1."
  }
}

variable "additional_iam_policy_arns" {
  type        = list(string)
  default     = []
  description = "Additional managed policies attached to the bootstrap role"

  validation {
    condition = alltrue([
      for arn in var.additional_iam_policy_arns : can(regex("^arn:aws[a-zA-Z-]*:iam::(aws|[0-9]{12}):policy/.+$", arn))
    ])
    error_message = "additional_iam_policy_arns must contain valid IAM managed-policy ARNs."
  }
}

variable "identity_center_instance_arn" {
  type        = string
  description = "ARN of the existing IAM Identity Center instance"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:sso:::instance/(sso)?ins-[a-zA-Z0-9.-]{16}$", var.identity_center_instance_arn))
    error_message = "identity_center_instance_arn must be an IAM Identity Center instance ARN such as arn:aws:sso:::instance/ssoins-0123456789abcdef."
  }
}

variable "user_id" {
  type        = string
  description = "Identity Store user that receives the one-time password and optional subscription"

  validation {
    condition     = can(regex("^([0-9a-fA-F]{10}-)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.user_id))
    error_message = "user_id must be an Identity Store user ID in UUID form, optionally prefixed by the 10-character identity-store identifier."
  }
}

variable "disable_mfa" {
  type        = bool
  default     = false
  description = "Whether the SSM bootstrap Command document disables MFA for the entire IAM Identity Center instance"

  validation {
    condition     = !var.disable_mfa || var.acknowledge_mfa_disable
    error_message = "acknowledge_mfa_disable must be true when disable_mfa is true. This changes sign-in for every user in the Identity Center instance and cannot be undone automatically at destroy."
  }
}

variable "acknowledge_mfa_disable" {
  type        = bool
  default     = false
  description = "Explicit acknowledgement of the instance-wide effect when disable_mfa is true"
}

variable "password_parameter_name" {
  type        = string
  default     = "/kiro/user/password"
  description = "SecureString parameter to which the SSM bootstrap Command document writes the one-time password"

  validation {
    condition     = length(var.password_parameter_name) <= 980 && can(regex("^/[a-zA-Z0-9_.\\-/]+$", var.password_parameter_name))
    error_message = "password_parameter_name must be an absolute Parameter Store path of at most 980 characters, leaving room for derived ownership parameter suffixes."
  }
}

variable "create_kiro_subscription" {
  type        = bool
  default     = false
  description = "Whether the SSM bootstrap Command document creates the out-of-state, billed Kiro profile and subscription through direct SigV4 API requests"

  validation {
    condition     = !var.create_kiro_subscription || var.acknowledge_subscription_cost
    error_message = "acknowledge_subscription_cost must be true when create_kiro_subscription is true because the billed subscription is outside Terraform state."
  }
}

variable "acknowledge_subscription_cost" {
  type        = bool
  default     = false
  description = "Explicit acknowledgement of the monthly charge and out-of-state lifecycle"
}

variable "kiro_region" {
  type        = string
  default     = "us-east-1"
  description = "Kiro profile/assignment endpoint and signing region, also used as the ListUserSubscriptions subscriptionRegion filter. It is independent from aws_region, which controls infrastructure, IAM Identity Center, and workforce-subscription endpoint signing"

  validation {
    condition     = contains(["us-east-1", "eu-central-1"], var.kiro_region)
    error_message = "kiro_region must be us-east-1 or eu-central-1."
  }
}

variable "kiro_subscription_plan" {
  type        = string
  default     = "Q_DEVELOPER_STANDALONE_PRO"
  description = "Billed plan used only when create_kiro_subscription is true"

  validation {
    condition = contains([
      "Q_DEVELOPER_STANDALONE_PRO",
      "Q_DEVELOPER_STANDALONE_PRO_PLUS",
      "Q_DEVELOPER_STANDALONE_POWER",
    ], var.kiro_subscription_plan)
    error_message = "kiro_subscription_plan must be Q_DEVELOPER_STANDALONE_PRO, Q_DEVELOPER_STANDALONE_PRO_PLUS, or Q_DEVELOPER_STANDALONE_POWER."
  }
}

variable "subscribe_attempts" {
  type        = number
  default     = 3
  description = "Maximum profile and subscription attempts, five seconds apart"

  validation {
    condition     = floor(var.subscribe_attempts) == var.subscribe_attempts && var.subscribe_attempts >= 1 && var.subscribe_attempts <= 20
    error_message = "subscribe_attempts must be an integer from 1 through 20."
  }
}

variable "stop_after_bootstrap" {
  type        = bool
  default     = true
  description = "Whether the instance is stopped after bootstrap verification when no subscription cleanup generation is active"
}

variable "bootstrap_timeout_seconds" {
  type        = number
  default     = 900
  description = "Maximum time for the custom SSM bootstrap document operation and its Terraform verification barrier"

  validation {
    condition = (
      floor(var.bootstrap_timeout_seconds) == var.bootstrap_timeout_seconds &&
      var.bootstrap_timeout_seconds >= 480 + (var.create_kiro_subscription ? 10 * var.subscribe_attempts : 0) &&
      var.bootstrap_timeout_seconds <= 3600
    )
    error_message = "bootstrap_timeout_seconds must be an integer from 480 + (10 * subscribe_attempts when subscription creation is enabled) through 3600. The lower bound includes status retries, the bounded 300-second package install, profile/subscription observation, and the custom document plus Terraform verification margin."
  }
}

variable "subscription_cleanup_generation" {
  type        = string
  default     = null
  description = "Plan-known generation that starts the instance and enables the cleanup Association and Terraform waiter; null disables cleanup"

  validation {
    condition     = var.subscription_cleanup_generation == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$", var.subscription_cleanup_generation))
    error_message = "subscription_cleanup_generation must be null or a 1-64 character label of letters, digits, dots, underscores, or hyphens that starts with a letter or digit."
  }
}

variable "subscription_cleanup_timeout_seconds" {
  type        = number
  default     = 900
  description = "Maximum time each cleanup or cleanup-verification Association waits"

  validation {
    condition = (
      floor(var.subscription_cleanup_timeout_seconds) == var.subscription_cleanup_timeout_seconds &&
      var.subscription_cleanup_timeout_seconds >= 120 + (10 * var.subscribe_attempts) &&
      var.subscription_cleanup_timeout_seconds <= 3600
    )
    error_message = "subscription_cleanup_timeout_seconds must be an integer from 120 + (10 * subscribe_attempts) through 3600."
  }
}
