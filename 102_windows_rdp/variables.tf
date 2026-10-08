variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "spirit-of-kiro"
  description = <<-DESC
    Prefix for the generated names and Name tags of everything in this root, so a second copy in one
    account stays tellable apart.

    This is the _monolithic template's stack_name variable under the name the rest of this repository
    uses. It stood in for AWS::StackName, and CloudFormation read it for three things: the Cognito pool
    and client names, the six DynamoDB table names, and the --stack argument of the cfn-signal calls in
    the userdata. The first two are reproduced; the third is gone, because there is no CloudFormation
    stack for a signal to reach.
  DESC

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.project_name))
    error_message = "project_name must be 2-41 characters of lowercase letters, digits and hyphens. It is interpolated into a Cognito pool name and six DynamoDB table names, both of which are more restrictive than a tag value."
  }
}
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2025-Korean-Full-Base"
  description = <<-DESC
    Public SSM parameter holding the Windows AMI id, as the _monolithic template had it. AWS publishes
    these per Windows release, edition and language, so the region never has to be mapped to an AMI id
    by hand.

    The default is the Korean Full Base image, which is what the original workshop used. Full Base
    rather than Core matters: the setup installs a GUI IDE and the whole point is an RDP desktop, so a
    Core image would come up with no shell to connect to. The language matters less, but it is the
    reason this is a variable - Windows_Server-2025-English-Full-Base is the same image in English.
  DESC

  validation {
    condition     = startswith(var.ami_ssm_parameter_name, "/aws/service/ami-windows-latest/")
    error_message = "ami_ssm_parameter_name must be an AWS public Windows AMI parameter path under /aws/service/ami-windows-latest/. A bare ami- id is not accepted here: this is resolved through a data source, and an id would have to be passed to the module directly."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "instance_type" {
  type        = string
  default     = "m5.2xlarge"
  description = "Instance type for the Windows workshop instance, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. m5.2xlarge)."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 100
  description = "Root volume size in GiB, as the _monolithic template had it"

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GiB, the size of the Windows Server Full Base root volume before anything the setup installs."
  }
}
variable "rdp_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-DESC
    Source CIDRs allowed to reach RDP. An empty list creates no ingress rule, leaving the instance
    reachable only through SSM Session Manager.

    This replaces the _monolithic template's InboundFromAnywhere parameter, a string constrained to
    "True" and "False" because CloudFormation parameters have no boolean type. A list says the same and
    more: ["0.0.0.0/0"] is that parameter set to True, [] is False, and anything narrower is the case the
    string could not express.

    The default is the whole internet because that is what the template defaulted to. Narrowing it to
    the address you connect from is the single most useful change to make in this file - Windows Server
    answers 3389 from first boot, so this is exposed for the entire several-minute setup window before
    the workshop account even exists.
  DESC

  validation {
    condition     = alltrue([for cidr in var.rdp_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "rdp_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "workshop_username" {
  type        = string
  default     = "kiro"
  description = "Windows local account the RDP login uses. One variable feeds both the secret that stores the credential and the instance that creates the account, so the two cannot disagree - which they could if each module carried its own default"

  validation {
    condition     = can(regex("^[^\"/\\\\\\[\\]:;|=,+*?<>@ ]{1,20}$", var.workshop_username))
    error_message = "workshop_username must be 1-20 characters and must not contain a space, @, or any of \" / \\ [ ] : ; | = , + * ? < >, because New-LocalUser rejects those on the instance and the failure never reaches Terraform."
  }
}
variable "git_clone_url" {
  type        = string
  default     = "https://github.com/iamhansko/spirit-of-kiro.git"
  description = "Repository the instance clones, as the _monolithic template had it"

  validation {
    condition     = can(regex("^https://[^\\s\"']+$", var.git_clone_url))
    error_message = "git_clone_url must be an https URL - the clone runs unattended with no credential helper."
  }
}
variable "git_clone_branch" {
  type        = string
  default     = "challenge"
  description = "Branch to clone, as the _monolithic template had it. It doubles as the directory name the clone lands in, so it appears in the launcher scripts and the desktop shortcut paths"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]{1,255}$", var.git_clone_branch))
    error_message = "git_clone_branch must be 1-255 characters of letters, digits, dots, underscores, slashes and hyphens, because it is used as a Windows directory name as well as a branch name."
  }
}
variable "dynamodb_tables" {
  type = map(object({
    hash_key       = string
    hash_key_type  = optional(string, "S")
    range_key      = optional(string)
    range_key_type = optional(string, "S")
  }))
  default = {
    items     = { hash_key = "id" }
    inventory = { hash_key = "id", range_key = "itemId" }
    location  = { hash_key = "itemId", range_key = "location" }
    users     = { hash_key = "userId" }
    usernames = { hash_key = "username" }
    persona   = { hash_key = "userId", range_key = "detail" }
  }
  description = <<-DESC
    The game's six tables and their key schemas, keyed by the logical name that becomes part of the
    table name and of the DYNAMODB_TABLE_<KEY> environment variable the server reads.

    These six entries are exactly the six aws_dynamodb_table resources the _monolithic template
    declared, and the defaults reproduce their key schemas. Collected here because this is the only
    place the difference between them is visible at a glance - reading the conversion, establishing that
    location is keyed on itemId while persona is keyed on userId takes six separate resource bodies.

    Keys flow to two modules, and each validates them for its own reason: dynamodb_tables checks what
    DynamoDB accepts in a table name, windows_ec2 checks what PowerShell accepts in an environment
    variable name, which is stricter. The condition below is the stricter of the two, so a bad key fails
    on this variable rather than inside a module.
  DESC

  validation {
    condition     = length(var.dynamodb_tables) > 0
    error_message = "dynamodb_tables must not be empty - the game server reads a table name for each of its six data stores and fails at runtime on an empty one."
  }
  validation {
    condition     = alltrue([for key in keys(var.dynamodb_tables) : can(regex("^[a-z][a-z0-9_]*$", key))])
    error_message = "dynamodb_tables keys must start with a lowercase letter and contain only lowercase letters, digits and underscores. Each is uppercased into a PowerShell environment variable name, where a hyphen or a dot parses as an operator and assigns nothing at all."
  }
}
variable "secret_recovery_window_in_days" {
  type        = number
  default     = 0
  description = "How long Secrets Manager keeps the workshop credential recoverable after destroy. Zero deletes it immediately, which is what repeated demo runs need - the Secrets Manager default of 30 leaves the name taken and a re-apply inside that window fails"

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0 for immediate deletion, or between 7 and 30 - Secrets Manager accepts nothing in between."
  }
}
variable "item_images_service_url" {
  type        = string
  default     = "https://d16sw0kh78rbrs.cloudfront.net"
  description = "Image service the game client calls. The one value in this project that nothing here creates: the default is the CloudFront distribution the original workshop ran, carried over from the _monolithic template as a literal, and it lives in someone else's account - so it can stop answering without anything in this configuration changing"

  validation {
    condition     = can(regex("^https?://[^\\s\"']+$", var.item_images_service_url))
    error_message = "item_images_service_url must be an http or https URL."
  }
}
variable "kiro_installer_url" {
  type        = string
  default     = "https://prod.download.desktop.kiro.dev/releases/stable/win32-x64/signed/0.7.45/kiro-ide-0.7.45-stable-win32-x64.exe"
  description = "Installer the instance downloads for the Kiro IDE, pinned to the version the _monolithic template pinned so the workshop installs the same IDE every time. A withdrawn version fails inside the setup's try block, which shows up as a desktop with no Kiro shortcut rather than as an error"

  validation {
    condition     = can(regex("^https://[^\\s\"']+\\.exe$", var.kiro_installer_url))
    error_message = "kiro_installer_url must be an https URL ending in .exe - it is run with /VERYSILENT, so an installer in another format would be started and never complete."
  }
}
variable "additional_user_data" {
  type        = string
  default     = null
  description = "Extra PowerShell appended to the end of the instance's setup, before the reboot. Null adds nothing. Watch user_data_byte_length when using this: the reproduced script already occupies about 15 KB of EC2's 16 KB user data limit"

  validation {
    condition     = var.additional_user_data == null || !can(regex("\r", var.additional_user_data))
    error_message = "additional_user_data must not contain a carriage return. It is interpolated into a PowerShell script, where a \\r makes every here-string terminator and block keyword fail to match, so the whole script fails to parse and no line of the setup runs (rules.md A-4)."
  }
}
