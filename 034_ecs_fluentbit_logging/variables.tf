variable "aws_region" {
  type        = string
  default     = null
  description = "Region everything is created in. Null takes the region from the provider chain (AWS_REGION or the shared config), which is how the _monolithic template left it"
  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to take it from the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "logging"
  description = "Prefix every generated name is built from. \"logging\" reproduces the names the _monolithic template used as literals - logging-vpc, logging-cluster, logging-svc, logging-ecr and the rest"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}$", var.project_name))
    error_message = "project_name must be 1-31 characters of lowercase letters, digits and hyphens, starting with a letter or digit, because it is used as the prefix of an ECR repository name as well as of tags."
  }
}
# --- Network ----------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.101.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.101.0.0/16)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two AZ letters the public subnets are placed in, as the _monolithic template placed them"
  validation {
    condition     = length(var.availability_zone_suffixes) == 2
    error_message = "availability_zone_suffixes must contain exactly two entries, which is what the network module declares subnets for."
  }
}
# --- Workbench --------------------------------------------------------------------------------------
variable "workbench_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM public parameter resolved to the workbench instance's AMI ID, as the _monolithic template's parameter defaulted"
  validation {
    condition     = can(regex("^/", var.workbench_ami_ssm_parameter_name))
    error_message = "workbench_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "workbench_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type for the code-server workbench, which is also the box that builds both container images. The _monolithic template used t3.micro - see the module's variable for why this is one size up"
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.workbench_instance_type))
    error_message = "workbench_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "workbench_root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB for the workbench. Both built images and both base images land on this disk"
  validation {
    condition     = var.workbench_root_volume_size >= 8
    error_message = "workbench_root_volume_size must be at least 8 GiB."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.100.3)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether code-server's port is open to 0.0.0.0/0, as the _monolithic template opened it. code-server is configured with auth: none, so while this is true the vscode_url output is the only thing standing between the internet and a shell in this account"
}
variable "ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source CIDR blocks allowed inbound on port 22 of the workbench, which is what the _monolithic template opened. An empty list closes SSH and leaves SSM Session Manager as the way in"
  validation {
    condition     = alltrue([for cidr in var.ssh_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ssh_ingress_cidr_blocks must contain valid IPv4 CIDR blocks, or be empty."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each step writes its completion marker. The userdata writes <path>/userdata, the build association writes <path>/image_build, the verification association writes <path>/images_pushed and the README association writes <path>/vscode_readme - each step waits for the previous marker in an until loop rather than trusting depends_on (rules.md D-5)"
  validation {
    condition     = can(regex("^/[^[:space:]]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path with no whitespace in it, because it is interpolated into shell test expressions unquoted."
  }
}
# --- Container images -------------------------------------------------------------------------------
variable "image_tag" {
  type        = string
  default     = "v1.0.0"
  description = "Tag both images are built, pushed and pulled under, as the _monolithic template tagged them"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be 1-128 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "application_base_image" {
  type        = string
  default     = "python:3.13-slim"
  description = "Base image the application image is built from, as the _monolithic template's Dockerfile had it. Pulled anonymously from Docker Hub, which rate-limits by source address - the workbench has a public address of its own, so that limit is per deployment rather than shared"
  validation {
    condition     = can(regex("^[^[:space:]]+:[^[:space:]:]+$", var.application_base_image))
    error_message = "application_base_image must be an image reference carrying an explicit tag (e.g. python:3.13-slim). An untagged reference resolves to :latest, which makes what gets built depend on the day it ran."
  }
}
variable "fluentbit_base_image" {
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:2.34.3"
  description = <<-DESC
    Base image the log router image is built from. The _monolithic template used
    public.ecr.aws/aws-observability/aws-for-fluent-bit:latest, and this pins a version instead.
    AWS's own guidance on that repository is explicit about the tags: "latest" tracks the most recent 2.x
    release and they recommend never deploying it, "stable" is a mutable pointer at a version that has
    passed longer testing, and a version number is the only tag they recommend consuming. Pinning also
    makes the version answerable from the configuration rather than only from the router's own startup
    banner, which matters here because that banner is in a log group this project creates.
    2.34.3 is the 2.x line AWS currently designates stable. Raising it is a deliberate step, not a
    consequence of re-running the build.
  DESC
  validation {
    condition     = can(regex("^[^[:space:]]+:[^[:space:]:]+$", var.fluentbit_base_image))
    error_message = "fluentbit_base_image must be an image reference carrying an explicit tag (e.g. public.ecr.aws/aws-observability/aws-for-fluent-bit:2.34.3)."
  }
}
# --- Where the logs go ------------------------------------------------------------------------------
variable "application_log_group_name" {
  type        = string
  default     = "/logging/cloudwatch"
  description = "Log group Fluent Bit delivers the application's lines to, as the _monolithic template's FireLens options named it. A literal rather than a derived name, so two copies of this project in one account collide here - override it to deploy twice"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_/.#-]{1,512}$", var.application_log_group_name))
    error_message = "application_log_group_name must be a valid CloudWatch Logs group name."
  }
}
variable "log_router_log_group_name" {
  type        = string
  default     = "/fluentbit/cloudwatch"
  description = "Log group the log router's own stdout goes to, as the _monolithic template's log configuration named it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_/.#-]{1,512}$", var.log_router_log_group_name))
    error_message = "log_router_log_group_name must be a valid CloudWatch Logs group name."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "How long records are kept in both log groups. The _monolithic template created neither group, so both kept everything forever"
  validation {
    condition     = var.log_retention_in_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts, or null to keep records forever."
  }
}
variable "firelens_auto_create_group" {
  type        = bool
  default     = false
  description = "Whether Fluent Bit is told to create the application log group itself, which is what the _monolithic template relied on. False here, because the group is declared in Terraform - see the log destination module's variable for the two things that relying on it costs"
}
variable "log_stream_prefix" {
  type        = string
  default     = "app-"
  description = "Prefix for the stream names Fluent Bit creates in the application log group, as the _monolithic template set it"
  validation {
    condition     = can(regex("^[^:*]*$", var.log_stream_prefix))
    error_message = "log_stream_prefix must not contain ':' or '*', which CloudWatch Logs rejects in a stream name."
  }
}
variable "fluentbit_log_level" {
  type        = string
  default     = "info"
  description = "FLB_LOG_LEVEL for the log router. The _monolithic template set \"error\", at which a healthy pipeline writes nothing to the router's log group and so looks identical to a broken one - see the service module's variable"
  validation {
    condition     = contains(["trace", "debug", "info", "warn", "warning", "error", "off"], var.fluentbit_log_level)
    error_message = "fluentbit_log_level must be one of trace, debug, info, warn, warning, error or off. Fluent Bit exits on an unrecognised level, which stops the essential log router container and therefore the whole task."
  }
}
# --- Cluster and capacity ---------------------------------------------------------------------------
variable "container_insights" {
  type        = string
  default     = "disabled"
  description = "containerInsights setting on the cluster. Off by default, because in a project about watching one log group it would be a second and larger log producer - see the cluster module's variable"
  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled."
  }
}
variable "container_instance_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "SSM public parameter resolved to the container instances' AMI ID, as the _monolithic template's parameter defaulted. It has to stay an ECS-optimized AMI: ecs-init is what puts the agent, the awslogs logging driver and ECS_ENABLE_AWSLOGS_EXECUTIONROLE_OVERRIDE in place, and this project depends on all three"
  validation {
    condition     = can(regex("^/", var.container_instance_ami_ssm_parameter_name))
    error_message = "container_instance_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "container_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the ECS container instances, as the _monolithic template had it. Both tasks fit on one"
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.container_instance_type))
    error_message = "container_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "container_instance_min_size" {
  type        = number
  default     = 1
  description = "Minimum container instances, as the _monolithic template had it"
  validation {
    condition     = var.container_instance_min_size >= 0
    error_message = "container_instance_min_size must be zero or greater."
  }
}
variable "container_instance_max_size" {
  type        = number
  default     = 1
  description = "Maximum container instances, as the _monolithic template had it. Managed scaling cannot add capacity at 1, which is only workable because both tasks fit on one instance"
  validation {
    condition     = var.container_instance_max_size >= var.container_instance_min_size
    error_message = "container_instance_max_size must be greater than or equal to container_instance_min_size."
  }
}
variable "container_instance_desired_capacity" {
  type        = number
  default     = 1
  description = "Container instances the group starts with, as the _monolithic template had it. The starting point only: ECS owns the field afterwards"
  validation {
    condition     = var.container_instance_desired_capacity >= var.container_instance_min_size && var.container_instance_desired_capacity <= var.container_instance_max_size
    error_message = "container_instance_desired_capacity must be between container_instance_min_size and container_instance_max_size inclusive."
  }
}
variable "ecs_config_options" {
  type        = map(string)
  default     = {}
  description = "Extra lines appended to /etc/ecs/ecs.config on each container instance. ECS_CLUSTER is always written from the cluster name and must not appear here. Empty, because the agent settings this project needs come from the ECS-optimized AMI rather than from this file - see the capacity module's variable"
  validation {
    condition     = alltrue([for key in keys(var.ecs_config_options) : can(regex("^ECS_[A-Z0-9_]+$", key))])
    error_message = "ecs_config_options keys must be ECS agent configuration variables (ECS_ followed by uppercase letters, digits and underscores)."
  }
}
# --- Service ----------------------------------------------------------------------------------------
variable "service_desired_count" {
  type        = number
  default     = 2
  description = "Tasks the service keeps running, as the _monolithic template had it. Each has its own Fluent Bit sidecar, so two is what shows the per-task metadata FireLens adds"
  validation {
    condition     = var.service_desired_count >= 0
    error_message = "service_desired_count must be zero or greater."
  }
}
variable "task_cpu" {
  type        = string
  default     = "512"
  description = "CPU units for the whole task, shared by the application and the log router, as the _monolithic template had it"
  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu))
    error_message = "task_cpu must be a whole number of CPU units expressed as a string (e.g. \"512\")."
  }
}
variable "task_memory" {
  type        = string
  default     = "1024"
  description = "Memory in MiB for the whole task, shared by the application and the log router, as the _monolithic template had it"
  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB expressed as a string (e.g. \"1024\")."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = false
  description = "Whether apply blocks until the service reports a steady state. False, so that a service which cannot converge still leaves the outputs and the workbench README in place - those hold the commands for diagnosing it"
}
# --- Step timing ------------------------------------------------------------------------------------
variable "build_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long Terraform waits for the image build association to report success. It covers the wait for the workbench bootstrap plus two docker builds and two pushes over the public internet"
  validation {
    condition     = var.build_timeout_seconds >= 300 && var.build_timeout_seconds <= 3600
    error_message = "build_timeout_seconds must be between 300 and 3600. Below 300 the association gives up before the workbench bootstrap has finished installing docker; 3600 is the execution timeout of the AWS-RunShellScript document itself."
  }
}
variable "image_verify_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long Terraform waits for the image verification association to report success. It waits on the build marker and then asks ECR about both repositories, so its budget is the marker wait plus two image polls"
  validation {
    condition     = var.image_verify_timeout_seconds >= 120 && var.image_verify_timeout_seconds <= 3600
    error_message = "image_verify_timeout_seconds must be between 120 and 3600."
  }
  validation {
    # Cross-variable: the script's own waits have to fit inside this, or Systems Manager gives up first and
    # the association reports nothing more useful than "unexpected state 'Failed'" while the message built
    # into the loop is never printed (rules.md B-1).
    condition     = (var.step_wait_attempts + 2 * var.image_verify_attempts) * var.step_wait_interval_seconds < var.image_verify_timeout_seconds
    error_message = "image_verify_timeout_seconds must exceed (step_wait_attempts + 2 * image_verify_attempts) * step_wait_interval_seconds, which is the worst case of waiting for the build marker and then polling ECR once per repository."
  }
}
variable "image_verify_attempts" {
  type        = number
  default     = 12
  description = "How many times the verification step asks ECR about each repository before failing. Small on purpose: by the time the build marker exists both pushes have already reported success, so this is covering read consistency rather than waiting for work to happen - a repository still empty after two minutes is empty because the push did not land"
  validation {
    condition     = var.image_verify_attempts >= 1
    error_message = "image_verify_attempts must be at least 1."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long Terraform waits for the README association to report success. It waits on the verification marker and then writes one file"
  validation {
    condition     = var.readme_timeout_seconds >= 120 && var.readme_timeout_seconds <= 3600
    error_message = "readme_timeout_seconds must be between 120 and 3600."
  }
}
variable "step_wait_attempts" {
  type        = number
  default     = 90
  description = "How many times each step polls for the marker it is waiting on, or for its image to appear in ECR, before failing with a message that names what is missing. Bounded rather than infinite, so a step that will never succeed says so instead of being killed by its own timeout with no output"
  validation {
    condition     = var.step_wait_attempts >= 1
    error_message = "step_wait_attempts must be at least 1."
  }
  validation {
    # Cross-variable: the polling has to give up before Systems Manager does, otherwise the association
    # reports nothing more useful than "unexpected state 'Failed'" and the message built into the loop is
    # never printed (rules.md B-1).
    condition     = var.step_wait_attempts * var.step_wait_interval_seconds < var.build_timeout_seconds
    error_message = "step_wait_attempts multiplied by step_wait_interval_seconds must be less than build_timeout_seconds, so that a step's own error message is what surfaces rather than the association timing out around it."
  }
}
variable "step_wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds between polls in each step's wait loop"
  validation {
    condition     = var.step_wait_interval_seconds >= 1
    error_message = "step_wait_interval_seconds must be at least 1."
  }
}
