variable "aws_region" {
  type        = string
  default     = null
  description = "Infrastructure and IAM Identity Center home region, including the workforce-subscription list endpoint/signing region. Null follows AWS_REGION or AWS_DEFAULT_REGION from the provider chain"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z0-9]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as us-east-1, or null to follow the provider chain."
  }
}

variable "expected_account_id" {
  type        = string
  default     = null
  description = "Optional 12-digit AWS account guard. When set, planning with credentials for another account is blocked"

  validation {
    condition     = var.expected_account_id == null || can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID, or null."
  }
}

variable "name_prefix" {
  type        = string
  default     = "kiro"
  description = "Prefix used for resource names and Name tags"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,19}$", var.name_prefix))
    error_message = "name_prefix must be 1-20 characters of letters, digits, dots, underscores, or hyphens, and must start with a letter or digit."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags applied through the root AWS provider"

  validation {
    condition = alltrue([
      for key, value in var.tags : length(key) >= 1 && length(key) <= 128 && length(value) <= 256
    ])
    error_message = "tags keys must be 1-128 characters and values must be at most 256 characters."
  }
}

# --- Network ----------------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "IPv4 CIDR for the bootstrap VPC; its first two /24 networks become the public NAT and private bootstrap subnets"

  validation {
    condition = (
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/(1[6-9]|2[0-3])$", var.vpc_cidr_block)) &&
      can(cidrsubnet(var.vpc_cidr_block, 24 - tonumber(split("/", var.vpc_cidr_block)[1]), 1))
    )
    error_message = "vpc_cidr_block must be a valid IPv4 VPC CIDR from /16 through /23 so it can provide distinct public and private /24 subnets."
  }
}

variable "availability_zone" {
  type        = string
  default     = null
  description = "Optional available AZ shared by the public NAT and private bootstrap subnets. Null selects the first AZ reported in the provider region"

  validation {
    condition     = var.availability_zone == null || can(regex("^[a-z0-9-]+$", var.availability_zone))
    error_message = "availability_zone must be an AWS availability-zone name such as us-east-1a, or null."
  }
}

# --- Identity Center user ---------------------------------------------------------------------------------
variable "user_name" {
  type        = string
  default     = "kiro"
  description = "Sign-in name of the IAM Identity Center user"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.user_name))
    error_message = "user_name must be 1-128 characters of letters, digits and +=,.@_-."
  }
}

variable "user_display_name" {
  type        = string
  default     = "Kiro User"
  description = "Display name of the IAM Identity Center user"

  validation {
    condition     = length(var.user_display_name) >= 1 && length(var.user_display_name) <= 1024
    error_message = "user_display_name must be 1-1024 characters."
  }
}

variable "user_given_name" {
  type        = string
  default     = "Kiro"
  description = "Given name of the IAM Identity Center user"

  validation {
    condition     = length(var.user_given_name) > 0
    error_message = "user_given_name must not be empty."
  }
}

variable "user_family_name" {
  type        = string
  default     = "User"
  description = "Family name of the IAM Identity Center user"

  validation {
    condition     = length(var.user_family_name) > 0
    error_message = "user_family_name must not be empty."
  }
}

variable "user_email" {
  type        = string
  default     = "pro@kiro.com"
  description = "Primary work email of the IAM Identity Center user"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.user_email))
    error_message = "user_email must be an email address."
  }
}

variable "disable_mfa" {
  type        = bool
  default     = false
  description = "Whether the SSM bootstrap Command document disables MFA for the entire IAM Identity Center instance. The safe default preserves the current setting"

  validation {
    condition     = !var.disable_mfa || var.acknowledge_instance_wide_mfa_disable
    error_message = "acknowledge_instance_wide_mfa_disable must be true when disable_mfa is true. This changes sign-in for every user in the Identity Center instance, and terraform destroy cannot restore the prior mode."
  }
}

variable "acknowledge_instance_wide_mfa_disable" {
  type        = bool
  default     = false
  description = "Explicit acknowledgement of the account-wide sign-in impact when disable_mfa is true"
}

