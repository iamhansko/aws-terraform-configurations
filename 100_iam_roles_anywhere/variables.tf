variable "aws_region" {
  type        = string
  default     = null
  description = "Region everything is created in. Null falls back to the provider's own chain (AWS_REGION, the shared config file, the instance profile), which is how the _monolithic template had it"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", coalesce(var.aws_region, "us-east-1")))
    error_message = "aws_region must be an AWS region name (e.g. ap-northeast-2), or null to use the provider's default chain."
  }
}
variable "stack_name" {
  type        = string
  default     = "roles"
  description = "Stands in for AWS::StackName, as the _monolithic template had it. Its only remaining use is the prefix of the Lambda function name, which CloudFormation generated and Terraform requires"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.stack_name))
    error_message = "stack_name must be 1-32 characters of letters, digits and hyphens, so that it can be part of a Lambda function name."
  }
}
variable "passphrase" {
  type        = string
  sensitive   = true
  default     = "rolePassword1234!"
  description = <<-DESC
    Passphrase ACM encrypts the exported private key with, and that openssl on the export instance
    then uses to decrypt it, as the _monolithic template had it.

    Marked sensitive here and in the module, which the conversion did not do. It is still written
    into the instance's user_data and still stored in state in clear, so this hides it from plan
    output and from nothing else - see the module's variable for the full account.
  DESC

  validation {
    condition     = length(var.passphrase) >= 4 && length(var.passphrase) <= 128
    error_message = "passphrase must be 4-128 characters, the range ACM accepts for an export passphrase."
  }
  validation {
    condition     = !can(regex("[\\s\"'`\\$\\\\]", var.passphrase))
    error_message = "passphrase must not contain whitespace, quotes, backticks, dollar signs or backslashes, because it is interpolated into a shell command in the instance's userdata (rules.md B-1)."
  }
}
variable "amazon_linux2023_ami_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM public parameter the export instance's AMI is read from, as the _monolithic template had it. It has to resolve to a dnf-based Amazon Linux with openssl and the SSM agent already present, because the bootstrap assumes all three"

  validation {
    condition     = can(regex("^/", var.amazon_linux2023_ami_parameter_name))
    error_message = "amazon_linux2023_ami_parameter_name must be an SSM parameter path starting with a slash."
  }
}
variable "bastion_export_timeout_seconds" {
  type        = number
  default     = 900
  description = <<-DESC
    How long the apply waits for the certificate export to finish and the four objects to appear in
    S3, and therefore the terminator Lambda's timeout: the function polls the bucket for exactly
    this long before it gives up, and only terminates the instance once the objects are there.

    It covers the whole bootstrap, from launch to the last put-object. Most of that budget is dnf:
    a full package update plus the Development Tools group is several minutes on a t3.medium, which
    is what bastion_install_development_tools can take back. The CreationPolicy this replaces
    allowed 10 minutes for the same work.

    At most 900, because that is the longest a Lambda function can run. The SSM association that
    used to carry this wait allowed up to an hour and did not actually wait - see the root main.tf.
  DESC

  validation {
    condition     = var.bastion_export_timeout_seconds >= 300 && var.bastion_export_timeout_seconds <= 900
    error_message = "bastion_export_timeout_seconds must be between 300 and 900. It is the terminator Lambda's timeout, and 900 is the most Lambda accepts; below 300 a full dnf update can outlast the wait, and the apply fails with the export still running."
  }
}
variable "session_duration_seconds" {
  type        = number
  default     = 43200
  description = <<-DESC
    Longest session IAM Roles Anywhere hands out here, applied to both the profile's
    duration_seconds and the vended role's max_session_duration.

    One value for both, because the effective limit is the smaller of the two and the _monolithic
    template set only one of them - see the module variable of the same name for what that
    produced. The credential helper still requests 3600 unless given --session-duration, which the
    test scripts in the outputs point out.
  DESC

  validation {
    condition     = var.session_duration_seconds >= 900 && var.session_duration_seconds <= 43200
    error_message = "session_duration_seconds must be between 900 and 43200, the range IAM accepts for a role's MaxSessionDuration."
  }
}
# --- network -------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "vpc_name" {
  type        = string
  default     = "vpc"
  description = "Name tag for the VPC, as the _monolithic template had it"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "igw"
  description = "Name tag for the internet gateway, as the _monolithic template had it"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "public-subnet"
  description = "Name tag for the public subnet, as the _monolithic template had it"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "public-rt"
  description = "Name tag for the public route table, as the _monolithic template had it"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
