variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Null falls back to the provider chain (AWS_REGION or the shared config), which is what the _monolithic template did"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region name (e.g. us-east-1), or null to use the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "firewall-natgw-tgw"
  description = "Name of this project, used as the README heading on the workbench and as the transit gateway's Name tag. It replaces the _monolithic template's stack_name variable, whose other two readers - a Lambda function name and a cfn-signal call - are both gone"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.project_name))
    error_message = "project_name must be 1-63 characters of lowercase letters, digits and hyphens, starting with a letter or digit."
  }
}
variable "al2023_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Public SSM parameter holding the latest Amazon Linux 2023 AMI id, as the _monolithic template had it. Read in the root and passed to the instance module as a resolved id, which keeps the lookup out of a module carrying depends_on (rules.md B-6/D-6)"

  validation {
    condition     = can(regex("^/[a-zA-Z0-9_./-]+$", var.al2023_ami_ssm_parameter_name))
    error_message = "al2023_ami_ssm_parameter_name must be an SSM parameter path starting with a slash."
  }
}
variable "availability_zone_a_suffix" {
  type        = string
  default     = "a"
  description = "Zone letter of the first availability zone, appended to the region to form a full zone name. The root builds the two zone names once and hands the same pair to both VPC modules, so the spoke's zone a and the egress VPC's zone a are provably the same zone - which is what the transit gateway's zone affinity depends on"

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_a_suffix))
    error_message = "availability_zone_a_suffix must be a single lowercase letter (e.g. a)."
  }
}
variable "availability_zone_b_suffix" {
  type        = string
  default     = "b"
  description = "Zone letter of the second availability zone. Must differ from availability_zone_a_suffix"

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_b_suffix))
    error_message = "availability_zone_b_suffix must be a single lowercase letter (e.g. b)."
  }
  validation {
    condition     = var.availability_zone_b_suffix != var.availability_zone_a_suffix
    error_message = "availability_zone_b_suffix must differ from availability_zone_a_suffix. The whole point of two of everything in the egress VPC is that each zone has its own firewall endpoint and NAT gateway; one zone used twice fails the firewall create and the transit gateway attachments outright."
  }
}
# --- Egress (inspection) VPC ---
variable "egress_vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR of the egress VPC, as the _monolithic template had it. Must not overlap app_vpc_cidr_block - both are propagated into the same transit gateway route table"

  validation {
    condition     = can(cidrhost(var.egress_vpc_cidr_block, 0))
    error_message = "egress_vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "egress_vpc_name" {
  type        = string
  default     = "egress-vpc"
  description = "Name tag of the egress VPC, as the _monolithic template tagged it"

  validation {
    condition     = length(var.egress_vpc_name) > 0
    error_message = "egress_vpc_name must not be empty."
  }
}
variable "egress_internet_gateway_name" {
  type        = string
  default     = "egress-igw"
  description = "Name tag of the egress VPC's internet gateway, as the _monolithic template tagged it"

  validation {
    condition     = length(var.egress_internet_gateway_name) > 0
    error_message = "egress_internet_gateway_name must not be empty."
  }
}
variable "egress_public_subnet_name_prefix" {
  type        = string
  default     = "egress-public-sn"
  description = "Name tag prefix of the egress VPC's public subnets, as the _monolithic template tagged them"

  validation {
    condition     = length(var.egress_public_subnet_name_prefix) > 0
    error_message = "egress_public_subnet_name_prefix must not be empty."
  }
}
variable "egress_peering_subnet_name_prefix" {
  type        = string
  default     = "egress-peering-sn"
  description = "Name tag prefix of the egress VPC's transit gateway attachment subnets, as the _monolithic template tagged them. \"peering\" is the original's word; nothing here is a VPC peering connection"

  validation {
    condition     = length(var.egress_peering_subnet_name_prefix) > 0
    error_message = "egress_peering_subnet_name_prefix must not be empty."
  }
}
variable "egress_firewall_subnet_name_prefix" {
  type        = string
  default     = "egress-firewall-sn"
  description = "Name tag prefix of the egress VPC's dedicated firewall subnets, as the _monolithic template tagged them"

  validation {
    condition     = length(var.egress_firewall_subnet_name_prefix) > 0
    error_message = "egress_firewall_subnet_name_prefix must not be empty."
  }
}
variable "egress_public_route_table_name" {
  type        = string
  default     = "egress-public-rt"
  description = "Name tag of the egress VPC's public route table, as the _monolithic template tagged it"

  validation {
    condition     = length(var.egress_public_route_table_name) > 0
    error_message = "egress_public_route_table_name must not be empty."
  }
}
variable "egress_peering_route_table_name_prefix" {
  type        = string
  default     = "egress-peering-rt"
  description = "Name tag prefix of the egress VPC's per-zone attachment route tables, as the _monolithic template tagged them"

  validation {
    condition     = length(var.egress_peering_route_table_name_prefix) > 0
    error_message = "egress_peering_route_table_name_prefix must not be empty."
  }
}
variable "egress_firewall_route_table_name_prefix" {
  type        = string
  default     = "egress-firewall-rt"
  description = "Name tag prefix of the egress VPC's per-zone firewall subnet route tables, as the _monolithic template tagged them"

  validation {
    condition     = length(var.egress_firewall_route_table_name_prefix) > 0
    error_message = "egress_firewall_route_table_name_prefix must not be empty."
  }
}
variable "egress_nat_gateway_name_prefix" {
  type        = string
  default     = "egress-natgw"
  description = "Name tag prefix of the two NAT gateways, as the _monolithic template tagged them"

  validation {
    condition     = length(var.egress_nat_gateway_name_prefix) > 0
    error_message = "egress_nat_gateway_name_prefix must not be empty."
  }
}
# --- Spoke VPC ---
variable "app_vpc_cidr_block" {
  type        = string
  default     = "172.16.0.0/16"
  description = "CIDR of the spoke VPC, as the _monolithic template had it. The egress VPC's public route table carries a return route for exactly this block, which the root takes from the module's output rather than from this variable so the two cannot disagree (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.app_vpc_cidr_block, 0))
    error_message = "app_vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 172.16.0.0/16)."
  }
}
variable "app_vpc_name" {
  type        = string
  default     = "app-vpc"
  description = "Name tag of the spoke VPC, as the _monolithic template tagged it"

  validation {
    condition     = length(var.app_vpc_name) > 0
    error_message = "app_vpc_name must not be empty."
  }
}
variable "app_private_subnet_name_prefix" {
  type        = string
  default     = "app-private-sn"
  description = "Name tag prefix of the spoke VPC's private subnets, as the _monolithic template tagged them"

  validation {
    condition     = length(var.app_private_subnet_name_prefix) > 0
    error_message = "app_private_subnet_name_prefix must not be empty."
  }
}
variable "app_route_table_name" {
  type        = string
  default     = "app-rt"
  description = "Name tag of the spoke VPC's route table, as the _monolithic template tagged it"

  validation {
    condition     = length(var.app_route_table_name) > 0
    error_message = "app_route_table_name must not be empty."
  }
}
# --- Transit gateway ---
variable "transit_gateway_name" {
  type        = string
  default     = "firewall-natgw-tgw"
  description = "Name tag of the transit gateway. The _monolithic template tagged nothing here"

  validation {
    condition     = length(var.transit_gateway_name) > 0
    error_message = "transit_gateway_name must not be empty."
  }
}
variable "egress_vpc_attachment_name" {
  type        = string
  default     = "tgw-egress"
  description = "Name tag of the egress VPC's transit gateway attachment, as the _monolithic template tagged it"

  validation {
    condition     = length(var.egress_vpc_attachment_name) > 0
    error_message = "egress_vpc_attachment_name must not be empty."
  }
}
variable "app_vpc_attachment_name" {
  type        = string
  default     = "tgw-app"
  description = "Name tag of the spoke VPC's transit gateway attachment, as the _monolithic template tagged it"

  validation {
    condition     = length(var.app_vpc_attachment_name) > 0
    error_message = "app_vpc_attachment_name must not be empty."
  }
}
variable "egress_attachment_appliance_mode_support" {
  type        = string
  default     = "disable"
  description = <<-DESC
    Whether the egress VPC's attachment runs in appliance mode, which makes the transit gateway pin both
    directions of a flow to one zone. Disabled, which is the _monolithic template's behaviour and what AWS
    recommends for this specific architecture.

    The reason it is not needed is that the firewall sits ahead of the NAT gateway and the return traffic
    is addressed to the NAT gateway's own Elastic IP, so it arrives there by itself and never needs to be
    steered back through the firewall. AWS's multi-VPC whitepaper says so directly for this pattern:
    appliance mode is for traffic sent between attachments, and nothing here is.

    It becomes necessary the moment the shape changes - inspecting traffic between two spoke VPCs, or
    moving the firewall behind the NAT gateway. Turning it on without that need costs nothing but is also
    not free of consequence: appliance mode changes how flows are distributed across zones, so an existing
    deployment's traffic moves zones when it is enabled.
  DESC

  validation {
    condition     = contains(["enable", "disable"], var.egress_attachment_appliance_mode_support)
    error_message = "egress_attachment_appliance_mode_support must be enable or disable."
  }
}
variable "transit_gateway_default_route_cidr_block" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Destination of the static route the transit gateway sends to the egress VPC, as the _monolithic template had it. 0.0.0.0/0 is what makes this centralized egress rather than selective inspection - narrowing it leaves everything outside the narrowed range going nowhere, because the gateway has no other default"

  validation {
    condition     = can(cidrhost(var.transit_gateway_default_route_cidr_block, 0))
    error_message = "transit_gateway_default_route_cidr_block must be a valid IPv4 CIDR block (e.g. 0.0.0.0/0)."
  }
}
# --- Network Firewall ---
variable "firewall_name" {
  type        = string
  default     = "firewall"
  description = "Name of the firewall, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.firewall_name))
    error_message = "firewall_name must be 1-128 characters of letters, digits and hyphens."
  }
}
variable "firewall_policy_name" {
  type        = string
  default     = "firewall-policy"
  description = "Name of the firewall policy, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.firewall_policy_name))
    error_message = "firewall_policy_name must be 1-128 characters of letters, digits and hyphens."
  }
}
variable "firewall_log_types" {
  type        = set(string)
  default     = ["ALERT", "FLOW"]
  description = "Firewall log types delivered to CloudWatch Logs. An addition - the _monolithic template configured no logging, which leaves a firewall whose drops are indistinguishable from a routing mistake. An empty set reproduces that state"

  validation {
    condition     = alltrue([for log_type in var.firewall_log_types : contains(["ALERT", "FLOW"], log_type)])
    error_message = "firewall_log_types entries must be ALERT or FLOW."
  }
}
variable "firewall_log_retention_days" {
  type        = number
  default     = 7
  description = "Retention of the firewall log groups. Short by default because FLOW logging writes a line per connection"

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.firewall_log_retention_days)
    error_message = "firewall_log_retention_days must be one of the values CloudWatch Logs accepts (0 for never expire, or 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}
