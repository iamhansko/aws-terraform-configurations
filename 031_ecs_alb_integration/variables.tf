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
  default     = "ecs-alb-integration"
  description = "Used only as the heading of the README written onto the workbench. Every AWS resource name in this project was a literal in the _monolithic template and is its own variable below, so changing this renames nothing"

  validation {
    condition     = length(var.project_name) > 0
    error_message = "project_name must not be empty."
  }
}
# --- Network ----------------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.10.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template's VpcCidr parameter had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.10.0.0/16)."
  }
}
variable "public_subnet_a_cidr_block" {
  type        = string
  default     = "10.10.0.0/24"
  description = "CIDR block of the public subnet in the first zone, as the _monolithic template's SubnetACidr parameter had it"

  validation {
    condition     = can(cidrhost(var.public_subnet_a_cidr_block, 0))
    error_message = "public_subnet_a_cidr_block must be a valid IPv4 CIDR block (e.g. 10.10.0.0/24)."
  }
}
variable "public_subnet_c_cidr_block" {
  type        = string
  default     = "10.10.1.0/24"
  description = "CIDR block of the public subnet in the second zone, as the _monolithic template's SubnetCCidr parameter had it"

  validation {
    condition     = can(cidrhost(var.public_subnet_c_cidr_block, 0))
    error_message = "public_subnet_c_cidr_block must be a valid IPv4 CIDR block (e.g. 10.10.1.0/24)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "The two AZ letters the public subnets are placed in. [\"a\", \"c\"] is what the _monolithic template selected by indexing data.aws_availability_zones - see the network module for why the index is gone"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2
    error_message = "availability_zone_suffixes must contain exactly two entries: an internet-facing ALB is rejected with fewer than two zones, and the network module declares one named subnet per zone rather than generating them."
  }

  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes entries must each be a single lowercase letter (e.g. a), which is appended to the region name to form the zone."
  }

  validation {
    condition     = var.availability_zone_suffixes[0] != var.availability_zone_suffixes[1]
    error_message = "availability_zone_suffixes entries must differ, because an ALB needs subnets in two different zones."
  }
}
variable "vpc_name" {
  type        = string
  default     = "mo-vpc"
  description = "Name tag for the VPC, as the _monolithic template had it"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "mo-igw"
  description = "Name tag for the internet gateway, as the _monolithic template had it"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "mo-public"
  description = "Base name tag for the public subnets, suffixed with the AZ letter. The _monolithic template tagged them mo-public-a and mo-public-c"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "mo-rt"
  description = "Name tag for the public route table, as the _monolithic template had it"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
# --- Key pair ---------------------------------------------------------------------------------------------
variable "key_name_prefix" {
  type        = string
  default     = "key-"
  description = "Prefix for the generated key pair name. The _monolithic template built \"key-<uuid segment>\"; the provider generates the unique part now (see providers.tf)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,200}$", var.key_name_prefix))
    error_message = "key_name_prefix must be 1-200 characters of letters, digits, dots, underscores or hyphens."
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
# --- Container image --------------------------------------------------------------------------------------
variable "ecr_repository_name" {
  type        = string
  default     = "monitoring"
  description = "Name of the ECR repository the workbench pushes to and the task definition pulls from, as the _monolithic template had it. A literal, so two copies of this project in one account collide on it - change it for the second"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.ecr_repository_name))
    error_message = "ecr_repository_name must start with a lowercase letter or digit and contain only lowercase letters, digits and . _ / -."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "The one tag the workbench pushes and the task definition pulls, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid container image tag."
  }
}
variable "ecr_force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository while images are still in it. True as the _monolithic template had it, and necessary here: the images are pushed by the workbench rather than by Terraform, so a destroy would otherwise stop at RepositoryNotEmptyException"
}
variable "ecr_scan_on_push" {
  type        = bool
  default     = false
  description = "Whether ECR runs a basic vulnerability scan on each push. False, which is what the _monolithic template got by not configuring it"
}
# --- Workbench --------------------------------------------------------------------------------------------
variable "bastion_instance_name" {
  type        = string
  default     = "bastion"
  description = "Name tag for the workbench instance, as the _monolithic template had it"

  validation {
    condition     = length(var.bastion_instance_name) > 0
    error_message = "bastion_instance_name must not be empty."
  }
}
variable "bastion_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type for the workbench, as the _monolithic template had it. It builds one small Python image, so the default is enough"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.bastion_instance_type))
    error_message = "bastion_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "bastion_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the workbench AMI, as the _monolithic template's BastionEc2AmiId parameter had it"

  validation {
    condition     = can(regex("^/", var.bastion_ami_ssm_parameter_name))
    error_message = "bastion_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "bastion_root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of the workbench root volume. Larger than the AL2023 default of 8 GiB the _monolithic template took, because this instance installs the Development Tools group and then builds and caches a container image on the same disk"

  validation {
    condition     = var.bastion_root_volume_size >= 8
    error_message = "bastion_root_volume_size must be at least 8 GiB, the size of the AL2023 root snapshot."
  }
}
variable "bastion_associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the workbench gets a public address, as the _monolithic template had it. Load-bearing: code-server is reached over it, and with no NAT gateway in this project it is also the instance's only route out for the dnf installs and the image push"
}
variable "bastion_security_group_name" {
  type        = string
  default     = "bastion-sg"
  description = "Name of the workbench security group, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.bastion_security_group_name)) && !startswith(var.bastion_security_group_name, "sg-")
    error_message = "bastion_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "bastion_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach code-server and SSH on the workbench. 0.0.0.0/0 as the _monolithic template had it, and worth narrowing: code-server is configured with auth: none, so whoever can reach the port has a root-capable shell in the browser"

  validation {
    condition     = length(var.bastion_ingress_cidr_blocks) > 0
    error_message = "bastion_ingress_cidr_blocks must contain at least one CIDR block, otherwise neither code-server nor SSH is reachable."
  }

  validation {
    condition     = alltrue([for cidr in var.bastion_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "bastion_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "bastion_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "Managed policies attached to the workbench role, as the _monolithic template had them. rules.md A-5 narrows the automated roles and exempts the workbench: a person sits here and runs docker build, ecr push, ecs describe-services, elbv2 describe-target-health and cloudwatch describe-alarms from it, and guessing that list in advance produces an AccessDenied halfway through a demo"

  validation {
    condition     = alltrue([for arn in var.bastion_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "bastion_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "bastion_iam_name_prefix" {
  type        = string
  default     = "Ec2AdminProfile-"
  description = "Prefix for the generated names of the workbench role and instance profile. The _monolithic template named the profile \"Ec2AdminProfile-<uuid segment>\"; the provider generates the unique part now (see providers.tf)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.bastion_iam_name_prefix))
    error_message = "bastion_iam_name_prefix must be 1-38 characters from the IAM name character set (letters, digits and +=,.@_-), leaving room for the suffix the provider appends within IAM's 64-character limit."
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
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to and the workbench security group opens, as the _monolithic template had it"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = "Port sshd listens on and the workbench security group opens, as the _monolithic template had it"

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "ssh_port must be a valid TCP port."
  }
}
variable "python_version" {
  type        = string
  default     = "3.12"
  description = "Python version installed on the workbench and symlinked to /usr/bin/python, as the _monolithic template had it. Unrelated to the version in the container image, which comes from src/Dockerfile"

  validation {
    condition     = can(regex("^3\\.[0-9]+$", var.python_version))
    error_message = "python_version must be a 3.x version (e.g. 3.12), matching an AL2023 pythonX.Y package name."
  }
}
# --- Load balancer ----------------------------------------------------------------------------------------
variable "load_balancer_name" {
  type        = string
  default     = "mo-alb"
  description = "Name of the ALB, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.load_balancer_name))
    error_message = "load_balancer_name must be 2-32 characters of letters, digits and hyphens, not beginning or ending with a hyphen."
  }
}
variable "target_group_name" {
  type        = string
  default     = "mo-tg"
  description = "Name of the target group the service registers its tasks into, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.target_group_name))
    error_message = "target_group_name must be 2-32 characters of letters, digits and hyphens, not beginning or ending with a hyphen."
  }
}
variable "alb_security_group_name" {
  type        = string
  default     = "alb-sg"
  description = "Name of the ALB security group. The _monolithic template left this unnamed and only tagged it alb-sg, so the provider generated a terraform-prefixed name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "alb_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach the ALB listener, as the _monolithic template had it. This is the public entry point of the demo"

  validation {
    condition     = length(var.alb_ingress_cidr_blocks) > 0
    error_message = "alb_ingress_cidr_blocks must contain at least one CIDR block, otherwise the ALB answers nobody."
  }

  validation {
    condition     = alltrue([for cidr in var.alb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "alb_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the ALB listens on, as the _monolithic template had it"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on. One value for the task definition's port mapping, the target group and its health check, the ALB's egress rule and the tasks' ingress rule (rules.md B-5)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/"
  description = "Path the target group health check requests, as the _monolithic template had it. The image in src/ also answers /health with 200, which is the conventional choice; / is kept so the check matches what the original configured"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}
# --- ECS --------------------------------------------------------------------------------------------------
variable "ecs_cluster_name" {
  type        = string
  default     = "ecs-cluster"
  description = "Name of the ECS cluster, as the _monolithic template had it. A literal, so two copies of this project in one account collide on it - change it for the second"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.ecs_cluster_name))
    error_message = "ecs_cluster_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "container_insights" {
  type        = string
  default     = "disabled"
  description = "Container Insights setting on the cluster. Disabled, which is what the _monolithic template got by not configuring it - and stating it means the dashboard renders the same whatever the account default is. The dashboard's widgets read AWS/ECS service metrics, which are published without it; only ECS/ContainerInsights per-task widgets would need \"enhanced\""

  validation {
    condition     = contains(["enabled", "disabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be enabled, disabled or enhanced."
  }
}
variable "task_family" {
  type        = string
  default     = "monitoring-task"
  description = "Family of the task definition, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "service_name" {
  type        = string
  default     = "monitoring-svc"
  description = "Name of the ECS service, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.service_name))
    error_message = "service_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "container_name" {
  type        = string
  default     = "monitoring"
  description = "Name of the container. The service's load_balancer block names it to decide which container's port the ALB registers, so it has to match the task definition exactly - which is why it is one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must start with a letter or digit and contain only letters, digits, underscores and hyphens."
  }
}
variable "task_cpu" {
  type        = string
  default     = "256"
  description = "CPU units for the Fargate task, as the _monolithic template had it"

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096", "8192", "16384"], var.task_cpu)
    error_message = "task_cpu must be one of the CPU sizes Fargate accepts: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}
variable "task_memory" {
  type        = string
  default     = "512"
  description = "Memory in MiB for the Fargate task, as the _monolithic template had it. Fargate accepts only certain pairs of CPU and memory and rejects the rest at RegisterTaskDefinition, so changing one usually means changing both"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory)) && tonumber(var.task_memory) >= 512
    error_message = "task_memory must be a whole number of MiB, at least 512, which is the smallest value Fargate accepts."
  }
}
variable "service_desired_count" {
  type        = number
  default     = 1
  description = "Number of tasks the service keeps running, as the _monolithic template had it"

  validation {
    condition     = var.service_desired_count >= 0
    error_message = "service_desired_count must be zero or greater."
  }
}
variable "ecs_service_security_group_name" {
  type        = string
  default     = "ecs-svc-sg"
  description = "Name of the tasks' security group. The _monolithic template left this unnamed and only tagged it ecs-svc-sg"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.ecs_service_security_group_name)) && !startswith(var.ecs_service_security_group_name, "sg-")
    error_message = "ecs_service_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "assign_public_ip" {
  type        = bool
  default     = true
  description = "Whether each task's network interface gets a public address. True as the _monolithic template had it, and load-bearing: the tasks sit in public subnets and there is no NAT gateway, so a public address is their only route to ECR and CloudWatch Logs. Setting this false leaves every task stopping with ResourceInitializationError"
}
variable "wait_for_steady_state" {
  type        = bool
  default     = true
  description = "Whether apply waits for the service to reach a steady state, which is what CloudFormation did for an AWS::ECS::Service. True makes a task that cannot start or a target that never passes its health check fail the apply instead of being discovered later in the console"
}
variable "log_group_name" {
  type        = string
  default     = "/ecs/monitoring"
  description = "Log group the container's stdout is written to. An addition: the _monolithic template's container definition had no logConfiguration at all, so a Fargate task that failed to start left no record of why anywhere"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and _ . / # -."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Days CloudWatch keeps the container log events. Set rather than left to never expire, because the group is an addition and an addition should not accumulate indefinitely"

  validation {
    condition     = var.log_retention_in_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], coalesce(var.log_retention_in_days, 1))
    error_message = "log_retention_in_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, ...), or null to keep events forever."
  }
}
# --- Dashboard and alarm ----------------------------------------------------------------------------------
variable "dashboard_name" {
  type        = string
  default     = "monitoring-dashboard"
  description = "Name of the CloudWatch dashboard, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.dashboard_name))
    error_message = "dashboard_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "metric_period" {
  type        = number
  default     = 60
  description = "Resolution of the dashboard widgets in seconds, as the _monolithic template had it"

  validation {
    condition     = contains([1, 5, 10, 30, 60, 300, 900, 3600], var.metric_period)
    error_message = "metric_period must be 1, 5, 10, 30, 60, 300, 900 or 3600 seconds."
  }
}
variable "alarm_name" {
  type        = string
  default     = "alb-5xx-alarm"
  description = "Name of the 5xx alarm, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.:/#-]{1,255}$", var.alarm_name))
    error_message = "alarm_name must be 1-255 characters of letters, digits and _ . : / # -."
  }
}
variable "alarm_threshold" {
  type        = number
  default     = 2
  description = "Number of 5xx responses in one period that puts the alarm into ALARM, as the _monolithic template had it"

  validation {
    condition     = var.alarm_threshold > 0
    error_message = "alarm_threshold must be greater than zero."
  }
}
variable "alarm_period" {
  type        = number
  default     = 300
  description = "Length of each evaluation period in seconds, as the _monolithic template had it"

  validation {
    condition     = contains([10, 20, 30, 60, 300, 900, 3600], var.alarm_period)
    error_message = "alarm_period must be 10, 20, 30, 60, 300, 900 or 3600 seconds, the resolutions CloudWatch accepts for a metric alarm."
  }
}
variable "alarm_evaluation_periods" {
  type        = number
  default     = 1
  description = "Consecutive periods that must breach before the alarm fires, as the _monolithic template had it"

  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "alarm_evaluation_periods must be at least 1."
  }
}
variable "alarm_actions" {
  type        = list(string)
  default     = []
  description = "ARNs notified when the alarm fires - an SNS topic, an Auto Scaling policy or an SSM OpsItem target. Empty, which is what the _monolithic template effectively had: it set actions_enabled = true and declared no actions. Nothing here creates a topic, so filling this in means pointing at one that already exists"

  validation {
    condition     = alltrue([for arn in var.alarm_actions : can(regex("^arn:aws(-[a-z]+)*:", arn))])
    error_message = "alarm_actions must contain ARNs."
  }
}
# --- Ordering and waits -----------------------------------------------------------------------------------
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where the bootstrap drops its completion marker. The two associations in the root wait for that marker rather than relying on depends_on or a provider timeout (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "image_wait_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the image verification association may take. It waits for the whole workbench bootstrap - dnf update, the Development Tools group, code-server, docker, then the build and the push"

  validation {
    condition     = var.image_wait_timeout_seconds > 0
    error_message = "image_wait_timeout_seconds must be positive."
  }
}
variable "image_wait_attempts" {
  type        = number
  default     = 60
  description = "How many times the image verification association polls, for the marker first and then for the image in ECR"

  validation {
    condition     = var.image_wait_attempts >= 1
    error_message = "image_wait_attempts must be at least 1."
  }

  validation {
    # A constraint about the pair rather than about either number, so it is written as a cross-variable
    # condition (Terraform 1.9, rules.md B-1). The script has two sequential polling phases, so it can run
    # for twice this product; if SSM gives up first the association reports a bare "Failed" with nothing in
    # it, where the script's own timeout prints which phase stalled and where to look.
    condition     = var.image_wait_attempts * var.image_wait_interval_seconds * 2 < var.image_wait_timeout_seconds
    error_message = "image_wait_attempts * image_wait_interval_seconds * 2 must be below image_wait_timeout_seconds, so the script reports which of its two phases timed out instead of SSM reporting an unexplained Failed."
  }
}
variable "image_wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds between polls in the image verification association"

  validation {
    condition     = var.image_wait_interval_seconds >= 1
    error_message = "image_wait_interval_seconds must be at least 1 second."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association may take. It waits for the same bootstrap marker as the image verification, so it needs the same allowance"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
