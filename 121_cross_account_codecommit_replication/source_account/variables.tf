variable "aws_region" {
  type        = string
  default     = null
  description = "Source-account region. Null follows the AWS provider credential chain."

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}

variable "source_account_id" {
  type        = string
  description = "Twelve-digit AWS account ID in which this source root must be applied."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }
}

variable "target_account_id" {
  type        = string
  description = "Twelve-digit AWS account ID containing the replication target."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.target_account_id))
    error_message = "target_account_id must be a 12-digit AWS account ID."
  }

  validation {
    condition     = var.target_account_id != var.source_account_id
    error_message = "target_account_id must differ from source_account_id; use a same-account replication design when both repositories share an account."
  }
}

variable "target_region" {
  type        = string
  description = "Region containing the target CodeCommit repository; take this from target_account.source_root_handoff."

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.target_region))
    error_message = "target_region must be a region code such as ap-northeast-2."
  }
}

variable "source_account_repository" {
  type        = string
  default     = "a-repo"
  description = "Source CodeCommit repository watched on main_branch."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.source_account_repository))
    error_message = "source_account_repository must be 1-100 characters of letters, digits, dots, underscores, and hyphens."
  }
}

variable "target_account_repository" {
  type        = string
  default     = "b-repo"
  description = "Target CodeCommit repository; this must equal the target root's agreed repository name."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.target_account_repository))
    error_message = "target_account_repository must be 1-100 characters of letters, digits, dots, underscores, and hyphens."
  }
}

variable "cross_account_role_name" {
  type        = string
  default     = "CrossAccountRole"
  description = "Fixed role name created by the independently applied target root."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.cross_account_role_name))
    error_message = "cross_account_role_name must be 1-64 characters accepted by IAM role names."
  }
}

variable "source_codebuild_role_name" {
  type        = string
  default     = "CodeCommitReplicationBuildRole"
  description = "Fixed source CodeBuild role name named in the target root's trust-policy condition."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.source_codebuild_role_name))
    error_message = "source_codebuild_role_name must be 1-64 characters accepted by IAM role names."
  }
}

variable "main_branch" {
  type        = string
  default     = "main"
  description = "Source branch whose creation and updates start replication."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]{0,254}$", var.main_branch)) && !strcontains(var.main_branch, "..") && !strcontains(var.main_branch, "@{") && !endswith(var.main_branch, "/") && !endswith(var.main_branch, ".")
    error_message = "main_branch must be a plain Git branch name without '..', '@{', or a trailing slash/dot."
  }
}

variable "project_name" {
  type        = string
  default     = "codecommit-replication"
  description = "Stable prefix used for generated same-account role and resource names."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,39}$", var.project_name))
    error_message = "project_name must be 2-40 lowercase letters, digits, or hyphens and start with a letter or digit."
  }
}

variable "pipeline_name" {
  type        = string
  default     = "codecommit-replication-pipeline"
  description = "Name of the source-account replication pipeline."

  validation {
    condition     = can(regex("^[A-Za-z0-9.@_-]{1,100}$", var.pipeline_name))
    error_message = "pipeline_name must be 1-100 characters accepted by CodePipeline names."
  }
}

variable "build_project_name" {
  type        = string
  default     = "codecommit-replication-build"
  description = "Name of the CodeBuild project that mirrors Git refs."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.build_project_name))
    error_message = "build_project_name must be 2-255 letters, digits, underscores, or hyphens and start with a letter or digit."
  }
}

variable "event_rule_name" {
  type        = string
  default     = "codecommit-replication-main"
  description = "Name of the EventBridge rule that starts the pipeline."

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{1,64}$", var.event_rule_name))
    error_message = "event_rule_name must be 1-64 characters accepted by EventBridge rule names."
  }
}

variable "artifact_bucket_prefix" {
  type        = string
  default     = "codecommit-replication-artifacts-"
  description = "Prefix for the generated pipeline artifact bucket name."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,35}[a-z0-9-]$", var.artifact_bucket_prefix)) && !strcontains(var.artifact_bucket_prefix, "--")
    error_message = "artifact_bucket_prefix must be 2-37 lowercase letters, digits, or hyphens and start with a letter or digit."
  }
}

variable "codebuild_image" {
  type        = string
  default     = "aws/codebuild/standard:7.0"
  description = "Pinned managed CodeBuild standard image containing Git and AWS CLI; replication does not install tools at runtime."

  validation {
    condition     = var.codebuild_image == "aws/codebuild/standard:7.0"
    error_message = "codebuild_image must stay aws/codebuild/standard:7.0. The buildspec relies on its bundled Git, Bash, and AWS CLI and intentionally performs no network installs."
  }
}

