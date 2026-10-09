variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null the provider chain decides (AWS_REGION / AWS_DEFAULT_REGION / profile), which is what the _monolithic file did"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like an AWS region (e.g. ap-northeast-2), or be null to defer to the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "cross-vpc-with-tgw"
  description = "Name prefix for everything in this root, and the title of the README written onto the workbench. Replaces the _monolithic file's stack_name variable, which existed to stand in for AWS::StackName"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen - it is used in security group names and Name tags."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = <<-DESC
    Zone suffixes both VPCs span, appended to the region to form zone names. Two, as the _monolithic
    template had (it wrote $${region}a and $${region}b into every subnet - doubled here because a
    heredoc interpolates, and written plainly the plan fails with "There is no variable named region").

    These are the for_each keys for every subnet, route table, NAT gateway and firewall subnet mapping
    below, which is why they are configuration literals rather than a data source lookup: a for_each key
    has to be known during plan (rules.md B-8). Reading them from data.aws_availability_zones would also
    make the set depend on which zones the account happens to have opted into, so adding a zone to an
    existing deployment could renumber the subnets.
  DESC

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones: the egress VPC places one NAT gateway and one firewall endpoint per zone, and a single-zone egress path loses everything when that zone does."
  }
  validation {
    condition     = length(distinct(var.availability_zone_suffixes)) == length(var.availability_zone_suffixes)
    error_message = "availability_zone_suffixes must not repeat a suffix; each one becomes a resource address."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "each availability_zone_suffixes entry must be a single lowercase letter (a, b, c ...), which is appended to the region name."
  }
}

# --- Egress VPC ---

