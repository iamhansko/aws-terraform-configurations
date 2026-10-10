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
  default     = "service-discovery-demo"
  description = <<-DESC
    Prefix for the names CloudFormation would have generated and Terraform requires - the cluster, the
    capacity provider and the two log groups. Replaces the _monolithic template's stack_name. The two
    service names were literals in the template and are variables of their own.

    That variable defaulted to "cluster" in this project and in 084 and 085 alike, so the three produced
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
    every test it printed is an aws ecs execute-command into the dnsutils task - which fails on the
    workbench with "SessionManagerPlugin is not found" before it contacts anything: the AWS CLI hands the
    session to the plugin, and Amazon Linux 2023 does not ship it. Pinned rather than "latest" so the
    workbench a given configuration builds does not depend on the day it boots; AWS lists 1.2.764.0 as the
    minimum supported.
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
  description = "Instance type of the ECS container instances, as the _monolithic template had it. Holds two awsvpc tasks, a limit set by its network interfaces rather than its CPU or memory - so the two instances launched up front hold exactly the three nginx tasks and the dnsutils task, and ECS managed scaling adds an instance for anything more, a rolling deployment included"

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
variable "service_discovery_namespace_name" {
  type        = string
  default     = "service-discovery.local"
  description = "DNS name of the Cloud Map private DNS namespace, as the _monolithic template had it. A private hosted zone associated with this VPC only, so two copies of this project in one account do not collide"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.service_discovery_namespace_name)) && length(var.service_discovery_namespace_name) <= 253
    error_message = "service_discovery_namespace_name must be a lowercase DNS name with at least two labels, such as service-discovery.local."
  }
}
# --- The server: nginx, registered in Cloud Map --------------------------------------------------------------
variable "app_service_name" {
  type        = string
  default     = "nginx-service"
  description = "Name of the nginx ECS service, as the _monolithic template had it. Unique within the cluster only"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.app_service_name))
    error_message = "app_service_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "app_image" {
  type        = string
  default     = "nginx:latest"
  description = "Image of the server tasks, as the _monolithic template had it. latest is what the template pulled; it makes the nginx version depend on when each task started"

  validation {
    condition     = can(regex("^[a-z0-9][a-zA-Z0-9._/:@-]*$", var.app_image))
    error_message = "app_image must be an image reference such as nginx:latest."
  }
}
variable "app_desired_count" {
  type        = number
  default     = 3
  description = "nginx tasks, as the _monolithic template had it. Three, so a lookup of the service name answers with three A records - one per task ENI, under the MULTIVALUE routing policy"

  validation {
    condition     = var.app_desired_count >= 1 && floor(var.app_desired_count) == var.app_desired_count
    error_message = "app_desired_count must be a positive whole number - with none, the service name has no records behind it."
  }
}
variable "app_container_port" {
  type        = number
  default     = 80
  description = "Port nginx listens on, as the _monolithic template had it. The task definition publishes it and the task security group opens it between tasks - one value for both (rules.md B-5). An A record carries no port, so a client has to know this one"

  validation {
    condition     = var.app_container_port >= 1 && var.app_container_port <= 65535 && floor(var.app_container_port) == var.app_container_port
    error_message = "app_container_port must be an integer between 1 and 65535."
  }
}
variable "app_port_name" {
  type        = string
  default     = "http"
  description = "Name of the nginx port mapping, as the _monolithic template had it. Nothing discovers by it in this project - Cloud Map A records carry addresses only - but it is kept as the template declared it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$", var.app_port_name))
    error_message = "app_port_name must be 1-64 lowercase letters, digits and hyphens, not starting or ending with a hyphen."
  }
}
variable "app_discovery_service_name" {
  type        = string
  default     = "nginx"
  description = "Name of the Cloud Map service the nginx tasks register in, as the _monolithic template had it - the first label of the name they resolve at"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.app_discovery_service_name))
    error_message = "app_discovery_service_name must be a single lowercase DNS label of 1-63 letters, digits and hyphens."
  }
}
variable "app_dns_ttl" {
  type        = number
  default     = 60
  description = "TTL in seconds of each task record, as the _monolithic template had it. Unlike a Service Connect client, a DNS client sees a new or stopped task once its cached answer expires - this is that bound"

  validation {
    condition     = var.app_dns_ttl >= 0 && floor(var.app_dns_ttl) == var.app_dns_ttl
    error_message = "app_dns_ttl must be a whole number of seconds, zero or greater."
  }
}
# --- The client: a dnsutils task the tests are run in ------------------------------------------------------
variable "client_service_name" {
  type        = string
  default     = "dnsutils-service"
  description = "Name of the dnsutils ECS service, as the _monolithic template had it. Unique within the cluster only"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.client_service_name))
    error_message = "client_service_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "client_image" {
  type        = string
  default     = "registry.k8s.io/e2e-test-images/agnhost:2.50"
  description = "Image of the client task, as the _monolithic template had it. agnhost is the Kubernetes test image: its default command, pause, keeps the task alive, and it carries curl, dig and nslookup"

  validation {
    condition     = can(regex("^[a-z0-9][a-zA-Z0-9._/:@-]*$", var.client_image))
    error_message = "client_image must be an image reference such as registry.k8s.io/e2e-test-images/agnhost:2.50."
  }
}
variable "client_desired_count" {
  type        = number
  default     = 1
  description = "dnsutils tasks, as the _monolithic template had it"

  validation {
    condition     = var.client_desired_count >= 1 && floor(var.client_desired_count) == var.client_desired_count
    error_message = "client_desired_count must be a positive whole number - the test commands open a session in the first running client task."
  }
}
variable "task_cpu" {
  type        = string
  default     = "256"
  description = "Task-level CPU units for both task definitions, as the _monolithic template had them"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu))
    error_message = "task_cpu must be a whole number of CPU units expressed as a string, e.g. \"256\"."
  }
}
variable "task_memory" {
  type        = string
  default     = "512"
  description = "Task-level memory in MiB for both task definitions, as the _monolithic template had them"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB expressed as a string, e.g. \"512\"."
  }
}
variable "task_role_policy_arns" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Managed policies on both task roles. Empty, which is a deliberate narrowing of the _monolithic
    template: it gave its one shared task role AmazonS3FullAccess, carried over from 084_ecs_exec where the
    container is the AWS CLI. Here the containers are nginx and agnhost, neither of which calls AWS, so the
    policy did nothing but let an ECS Exec session in the dnsutils task - or anything that compromised an
    nginx task - read, write and delete every bucket in the account. The ECS Exec permissions the dnsutils
    task does need are granted by its service module. Pass the original ARN back to restore it.
  DESC

  validation {
    condition     = alltrue([for arn in var.task_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "task_role_policy_arns must contain valid IAM policy ARNs, or be empty."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Retention of the two task log groups, the dnsutils one also holding the ECS Exec session logs. The _monolithic template had one group for both, with no retention, which keeps them forever"

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