# --- private certificate authority ---------------------------------------------------------------
variable "ca_key_storage_security_standard" {
  type        = string
  default     = "FIPS_140_2_LEVEL_3_OR_HIGHER"
  description = "HSM class backing the CA key, as the _monolithic template had it. Level 3 is not offered in every region; where it is not, the create call fails with InvalidArgsException and the answer is level 2"

  validation {
    condition     = contains(["FIPS_140_2_LEVEL_2_OR_HIGHER", "FIPS_140_2_LEVEL_3_OR_HIGHER"], var.ca_key_storage_security_standard)
    error_message = "ca_key_storage_security_standard must be FIPS_140_2_LEVEL_2_OR_HIGHER or FIPS_140_2_LEVEL_3_OR_HIGHER."
  }
}
variable "ca_key_algorithm" {
  type        = string
  default     = "RSA_2048"
  description = "Algorithm of the CA key pair, as the _monolithic template had it. Has to stay RSA, because the test scripts prove the exported key matches the certificate with openssl rsa"

  validation {
    condition     = contains(["RSA_2048", "RSA_4096", "EC_prime256v1", "EC_secp384r1"], var.ca_key_algorithm)
    error_message = "ca_key_algorithm must be one of RSA_2048, RSA_4096, EC_prime256v1, EC_secp384r1."
  }
}
variable "ca_signing_algorithm" {
  type        = string
  default     = "SHA256WITHRSA"
  description = "Algorithm the CA signs with, as the _monolithic template had it. Must match the key family in ca_key_algorithm; the module rejects a mismatched pair in plan rather than letting apply fail on InvalidArgsException"

  validation {
    condition = contains([
      "SHA256WITHRSA", "SHA384WITHRSA", "SHA512WITHRSA",
      "SHA256WITHECDSA", "SHA384WITHECDSA", "SHA512WITHECDSA",
    ], var.ca_signing_algorithm)
    error_message = "ca_signing_algorithm must be one of SHA256WITHRSA, SHA384WITHRSA, SHA512WITHRSA, SHA256WITHECDSA, SHA384WITHECDSA, SHA512WITHECDSA."
  }
}
variable "ca_subject_organization" {
  type        = string
  default     = "Peccy Inc"
  description = "Organization in the CA's subject distinguished name, as the _monolithic template had it"

  validation {
    condition     = length(var.ca_subject_organization) > 0 && length(var.ca_subject_organization) <= 64
    error_message = "ca_subject_organization must be 1-64 characters, the X.509 limit for the O attribute."
  }
}
variable "ca_subject_organizational_unit" {
  type        = string
  default     = "Red Team"
  description = "Organizational unit in the CA's subject distinguished name, as the _monolithic template had it"

  validation {
    condition     = length(var.ca_subject_organizational_unit) > 0 && length(var.ca_subject_organizational_unit) <= 64
    error_message = "ca_subject_organizational_unit must be 1-64 characters, the X.509 limit for the OU attribute."
  }
}
variable "ca_subject_country" {
  type        = string
  default     = "KR"
  description = "Two letter country code in the CA's subject distinguished name, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[A-Z]{2}$", var.ca_subject_country))
    error_message = "ca_subject_country must be a two letter uppercase ISO 3166-1 alpha-2 code (e.g. KR)."
  }
}
variable "ca_certificate_validity_years" {
  type        = number
  default     = 10
  description = "Validity of the CA's self-signed certificate in years, as the _monolithic template had it. It has to outlast every certificate the CA issues - one valid past its issuer's expiry is issued without complaint and then fails validation"

  validation {
    condition     = var.ca_certificate_validity_years >= 1 && var.ca_certificate_validity_years <= 100
    error_message = "ca_certificate_validity_years must be between 1 and 100."
  }
}
variable "ca_permanent_deletion_time_in_days" {
  type        = number
  default     = 7
  description = "Days a deleted CA stays restorable. 7, the AWS minimum, rather than the provider default of 30 the _monolithic template inherited - the CA is the one resource here billed by the month, and a demo CA is not worth keeping restorable"

  validation {
    condition     = var.ca_permanent_deletion_time_in_days >= 7 && var.ca_permanent_deletion_time_in_days <= 30
    error_message = "ca_permanent_deletion_time_in_days must be between 7 and 30, the range AWS Private CA accepts."
  }
}
# --- issued client certificate -------------------------------------------------------------------
variable "certificate_domain_name" {
  type        = string
  default     = "rolesanywhere.com"
  description = "Subject common name of the certificate the CA issues, as the _monolithic template had it. Nothing resolves it - it identifies the certificate rather than naming a host"

  validation {
    condition     = can(regex("^[a-zA-Z0-9*]([a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?$", var.certificate_domain_name))
    error_message = "certificate_domain_name must be a DNS-shaped name of at most 253 characters, which is the form ACM accepts for a certificate subject."
  }
}
variable "certificate_key_algorithm" {
  type        = string
  default     = "RSA_2048"
  description = "Key algorithm of the issued certificate, as the _monolithic template had it. Has to stay RSA for the same reason as the CA's key"

  validation {
    condition     = contains(["RSA_1024", "RSA_2048", "EC_prime256v1", "EC_secp384r1", "EC_secp521r1"], var.certificate_key_algorithm)
    error_message = "certificate_key_algorithm must be one of RSA_1024, RSA_2048, EC_prime256v1, EC_secp384r1, EC_secp521r1."
  }
}
# --- IAM Roles Anywhere --------------------------------------------------------------------------
variable "trust_anchor_name" {
  type        = string
  default     = "iam-ra-ta"
  description = "Name of the trust anchor, as the _monolithic template had it. Account-wide and region-wide, so a second copy of this project in the same region fails on it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.:/=+@-]{1,255}$", var.trust_anchor_name))
    error_message = "trust_anchor_name must be 1-255 characters of letters, digits and _.:/=+@-."
  }
}
variable "profile_name" {
  type        = string
  default     = "iam-ra-profile"
  description = "Name of the IAM Roles Anywhere profile, as the _monolithic template had it. Account-wide and region-wide, like the trust anchor name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.:/=+@-]{1,255}$", var.profile_name))
    error_message = "profile_name must be 1-255 characters of letters, digits and _.:/=+@-."
  }
}
variable "vended_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
  description = "Managed policies on the role a certificate vends, as the _monolithic template had them. The test scripts assert both halves of this - that s3:ListBucket works and that s3:PutObject and ec2:DescribeInstances are refused - so widening it makes those deny checks fail, which is the check working"

  validation {
    condition     = length(var.vended_role_policy_arns) > 0 && alltrue([for arn in var.vended_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "vended_role_policy_arns must be a non-empty list of IAM policy ARNs."
  }
}
# --- artifact bucket -----------------------------------------------------------------------------
variable "artifact_bucket_prefix" {
  type        = string
  default     = "iam-roles-anywhere-"
  description = "Prefix for the generated name of the bucket the exported certificate and key land in. The _monolithic template named the bucket nothing at all and took the provider's terraform-<timestamp> default, which says nothing about what is in it"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,40}$", var.artifact_bucket_prefix))
    error_message = "artifact_bucket_prefix must be 2-41 characters of lowercase letters, digits, dots and hyphens."
  }
}
variable "artifact_bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether destroy empties the bucket first, as the _monolithic template had it. True, and deliberately so: the bootstrap writes four objects Terraform does not track, and one of them is an unencrypted private key that should not outlive the demo"
}
# --- export instance -----------------------------------------------------------------------------
variable "bastion_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the export instance, as the _monolithic template had it. The size decides how long the bootstrap takes, which is what bastion_export_timeout_seconds has to cover"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.bastion_instance_type))
    error_message = "bastion_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "bastion_instance_name" {
  type        = string
  default     = "bastion-ec2"
  description = "Name tag for the export instance, as the _monolithic template had it. Kept at the template's value so a console listing matches the original, even though the module is named for what the instance actually does"

  validation {
    condition     = length(var.bastion_instance_name) > 0
    error_message = "bastion_instance_name must not be empty."
  }
}
variable "bastion_security_group_name" {
  type        = string
  default     = "certificate-export-ec2-sg"
  description = "Name of the export instance's security group. Nothing in the _monolithic template to match: it attached the VPC's default security group instead - see the module's main.tf for why a group of its own is created here"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.bastion_security_group_name)) && !startswith(var.bastion_security_group_name, "sg-")
    error_message = "bastion_security_group_name must be 1-255 characters from the set AWS accepts for a security group name, with no apostrophe, and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "bastion_security_group_description" {
  type        = string
  default     = "Outbound only group for the instance that exports the issued certificate to S3"
  description = "Description for that security group. No apostrophe: EC2 rejects one with InvalidParameterValue, and changing this value at all replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.bastion_security_group_description))
    error_message = "bastion_security_group_description must be 1-255 characters from the set AWS accepts for a security group description, with no apostrophe (rules.md F-1)."
  }
}
variable "bastion_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  description = <<-DESC
    Managed policies on the export instance's role, on top of the inline policy the module writes
    for the export itself.

    The _monolithic template attached AdministratorAccess. This narrows it, which A-5 allows for a
    policy the original really did write as long as the reason is recorded - the module's main.tf
    carries the full account. In short: this instance is not a workbench, nobody logs into it, it
    runs one script and is terminated in the same apply, and while it runs it holds an unencrypted
    private key. Adding arn:aws:iam::aws:policy/AdministratorAccess here reproduces the template.
  DESC

  validation {
    condition     = alltrue([for arn in var.bastion_iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "bastion_iam_policy_arns must contain IAM policy ARNs."
  }
}
variable "bastion_install_development_tools" {
  type        = bool
  default     = true
  description = "Whether the bootstrap installs the Development Tools group, as the _monolithic template did. Nothing in the script compiles anything, so this is only a few minutes of the export timeout's budget"
}
# --- terminator Lambda ---------------------------------------------------------------------------
variable "lambda_function_name_suffix" {
  type        = string
  default     = "instance-terminator"
  description = "Suffix appended to stack_name to name the Lambda function. The _monolithic template's name was custom-resource-lambda-function, after the CloudFormation custom resource this no longer is - see the module's main.tf"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,31}$", var.lambda_function_name_suffix))
    error_message = "lambda_function_name_suffix must be 1-31 characters of letters, digits, hyphens and underscores, so that stack_name plus this fits the 64 character Lambda function name limit."
  }
}
variable "lambda_source_relative_path" {
  type        = string
  default     = "lambda_src/custom_resource_lambda_function/index.py"
  description = "Path, relative to this root, of the Python the deployment package is built from. A variable so the layout is stated rather than assumed, and relative because archive_file resolves it against path.module"

  validation {
    condition     = can(regex("^[^/].*\\.py$", var.lambda_source_relative_path))
    error_message = "lambda_source_relative_path must be a relative path to a .py file."
  }
}
variable "lambda_build_relative_path" {
  type        = string
  default     = "build/custom_resource_lambda_function.zip"
  description = "Path, relative to this root, where the built deployment package is written. The build/ directory is a product of plan rather than something to edit - archive_file writes the zip while the configuration is read"

  validation {
    condition     = can(regex("^[^/].*\\.zip$", var.lambda_build_relative_path))
    error_message = "lambda_build_relative_path must be a relative path to a .zip file."
  }
}
variable "lambda_handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point of the function, as module.function. Must match the Python in lambda_source_relative_path, which archive_file zips as index.py; a mismatch is created without complaint and fails every invocation with Runtime.HandlerNotFound"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+\\.[A-Za-z0-9_]+$", var.lambda_handler))
    error_message = "lambda_handler must be of the form module.function (e.g. index.lambda_handler)."
  }
}
variable "lambda_runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime, as the _monolithic template had it. Must stay Python: the package is one .py file and boto3 is on the path only because the Python runtimes bundle it"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.lambda_runtime))
    error_message = "lambda_runtime must be a python3.x runtime."
  }
}
variable "lambda_policy_actions" {
  type        = list(string)
  default     = ["ec2:DescribeInstances", "ec2:TerminateInstances"]
  description = "EC2 actions on the function's role. The _monolithic template granted ec2:*; the handler makes two EC2 calls - DescribeInstances while it waits for the export, TerminateInstances once it has arrived - so this is those two (rules.md A-5, and the module's main.tf for the reasoning). The function's timeout is not a separate variable: it is bastion_export_timeout_seconds, because the invocation is the wait"

  validation {
    condition     = length(var.lambda_policy_actions) > 0 && alltrue([for action in var.lambda_policy_actions : can(regex("^ec2:[A-Za-z*]+$", action))])
    error_message = "lambda_policy_actions must be a non-empty list of ec2: actions."
  }
}
variable "lambda_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  description = "Managed policies on the function's role, as the _monolithic template had them. AWSLambdaBasicExecutionRole is what lets it write the log that explains a failed invocation"

  validation {
    condition     = alltrue([for arn in var.lambda_iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "lambda_iam_policy_arns must contain IAM policy ARNs."
  }
}
