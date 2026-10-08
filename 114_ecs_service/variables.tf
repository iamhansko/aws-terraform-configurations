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
  default     = "container-logs-firehose-streaming"
  description = "Prefix for the names CloudFormation used to generate - the cluster, the service and the delivery stream. Replaces the _monolithic template's stack_name, and keeps its default so those three names come out the same"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.project_name))
    error_message = "project_name must be 2-41 characters of lowercase letters, digits and hyphens, so every name derived from it stays within its own service's limit."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the ALB listener and code-server accept traffic from 0.0.0.0/0. True as the _monolithic template had it - a bool here where that template used a string validated against [\"True\", \"False\"]. code-server has no authentication in front of it"
}
# --- Network ----------------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "The two AZ letters the subnets are placed in, as the _monolithic template's resources used them"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2 && alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must contain exactly two single lowercase letters, because the network module declares one public and one private subnet per zone by name."
  }
}
# --- VS Code workbench ------------------------------------------------------------------------------------
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the VS Code workbench, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.102.3"
  description = "code-server release installed on the workbench. Pinned, where the _monolithic template asked the GitHub API for the latest release at boot - which is unauthenticated, rate-limited per source address, and installs something different every month"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.102.3)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where the bootstrap drops its completion marker. The README association waits for that marker rather than relying on depends_on (rules.md D-5/H-2)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README association may take. It first waits for the workbench bootstrap, which runs dnf update and downloads code-server"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
# --- Log delivery -----------------------------------------------------------------------------------------
variable "log_group_name" {
  type        = string
  default     = "/ecs/task/container/logs"
  description = "Log group the containers write to and Firehose is subscribed to, as the _monolithic template named it. A literal, so two copies of this project in one account collide on it - change it for the second"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and _ . / # -."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = null
  description = "Days CloudWatch keeps the container log events. Null keeps them forever, as the _monolithic template did by not setting it"

  validation {
    condition     = var.log_retention_in_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], coalesce(var.log_retention_in_days, 1))
    error_message = "log_retention_in_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, ...), or null."
  }
}
variable "firehose_buffering_interval_seconds" {
  type        = number
  default     = 300
  description = "Seconds Firehose holds records before writing an object to S3. 300 is Firehose's default and what the _monolithic template got by not setting it. Lower it to 60 to see objects sooner"

  validation {
    condition     = var.firehose_buffering_interval_seconds >= 0 && var.firehose_buffering_interval_seconds <= 900
    error_message = "firehose_buffering_interval_seconds must be between 0 and 900."
  }
}
variable "force_destroy_destination_bucket" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the Firehose destination bucket first. True, because Firehose writes objects Terraform does not track and a destroy would otherwise stop at BucketNotEmpty. The delivered logs are deleted with it"
}
# --- Load balancer ----------------------------------------------------------------------------------------
variable "load_balancer_name" {
  type        = string
  default     = "public-alb"
  description = "Name of the ALB, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.load_balancer_name))
    error_message = "load_balancer_name must be 2-32 characters of letters, digits and hyphens, not beginning or ending with a hyphen."
  }
}
variable "target_group_names" {
  type = object({
    primary   = string
    alternate = string
  })
  default = {
    primary   = "alb-tg-1"
    alternate = "alb-tg-2"
  }
  description = "Names of the two target groups, as the _monolithic template had them"

  validation {
    condition     = var.target_group_names.primary != var.target_group_names.alternate
    error_message = "target_group_names.primary and target_group_names.alternate must differ."
  }
}
# --- ECS service ------------------------------------------------------------------------------------------
variable "container_image" {
  type        = string
  default     = "nginx"
  description = "Image the service runs, as the _monolithic template had it. Untagged means latest, pulled anonymously from Docker Hub"

  validation {
    condition     = length(var.container_image) > 0
    error_message = "container_image must not be empty."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on. One value for the task definition, both target groups, their health checks, the ALB's egress rule and the tasks' ingress rule (rules.md B-5)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "service_desired_count" {
  type        = number
  default     = 2
  description = "Number of tasks, as the _monolithic template had it"

  validation {
    condition     = var.service_desired_count >= 0
    error_message = "service_desired_count must be zero or greater."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = true
  description = "Whether apply waits for the service to reach a steady state, which is what CloudFormation did for the _monolithic stack"
}
