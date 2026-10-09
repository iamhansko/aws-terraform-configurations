variable "name" {
  type        = string
  default     = "ecs-cicd-alb"
  description = "Name of the ALB, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 32 characters or fewer of letters, digits and hyphens, and must not start with \"internal-\", which elbv2 reserves."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC ID where the ALB's security group and both target groups are created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the VPC, which scopes the ALB's egress to the task ENIs instead of to 0.0.0.0/0. Taken from the network module rather than restated (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.100.0.0/16)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Public subnets the ALB's nodes are placed in"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least two valid subnet IDs - elbv2 refuses to create a load balancer spanning fewer than two availability zones."
  }
}
variable "internal" {
  type        = bool
  default     = false
  description = "Whether the ALB is internal. False as the _monolithic template had it, which is what makes the deployed application reachable from a browser and requires the public subnets above"
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the production listener accepts traffic on, as the _monolithic template had it"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "target_port" {
  type        = number
  default     = 80
  description = "Port the registered targets listen on. With awsvpc targets this is the container port, so the caller passes the same value to the service module (rules.md B-5)"

  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "target_port must be a valid TCP port."
  }
}
variable "target_type" {
  type        = string
  default     = "ip"
  description = "How the target groups register targets. Must be \"ip\": the task definition uses network_mode awsvpc, so each task has its own ENI and registers by address"

  validation {
    condition     = contains(["ip", "instance"], var.target_type)
    error_message = "target_type must be ip or instance."
  }
  validation {
    condition     = var.target_type == "ip"
    error_message = "target_type must be ip in this project. The task definition uses network_mode awsvpc, and ECS rejects a service whose target group is target_type instance against an awsvpc task definition. To use instance, change the task definition to bridge or host networking and give the container a host port for the ALB to register."
  }
}
variable "target_group_names" {
  type = map(string)
  default = {
    blue  = "cicd-tg"
    green = "green-tg"
  }
  description = "The two target group names, keyed by their role in the deployment. The names are what the _monolithic template used, and the keys are literals so each group has a plan-time resource address (rules.md B-8)"

  validation {
    condition     = length(setsubtract(keys(var.target_group_names), ["blue", "green"])) == 0 && length(var.target_group_names) == 2
    error_message = "target_group_names must contain exactly the keys blue and green - CodeDeploy's target group pair has exactly two members, and the outputs name them by these keys."
  }
  validation {
    condition     = alltrue([for name in values(var.target_group_names) : can(regex("^[a-zA-Z0-9-]{1,32}$", name))])
    error_message = "target_group_names values must each be 32 characters or fewer of letters, digits and hyphens, which is what elbv2 accepts for a target group name."
  }
  validation {
    condition     = length(toset(values(var.target_group_names))) == 2
    error_message = "target_group_names values must differ. CodeDeploy's target group pair has to name two distinct groups, and a duplicate name is rejected at creation rather than at deployment time."
  }
}
variable "initial_target_group_key" {
  type        = string
  default     = "blue"
  description = "Which target group the listener forwards to at creation, and therefore which one the service registers into first. The caller passes the matching ARN to the service module, so the two cannot disagree (rules.md B-5)"

  validation {
    condition     = contains(["blue", "green"], var.initial_target_group_key)
    error_message = "initial_target_group_key must be blue or green."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path both target groups health-check, as the _monolithic template had it. The seeded Flask application answers it, and so does the container health check in the task definition"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/'."
  }
}
variable "security_group_name" {
  type        = string
  default     = "alb-sg"
  description = "Name of the ALB's security group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the public ALB in front of the blue/green ECS service"
  description = "Description attached to the ALB's security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, and changing this value replaces the group (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the listener port accepts traffic from 0.0.0.0/0. True as the _monolithic template had it - the point of the demo is opening the deployed application in a browser"
}
variable "revoke_rules_on_delete" {
  type        = bool
  default     = true
  description = "Whether Terraform revokes this group's attached rules before deleting it. Only changes Terraform's delete behaviour - it does not replace the group (rules.md F-2)"
}
