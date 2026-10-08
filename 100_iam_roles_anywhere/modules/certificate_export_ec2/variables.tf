variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Subnet the instance launches in. Must be a public subnet with a route to an internet gateway, or have interface endpoints for ACM, S3 and Systems Manager: the bootstrap reaches all three and this project builds no NAT gateway and no endpoints"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI for the instance, resolved by the caller. Taken as an id rather than looked up here so the module does not need to know the caller reads it from an SSM public parameter (rules.md B-6). The bootstrap assumes a dnf-based Amazon Linux with openssl present and the SSM agent preinstalled"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type, as the _monolithic template had it. The work is a package update and two openssl operations, so the size is about how quickly the bootstrap finishes rather than about capacity - and how quickly it finishes is what the caller's export timeout has to cover"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "instance_name" {
  type        = string
  default     = "bastion-ec2"
  description = "Name tag for the instance, as the _monolithic template had it. Kept at the template's value even though the module is named for what the instance does, so that someone comparing a console listing against the original finds the same tag"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public address, as the _monolithic template had it. True is required with the subnet this project builds: a public address is the instance's only route to ACM, S3 and Systems Manager, because there is no NAT gateway and no interface endpoint"
}
variable "security_group_name" {
  type        = string
  default     = "certificate-export-ec2-sg"
  description = "Name of the security group. Not from the _monolithic template, which attached the VPC's default security group instead - see main.tf for why a group of its own is created here"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs (rules.md F-1)."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Outbound only group for the instance that exports the issued certificate to S3"
  description = "Description attached to the security group. Changing it replaces the group, because AWS has no API to modify a security group description - so classification belongs in tags rather than here (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "instance_profile_name_prefix" {
  type        = string
  default     = "certificate-export-ec2-"
  description = "Prefix for the generated instance profile name. A prefix because profile names are account-wide; the name differs from the _monolithic template's Ec2AdminProfile because the role is no longer an administrator - see the policy comment in main.tf"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.instance_profile_name_prefix))
    error_message = "instance_profile_name_prefix must be 1-38 characters of letters, digits and +=,.@_- leaving room for the generated suffix inside the 64 character instance profile name limit."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  description = <<-DESC
    Managed policies attached to the instance role, on top of the inline policy the module writes
    for the export itself.

    AmazonSSMManagedInstanceCore by default, for debugging only. Nothing in the export depends on
    Systems Manager any more - the terminator Lambda watches the bucket, not the instance - but
    when the export fails the Lambda leaves the instance running, and a Session Manager session
    (the cloud_init_log_command output) is the way to read its log without a key pair. An empty
    list is valid; the console output then remains as the only window into the bootstrap.

    It used to be required, by a validation that existed for an SSM association gating the
    termination. That association could not hold the apply - see the root main.tf - and was
    removed, and the requirement went with it.

    The _monolithic template attached AdministratorAccess instead, and main.tf records why that is
    narrowed here. Adding arn:aws:iam::aws:policy/AdministratorAccess to this list reproduces the
    template.
  DESC

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must contain IAM policy ARNs (e.g. arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore)."
  }
}
variable "certificate_arn" {
  type        = string
  description = "ARN of the ACM certificate the bootstrap exports. Injected rather than looked up (rules.md B-6), and also the Resource of the inline acm:ExportCertificate statement - so a certificate from somewhere else is denied rather than silently exported"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN (e.g. arn:aws:acm:ap-northeast-2:111122223333:certificate/...)."
  }
}
variable "artifact_bucket_name" {
  type        = string
  description = "Name of the bucket the four exported files are uploaded to. Injected as a name rather than discovered, so this module does not need to know how the bucket was built (rules.md B-6)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.artifact_bucket_name))
    error_message = "artifact_bucket_name must be a valid S3 bucket name of 3-63 characters."
  }
}
variable "artifact_bucket_arn" {
  type        = string
  description = <<-DESC
    ARN of that same bucket, taken alongside the name because an IAM policy needs the ARN and the
    AWS CLI needs the name, and deriving one from the other in here would mean assuming the
    partition.

    Both are required rather than one being optional: a policy scoped to the wrong bucket produces
    an AccessDenied inside cloud-init that nothing surfaces until the apply gives up at the
    terminator Lambda's wait (rules.md A-5 for taking the ARN rather than widening the policy).
  DESC

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.artifact_bucket_arn))
    error_message = "artifact_bucket_arn must be an S3 bucket ARN (e.g. arn:aws:s3:::my-bucket)."
  }
  validation {
    # The pair has to describe one bucket. Cross-variable, because neither value is wrong on its
    # own (rules.md B-1).
    condition     = endswith(var.artifact_bucket_arn, ":${var.artifact_bucket_name}")
    error_message = "artifact_bucket_arn must be the ARN of artifact_bucket_name. Two different buckets here means the bootstrap uploads to one and is authorized for the other, which fails as an AccessDenied inside cloud-init with nothing to report it."
  }
}
variable "passphrase" {
  type        = string
  sensitive   = true
  default     = "rolePassword1234!"
  description = <<-DESC
    Passphrase ACM encrypts the exported private key with, and that openssl then uses to decrypt
    it. It exists for the length of one export: both the encrypted and the decrypted key end up in
    the bucket, so this protects the key in transit out of ACM and nothing after that.

    Marked sensitive, so it is redacted in plan output. It is still interpolated into user_data,
    which anything on the instance can read back from the instance metadata service, and it is
    still stored in the Terraform state in clear - neither of which is acceptable for a passphrase
    protecting something that matters.
  DESC

  validation {
    condition     = length(var.passphrase) >= 4 && length(var.passphrase) <= 128
    error_message = "passphrase must be 4-128 characters, the range ACM accepts for an export passphrase."
  }
  validation {
    # The value is interpolated into a double-quoted shell word and into openssl's pass: argument,
    # so these characters would end the quoting or be expanded by the shell. The result is not an
    # error message, it is a different passphrase on the two sides of the export and an openssl
    # that reports only "bad decrypt" (rules.md B-1).
    condition     = !can(regex("[\\s\"'`\\$\\\\]", var.passphrase))
    error_message = "passphrase must not contain whitespace, quotes, backticks, dollar signs or backslashes, because it is interpolated into a shell command in the instance's userdata. A character the shell expands produces a passphrase that differs between the ACM export and the openssl decrypt, which fails with \"bad decrypt\" rather than with anything naming this variable."
  }
}
variable "install_development_tools" {
  type        = bool
  default     = true
  description = "Whether the bootstrap installs the Development Tools group, as the _monolithic template did. Nothing here compiles anything - the script needs jq, openssl and the AWS CLI, and the first is installed separately while the other two are already on the AMI - so this is several minutes of download that only matters because it is several minutes of the caller's export timeout"
}