variable "firewall_delete_protection" {
  type        = bool
  default     = false
  description = "Whether the firewall refuses to be deleted, as the _monolithic template set it. True would make terraform destroy fail and leave the most expensive resource in this project billing by the hour"
}
# --- Key pair ---
variable "key_pair_name" {
  type        = string
  default     = null
  description = "Exact name for the generated key pair. Null generates one from the project name, which is what lets this project be applied twice in one account"

  validation {
    condition     = var.key_pair_name == null || can(regex("^[ -~]{1,255}$", var.key_pair_name))
    error_message = "key_pair_name must be 1-255 printable ASCII characters, or null to generate one."
  }
}
variable "key_pair_rsa_bits" {
  type        = number
  default     = 4096
  description = "Size of the generated RSA key, as the _monolithic template had it"

  validation {
    condition     = contains([2048, 3072, 4096], var.key_pair_rsa_bits)
    error_message = "key_pair_rsa_bits must be 2048, 3072 or 4096."
  }
}
# --- Workbench instance ---
variable "workbench_instance_name" {
  type        = string
  default     = "app-bastion"
  description = "Name tag of the workbench instance, as the _monolithic template tagged it"

  validation {
    condition     = length(var.workbench_instance_name) > 0
    error_message = "workbench_instance_name must not be empty."
  }
}
variable "workbench_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the workbench, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.workbench_instance_type))
    error_message = "workbench_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "workbench_security_group_name" {
  type        = string
  default     = "app-bastion-sg"
  description = "Name of the workbench's security group. The _monolithic template created none and attached the spoke VPC's default group - see modules/vscode_ec2/main.tf for what that substitution costs if the egress rule is forgotten"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.workbench_security_group_name)) && !startswith(var.workbench_security_group_name, "sg-")
    error_message = "workbench_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "workbench_egress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Destinations the workbench may reach outbound, every one of them through the firewall. An empty list leaves the instance with no outbound access at all, which is the silent failure rules.md F-2 exists for - and here it also means nothing ever reaches the firewall, so the demo proves nothing"

  validation {
    condition     = alltrue([for cidr in var.workbench_egress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "workbench_egress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 0.0.0.0/0)."
  }
}
variable "workbench_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Source CIDRs allowed to reach code-server on the workbench. Empty, because the IDE is reached by a Session Manager port forward that the agent terminates on the instance's own loopback address and that therefore never crosses the security group - and because there is no inbound path into the spoke VPC in the first place"

  validation {
    condition     = alltrue([for cidr in var.workbench_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "workbench_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 172.16.0.0/16)."
  }
}
variable "workbench_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "Managed policies on the workbench's instance role. AdministratorAccess, which the _monolithic template attached in Terraform itself - so narrowing it is a change to what the original did, and rules.md H-1 keeps it broad for a human workbench anyway (rules.md A-5)"

  validation {
    condition     = length(var.workbench_iam_policy_arns) > 0 && alltrue([for arn in var.workbench_iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "workbench_iam_policy_arns must be a non-empty list of IAM policy ARNs - an empty list removes SSM access, which is the only way to reach this instance."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to on the workbench and the local port the Session Manager forward opens"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be between 1 and 65535."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release installed on the workbench, pinned so the IDE does not depend on the day the instance was launched"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part version (e.g. 4.100.3)."
  }
}
variable "workbench_dnf_packages" {
  type        = list(string)
  default     = ["bind-utils", "wget", "tar", "gzip", "jq"]
  description = "Packages installed on the workbench. bind-utils is the _monolithic template's own and only choice, which says what the instance was for: dig, to watch the firewall's DNS rules take effect"

  validation {
    condition     = alltrue([for package in var.workbench_dnf_packages : can(regex("^[a-zA-Z0-9._+-]+$", package))])
    error_message = "workbench_dnf_packages entries must be plain package names - they are interpolated into a dnf command line."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where the user data leaves its completion marker and the README association leaves its own. The SSM association waits for the first marker before writing anything, which is what orders it after the bootstrap rather than after the instance's create call (rules.md D-5)"

  validation {
    condition     = can(regex("^/[^ ]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path with no spaces."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 1200
  description = <<-DESC
    How long the README association may take before Terraform gives up on it.

    It has to cover the whole bootstrap, because the association's first act is to wait for the user data's
    marker. On this instance the bootstrap is a dnf update plus a code-server download, all of it over the
    transit gateway, through the firewall and out of a NAT gateway - several minutes on a cold start.

    Too low produces "unexpected state 'Failed'" on a configuration that is entirely correct. If that
    happens, read the run command invocation before changing anything: an execution time of a hundredth of
    a second means the script failed to parse rather than timing out, which is the CRLF signature rules.md
    A-4 describes.
  DESC

  validation {
    condition     = var.readme_timeout_seconds >= 60 && var.readme_timeout_seconds <= 3600
    error_message = "readme_timeout_seconds must be between 60 and 3600. Below a minute cannot cover a dnf update and a code-server download over an inspected egress path."
  }
}
