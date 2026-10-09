variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster. Account and region wide, so a second copy of this project collides here"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "container_insights" {
  type        = string
  description = "Container Insights setting. The _monolithic template used enhanced, which is what the per-task and per-container CPU widgets on the dashboard query - the ECS/ContainerInsights namespace they read is only populated in that mode"

  validation {
    condition     = contains(["enabled", "enhanced", "disabled"], var.container_insights)
    error_message = "container_insights must be enabled, enhanced or disabled."
  }
}
variable "managed_storage_kms_key_id" {
  type        = string
  default     = null
  description = <<-DESC
    Customer managed key encrypting Fargate ephemeral storage and the EBS volumes ECS manages for
    tasks. Null leaves it on the AWS-owned key, and that is a deliberate divergence from the
    _monolithic template, which passed the project key here.

    The template's version of this cannot work as written. A customer managed key used for ECS
    managed storage needs key policy statements granting fargate.amazonaws.com
    kms:GenerateDataKeyWithoutPlaintext and kms:CreateGrant, conditioned on the cluster's account
    and name. The template created the key with no key policy at all, so it kept the default -
    account root plus IAM delegation - and the ECS service principal is not an IAM principal in
    this account, so nothing grants it.

    The consequence lands on the red stack, which is the Fargate one: the service is created, and
    every task it starts stops during provisioning with a KMS error in its stopped reason.
    Nothing fails at apply.

    So it defaults to null. To turn it on, add those statements to the key policy in
    modules/kms_key and pass the key ARN here - the cluster name is defined once in the root, so
    the condition can be built from the same value this module receives (rules.md B-5).
  DESC

  validation {
    condition     = var.managed_storage_kms_key_id == null || can(regex("^arn:aws[a-z-]*:kms:", var.managed_storage_kms_key_id))
    error_message = "managed_storage_kms_key_id must be a KMS key ARN, or null to use the AWS-owned key."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the container instance security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the Auto Scaling group launches instances into. Private rather than public because outbound goes through the per-zone NAT gateways, and the ECS agent has to reach the ECS and ECR endpoints to register at all"

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids must contain at least one subnet."
  }
  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "ECS-optimized AMI the instances launch from. An ami- ID rather than an SSM parameter path, so the lookup stays in the root where it is read at plan time rather than deferred by this module's depends_on (rules.md B-6, D-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_type" {
  type        = string
  description = "Instance type of the container instances"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair attached to each instance. These instances have no inbound security group rule, so this is a fallback for when the SSM agent itself is what is broken"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "instance_name" {
  type        = string
  description = "Name tag of each container instance and its root volume. The _monolithic template tagged them ws25-ecs-container-green, which reads as belonging to the green stack - they carry tasks from both"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "root_device_name" {
  type        = string
  description = "Root device name of the AMI. /dev/xvda for the Amazon Linux ECS-optimized AMI; a wrong value here adds a second volume instead of resizing the root one"

  validation {
    condition     = can(regex("^/dev/", var.root_device_name))
    error_message = "root_device_name must be a device path starting with /dev/."
  }
}
variable "root_volume_size" {
  type        = number
  description = "Root volume size in GiB for each container instance. The _monolithic template declared no block device mapping, so each instance took the AMI default of 30 GiB"

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GiB, the size of the ECS-optimized AMI snapshot - EC2 rejects a smaller volume with InvalidBlockDeviceMapping."
  }
}
variable "ecs_config_options" {
  type        = map(string)
  default     = {}
  description = "Extra key=value lines appended to /etc/ecs/ecs.config. ECS_CLUSTER is always written and is not taken from here"

  validation {
    condition     = alltrue([for key in keys(var.ecs_config_options) : can(regex("^ECS_[A-Z0-9_]+$", key))])
    error_message = "ecs_config_options keys must be ECS agent variables (ECS_ prefixed, uppercase)."
  }
  validation {
    condition     = !contains(keys(var.ecs_config_options), "ECS_CLUSTER")
    error_message = "ECS_CLUSTER must not be set here: it is written from cluster_name, and a second line for the same key in ecs.config makes which cluster the agent joins depend on the agent's parse order."
  }
}
variable "launch_template_name_prefix" {
  type        = string
  description = "Prefix for the generated launch template name. A prefix rather than the template's fixed asg-launch-template, which is account-wide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9()./_-]{3,99}$", var.launch_template_name_prefix))
    error_message = "launch_template_name_prefix must be 3-99 characters from the set EC2 accepts in a launch template name."
  }
}
variable "auto_scaling_group_name_prefix" {
  type        = string
  description = "Prefix for the generated Auto Scaling group name. A prefix rather than the template's fixed ecs-asg, and it also lets the group be replaced before the old one is destroyed - the capacity provider holds a reference to its ARN"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,200}$", var.auto_scaling_group_name_prefix))
    error_message = "auto_scaling_group_name_prefix must be 1-200 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "min_size" {
  type        = number
  description = "Minimum instances in the Auto Scaling group"

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must not be negative."
  }
}
variable "max_size" {
  type        = number
  description = "Maximum instances in the Auto Scaling group. The _monolithic template set min, max and desired all to 3, so managed scaling had nothing to scale - it is kept, because the EC2 stack asks for three tasks and each awsvpc task needs an interface on an instance"

  validation {
    condition     = var.max_size >= 1
    error_message = "max_size must be at least 1."
  }
  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be greater than or equal to min_size: Auto Scaling rejects the inverted pair at CreateAutoScalingGroup."
  }
}
variable "desired_capacity" {
  type        = number
  description = "Instances the Auto Scaling group starts with"

  validation {
    condition     = var.desired_capacity >= 0
    error_message = "desired_capacity must not be negative."
  }
  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must sit between min_size and max_size inclusive."
  }
}
variable "capacity_distribution_strategy" {
  type        = string
  description = "How the Auto Scaling group spreads instances across zones. The _monolithic template used balanced-only, which refuses to launch into a zone that is unavailable rather than piling the shortfall into another"

  validation {
    condition     = contains(["balanced-only", "balanced-best-effort"], var.capacity_distribution_strategy)
    error_message = "capacity_distribution_strategy must be balanced-only or balanced-best-effort."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Name of the EC2 capacity provider. Account and region wide, and worth knowing: a capacity provider cannot be renamed and cannot be deleted while a cluster still lists it, so a change here is a slow replacement"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.capacity_provider_name)) && !startswith(var.capacity_provider_name, "aws") && !startswith(var.capacity_provider_name, "ecs") && !startswith(var.capacity_provider_name, "fargate")
    error_message = "capacity_provider_name must be 1-255 characters of letters, digits, underscores and hyphens, and must not start with aws, ecs or fargate, which ECS reserves."
  }
}
variable "managed_scaling_status" {
  type        = string
  description = "Whether ECS manages the scaling of the Auto Scaling group"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_scaling_status)
    error_message = "managed_scaling_status must be ENABLED or DISABLED."
  }
}
variable "managed_scaling_target_capacity" {
  type        = number
  description = "Target utilization percentage ECS scales the group towards. 100 packs instances fully before adding another"

  validation {
    condition     = var.managed_scaling_target_capacity >= 1 && var.managed_scaling_target_capacity <= 100
    error_message = "managed_scaling_target_capacity must be between 1 and 100."
  }
}
variable "managed_scaling_minimum_step_size" {
  type        = number
  description = "Smallest number of instances ECS adds or removes in one scaling action"

  validation {
    condition     = var.managed_scaling_minimum_step_size >= 1 && var.managed_scaling_minimum_step_size <= 10000
    error_message = "managed_scaling_minimum_step_size must be between 1 and 10000."
  }
}
variable "managed_scaling_maximum_step_size" {
  type        = number
  description = "Largest number of instances ECS adds or removes in one scaling action. The _monolithic template used 10000, which is the ceiling and is bounded by max_size anyway"

  validation {
    condition     = var.managed_scaling_maximum_step_size >= 1 && var.managed_scaling_maximum_step_size <= 10000
    error_message = "managed_scaling_maximum_step_size must be between 1 and 10000."
  }
  validation {
    condition     = var.managed_scaling_maximum_step_size >= var.managed_scaling_minimum_step_size
    error_message = "managed_scaling_maximum_step_size must be greater than or equal to managed_scaling_minimum_step_size."
  }
}
variable "managed_scaling_instance_warmup_period" {
  type        = number
  description = "Seconds ECS waits before counting a new instance towards the metric. Too long and it keeps adding instances it already has"

  validation {
    condition     = var.managed_scaling_instance_warmup_period >= 0 && var.managed_scaling_instance_warmup_period <= 10000
    error_message = "managed_scaling_instance_warmup_period must be between 0 and 10000 seconds."
  }
}
variable "additional_capacity_providers" {
  type        = list(string)
  description = "Capacity providers attached to the cluster alongside the EC2 one. FARGATE and FARGATE_SPOT, because the red stack runs on Fargate"

  validation {
    condition     = alltrue([for provider in var.additional_capacity_providers : contains(["FARGATE", "FARGATE_SPOT"], provider)])
    error_message = "additional_capacity_providers may only contain FARGATE and FARGATE_SPOT: any other provider is a named resource and belongs in a module that creates it."
  }
}
variable "iam_role_name_prefix" {
  type        = string
  description = "Prefix for the generated container instance role and instance profile names. A prefix rather than the template's fixed ContainerInstanceIamRole, which is account-wide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.iam_role_name_prefix))
    error_message = "iam_role_name_prefix must be 1-38 characters from the set IAM accepts in a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs on the container instance role. Both of the _monolithic template's are kept: they are AWS service-role policies already scoped to what an agent and the SSM agent do, so there is nothing to narrow (rules.md A-5)"

  validation {
    condition     = length(var.iam_policy_arns) > 0
    error_message = "iam_policy_arns must contain at least one policy: without the container service policy the agent cannot call RegisterContainerInstance and the instance never joins the cluster."
  }
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "all_traffic_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on every protocol and port, keyed by a caller-chosen label. The root passes the app VPC default security group here, reproducing the _monolithic template - the tasks use awsvpc, so the load balancer reaches the ECS service group rather than this one"

  validation {
    condition     = alltrue([for label in keys(var.all_traffic_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "all_traffic_source_security_groups keys land in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.all_traffic_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "all_traffic_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the container instance security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  description = "Description of the container instance security group"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty."
  }
  validation {
    # rules.md F-1.
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
