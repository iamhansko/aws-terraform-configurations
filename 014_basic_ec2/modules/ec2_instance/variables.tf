variable "name" {
  type        = string
  description = "Name tag for the instance, also used as the default base for the security group name"
  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC ID where the instance's security group is created"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Subnet ID the instance is launched into"
  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name used to launch the instance. When null, the instance is reachable only through SSM Session Manager"
  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type"
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the AMI ID. A parameter rather than the _monolithic template's hardcoded region-to-AMI map, which only had entries for two regions and went stale with every AMI release"
  validation {
    condition     = can(regex("^/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = false
  description = "Whether to associate a public IP address with the instance"
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of the instance's root EBS volume"
  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the security group created for the instance"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for an EC2 instance"
  description = "Description attached to the security group"
  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
# One entry per rule, rather than a list of ports crossed with a list of sources.
# A cross product would silently open every port to every source, so turning one
# port on for one caller would widen the others too.
variable "ingress_cidr_rules" {
  type = map(object({
    port       = number
    cidr_block = string
  }))
  default     = {}
  description = "Inbound TCP rules admitting a CIDR block, keyed by a caller-chosen label used in the rule description and resource address (e.g. { app_from_anywhere = { port = 3000, cidr_block = \"0.0.0.0/0\" } }). Keyed by label rather than by value so a CIDR taken from another module's output still produces statically known for_each keys (rules.md B-8)"
  validation {
    condition     = alltrue([for label in keys(var.ingress_cidr_rules) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_cidr_rules keys are labels used in rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for rule in values(var.ingress_cidr_rules) : rule.port > 0 && rule.port <= 65535])
    error_message = "ingress_cidr_rules ports must be valid TCP ports."
  }
  validation {
    condition     = alltrue([for rule in values(var.ingress_cidr_rules) : can(cidrhost(rule.cidr_block, 0))])
    error_message = "ingress_cidr_rules cidr_block values must be valid IPv4 CIDR blocks."
  }
}
variable "ingress_source_group_rules" {
  type = map(object({
    port              = number
    security_group_id = string
  }))
  default     = {}
  description = "Inbound TCP rules admitting another security group, keyed by a caller-chosen label (e.g. { ssh_from_public_ec2 = { port = 22, security_group_id = sg-... } }). A map rather than a list because these IDs are usually another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"
  validation {
    condition     = alltrue([for label in keys(var.ingress_source_group_rules) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_group_rules keys are labels used in rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for rule in values(var.ingress_source_group_rules) : rule.port > 0 && rule.port <= 65535])
    error_message = "ingress_source_group_rules ports must be valid TCP ports."
  }
  validation {
    condition     = alltrue([for rule in values(var.ingress_source_group_rules) : can(regex("^sg-[0-9a-f]+$", rule.security_group_id))])
    error_message = "ingress_source_group_rules security_group_id values must be valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the instance, on top of the one this module creates. The module never looks these resources up itself (rules.md B-6)"
  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  description = "IAM managed policy ARNs attached to the instance's role. AmazonSSMManagedInstanceCore alone is enough for Session Manager, which is how the private instance is reached without a bastion hop. Set to [] to launch the instance with no instance profile at all"
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "user_data" {
  type        = string
  default     = null
  description = "Optional shell script run on first boot. When null, no user data is set"
  validation {
    condition     = var.user_data == null || length(var.user_data) < 16000
    error_message = "user_data must stay under EC2's 16 KB user data limit."
  }
}