variable "egress_vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Primary CIDR of the egress VPC, as the _monolithic template had it. Only the egress VPC module reads it, and the subnet blocks above have to stay inside it - AWS rejects a subnet outside its VPC's range with InvalidSubnet.Range, which says nothing about which of the three maps is wrong"

  validation {
    condition     = can(cidrhost(var.egress_vpc_cidr_block, 0))
    error_message = "egress_vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "egress_public_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "10.0.0.0/24"
    b = "10.0.1.0/24"
  }
  description = "Public subnets of the egress VPC by zone suffix, as the _monolithic template had them. These hold the NAT gateways and are the only subnets in either VPC with a route to an internet gateway"

  validation {
    condition     = alltrue([for cidr in values(var.egress_public_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "every egress_public_subnet_cidr_blocks value must be a valid IPv4 CIDR block."
  }
  validation {
    # Cross-variable, available since Terraform 1.9 (rules.md B-1). A missing key is not a type error:
    # the subnet resource's for_each would index the map with a suffix it does not hold and the plan
    # fails with "Invalid index", which does not say which of the three maps is short.
    condition     = alltrue([for suffix in var.availability_zone_suffixes : contains(keys(var.egress_public_subnet_cidr_blocks), suffix)])
    error_message = "egress_public_subnet_cidr_blocks must have an entry for every suffix in availability_zone_suffixes."
  }
}
variable "egress_attachment_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "10.0.2.0/24"
    b = "10.0.3.0/24"
  }
  description = <<-DESC
    Subnets of the egress VPC that hold the transit gateway attachment's ENIs, by zone suffix. Same
    addresses the _monolithic template used for what it called its "peering" subnets
    (egress-peering-sn-a/b, 10.0.2.0/24 and 10.0.3.0/24).

    Renamed because nothing here peers. There is no VPC peering connection in this project; these
    subnets exist so the transit gateway can place an attachment ENI in each zone, and the route table
    on them is what turns traffic arriving from the gateway towards a NAT gateway. Calling them peering
    subnets sends the next reader looking for a aws_vpc_peering_connection that was never there.
  DESC

  validation {
    condition     = alltrue([for cidr in values(var.egress_attachment_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "every egress_attachment_subnet_cidr_blocks value must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : contains(keys(var.egress_attachment_subnet_cidr_blocks), suffix)])
    error_message = "egress_attachment_subnet_cidr_blocks must have an entry for every suffix in availability_zone_suffixes."
  }
}
variable "egress_firewall_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "10.0.4.0/24"
    b = "10.0.5.0/24"
  }
  description = "Subnets of the egress VPC that hold the Network Firewall endpoints, by zone suffix, as the _monolithic template had them. A firewall subnet must contain nothing but the firewall endpoint - AWS reserves it - and it deliberately has no route table association of its own here, which is the subject of the long note in modules/network_firewall/main.tf"

  validation {
    condition     = alltrue([for cidr in values(var.egress_firewall_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "every egress_firewall_subnet_cidr_blocks value must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : contains(keys(var.egress_firewall_subnet_cidr_blocks), suffix)])
    error_message = "egress_firewall_subnet_cidr_blocks must have an entry for every suffix in availability_zone_suffixes."
  }
}

# --- App VPC ---

variable "app_vpc_cidr_block" {
  type        = string
  default     = "172.16.0.0/16"
  description = "Primary CIDR of the app VPC, as the _monolithic template had it. This is the destination of the egress VPC public route table's return route, so a change here has to reach that route - which is why both read this one variable rather than restating the block (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.app_vpc_cidr_block, 0))
    error_message = "app_vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 172.16.0.0/16)."
  }
}
variable "app_private_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "172.16.0.0/24"
    b = "172.16.1.0/24"
  }
  description = "Private subnets of the app VPC by zone suffix, as the _monolithic template had them. These hold both the transit gateway attachment and the workbench, and they have no internet gateway and no NAT gateway of their own - everything leaves through the transit gateway"

  validation {
    condition     = alltrue([for cidr in values(var.app_private_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "every app_private_subnet_cidr_blocks value must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : contains(keys(var.app_private_subnet_cidr_blocks), suffix)])
    error_message = "app_private_subnet_cidr_blocks must have an entry for every suffix in availability_zone_suffixes."
  }
}

# --- Transit gateway ---

variable "transit_gateway_auto_accept_shared_attachments" {
  type        = string
  default     = "enable"
  description = "Whether attachments shared from another account are accepted without approval. Enabled, as the _monolithic template had it, and worth narrowing for anything beyond a demo: both VPCs here are in the same account, so nothing in this root needs it"

  validation {
    condition     = contains(["enable", "disable"], var.transit_gateway_auto_accept_shared_attachments)
    error_message = "transit_gateway_auto_accept_shared_attachments must be either enable or disable."
  }
}
variable "default_route_cidr_block" {
  type        = string
  default     = "0.0.0.0/0"
  description = "The destination that means 'everything not local'. A variable only so the three route resources in this root and the two in the egress VPC module cannot disagree about it; there is no sensible second value for a centralized egress design"

  validation {
    condition     = can(cidrhost(var.default_route_cidr_block, 0))
    error_message = "default_route_cidr_block must be a valid IPv4 CIDR block."
  }
}

# --- Network Firewall ---

variable "firewall_name" {
  type        = string
  default     = "firewall"
  description = "Name of the Network Firewall, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.firewall_name))
    error_message = "firewall_name must be 1-128 characters of letters, digits and hyphens."
  }
}
variable "firewall_blocked_dns_port" {
  type        = number
  default     = 53
  description = "Destination port the stateful rule group drops, as the _monolithic template's rules_string did. Blocking DNS egress stops a host from using a resolver outside the VPC; the Amazon-provided resolver at the VPC+2 address is answered inside the VPC and never crosses the transit gateway, so ordinary name resolution keeps working and 'dig @8.8.8.8' is what the rule is aimed at"

  validation {
    condition     = var.firewall_blocked_dns_port > 0 && var.firewall_blocked_dns_port <= 65535
    error_message = "firewall_blocked_dns_port must be a valid TCP/UDP port."
  }
}
variable "firewall_rule_group_capacity" {
  type        = number
  default     = 100
  description = "Reserved capacity for each of the two rule groups, as the _monolithic template had it. Capacity is fixed at creation: raising it later replaces the rule group, and the policy that references it is updated in place, so the change is not destructive to the firewall itself"

  validation {
    condition     = var.firewall_rule_group_capacity >= 1 && var.firewall_rule_group_capacity <= 30000
    error_message = "firewall_rule_group_capacity must be between 1 and 30000."
  }
}
variable "firewall_delete_protection" {
  type        = bool
  default     = false
  description = "Whether AWS refuses to delete the firewall. False, as the _monolithic template had it, and that is the right default for a demo: a Network Firewall bills per hour from creation, and with this on terraform destroy fails partway through and leaves it running"
}
variable "firewall_subnet_change_protection" {
  type        = bool
  default     = false
  description = "Whether AWS refuses to change the firewall's subnets. False, as the _monolithic template had it"
}
variable "firewall_policy_change_protection" {
  type        = bool
  default     = false
  description = "Whether AWS refuses to change the firewall's policy association. False, as the _monolithic template had it"
}
variable "enable_firewall_logging" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether to send the firewall's FLOW and ALERT logs to CloudWatch Logs. On, and this is an addition -
    the _monolithic template configured no logging at all.

    It is here because it is the only way to observe whether the firewall sees any traffic. With the
    routing this project reproduces it sees none, so an empty FLOW log group is the proof of that, and
    without a logging configuration there is nothing to look at and no way to tell an idle firewall from
    a bypassed one. See the note above aws_networkfirewall_firewall in modules/network_firewall/main.tf.
  DESC
}
variable "firewall_log_retention_days" {
  type        = number
  default     = 7
  description = "Retention on the firewall's log groups. Set rather than left at never-expire so a destroyed project stops costing anything; the log groups are Terraform resources, so destroy removes them either way"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.firewall_log_retention_days)
    error_message = "firewall_log_retention_days must be one of the retention periods CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

# --- Key pair ---

variable "key_name" {
  type        = string
  default     = "cross-vpc-with-tgw-key"
  description = "Name of the generated EC2 key pair. A literal name rather than the _monolithic template's uuid-derived one, which is why this root cannot be applied twice into one account and region - see providers.tf. Nothing can actually use the key: the workbench sits in a private subnet with no inbound rule, so the key is reproduced for parity and SSM Session Manager is the way in"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 characters of letters, digits, dots, underscores or hyphens."
  }
}

# --- Workbench ---

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the workbench, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "vscode_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the workbench's AMI ID, as the _monolithic template's amazon_linux2023_ami_id parameter defaulted to"

  validation {
    condition     = can(regex("^/", var.vscode_ami_ssm_parameter_name))
    error_message = "vscode_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "vscode_root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of the workbench's root volume. The _monolithic template left this at the AMI default, which is tight once code-server and its extensions are on it"

  validation {
    condition     = var.vscode_root_volume_size >= 8
    error_message = "vscode_root_volume_size must be at least 8 GiB."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.140.0"
  description = "code-server release to install. Pinned rather than resolved from the GitHub releases API at boot, which makes the installed version a function of the day of the apply and fails closed when the unauthenticated rate limit is hit"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.140.0)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "TCP port code-server binds to. Nothing in a security group opens it - the workbench is in a private subnet with no inbound rule - so this is the port the SSM port-forwarding command in the outputs targets"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "vscode_security_group_name" {
  type        = string
  default     = "vscode-sg"
  description = "Suffix of the workbench security group's name; the project name is prefixed. The _monolithic template created no security group and attached the app VPC's default group instead (rules.md F-2)"

  validation {
    condition     = length(var.vscode_security_group_name) > 0
    error_message = "vscode_security_group_name must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.vscode_security_group_name)) && !startswith(var.vscode_security_group_name, "sg-")
    error_message = "vscode_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs (rules.md F-1)."
  }
}
variable "vscode_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = <<-DESC
    CIDR blocks allowed inbound to code_server_port on the workbench. Empty, and empty is the only value
    that means anything here: the app VPC has no internet gateway, so no address outside it can reach
    this instance however the group is written.

    A CIDR inside the app or egress VPC's range does work, which is the case this is kept for - there is
    nothing else in either VPC today, so it stays off by default (rules.md B-4). Note there is
    deliberately no allow_inbound_from_anywhere switch, unlike the other workbenches in this repository:
    a flag promising inbound access from 0.0.0.0/0 to a subnet with no route from the internet would
    create a rule, change nothing, and read as though the IDE were exposed.
  DESC

  validation {
    condition     = alltrue([for cidr in var.vscode_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "vscode_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "vscode_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AdministratorAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = <<-DESC
    Managed policies on the workbench's instance role - the same two the _monolithic template attached,
    in the same order.

    AdministratorAccess is kept deliberately. rules.md A-5 has two cases and this is the second: the
    broad policy was in the template's Terraform rather than hidden in a bootstrap script, so narrowing
    it would be a change to what the original did. It is also the case rules.md A-5 exempts - this is a
    human's workbench, not a controller, and rules.md H-1 takes a broad role on a workbench as the
    premise. The host has to be able to read route tables, describe the firewall and tail its logs,
    which is most of what the outputs of this root tell someone to do.

    AmazonSSMManagedInstanceCore is load-bearing rather than convenient: it is what lets the instance
    register with Systems Manager, and Session Manager is the only way onto this host and the only way
    to reach code-server at all. Without it the aws_ssm_association that writes the README never finds a
    target and apply fails on a timeout.
  DESC

  validation {
    condition     = alltrue([for arn in var.vscode_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "vscode_iam_policy_arns must contain valid IAM policy ARNs."
  }
  validation {
    condition     = contains(var.vscode_iam_policy_arns, "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore")
    error_message = "vscode_iam_policy_arns must include AmazonSSMManagedInstanceCore. The workbench is in a private subnet with no inbound rule, so Session Manager is the only way to reach it, and the aws_ssm_association that renders the README onto it would otherwise wait for a target that never registers and fail the apply with 'unexpected state Failed' (rules.md H-2)."
  }
}
variable "vscode_metadata_http_tokens" {
  type        = string
  default     = "required"
  description = "Whether IMDSv2 is mandatory on the workbench. Required, where the _monolithic template left EC2's default of optional. The instance role is AdministratorAccess, and a token-less metadata read is exactly the shape an SSRF uses to get at it; nothing in the bootstrap is affected because the AWS CLI and SDKs negotiate the token themselves"

  validation {
    condition     = contains(["required", "optional"], var.vscode_metadata_http_tokens)
    error_message = "vscode_metadata_http_tokens must be either required or optional."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory the workbench touches a completion marker in once its bootstrap has finished, and the directory the README association waits on (rules.md D-5/H-2). Passed to the module and read back from its output so the path exists in one place (rules.md B-5)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null to skip the marker entirely."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = <<-DESC
    How long apply waits for the README association to report success.

    Generous on purpose. The association does not start work until the workbench's bootstrap has
    touched its marker, and that bootstrap runs dnf update and downloads code-server over the full
    centralized egress path - app VPC, transit gateway, egress VPC attachment subnet, NAT gateway,
    internet gateway. Every one of those hops is a place this project can be wrong, and when one is the
    symptom is this timeout rather than an error naming the broken route.
  DESC

  validation {
    condition     = var.readme_timeout_seconds >= 60
    error_message = "readme_timeout_seconds must be at least 60; the association waits on a bootstrap that installs code-server over the egress path, which takes minutes."
  }
}
variable "egress_check_script_path" {
  type        = string
  default     = "/home/ec2-user/egress-check.sh"
  description = "Absolute path of the helper script the workbench's bootstrap writes out. It runs the three probes that distinguish a working centralized egress path from a broken one, and whose results also show whether the firewall is in that path at all"

  validation {
    condition     = can(regex("^/", var.egress_check_script_path))
    error_message = "egress_check_script_path must be an absolute path starting with '/'."
  }
}
variable "public_ip_echo_url" {
  type        = string
  default     = "https://ifconfig.me"
  description = "Service the helper script asks for the source address the internet sees. The answer should be one of the egress VPC's NAT gateway addresses, never the workbench's own 172.16 address - that is the single clearest confirmation that egress is centralized"

  validation {
    condition     = can(regex("^https://", var.public_ip_echo_url))
    error_message = "public_ip_echo_url must be an https URL."
  }
}
variable "external_dns_resolver" {
  type        = string
  default     = "8.8.8.8"
  description = "Resolver the helper script queries to exercise the firewall's stateful DNS rule. It has to be outside the VPC: a query to the Amazon-provided resolver is answered inside the VPC and never reaches the transit gateway, so it would pass whether the rule works or not"

  validation {
    condition     = can(cidrhost("${var.external_dns_resolver}/32", 0))
    error_message = "external_dns_resolver must be a single IPv4 address (e.g. 8.8.8.8)."
  }
}
