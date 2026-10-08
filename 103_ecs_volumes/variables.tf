variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "arm64-bind-mounts"
  description = "Prefix for the names and Name tags of everything in this root. Replaces the _monolithic template's stack_name, which stood in for AWS::StackName and supplied the names CloudFormation would otherwise have generated - the ECR repository, the cluster and the service all took their names from it, and all three are names Terraform requires and CloudFormation did not"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be 2-31 characters of lowercase letters, digits and hyphens. Lowercase because the ECR repository name is derived from it and ECR rejects uppercase at apply time."
  }
}
# --- AMIs -----------------------------------------------------------------------------------------
variable "builder_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  description = "Public SSM parameter holding the AMI id for the image builder, as the _monolithic template had it. A plain Amazon Linux 2023 arm64 image - the builder runs docker, not the ECS agent, so it does not need the ECS-optimized AMI"

  validation {
    condition     = startswith(var.builder_ami_ssm_parameter_name, "/aws/service/ami-amazon-linux-latest/")
    error_message = "builder_ami_ssm_parameter_name must be an Amazon Linux public parameter path under /aws/service/ami-amazon-linux-latest/."
  }

  validation {
    # The builder builds without --platform, so the image it pushes has the architecture of this AMI. A
    # parameter naming an x86 image produces an amd64 image that every arm64 container instance then
    # refuses, with the failure appearing as a stopped task rather than anywhere near here.
    condition     = can(regex("arm64", var.builder_ami_ssm_parameter_name))
    error_message = "builder_ami_ssm_parameter_name must name an arm64 image, because the builder tags and pushes without --platform and the container instances that pull the result are arm64. The image_builder_ec2 module's instance_type variable describes what an architecture mismatch looks like."
  }
}
variable "container_instance_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
  description = "Public SSM parameter holding the AMI id for the container instances, as the _monolithic template had it. ECS-optimized, because the ECS agent and the /etc/ecs/ecs.config convention the launch template writes into come from the AMI - a plain Amazon Linux image launches fine, runs no agent, and never joins the cluster"

  validation {
    condition     = startswith(var.container_instance_ami_ssm_parameter_name, "/aws/service/ecs/optimized-ami/")
    error_message = "container_instance_ami_ssm_parameter_name must be an ECS-optimized AMI public parameter path under /aws/service/ecs/optimized-ami/."
  }

  validation {
    condition     = can(regex("arm64", var.container_instance_ami_ssm_parameter_name))
    error_message = "container_instance_ami_ssm_parameter_name must name an arm64 image, to match the instance family and the architecture of the image the builder pushes."
  }
}
# --- Network --------------------------------------------------------------------------------------
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
  description = "The two AZ letters the subnets are placed in, appended to the region name. ['a', 'c'] is what the _monolithic template's resources used, out of the a/b/c its AzMapping defined. Worth checking against container_instance_types: a zone with no capacity for that family leaves the Auto Scaling group short without failing the apply"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2 && alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must contain exactly two single lowercase letters, because the network module declares one public and one private subnet per zone by name."
  }
}
# --- Image builder --------------------------------------------------------------------------------
variable "builder_instance_type" {
  type        = string
  default     = "t4g.medium"
  description = "Instance type for the image builder, as the _monolithic template had it. Has to be a Graviton family, which the module validates and explains"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.builder_instance_type))
    error_message = "builder_instance_type must be a valid EC2 instance type (e.g. t4g.medium)."
  }
}
variable "builder_root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB for the image builder. The _monolithic template left this unset, taking the AMI's 8 GiB, which does not hold the base image plus the intermediate layers plus the built image - see the module variable for why that failure is invisible"

  validation {
    condition     = var.builder_root_volume_size >= 20
    error_message = "builder_root_volume_size must be at least 20 GiB."
  }
}
variable "builder_ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Source CIDRs allowed to reach port 22 on the image builder. Empty creates no ingress rule, which is what the _monolithic template's security group had - the instance role and the SSM agent make Session Manager the way in, so nothing needs an open port"

  validation {
    condition     = alltrue([for cidr in var.builder_ssh_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "builder_ssh_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "java_base_image" {
  type        = string
  default     = "amazoncorretto:21"
  description = "Base image the test container is built from, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9][a-zA-Z0-9._/-]*:[a-zA-Z0-9][a-zA-Z0-9._-]*$", var.java_base_image))
    error_message = "java_base_image must be an image reference including an explicit tag, e.g. amazoncorretto:21."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "The tag the builder pushes and the task definition pulls. One value for both, through the repository module (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be 1-128 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "write_size_mb" {
  type        = number
  default     = 200
  description = "Size in MiB of each file the in-container test writes, as the _monolithic template had it. Raising it is the way to make the volume's behaviour visible sooner, and is also what fills the container instance root volume - the two have to move together"

  validation {
    condition     = var.write_size_mb >= 1
    error_message = "write_size_mb must be at least 1."
  }
}
variable "retained_file_count" {
  type        = number
  default     = 5
  description = "How many written files the test keeps before deleting the oldest, as the _monolithic template had it. This times write_size_mb is roughly what a single task occupies on the host volume"

  validation {
    condition     = var.retained_file_count >= 1
    error_message = "retained_file_count must be at least 1."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = <<-DESC
    Directory on the image builder in which the userdata writes its completion marker, and in which the
    verification association writes its own (rules.md B-4, D-5).

    /run because it is a tmpfs: the markers mean "this boot did the work", and a marker surviving a reboot
    on a disk would mean the association's until loop returns immediately on an instance that has not
    actually rebuilt anything.
  DESC

  validation {
    condition     = can(regex("^/[^\\s]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
# --- Cluster and capacity -------------------------------------------------------------------------
variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = "containerInsights cluster setting, as the _monolithic template had it. enhanced reports per-task and per-container metrics, which is the mode worth paying for when the thing being watched is one container's I/O"

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled."
  }
}
variable "container_instance_types" {
  type        = list(string)
  default     = ["r8g.2xlarge", "r7g.2xlarge", "r6g.2xlarge", "m8g.2xlarge", "m7g.2xlarge", "m6g.2xlarge"]
  description = "Instance types offered to the mixed instances policy. The _monolithic template had ['r8g.2xlarge'] alone, which on an entirely spot group is one capacity pool per zone - too shallow in ap-northeast-1 to hold four instances, with one zone refusing every launch and the other reclaiming most of what it granted. The other five are the same 8 vCPU shape from neighbouring Graviton generations; the module variable has the numbers. Pass ['r8g.2xlarge'] to reproduce the original exactly"

  validation {
    condition     = length(var.container_instance_types) >= 1 && alltrue([for type in var.container_instance_types : can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", type))])
    error_message = "container_instance_types must contain at least one valid EC2 instance type (e.g. r8g.2xlarge)."
  }
}
variable "container_instance_min_size" {
  type        = number
  default     = 4
  description = "Minimum container instances, as the _monolithic template had it"

  validation {
    condition     = var.container_instance_min_size >= 0
    error_message = "container_instance_min_size must be zero or greater."
  }
}
variable "container_instance_max_size" {
  type        = number
  default     = 8
  description = "Maximum container instances, as the _monolithic template had it. The ceiling ECS managed scaling is allowed to reach"

  validation {
    condition     = var.container_instance_max_size >= var.container_instance_min_size
    error_message = "container_instance_max_size must be greater than or equal to container_instance_min_size."
  }
}
variable "container_instance_desired_capacity" {
  type        = number
  default     = 4
  description = "Container instances launched up front, as the _monolithic template had it. Only the starting value: ECS managed scaling owns this field once the capacity provider is active, which is why the module tells Terraform to ignore changes to it"

  validation {
    condition     = var.container_instance_desired_capacity >= var.container_instance_min_size && var.container_instance_desired_capacity <= var.container_instance_max_size
    error_message = "container_instance_desired_capacity must be between container_instance_min_size and container_instance_max_size inclusive."
  }
}
variable "container_instance_root_volume_size" {
  type        = number
  default     = 100
  description = "Root volume size in GiB for the container instances. The _monolithic template left this unset, taking the ECS-optimized AMI's 30 GiB. Raised because the bind mount lands on this volume and the task writes write_size_mb files into it in a loop"

  validation {
    condition     = var.container_instance_root_volume_size >= 30
    error_message = "container_instance_root_volume_size must be at least 30 GiB, the ECS-optimized AMI's own root volume size."
  }
}
variable "ecs_config_options" {
  type        = map(string)
  default     = {}
  description = "Extra lines written into /etc/ecs/ecs.config on each container instance, alongside ECS_CLUSTER. Empty reproduces the _monolithic template. Agent behaviour belongs in this file rather than in a command run against a live instance, which is the same argument rules.md E-5 makes for an Add-on's configuration_values"

  validation {
    condition     = alltrue([for key in keys(var.ecs_config_options) : can(regex("^ECS_[A-Z0-9_]+$", key))])
    error_message = "ecs_config_options keys must be ECS agent variable names, e.g. ECS_IMAGE_PULL_BEHAVIOR."
  }
}
# --- Service and volume ---------------------------------------------------------------------------
variable "service_desired_count" {
  type        = number
  default     = 2
  description = "Tasks the service keeps running, as the _monolithic template had it. Two so that the spread placement strategies have something to spread"

  validation {
    condition     = var.service_desired_count >= 0
    error_message = "service_desired_count must be zero or greater."
  }
}
variable "task_cpu" {
  type        = string
  default     = "2048"
  description = "Task-level CPU units, as the _monolithic template had it. A string because that is what the ECS API takes"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu))
    error_message = "task_cpu must be a whole number of CPU units expressed as a string, e.g. \"2048\"."
  }
}
variable "task_memory" {
  type        = string
  default     = "15360"
  description = "Task-level memory in MiB, as the _monolithic template had it. A hard reservation: an instance type with less available than this places nothing, reported as a service event rather than as an error"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB expressed as a string, e.g. \"15360\"."
  }
}
variable "host_volume_path" {
  type        = string
  default     = "/ecs/test"
  description = "Directory on the container instance the task bind-mounts, as the _monolithic template had it. One value passed to both the launch template, which creates it, and the task definition, which mounts it (rules.md B-5)"

  validation {
    condition     = can(regex("^/[^\\s]+$", var.host_volume_path))
    error_message = "host_volume_path must be an absolute path with no whitespace."
  }
}
variable "container_mount_path" {
  type        = string
  default     = "/app/test"
  description = "Path inside the container the host directory appears at, as the _monolithic template had it. One value passed to both the image build, whose test script writes there, and the task definition, which mounts there (rules.md B-5)"

  validation {
    condition     = can(regex("^/[^\\s]+$", var.container_mount_path))
    error_message = "container_mount_path must be an absolute path with no whitespace."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "How long the container's log lines are kept. Null keeps them forever, which is what the _monolithic template's bare log group did - for a container that logs every second per task, indefinitely"

  validation {
    condition     = var.log_retention_in_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts, or null to keep logs forever."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = false
  description = "Whether apply waits for the service to reach a steady state. False is the provider default and what the _monolithic template effectively had. True makes an image that cannot be pulled or spot capacity that never arrives fail the apply instead of being something to discover afterwards from the service's events"
}
# --- Image verification step -----------------------------------------------------------------------
variable "image_wait_attempts" {
  type        = number
  default     = 60
  description = <<-DESC
    How many times the verification association asks ECR whether the image is there before giving up,
    once a second apart from image_wait_interval_seconds.

    This step is what replaces the CloudFormation CreationPolicy the builder instance carried. The marker
    file only says the userdata script reached its end - the script does not stop on error - so the thing
    that actually decides whether the build worked is asking the repository.
  DESC

  validation {
    condition     = var.image_wait_attempts >= 1
    error_message = "image_wait_attempts must be at least 1."
  }
}
variable "image_wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds between those attempts"

  validation {
    condition     = var.image_wait_interval_seconds >= 1
    error_message = "image_wait_interval_seconds must be at least 1."
  }
}
variable "image_wait_timeout_seconds" {
  type        = number
  default     = 1800
  description = <<-DESC
    How long Terraform waits for the verification association to report success.

    Has to exceed the association's own budget, and the cross-variable validation below enforces it. If
    SSM gives up first the apply fails with "unexpected state 'Failed'" and nothing else - the script's
    own message about which repository it was waiting on is lost, which is the one piece of information
    worth having at that point. The same argument rules.md E-9 makes for keeping a helm timeout below the
    association's.

    The budget it has to clear is not only the polling: the association cannot run at all until the
    instance has registered with SSM, and the userdata ahead of the marker installs docker, pulls a JDK
    base image, runs a yum update inside it and pushes the result.
  DESC

  validation {
    condition     = var.image_wait_timeout_seconds >= 60
    error_message = "image_wait_timeout_seconds must be at least 60."
  }

  validation {
    # Cross-variable condition, available since Terraform 1.9 (rules.md B-1). 120 seconds of headroom for
    # the instance to register with SSM and for the association to be scheduled.
    condition     = var.image_wait_timeout_seconds >= (var.image_wait_attempts * var.image_wait_interval_seconds) + 120
    error_message = "image_wait_timeout_seconds must exceed image_wait_attempts * image_wait_interval_seconds by at least 120 seconds, so that the association's own polling runs out first and reports which image it was waiting for - rather than SSM timing out and reporting only that the association failed."
  }
}