variable "codebuild_compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
  description = "CodeBuild compute size for Git mirroring."

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE"], var.codebuild_compute_type)
    error_message = "codebuild_compute_type must be a supported BUILD_GENERAL1 Linux container size."
  }
}

variable "build_timeout_minutes" {
  type        = number
  default     = 15
  description = "Maximum duration of one repository mirror build."

  validation {
    condition     = var.build_timeout_minutes >= 5 && var.build_timeout_minutes <= 2160
    error_message = "build_timeout_minutes must be between 5 and 2160."
  }
}

variable "build_log_retention_days" {
  type        = number
  default     = 14
  description = "CloudWatch Logs retention for CodeBuild output."

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.build_log_retention_days)
    error_message = "build_log_retention_days must be a retention period CloudWatch Logs accepts."
  }
}

variable "initial_commit_file_path" {
  type        = string
  default     = "README.md"
  description = "Repository-relative file path written by the create-only initial commit before CodePipeline is created."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]{0,255}$", var.initial_commit_file_path)) && alltrue([for segment in split("/", var.initial_commit_file_path) : !contains(["", ".", ".."], segment)])
    error_message = "initial_commit_file_path must be a 1-256 character relative path using letters, digits, dots, underscores, slashes, or hyphens, without empty, '.' or '..' segments."
  }
}

variable "initial_commit_file_content" {
  type        = string
  default     = "# Cross-account CodeCommit replication\n"
  description = "Non-empty content written to initial_commit_file_path when the source repository has no branch."

  validation {
    condition     = length(trimspace(var.initial_commit_file_content)) > 0 && length(var.initial_commit_file_content) <= 8192
    error_message = "initial_commit_file_content must contain 1-8192 characters and must not be only whitespace."
  }
}

variable "initial_commit_message" {
  type        = string
  default     = "Initialize main before CodePipeline creation"
  description = "Commit message for the create-only commit that establishes main_branch."

  validation {
    condition     = length(trimspace(var.initial_commit_message)) > 0 && length(var.initial_commit_message) <= 256
    error_message = "initial_commit_message must contain 1-256 characters and must not be only whitespace."
  }
}

variable "pipeline_role_propagation_wait_seconds" {
  type        = number
  default     = 30
  description = <<-DESC
    How long to wait after writing the CodePipeline service role policy before creating the pipeline.

    IAM is eventually consistent across service endpoints. Without this wait, an immediate first execution
    can fail its Source action with "no identity-based policy allows codecommit:GetBranch" even though
    GetRolePolicy already returns that exact permission. A later retry succeeds after propagation, but that
    leaves a fresh deployment dependent on a second run rather than fixing its creation order.
  DESC

  validation {
    condition     = var.pipeline_role_propagation_wait_seconds >= 0 && floor(var.pipeline_role_propagation_wait_seconds) == var.pipeline_role_propagation_wait_seconds
    error_message = "pipeline_role_propagation_wait_seconds must be a whole number of seconds, zero or greater."
  }
}

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the source-account workbench VPC."

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0)) && tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR of /24 or shorter."
  }
}

variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "Availability-zone suffix for the one public workbench subnet."

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be one lowercase letter."
  }
}

variable "vpc_name" {
  type        = string
  default     = "codecommit-replication-vpc"
  description = "Name tag for the workbench VPC."

  validation {
    condition     = length(trimspace(var.vpc_name)) > 0 && length(var.vpc_name) <= 255
    error_message = "vpc_name must be 1-255 characters and not blank."
  }
}

variable "internet_gateway_name" {
  type        = string
  default     = "codecommit-replication-igw"
  description = "Name tag for the workbench internet gateway."

  validation {
    condition     = length(trimspace(var.internet_gateway_name)) > 0 && length(var.internet_gateway_name) <= 255
    error_message = "internet_gateway_name must be 1-255 characters and not blank."
  }
}

variable "public_subnet_name" {
  type        = string
  default     = "codecommit-replication-public"
  description = "Base Name tag for the public workbench subnet."

  validation {
    condition     = length(trimspace(var.public_subnet_name)) > 0 && length(var.public_subnet_name) <= 253
    error_message = "public_subnet_name must be 1-253 characters and not blank."
  }
}

variable "public_route_table_name" {
  type        = string
  default     = "codecommit-replication-public-rt"
  description = "Name tag for the public route table."

  validation {
    condition     = length(trimspace(var.public_route_table_name)) > 0 && length(var.public_route_table_name) <= 255
    error_message = "public_route_table_name must be 1-255 characters and not blank."
  }
}