# --- Optional billed subscription ------------------------------------------------------------------------
variable "create_kiro_subscription" {
  type        = bool
  default     = true
  description = "Whether the SSM bootstrap Command document uses direct SigV4 API requests to create the Kiro profile and billed per-user subscription. Enabled by default because profile/subscription creation is the purpose of this root; set false to create only the user and OTP"

  validation {
    condition     = !var.create_kiro_subscription || var.acknowledge_monthly_kiro_subscription
    error_message = "acknowledge_monthly_kiro_subscription must be true when create_kiro_subscription is true, because the subscription is billed monthly and exists outside Terraform state."
  }
}

variable "acknowledge_monthly_kiro_subscription" {
  type        = bool
  default     = true
  description = "Explicit acknowledgement that the default Kiro subscription creates a monthly billed object outside Terraform state; set false together with create_kiro_subscription=false to disable it"
}

variable "kiro_region" {
  type        = string
  default     = "us-east-1"
  description = "Kiro profile/assignment endpoint and signing region, also used as the ListUserSubscriptions subscriptionRegion filter; independent from aws_region, which controls infrastructure, IAM Identity Center, and workforce-subscription endpoint signing"

  validation {
    condition     = contains(["us-east-1", "eu-central-1"], var.kiro_region)
    error_message = "kiro_region must be us-east-1 or eu-central-1."
  }
}

variable "kiro_subscription_plan" {
  type        = string
  default     = "Q_DEVELOPER_STANDALONE_PRO"
  description = "Monthly billed Kiro plan used only when create_kiro_subscription is true"

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

# --- Bootstrap instance -----------------------------------------------------------------------------------
variable "bootstrap_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Public SSM parameter containing the Amazon Linux 2023 x86_64 AMI ID"

  validation {
    condition = (
      startswith(var.bootstrap_ami_ssm_parameter_name, "/aws/service/ami-amazon-linux-latest/al2023-") &&
      strcontains(var.bootstrap_ami_ssm_parameter_name, "x86_64")
    )
    error_message = "bootstrap_ami_ssm_parameter_name must identify an Amazon Linux 2023 x86_64 image because the SSM bootstrap Command document uses dnf and installs x86_64 packages."
  }
}

variable "bootstrap_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type for the one-shot bootstrap host"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.bootstrap_instance_type))
    error_message = "bootstrap_instance_type must be a valid EC2 instance type, such as t3.small."
  }
}

variable "password_parameter_name" {
  type        = string
  default     = "/kiro/user/password"
  description = "SecureString parameter that receives the one-time password. Override it when deploying another copy in the same account and region"

  validation {
    condition     = length(var.password_parameter_name) <= 980 && can(regex("^/[a-zA-Z0-9_.\\-/]+$", var.password_parameter_name))
    error_message = "password_parameter_name must be an absolute Parameter Store path of at most 980 characters, leaving room for derived ownership parameter suffixes."
  }
}

variable "additional_iam_policy_arns" {
  type        = list(string)
  default     = []
  description = "Additional managed policies attached to the bootstrap role. Required original policies are component-owned and cannot be removed through this input"

  validation {
    condition = alltrue([
      for arn in var.additional_iam_policy_arns : can(regex("^arn:aws[a-zA-Z-]*:iam::(aws|[0-9]{12}):policy/.+$", arn))
    ])
    error_message = "additional_iam_policy_arns must contain valid IAM managed-policy ARNs."
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
  description = "Plan-known teardown generation. Null keeps cleanup disabled; set a changed stable label before destroy to start the instance and run the Terraform-managed cleanup Association and waiter"

  validation {
    condition     = var.subscription_cleanup_generation == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$", var.subscription_cleanup_generation))
    error_message = "subscription_cleanup_generation must be null or a 1-64 character label of letters, digits, dots, underscores, or hyphens that starts with a letter or digit. Use a new value, such as cleanup-20261014-1, to request another cleanup execution."
  }
}

variable "subscription_cleanup_timeout_seconds" {
  type        = number
  default     = 900
  description = "Maximum time each cleanup or cleanup-verification SSM Association waits"

  validation {
    condition = (
      floor(var.subscription_cleanup_timeout_seconds) == var.subscription_cleanup_timeout_seconds &&
      var.subscription_cleanup_timeout_seconds >= 120 + (10 * var.subscribe_attempts) &&
      var.subscription_cleanup_timeout_seconds <= 3600
    )
    error_message = "subscription_cleanup_timeout_seconds must be an integer from 120 + (10 * subscribe_attempts) through 3600."
  }
}
