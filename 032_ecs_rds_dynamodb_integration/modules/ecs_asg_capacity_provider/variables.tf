variable "vpc_id" {
  type        = string
  description = "VPC ID the container instance security group is created in"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the Auto Scaling group places instances in, as the _monolithic template had it. Private, so outbound goes through the per-zone NAT gateways - an awsvpc task on an EC2 instance never receives a public address, so a public subnet would not help it"
  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least two valid subnet IDs, because the group is asked to balance capacity across Availability Zones."
  }
}
variable "cluster_name" {
  type        = string
  description = "Cluster the instances join and the capacity provider is attached to. Written into /etc/ecs/ecs.config by the launch template userdata"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI for the container instances. An ECS-optimized AMI, resolved by the caller from the public SSM parameter so this module takes an ami- id and does not have to know where it came from (rules.md B-6)"
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "EC2 key pair name, as the template set on its launch template. Null launches without one; the role carries AmazonSSMManagedInstanceCore either way, so Session Manager still works"
  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters, or null."
  }
}
variable "instance_name" {
  type        = string
  default     = "ecs-container-instance"
  description = "Name tag for the instances, and the prefix for the generated launch template and Auto Scaling group names. As the template tagged them"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,100}$", var.instance_name))
    error_message = "instance_name must be 1-100 characters of letters, digits, dots, underscores and hyphens, because it also prefixes generated Auto Scaling group and launch template names."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the container instances, as the template had it. Note what it bounds: an awsvpc task takes one ENI and the primary interface takes one, so a t3.medium with its three-ENI limit runs two tasks at most. Three instances carry the three services here with room to spare"
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "min_size" {
  type        = number
  default     = 3
  description = "Minimum instances in the group, as the template had it"
  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be zero or more."
  }
}
variable "max_size" {
  type        = number
  default     = 3
  description = "Maximum instances in the group, as the template had it. Equal to min_size, which means ECS managed scaling can calculate a desired capacity and never act on it - fixed capacity is what the template declared and three instances is enough for three single-task services, so it is kept. Raise this to let managed scaling do anything"
  validation {
    condition     = var.max_size >= 1
    error_message = "max_size must be at least 1."
  }
  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be at least min_size."
  }
}
variable "desired_capacity" {
  type        = number
  default     = 3
  description = "Instances requested at launch, as the template had it. The starting point only: ECS managed scaling owns this field afterwards, which is why Terraform ignores changes to it (see main.tf)"
  validation {
    condition     = var.desired_capacity >= 0
    error_message = "desired_capacity must be zero or more."
  }
  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be between min_size and max_size. The Auto Scaling API rejects a value outside that range at apply."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ecs-container-instance-sg"
  description = "Name of the container instance security group, as the template named it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security Group"
  description = "Description attached to the container instance security group, as the template had it. Changing it replaces the group, and the launch template with it (rules.md F-1)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on every protocol and port, keyed by a caller-chosen label. Empty, because awsvpc task traffic never touches this group - see main.tf. A map rather than a list, because such IDs come from other modules and are unknown at plan time (rules.md B-8)"
  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys must be letters, digits, dots, underscores or hyphens, because they end up in a security group rule description (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups values must be valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "Managed policy ARNs on the container instance role, exactly the two the template attached. AmazonEC2ContainerServiceforEC2Role is the AWS service-role policy for this role and is what lets the agent register, poll for tasks and pull from ECR; AmazonSSMManagedInstanceCore is what makes Session Manager work for getting onto an instance in a private subnet (rules.md A-5 - these are scoped service-role policies, not a broad grant)"
  validation {
    condition     = length(var.iam_policy_arns) > 0
    error_message = "iam_policy_arns must contain at least one policy. Without AmazonEC2ContainerServiceforEC2Role the agent's RegisterContainerInstance call is denied and the instance never appears in the cluster."
  }
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "ecs_config_options" {
  type        = map(string)
  default     = {}
  description = "Extra /etc/ecs/ecs.config lines, on top of the ECS_CLUSTER line this module always writes. Empty, which is what the template wrote - in particular ECS_ENABLE_TASK_ENI is not needed, because the ECS-optimized AMI advertises the task-eni capability on its own (see main.tf)"
  validation {
    condition     = alltrue([for key in keys(var.ecs_config_options) : can(regex("^[A-Z][A-Z0-9_]*$", key))])
    error_message = "ecs_config_options keys must be upper-case agent variable names (e.g. ECS_RESERVED_MEMORY), because each is written as KEY=value into /etc/ecs/ecs.config."
  }
}
variable "metadata_http_tokens" {
  type        = string
  default     = "required"
  description = "Whether IMDSv2 is enforced, as the template set on its launch template. required is IMDSv2-only; optional allows IMDSv1, which the ECS agent does not need"
  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "metadata_http_tokens must be required or optional."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Name of the capacity provider. No default: CloudFormation generated this name, so the caller derives it from the project name as the template derived it from the stack name"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name)) && !startswith(lower(var.capacity_provider_name), "aws") && !startswith(lower(var.capacity_provider_name), "ecs") && !startswith(lower(var.capacity_provider_name), "fargate")
    error_message = "capacity_provider_name must be 1-255 characters of letters, digits, underscores and hyphens, and must not start with aws, ecs or fargate - ECS reserves those prefixes and rejects the name at apply."
  }
}
variable "additional_capacity_providers" {
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
  description = "Capacity providers attached to the cluster alongside the one this module creates, as the template listed them. Attaching the two Fargate providers costs nothing and is not used by anything here - every task definition requires EC2 compatibility - but it is what the template declared, and removing one later requires the cluster's provider list to be put again"
  validation {
    condition     = alltrue([for name in var.additional_capacity_providers : contains(["FARGATE", "FARGATE_SPOT"], name)])
    error_message = "additional_capacity_providers may only contain FARGATE and FARGATE_SPOT. Another Auto Scaling group provider would have to be created before it could be named here, and ECS rejects an unknown name at apply."
  }
}
variable "managed_scaling_status" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS sets the Auto Scaling group's desired capacity from the tasks waiting to be placed, as the template had it. Enabled is also why Terraform ignores changes to desired_capacity (see main.tf)"
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_scaling_status)
    error_message = "managed_scaling_status must be ENABLED or DISABLED."
  }
}
variable "managed_scaling_target_capacity" {
  type        = number
  default     = 100
  description = "Percentage of the group's capacity ECS aims to keep in use, as the template had it. 100 means no deliberate headroom, so a new task waits for a new instance rather than landing on a spare one"
  validation {
    condition     = var.managed_scaling_target_capacity >= 1 && var.managed_scaling_target_capacity <= 100
    error_message = "managed_scaling_target_capacity must be between 1 and 100."
  }
}
variable "managed_scaling_instance_warmup_period" {
  type        = number
  default     = 30
  description = "Seconds ECS waits before counting a newly launched instance toward capacity, as the template had it"
  validation {
    condition     = var.managed_scaling_instance_warmup_period >= 0 && var.managed_scaling_instance_warmup_period <= 10000
    error_message = "managed_scaling_instance_warmup_period must be between 0 and 10000 seconds."
  }
}
variable "managed_scaling_minimum_step_size" {
  type        = number
  default     = 1
  description = "Fewest instances ECS adds or removes in one scaling action, as the template had it"
  validation {
    condition     = var.managed_scaling_minimum_step_size >= 1 && var.managed_scaling_minimum_step_size <= 10000
    error_message = "managed_scaling_minimum_step_size must be between 1 and 10000."
  }
}
variable "managed_scaling_maximum_step_size" {
  type        = number
  default     = 10000
  description = "Most instances ECS adds or removes in one scaling action, as the template had it. 10000 is the API's maximum and is effectively no limit; with min_size equal to max_size here it has nothing to act on either way"
  validation {
    condition     = var.managed_scaling_maximum_step_size >= 1 && var.managed_scaling_maximum_step_size <= 10000
    error_message = "managed_scaling_maximum_step_size must be between 1 and 10000."
  }
  validation {
    condition     = var.managed_scaling_maximum_step_size >= var.managed_scaling_minimum_step_size
    error_message = "managed_scaling_maximum_step_size must be at least managed_scaling_minimum_step_size."
  }
}
variable "managed_draining" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS drains tasks off an instance the Auto Scaling group is terminating, as the template had it. Disabled means a terminating instance takes its running tasks with it"
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_draining)
    error_message = "managed_draining must be ENABLED or DISABLED."
  }
}
variable "managed_termination_protection" {
  type        = string
  default     = "DISABLED"
  description = "Whether ECS protects instances running tasks from scale-in, as the template had it. Enabling it also requires protect_from_scale_in on the Auto Scaling group, which this module does not set - the two are validated together by ECS and the error names the group rather than this field"
  validation {
    condition     = var.managed_termination_protection == "DISABLED"
    error_message = "managed_termination_protection must be DISABLED. ENABLED additionally requires the Auto Scaling group to set protect_from_scale_in, which this module does not declare - add it before allowing this."
  }
}
variable "capacity_distribution_strategy" {
  type        = string
  default     = "balanced-only"
  description = "How the Auto Scaling group spreads instances across zones, as the template had it. balanced-only refuses to launch into a zone that cannot satisfy the request rather than piling the shortfall into the other zone"
  validation {
    condition     = contains(["balanced-only", "balanced-best-effort"], var.capacity_distribution_strategy)
    error_message = "capacity_distribution_strategy must be balanced-only or balanced-best-effort."
  }
}
variable "default_strategy_base" {
  type        = number
  default     = 0
  description = "Tasks placed on this provider before the weights apply, as the template had it. Zero, which is the only sensible value when the cluster's default strategy names one provider"
  validation {
    condition     = var.default_strategy_base >= 0 && var.default_strategy_base <= 100000
    error_message = "default_strategy_base must be between 0 and 100000."
  }
}
variable "default_strategy_weight" {
  type        = number
  default     = 100
  description = "Relative share of tasks this provider takes in the cluster's default strategy, as the template had it. With one provider in the strategy the number is arbitrary as long as it is above zero"
  validation {
    condition     = var.default_strategy_weight >= 1 && var.default_strategy_weight <= 1000
    error_message = "default_strategy_weight must be between 1 and 1000. Zero would mean the default strategy places nothing on the only provider it names."
  }
}