variable "key_name" {
  type        = string
  default     = null
  description = "Optional exact EC2 key-pair name; null uses key_name_prefix and a generated suffix."

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters, or null."
  }
}

variable "key_name_prefix" {
  type        = string
  default     = "codecommit-replication-key-"
  description = "Prefix for the generated EC2 key-pair name."

  validation {
    condition     = can(regex("^[ -~]{1,200}$", var.key_name_prefix))
    error_message = "key_name_prefix must be 1-200 printable ASCII characters."
  }
}

variable "key_rsa_bits" {
  type        = number
  default     = 4096
  description = "RSA size for the generated workbench key pair."

  validation {
    condition     = contains([2048, 3072, 4096], var.key_rsa_bits)
    error_message = "key_rsa_bits must be 2048, 3072, or 4096."
  }
}

variable "vscode_name" {
  type        = string
  default     = "codecommit-replication-workbench"
  description = "Name tag and generated IAM-name prefix for the code-server workbench."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,37}$", var.vscode_name))
    error_message = "vscode_name must be 1-37 IAM-compatible characters, leaving room for Terraform's generated role-name suffix."
  }
}

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the source workbench."

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type such as t3.medium."
  }
}

variable "vscode_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Public SSM parameter resolving to the AL2023 workbench AMI."

  validation {
    condition     = can(regex("^/", var.vscode_ami_ssm_parameter_name))
    error_message = "vscode_ami_ssm_parameter_name must be an absolute SSM parameter path."
  }
}

variable "vscode_root_volume_size" {
  type        = number
  default     = 30
  description = "Encrypted gp3 root volume size in GiB."

  validation {
    condition     = var.vscode_root_volume_size >= 8 && var.vscode_root_volume_size <= 16384
    error_message = "vscode_root_volume_size must be between 8 and 16384 GiB."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.109.5"
  description = "Pinned code-server release installed on the workbench."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "code_server_port" {
  type        = number
  default     = 8000
  description = "TCP port on which code-server listens."

  validation {
    condition     = var.code_server_port >= 1 && var.code_server_port <= 65535
    error_message = "code_server_port must be between 1 and 65535."
  }
}

variable "vscode_security_group_name_prefix" {
  type        = string
  default     = "codecommit-replication-workbench-"
  description = "Generated name prefix for the workbench security group."

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,200}$", var.vscode_security_group_name_prefix)) && !startswith(var.vscode_security_group_name_prefix, "sg-")
    error_message = "vscode_security_group_name_prefix must use the EC2 security-group character set, contain no apostrophe, and not start with sg-."
  }
}

variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the controlled inbound rules use 0.0.0.0/0. When false (the default), they use only the public IPv4 /32 dynamically returned by my_ip_lookup_url"
}

variable "ingress_prefix_list_ids" {
  type        = list(string)
  default     = []
  description = "Static managed prefix-list IDs also allowed to reach code-server."

  validation {
    condition     = alltrue([for id in var.ingress_prefix_list_ids : can(regex("^pl-[0-9a-f]+$", id))])
    error_message = "ingress_prefix_list_ids must contain valid managed prefix-list IDs."
  }
}

variable "vscode_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AWSCodeCommitPowerUser",
    "arn:aws:iam::aws:policy/AWSCodePipeline_ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSCodeBuildReadOnlyAccess",
  ]
  description = "Managed policies for Session Manager, seeding the source repository, and reading pipeline/build status. The human workbench does not receive account administrator access."

  validation {
    condition     = length(var.vscode_iam_policy_arns) > 0 && alltrue([for arn in var.vscode_iam_policy_arns : can(regex("^arn:[a-z0-9-]+:iam::aws:policy/", arn))])
    error_message = "vscode_iam_policy_arns must contain AWS managed-policy ARNs."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Absolute workbench directory containing userdata and README completion markers."

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path."
  }
}

variable "readme_timeout_seconds" {
  type        = number
  default     = 1200
  description = "Maximum SSM association wait while workbench userdata completes and README is written."

  validation {
    condition     = var.readme_timeout_seconds >= 60 && var.readme_timeout_seconds <= 3600
    error_message = "readme_timeout_seconds must be between 60 and 3600."
  }
}

variable "my_ip_lookup_url" {
  type        = string
  default     = "https://checkip.amazonaws.com/"
  description = "Trusted HTTPS endpoint that returns the public IPv4 address of the machine running Terraform. The address is converted to a /32 and used when an allow_inbound_from_anywhere switch is false"

  validation {
    condition     = startswith(var.my_ip_lookup_url, "https://")
    error_message = "my_ip_lookup_url must be an HTTPS URL because its response controls which source address the security groups admit."
  }
}
