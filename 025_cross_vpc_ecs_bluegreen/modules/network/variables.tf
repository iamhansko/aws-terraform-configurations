variable "region" {
  type        = string
  description = "Region the subnets' availability zones are built from. Passed in rather than read with data.aws_region inside this module, both because a module should not have to look up what the caller already knows (rules.md B-6) and because a data source in a module that carries depends_on is deferred to apply, which would make every availability_zone unknown at plan time (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code (e.g. ap-northeast-2)."
  }
}
variable "hub_vpc_name" {
  type        = string
  description = "Name tag of the hub VPC, the internet-facing side holding the public NLB and the workbench"

  validation {
    condition     = length(var.hub_vpc_name) > 0
    error_message = "hub_vpc_name must not be empty."
  }
}
variable "hub_vpc_cidr_block" {
  type        = string
  description = "CIDR block of the hub VPC. Must not overlap app_vpc_cidr_block - VPC peering rejects overlapping ranges, and the error names the connection rather than the overlap"

  validation {
    condition     = can(cidrhost(var.hub_vpc_cidr_block, 0))
    error_message = "hub_vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 172.28.0.0/16)."
  }
}
variable "app_vpc_name" {
  type        = string
  description = "Name tag of the app VPC, which holds the ECS cluster, the internal load balancers and Aurora"

  validation {
    condition     = length(var.app_vpc_name) > 0
    error_message = "app_vpc_name must not be empty."
  }
}
variable "app_vpc_cidr_block" {
  type        = string
  description = "CIDR block of the app VPC. Also the source range allowed inbound on the ECR endpoint security group"

  validation {
    condition     = can(cidrhost(var.app_vpc_cidr_block, 0))
    error_message = "app_vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.200.0.0/16)."
  }
}
variable "hub_public_subnet_cidr_blocks" {
  type        = map(string)
  description = "Hub public subnets, keyed by availability zone suffix. The keys are the zone letters and the module builds the zone name as region + suffix, so the map decides both how many subnets exist and which zones they land in"

  validation {
    condition     = length(var.hub_public_subnet_cidr_blocks) >= 2
    error_message = "hub_public_subnet_cidr_blocks must contain at least two zones: an internet-facing load balancer requires subnets in two availability zones, and ELB rejects a single-zone set at creation."
  }
  validation {
    condition     = alltrue([for suffix in keys(var.hub_public_subnet_cidr_blocks) : can(regex("^[a-z]$", suffix))])
    error_message = "hub_public_subnet_cidr_blocks keys must each be a single lowercase letter naming an availability zone suffix (e.g. a, b, c)."
  }
  validation {
    condition     = alltrue([for cidr in values(var.hub_public_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "hub_public_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}
variable "app_public_subnet_cidr_blocks" {
  type        = map(string)
  description = "App public subnets, keyed by availability zone suffix. These hold the NAT gateways, so a zone present in app_private_subnet_cidr_blocks must be present here too"

  validation {
    condition     = length(var.app_public_subnet_cidr_blocks) >= 2
    error_message = "app_public_subnet_cidr_blocks must contain at least two zones."
  }
  validation {
    condition     = alltrue([for cidr in values(var.app_public_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "app_public_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}
variable "app_private_subnet_cidr_blocks" {
  type        = map(string)
  description = "App private subnets, keyed by availability zone suffix. The ECS container instances, the tasks and both internal load balancers live here, and each zone gets its own NAT gateway and route table"

  validation {
    condition     = length(var.app_private_subnet_cidr_blocks) >= 2
    error_message = "app_private_subnet_cidr_blocks must contain at least two zones."
  }
  validation {
    condition     = alltrue([for cidr in values(var.app_private_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "app_private_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
  validation {
    # Cross-variable condition, available since Terraform 1.9 (rules.md B-1). The constraint is
    # about the pair: a NAT gateway for a private zone is placed in the public subnet of the same
    # zone, so a private zone with no public counterpart fails with an index error on
    # aws_subnet.app_public, which reads as a bug in the module rather than a gap in the input.
    condition     = alltrue([for suffix in keys(var.app_private_subnet_cidr_blocks) : contains(keys(var.app_public_subnet_cidr_blocks), suffix)])
    error_message = "every zone in app_private_subnet_cidr_blocks must also appear in app_public_subnet_cidr_blocks, because that zone's NAT gateway is placed in its public subnet."
  }
}
variable "app_internal_subnet_cidr_blocks" {
  type        = map(string)
  description = "App internal subnets, keyed by availability zone suffix. Only the Aurora subnet group uses these, and their route tables carry the peering route and nothing else - no 0.0.0.0/0 in either direction, which is the point of the tier"

  validation {
    condition     = length(var.app_internal_subnet_cidr_blocks) >= 2
    error_message = "app_internal_subnet_cidr_blocks must contain at least two zones: an RDS subnet group requires subnets in at least two availability zones."
  }
  validation {
    condition     = alltrue([for cidr in values(var.app_internal_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "app_internal_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}
variable "hub_internet_gateway_name" {
  type        = string
  description = "Name tag of the hub VPC internet gateway"

  validation {
    condition     = length(var.hub_internet_gateway_name) > 0
    error_message = "hub_internet_gateway_name must not be empty."
  }
}
variable "app_internet_gateway_name" {
  type        = string
  description = "Name tag of the app VPC internet gateway"

  validation {
    condition     = length(var.app_internet_gateway_name) > 0
    error_message = "app_internet_gateway_name must not be empty."
  }
}
variable "hub_public_subnet_name_prefix" {
  type        = string
  description = "Name tag prefix for hub public subnets; the zone suffix is appended"

  validation {
    condition     = length(var.hub_public_subnet_name_prefix) > 0
    error_message = "hub_public_subnet_name_prefix must not be empty."
  }
}
variable "app_public_subnet_name_prefix" {
  type        = string
  description = "Name tag prefix for app public subnets; the zone suffix is appended"

  validation {
    condition     = length(var.app_public_subnet_name_prefix) > 0
    error_message = "app_public_subnet_name_prefix must not be empty."
  }
}
variable "app_private_subnet_name_prefix" {
  type        = string
  description = "Name tag prefix for app private subnets; the zone suffix is appended"

  validation {
    condition     = length(var.app_private_subnet_name_prefix) > 0
    error_message = "app_private_subnet_name_prefix must not be empty."
  }
}
variable "app_internal_subnet_name_prefix" {
  type        = string
  description = "Name tag prefix for app internal subnets; the zone suffix is appended"

  validation {
    condition     = length(var.app_internal_subnet_name_prefix) > 0
    error_message = "app_internal_subnet_name_prefix must not be empty."
  }
}
variable "hub_public_route_table_name" {
  type        = string
  description = "Name tag of the hub public route table"

  validation {
    condition     = length(var.hub_public_route_table_name) > 0
    error_message = "hub_public_route_table_name must not be empty."
  }
}
variable "app_public_route_table_name" {
  type        = string
  description = "Name tag of the app public route table"

  validation {
    condition     = length(var.app_public_route_table_name) > 0
    error_message = "app_public_route_table_name must not be empty."
  }
}
variable "app_private_route_table_name_prefix" {
  type        = string
  description = "Name tag prefix for the per-zone app private route tables"

  validation {
    condition     = length(var.app_private_route_table_name_prefix) > 0
    error_message = "app_private_route_table_name_prefix must not be empty."
  }
}
variable "app_internal_route_table_name_prefix" {
  type        = string
  description = "Name tag prefix for the per-zone app internal route tables"

  validation {
    condition     = length(var.app_internal_route_table_name_prefix) > 0
    error_message = "app_internal_route_table_name_prefix must not be empty."
  }
}
variable "app_nat_gateway_name_prefix" {
  type        = string
  description = "Name tag prefix for the per-zone app NAT gateways and their Elastic IPs"

  validation {
    condition     = length(var.app_nat_gateway_name_prefix) > 0
    error_message = "app_nat_gateway_name_prefix must not be empty."
  }
}
variable "peering_connection_name" {
  type        = string
  description = "Name tag of the VPC peering connection between the hub and app VPCs"

  validation {
    condition     = length(var.peering_connection_name) > 0
    error_message = "peering_connection_name must not be empty."
  }
}
variable "hub_flow_log_group_name" {
  type        = string
  description = "CloudWatch Logs group the hub VPC flow log writes to. The dashboard queries this group by name, so it is one value rather than two (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.hub_flow_log_group_name))
    error_message = "hub_flow_log_group_name must be 1-512 characters of letters, digits and the set _./#- that CloudWatch Logs accepts in a log group name."
  }
}
variable "app_flow_log_group_name" {
  type        = string
  description = "CloudWatch Logs group the app VPC flow log writes to"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.app_flow_log_group_name))
    error_message = "app_flow_log_group_name must be 1-512 characters of letters, digits and the set _./#- that CloudWatch Logs accepts in a log group name."
  }
}
variable "flow_log_retention_in_days" {
  type        = number
  description = "Retention for both flow log groups. The _monolithic template created no log groups at all and so had no retention: ALL traffic from two VPCs accumulated indefinitely, and survived destroy"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_in_days)
    error_message = "flow_log_retention_in_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "flow_log_max_aggregation_interval" {
  type        = number
  description = "Seconds flow log records are aggregated over before publishing"

  validation {
    condition     = contains([60, 600], var.flow_log_max_aggregation_interval)
    error_message = "flow_log_max_aggregation_interval must be 60 or 600, the only two values EC2 accepts."
  }
}
variable "flow_log_role_name_prefix" {
  type        = string
  description = "Prefix for the generated flow log delivery role name. A prefix rather than the template's fixed VpcAFlowLogIamRole and VpcBFlowLogIamRole: an IAM role name is account-wide, so a fixed one collides with a second copy of this project and the failure is EntityAlreadyExists partway through apply"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.flow_log_role_name_prefix))
    error_message = "flow_log_role_name_prefix must be 1-38 characters from the set IAM accepts in a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "app_ecr_endpoint_security_group_name" {
  type        = string
  description = "Name of the security group guarding both ECR interface endpoints"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.app_ecr_endpoint_security_group_name)) && !startswith(var.app_ecr_endpoint_security_group_name, "sg-")
    error_message = "app_ecr_endpoint_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "app_ecr_endpoint_security_group_description" {
  type        = string
  description = "Description of the ECR endpoint security group. The _monolithic template used the literal \"Security Group\" for all nine of its groups, which says nothing in a console listing"

  validation {
    condition     = length(var.app_ecr_endpoint_security_group_description) > 0
    error_message = "app_ecr_endpoint_security_group_description must not be empty: AWS rejects an empty description, and an omitted one becomes \"Managed by Terraform\"."
  }
  validation {
    # The charset check that only fails at apply otherwise (rules.md F-1). An apostrophe is the
    # realistic way to trip it - "the endpoint's security group" reads naturally and EC2 rejects
    # the CreateSecurityGroup call with InvalidParameterValue, by which point both VPCs exist.
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.app_ecr_endpoint_security_group_description))
    error_message = "app_ecr_endpoint_security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
variable "https_port" {
  type        = number
  description = "Port the ECR interface endpoints are reached on"

  validation {
    condition     = var.https_port > 0 && var.https_port <= 65535
    error_message = "https_port must be a valid TCP port."
  }
}
