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
  default     = "lambda-container"
  description = "Prefix for the generated names - the key pair, the bucket, the IAM roles - and the heading of the README written onto the workbench. The names the _monolithic template set literally are their own variables below, with its values as defaults"

  validation {
    # 20, so "<project_name>-result-" stays inside S3's 37-character bucket_prefix limit.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,19}$", var.project_name))
    error_message = "project_name must be 2-20 characters of lowercase letters, digits and hyphens, so the bucket prefix built from it stays inside S3's 37-character limit."
  }
}
# --- Network ----------------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "public_subnet_cidr_block" {
  type        = string
  default     = "10.0.0.0/24"
  description = "CIDR block of the one public subnet, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr_block, 0))
    error_message = "public_subnet_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/24)."
  }
}
variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "Zone letter for the public subnet, as the _monolithic template hard-coded it"

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single lowercase letter (e.g. a)."
  }
}
# --- Workbench --------------------------------------------------------------------------------------------
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the workbench AMI, as the _monolithic template's AmiId parameter had it. x86_64, which is also what fixes the function's architecture: the image is built natively on this instance"

  validation {
    condition     = can(regex("^/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "vscode_instance_name" {
  type        = string
  default     = "vscode"
  description = "Name tag of the workbench, as the _monolithic template had it"

  validation {
    condition     = length(var.vscode_instance_name) > 0
    error_message = "vscode_instance_name must not be empty."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the workbench, as the _monolithic template had it. Has to be x86_64, because the function is x86_64 and the image is built natively here"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type)) && !can(regex("^[a-z]+[0-9]+g[a-z]*\\.", var.vscode_instance_type))
    error_message = "vscode_instance_type must be an x86_64 EC2 instance type (e.g. t3.medium). A Graviton type (t4g, m7g, ...) cannot boot the x86_64 AMI, and an image built on one would not run on the x86_64 function either."
  }
}
variable "vscode_root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. Larger than the 8 GiB AL2023 default the _monolithic template took, because the Lambda base image and the build cache land on this disk"

  validation {
    condition     = var.vscode_root_volume_size >= 8
    error_message = "vscode_root_volume_size must be at least 8 GiB, the size of the AL2023 root snapshot."
  }
}
variable "vscode_security_group_name" {
  type        = string
  default     = "vscode-sg"
  description = "Name of the workbench security group, as the _monolithic template had it. Unique per VPC rather than per account, so the literal does not collide with other projects"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.vscode_security_group_name)) && !startswith(var.vscode_security_group_name, "sg-")
    error_message = "vscode_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether code-server is reachable from 0.0.0.0/0, as the _monolithic template's InboundFromAnywhere parameter switched it - a bool now, where the template took the strings \"True\" and \"False\". False opens nothing, and the workbench is then reachable only through Session Manager. code-server runs with auth: none, so true is an unauthenticated shell with AdministratorAccess on a public address"
}
variable "ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Sources allowed to SSH to the workbench. Empty, as the _monolithic template had it: it generated a key pair and opened no SSH port"

  validation {
    condition     = alltrue([for cidr in var.ssh_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ssh_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.104.2"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.104.2)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to, as the _monolithic template had it"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "vscode_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "Managed policies on the workbench role, as the _monolithic template had them. rules.md A-5 exempts the workbench: a person sits here and rebuilds, pushes, updates and invokes, and guessing that list in advance produces an AccessDenied halfway through a demo"

  validation {
    condition     = alltrue([for arn in var.vscode_iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "vscode_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "key_rsa_bits" {
  type        = number
  default     = 4096
  description = "Size of the generated RSA key, as the _monolithic template had it"

  validation {
    condition     = contains([2048, 3072, 4096], var.key_rsa_bits)
    error_message = "key_rsa_bits must be 2048, 3072 or 4096."
  }
}
# --- Image ------------------------------------------------------------------------------------------------
variable "ecr_repository_name" {
  type        = string
  default     = "lambda"
  description = "Name of the ECR repository, as the _monolithic template had it. Account-and-region unique, so a second copy of this project in one account collides here - change it for the second"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.ecr_repository_name))
    error_message = "ecr_repository_name must start with a lowercase letter or digit and contain only lowercase letters, digits and . _ / -."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "The tag the workbench pushes and the function is created from, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid container image tag."
  }
}
variable "ecr_force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository with images still in it. True as the _monolithic template had it, and necessary: the images are pushed by the workbench, not by Terraform"
}
variable "ecr_scan_on_push" {
  type        = bool
  default     = false
  description = "Whether ECR runs a basic vulnerability scan on each push. False, which is what the _monolithic template got by not configuring it"
}
# --- Function ---------------------------------------------------------------------------------------------
variable "function_name" {
  type        = string
  default     = "python-container"
  description = "Name of the Lambda function, as the _monolithic template had it. Account-and-region unique"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "lambda_timeout" {
  type        = number
  default     = 15
  description = "Seconds an invocation may run, as the _monolithic template had it"

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 1 and 900 seconds."
  }
}
variable "lambda_memory_size" {
  type        = number
  default     = 128
  description = "Memory in MB, as the _monolithic template had it"

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "lambda_memory_size must be between 128 and 10240 MB."
  }
}
variable "lambda_log_retention_in_days" {
  type        = number
  default     = 14
  description = "Days CloudWatch keeps the function's logs. An addition: the _monolithic template let Lambda create the group itself, which never expires and outlives terraform destroy"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.lambda_log_retention_in_days)
    error_message = "lambda_log_retention_in_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, ...)."
  }
}
variable "lambda_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Extra managed policies on the function's role. Empty: its one S3 call is granted inline. Set [\"arn:aws:iam::aws:policy/AmazonS3FullAccess\"] for the _monolithic template's breadth (rules.md A-5)"

  validation {
    condition     = alltrue([for arn in var.lambda_additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "lambda_additional_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "result_object_key" {
  type        = string
  default     = "cat.html"
  description = "Key the function writes its page to, as the _monolithic template's handler hard-coded it. The handler reads it as OBJECT_KEY and the role's S3 grant is scoped to it, so one value reaches both"

  validation {
    condition     = length(var.result_object_key) >= 1 && length(var.result_object_key) <= 1024 && !startswith(var.result_object_key, "/")
    error_message = "result_object_key must be 1-1024 characters and must not start with a slash."
  }
}
variable "source_url" {
  type        = string
  default     = "https://cataas.com/cat?html=true"
  description = "Page the function fetches, as the _monolithic template's handler hard-coded it"

  validation {
    condition     = can(regex("^https?://", var.source_url))
    error_message = "source_url must be an http or https URL."
  }
}
variable "source_request_timeout_seconds" {
  type        = number
  default     = 10
  description = "Seconds the handler waits on source_url before giving up. An addition: the _monolithic template's requests.get had no timeout, so a stalled connection ran into Lambda's own timeout and the log said only that the invocation timed out"

  validation {
    # About the pair, so a cross-variable condition (rules.md B-1). The references run one way only - nothing
    # in lambda_timeout's validation reads this - so it cannot form a cycle.
    condition     = var.source_request_timeout_seconds > 0 && var.source_request_timeout_seconds < var.lambda_timeout
    error_message = "source_request_timeout_seconds must be positive and shorter than lambda_timeout, so the handler can report a stalled fetch itself before Lambda kills the invocation."
  }
}
variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the result bucket before deleting it. The _monolithic template declared a bare bucket, so a destroy after a single invocation stopped at BucketNotEmpty. True, and the page the function wrote goes with it"
}
# --- Ordering and waits -----------------------------------------------------------------------------------
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each bootstrap stage drops its completion marker. The associations wait on these rather than on depends_on or a provider timeout (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "image_wait_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the image gate may take. It waits for the whole workbench bootstrap - dnf update, the Development Tools group, code-server, docker - and then for the image to be in ECR. The same value, capped at Lambda's 900 seconds, is how long modules/ecr_image_waiter holds CreateFunction"

  validation {
    condition     = var.image_wait_timeout_seconds > 0
    error_message = "image_wait_timeout_seconds must be positive."
  }
}
variable "image_wait_attempts" {
  type        = number
  default     = 60
  description = "How many times the image gate polls, first for the bootstrap marker and then for the image"

  validation {
    condition     = var.image_wait_attempts >= 1
    error_message = "image_wait_attempts must be at least 1."
  }

  validation {
    # About the combination, so a cross-variable condition (rules.md B-1). The gate has two sequential polling
    # phases; if SSM gives up first the association reports a bare "Failed", where the script's own timeout
    # says which phase stalled.
    condition     = var.image_wait_attempts * var.image_wait_interval_seconds * 2 < var.image_wait_timeout_seconds
    error_message = "image_wait_attempts * image_wait_interval_seconds * 2 must be below image_wait_timeout_seconds, so the gate reports which phase timed out instead of SSM reporting an unexplained Failed."
  }
}
variable "image_wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds between polls in the image gate"

  validation {
    condition     = var.image_wait_interval_seconds >= 1
    error_message = "image_wait_interval_seconds must be at least 1 second."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long the README association may take. It waits for the image gate's marker, which already exists by the time this association is created, so it is short"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
