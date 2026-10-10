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
  default     = "exec-demo"
  description = <<-DESC
    Prefix for the names CloudFormation would have generated and Terraform requires - the cluster, the
    capacity provider, the service and the log group. Replaces the _monolithic template's stack_name.

    That variable defaulted to "cluster" in this project and in 085 and 086 alike, so the three produced
    the same cluster name "cluster-ecs-cluster" and the same capacity provider name. ECS cluster names are
    unique per account and region, and CreateCluster on an existing name returns the existing cluster
    rather than failing - so a second project applied into the same account silently shared the first
    one's cluster, and destroying either took it from both. Each project now has its own default.
  DESC

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be 2-31 characters of lowercase letters, digits and hyphens."
  }

  validation {
    # The capacity provider name starts with project_name, and ECS rejects a capacity provider name that
    # starts with aws, ecs or fargate - at apply, after the Auto Scaling group already exists.
    condition     = !can(regex("^(aws|ecs|fargate)", var.project_name))
    error_message = "project_name must not start with aws, ecs or fargate, because it prefixes the capacity provider name and ECS reserves those prefixes."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether code-server accepts traffic from 0.0.0.0/0. True as the _monolithic template had it - a bool where that template used a string validated against [\"True\", \"False\"]. code-server has no authentication in front of it"
}
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
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.102.3)."
  }
}
variable "workbench_python_version" {
  type        = string
  default     = "3.13"
  description = "Python installed on the workbench and linked as /usr/bin/python, as the _monolithic template did with python3.13. It has to be a version Amazon Linux 2023 packages as python<version>"

  validation {
    condition     = can(regex("^3\\.[0-9]{1,2}$", var.workbench_python_version))
    error_message = "workbench_python_version must be a Python 3 minor version such as 3.13."
  }
}
variable "session_manager_plugin_version" {
  type        = string
  default     = "1.2.835.0"
  description = <<-DESC
    Session Manager plugin installed on the workbench. The _monolithic template did not install it, and
    without it aws ecs execute-command - this project's subject - fails on the workbench with
    "SessionManagerPlugin is not found" before it contacts anything: the AWS CLI hands the session to the
    plugin, and Amazon Linux 2023 does not ship it. Pinned rather than "latest" so the workbench a given
    configuration builds does not depend on the day it boots; AWS lists 1.2.764.0 as the minimum supported.
  DESC

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.session_manager_plugin_version))
    error_message = "session_manager_plugin_version must be a four-part version such as 1.2.835.0, as published under s3://session-manager-downloads/plugin/."
  }
}
variable "container_instance_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "Public SSM parameter resolved to the container instances' AMI, as the _monolithic template's EcsAmiId parameter had it. It has to be an ECS-optimized x86_64 image to match container_instance_type"

  validation {
    condition     = can(regex("^/aws/service/ecs/optimized-ami/", var.container_instance_ami_ssm_parameter_name))
    error_message = "container_instance_ami_ssm_parameter_name must be one of the ECS-optimized AMI parameters under /aws/service/ecs/optimized-ami/. Another image has no ECS agent, so its instances launch and never join the cluster."
  }
}
variable "container_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the ECS container instances, as the _monolithic template had it. Holds two awsvpc tasks, a limit set by its network interfaces rather than its CPU or memory"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.container_instance_type))
    error_message = "container_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }

  validation {
    # The AMI parameter above is x86_64. EC2 refuses an arm64 type with that AMI at launch, which the Auto
    # Scaling group records as a failed activity - and the apply then waits out its capacity timeout.
    condition     = !can(regex("^[a-z]+[0-9]+g[a-z]*\\.", var.container_instance_type))
    error_message = "container_instance_type must be an x86_64 type to match the x86_64 ECS-optimized AMI. To use Graviton, point container_instance_ami_ssm_parameter_name at the arm64 parameter and change this check."
  }
}
variable "container_instance_min_size" {
  type        = number
  default     = 1
  description = "Minimum container instances, as the _monolithic template had it"

  validation {
    condition     = var.container_instance_min_size >= 0 && floor(var.container_instance_min_size) == var.container_instance_min_size
    error_message = "container_instance_min_size must be a whole number, zero or greater."
  }
}
variable "container_instance_desired_capacity" {
  type        = number
  default     = 2
  description = "Container instances launched up front, as the _monolithic template had it. ECS managed scaling owns the number after that"

  validation {
    condition     = var.container_instance_desired_capacity >= var.container_instance_min_size && var.container_instance_desired_capacity <= var.container_instance_max_size
    error_message = "container_instance_desired_capacity must be between container_instance_min_size and container_instance_max_size."
  }
}
variable "container_instance_max_size" {
  type        = number
  default     = 6
  description = "Maximum container instances, as the _monolithic template had it"

  validation {
    condition     = var.container_instance_max_size >= 1 && var.container_instance_max_size >= var.container_instance_min_size
    error_message = "container_instance_max_size must be at least 1 and at least container_instance_min_size."
  }
}
variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = "containerInsights setting of the cluster, as the _monolithic template had it"

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled."
  }
}
variable "additional_cluster_capacity_providers" {
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
  description = "Capacity providers associated with the cluster besides the EC2 one, as the _monolithic template listed them. Nothing in this project is placed on them; the default strategy names the EC2 provider alone"

  validation {
    condition     = alltrue([for name in var.additional_cluster_capacity_providers : contains(["FARGATE", "FARGATE_SPOT"], name)])
    error_message = "additional_cluster_capacity_providers may contain only FARGATE and FARGATE_SPOT, the AWS-managed providers a cluster can be associated with without creating anything."
  }
}
variable "aws_cli_image" {
  type        = string
  default     = "amazon/aws-cli:latest"
  description = "Image of the container a session is opened in, as the _monolithic template had it. latest is what the template pulled; it makes the CLI version inside the task depend on when the task started"

  validation {
    condition     = can(regex("^[a-z0-9][a-zA-Z0-9._/:@-]*$", var.aws_cli_image))
    error_message = "aws_cli_image must be an image reference such as amazon/aws-cli:latest."
  }
}
variable "service_desired_count" {
  type        = number
  default     = 1
  description = "Tasks the service keeps running, as the _monolithic template had it"

  validation {
    condition     = var.service_desired_count >= 1 && floor(var.service_desired_count) == var.service_desired_count
    error_message = "service_desired_count must be a positive whole number - the exec commands open a session in the first running task."
  }
}
variable "task_cpu" {
  type        = string
  default     = "256"
  description = "Task-level CPU units, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu))
    error_message = "task_cpu must be a whole number of CPU units expressed as a string, e.g. \"256\"."
  }
}
variable "task_memory" {
  type        = string
  default     = "512"
  description = "Task-level memory in MiB, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB expressed as a string, e.g. \"512\"."
  }
}
variable "task_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
  description = <<-DESC
    Managed policies on the task role - what a command run in an ECS Exec session can do, because the
    session runs as the task role. AmazonS3FullAccess is what the _monolithic template attached, and it is
    kept: the container is the AWS CLI, and running a command against S3 from inside the task, with no
    credentials configured, is the demonstration. It is also the widest thing in the project - anyone who
    can call ecs:ExecuteCommand on this service can read, write and delete every bucket in the account.
    AmazonS3ReadOnlyAccess keeps the demonstration and drops the writes; an empty list leaves exec working
    with no AWS access at all.
  DESC

  validation {
    condition     = alltrue([for arn in var.task_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "task_role_policy_arns must contain valid IAM policy ARNs, or be empty."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Retention of the task log group, which also holds the ECS Exec session logs. The _monolithic template set none, which keeps them forever"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a value CloudWatch Logs accepts, e.g. 1, 3, 5, 7, 14, 30, 60, 90, 180 or 365."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/var/lib/terraform"
  description = "Directory on the workbench where its bootstrap drops a completion marker, which the README association waits for rather than relying on depends_on (rules.md D-5/H-2). Under /var/lib rather than the /run most of this repository uses, as 122_eks_multi_cluster_application_management_with_karmada explains: /run is a tmpfs emptied on every boot, so after a stop and start of the workbench the README association, re-run by a changed output, would wait for a userdata marker that is gone and fail at its timeout"

  validation {
    condition     = can(regex("^/[^\\s]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path with no whitespace."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 1200
  description = "How long the README association may take, including its wait for the workbench bootstrap - a dnf update, the Development Tools group, code-server, Python and docker. The _monolithic template gave its CreationPolicy 7 minutes for the bootstrap alone"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}
