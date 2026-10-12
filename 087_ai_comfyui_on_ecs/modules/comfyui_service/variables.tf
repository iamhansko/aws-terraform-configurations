variable "name" {
  type        = string
  description = "Name of the service, and of the task family and the log group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.name))
    error_message = "name must be 1-255 letters, digits, hyphens and underscores, starting with a letter or digit."
  }
}
variable "region" {
  type        = string
  description = "Region of the log group, for the awslogs driver. Passed in rather than read here, because this module waits on others and a data source would wait with it (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as ap-northeast-2."
  }
}
variable "partition" {
  type        = string
  default     = "aws"
  description = "AWS partition, for the managed policy ARN"

  validation {
    condition     = contains(["aws", "aws-cn", "aws-us-gov"], var.partition)
    error_message = "partition must be aws, aws-cn or aws-us-gov."
  }
}
variable "cluster_arn" {
  type        = string
  description = "ARN of the cluster the service runs in"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecs:[^:]+:[0-9]{12}:cluster/", var.cluster_arn))
    error_message = "cluster_arn must be an ECS cluster ARN."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Capacity provider the service places its task on - the GPU Auto Scaling group's. Taken from that module's output, which waits for the cluster to have the provider"

  validation {
    condition     = length(var.capacity_provider_name) > 0
    error_message = "capacity_provider_name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC of the service's security group"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the task's network interface may be placed in - those the GPU instances launch into"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID."
  }
}
variable "image" {
  type        = string
  description = "Image the task runs. The root hands this over through the build trigger, so the task definition is not created before the image exists"

  validation {
    condition     = can(regex("^[^\\s]+:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image))
    error_message = "image must be a full image reference with a tag."
  }
}
variable "container_name" {
  type        = string
  default     = "ComfyUIContainer"
  description = "Name of the container, the blueprint's. The load balancer registration names it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must be 1-255 letters, digits, hyphens and underscores."
  }
}
variable "container_port" {
  type        = number
  description = "Port ComfyUI listens on - fixed by the Dockerfile's --port, which is why the caller passes the one value to this, the target group and the health check"

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be a TCP port number."
  }
}
variable "memory_reservation_mib" {
  type        = number
  description = "Soft memory limit of the container. The caller derives it from the instance types, as the blueprint did"

  validation {
    condition     = var.memory_reservation_mib >= 6 && floor(var.memory_reservation_mib) == var.memory_reservation_mib
    error_message = "memory_reservation_mib must be a whole number of MiB, at least 6 - the ECS minimum."
  }
}
variable "gpu_count" {
  type        = number
  default     = 1
  description = "GPUs reserved for the container, one as the blueprint had it - all an xlarge G instance has"

  validation {
    condition     = var.gpu_count >= 1 && floor(var.gpu_count) == var.gpu_count
    error_message = "gpu_count must be a positive whole number."
  }
}
variable "max_swap_mib" {
  type        = number
  default     = 10240
  description = "Swap the container may use, 10 GiB as the blueprint had it"

  validation {
    condition     = var.max_swap_mib >= 0
    error_message = "max_swap_mib must not be negative."
  }
}
variable "swappiness" {
  type        = number
  default     = 60
  description = "Container swappiness, 60 as the blueprint had it - the kernel's default"

  validation {
    condition     = var.swappiness >= 0 && var.swappiness <= 100
    error_message = "swappiness must be between 0 and 100."
  }
}
variable "environment" {
  type        = map(string)
  default     = {}
  description = "Plaintext environment variables of the container. Visible to anyone who can read the task definition, so nothing secret belongs here"

  validation {
    condition     = alltrue([for key in keys(var.environment) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", key))])
    error_message = "environment keys must be valid environment variable names."
  }
}
variable "volume_name" {
  type        = string
  description = "Name of the Docker volume - and so of the EBS volume REX-Ray creates for it, which finds it again by this name on every later instance"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,254}$", var.volume_name))
    error_message = "volume_name must be 1-255 letters, digits, hyphens, underscores and dots."
  }
}
variable "volume_driver" {
  type        = string
  description = "Docker volume driver - the REX-Ray plugin the instances install, named exactly as they install it"

  validation {
    condition     = length(var.volume_driver) > 0
    error_message = "volume_driver must not be empty."
  }
}
variable "volume_size_gib" {
  type        = number
  default     = 250
  description = "Size of the EBS volume the plugin creates, 250 GiB as the blueprint had it. Read only when the volume is first created - it does not resize an existing one"

  validation {
    condition     = var.volume_size_gib >= 1 && var.volume_size_gib <= 16384
    error_message = "volume_size_gib must be between 1 and 16384."
  }
}
variable "volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS type of the volume the plugin creates, gp3 as the blueprint had it"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "st1", "sc1"], var.volume_type)
    error_message = "volume_type must be an EBS volume type."
  }
}
variable "mount_path" {
  type        = string
  default     = "/home/user/opt/ComfyUI"
  description = "Where the volume is mounted - ComfyUI's install directory in the image, as the blueprint mounted it"

  validation {
    condition     = startswith(var.mount_path, "/")
    error_message = "mount_path must be an absolute path."
  }
}
variable "target_group_arn" {
  type        = string
  description = "Target group the task registers in"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:", var.target_group_arn))
    error_message = "target_group_arn must be an ELB target group ARN."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups admitted on the container port, keyed by a label the caller chooses. A map rather than a list because the IDs are other modules' outputs, unknown at plan, and for_each needs keys known then (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys go into rule descriptions, so each must be letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the service's security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\"."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security Group for ECS Service"
  description = "Description of the service's security group, as the blueprint wrote it. Changing it replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set EC2 accepts for a security group description. An apostrophe is not allowed - EC2 rejects it only at apply."
  }
}
variable "desired_count" {
  type        = number
  default     = 1
  description = "Tasks the service keeps running, one as the blueprint had it. The admin page's scale-up sets it back to one if it was lowered, which is the only thing that changes it"

  validation {
    condition     = var.desired_count >= 0 && var.desired_count <= 1
    error_message = "desired_count must be 0 or 1 - there is one GPU and one volume."
  }
}
variable "health_check_grace_period_seconds" {
  type        = number
  default     = 30
  description = "How long the service ignores load balancer health checks after a task starts, 30 seconds as the blueprint had it"

  validation {
    condition     = var.health_check_grace_period_seconds >= 0 && var.health_check_grace_period_seconds <= 2147483647
    error_message = "health_check_grace_period_seconds must not be negative."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 731
  description = "Retention of ComfyUI's log group, two years as the blueprint's LogGroup defaulted it"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "log_stream_prefix" {
  type        = string
  default     = "comfy-ui"
  description = "Prefix of the task's log streams, the blueprint's"

  validation {
    condition     = can(regex("^[^:*]{1,512}$", var.log_stream_prefix))
    error_message = "log_stream_prefix must be 1-512 characters without : or *."
  }
}
