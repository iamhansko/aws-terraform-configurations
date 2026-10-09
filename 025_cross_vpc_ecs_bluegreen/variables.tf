variable "aws_region" {
  type        = string
  default     = null
  description = "Region everything is built in. Null falls through to the provider chain (AWS_REGION or the shared config), which is what the _monolithic template did"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be an AWS region code (e.g. ap-northeast-2), or null to use the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "ws25"
  description = "Prefix for every name in this project. Replaces the _monolithic template's stack_name, which fed a synthetic CloudFormation stack ARN - see providers.tf. The names that have to be unique account-wide use a generated suffix on top of this, so two copies of the project can coexist"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "project_name must start with a lowercase letter, contain only lowercase letters, digits and hyphens, and be 21 characters or fewer: it is a prefix on load balancer and target group names, which are limited to 32 characters."
  }
}
# --- Network ---
variable "hub_vpc_cidr_block" {
  type        = string
  default     = "172.28.0.0/16"
  description = "CIDR of the hub VPC, the internet-facing side"

  validation {
    condition     = can(cidrhost(var.hub_vpc_cidr_block, 0))
    error_message = "hub_vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "hub_public_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "172.28.0.0/20"
    c = "172.28.16.0/20"
  }
  description = "Hub public subnets by zone suffix. Two zones, as the _monolithic template had it, which is the minimum an internet-facing load balancer accepts"

  validation {
    condition     = alltrue([for cidr in values(var.hub_public_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "hub_public_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}
variable "app_vpc_cidr_block" {
  type        = string
  default     = "10.200.0.0/16"
  description = "CIDR of the app VPC. Must not overlap hub_vpc_cidr_block, which the cross-variable validation below enforces"

  validation {
    condition     = can(cidrhost(var.app_vpc_cidr_block, 0))
    error_message = "app_vpc_cidr_block must be a valid IPv4 CIDR block."
  }
  validation {
    # Cross-variable condition (rules.md B-1). Two overlapping ranges cannot be peered at all, and
    # EC2 rejects the connection rather than the CIDR - so the error names the peering connection
    # and says nothing about which of the two blocks is wrong. The check is a weak one on purpose:
    # a full overlap test is not expressible here, and the realistic mistake is giving both VPCs
    # the same block.
    condition     = var.app_vpc_cidr_block != var.hub_vpc_cidr_block
    error_message = "app_vpc_cidr_block must differ from hub_vpc_cidr_block: EC2 refuses to peer VPCs with overlapping CIDR blocks, and reports it against the peering connection rather than against either range."
  }
}
variable "app_public_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "10.200.10.0/24"
    b = "10.200.11.0/24"
    c = "10.200.12.0/24"
  }
  description = "App public subnets by zone suffix. These hold the NAT gateways and nothing else"

  validation {
    condition     = alltrue([for cidr in values(var.app_public_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "app_public_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}
variable "app_private_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "10.200.20.0/24"
    b = "10.200.21.0/24"
    c = "10.200.22.0/24"
  }
  description = "App private subnets by zone suffix. The container instances, the tasks, the internal ALB and the internal NLB all live here, and each zone gets its own NAT gateway"

  validation {
    condition     = alltrue([for cidr in values(var.app_private_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "app_private_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}
variable "app_internal_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "10.200.30.0/24"
    c = "10.200.31.0/24"
  }
  description = "App internal subnets by zone suffix, for the Aurora subnet group only. No route to the internet in either direction"

  validation {
    condition     = alltrue([for cidr in values(var.app_internal_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "app_internal_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}
variable "flow_log_retention_in_days" {
  type        = number
  default     = 7
  description = "Retention on both VPC flow log groups. The _monolithic template declared no log groups, so ALL traffic from two VPCs accumulated with no retention and survived destroy"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_in_days)
    error_message = "flow_log_retention_in_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "flow_log_max_aggregation_interval" {
  type        = number
  default     = 600
  description = "Seconds flow log records are aggregated over. 600 in the _monolithic template, which is the cheaper of the two values EC2 accepts"

  validation {
    condition     = contains([60, 600], var.flow_log_max_aggregation_interval)
    error_message = "flow_log_max_aggregation_interval must be 60 or 600."
  }
}
variable "https_port" {
  type        = number
  default     = 443
  description = "Port the ECR interface endpoints are reached on"

  validation {
    condition     = var.https_port > 0 && var.https_port <= 65535
    error_message = "https_port must be a valid TCP port."
  }
}
# --- Key pair ---
variable "key_rsa_bits" {
  type        = number
  default     = 4096
  description = "Size of the generated SSH key, as the _monolithic template had it"

  validation {
    condition     = contains([2048, 3072, 4096], var.key_rsa_bits)
    error_message = "key_rsa_bits must be 2048, 3072 or 4096."
  }
}
# --- KMS ---
variable "kms_enable_key_rotation" {
  type        = bool
  default     = true
  description = "Whether KMS rotates the key material automatically, as the _monolithic template had it"
}
variable "kms_rotation_period_in_days" {
  type        = number
  default     = 90
  description = "Days between automatic key rotations"

  validation {
    condition     = var.kms_rotation_period_in_days >= 90 && var.kms_rotation_period_in_days <= 2560
    error_message = "kms_rotation_period_in_days must be between 90 and 2560."
  }
}
variable "kms_deletion_window_in_days" {
  type        = number
  default     = 7
  description = "Days KMS waits before destroying the key after a destroy. Seven rather than the provider default of 30: the alias is held against a new key for the whole window, so a destroy and re-apply inside it fails on the alias"

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}
# --- Workbench ---
variable "workbench_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Public SSM parameter resolved to the workbench AMI. Read in the root rather than inside the module, so the lookup happens at plan time instead of being deferred by the module's depends_on (rules.md D-6)"

  validation {
    condition     = can(regex("^/", var.workbench_ami_ssm_parameter_name))
    error_message = "workbench_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "workbench_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type of the workbench, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.workbench_instance_type))
    error_message = "workbench_instance_type must be a valid EC2 instance type."
  }
}
variable "workbench_root_volume_size" {
  type        = number
  default     = 50
  description = "Root volume size in GiB. Larger than the 8 GiB AL2023 default the _monolithic template inherited, because this instance builds four container images and keeps every build layer"

  validation {
    condition     = var.workbench_root_volume_size >= 20
    error_message = "workbench_root_volume_size must be at least 20 GiB: four ubuntu-based images plus the build cache do not fit in less."
  }
}
variable "workbench_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source ranges allowed to reach code-server and SSH on the workbench. 0.0.0.0/0 as the _monolithic template had it, and code-server runs with auth disabled - so the URL is the credential. Narrow this to an office range for anything that outlives a demo"

  validation {
    condition     = length(var.workbench_ingress_cidr_blocks) > 0
    error_message = "workbench_ingress_cidr_blocks must contain at least one range: with none, code-server is unreachable and so is the README this project writes onto the instance."
  }
  validation {
    condition     = alltrue([for cidr in var.workbench_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "workbench_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "workbench_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "Managed policies on the workbench role. Broad on purpose: rules.md A-5 narrows the automated roles and excludes the workbench, because a person drives this one and the demo runs docker, ecr, elbv2, ecs, s3 and secretsmanager calls from it"

  validation {
    condition     = length(var.workbench_iam_policy_arns) > 0
    error_message = "workbench_iam_policy_arns must contain at least one policy."
  }
  validation {
    condition     = alltrue([for arn in var.workbench_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "workbench_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release installed on the workbench, pinned as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.100.3)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "ssh_port" {
  type        = number
  default     = 10100
  description = "Port sshd is moved to on the workbench, as the _monolithic template had it. Port 22 stays closed"

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "ssh_port must be a valid TCP port."
  }
}
variable "python_version" {
  type        = string
  default     = "3.12"
  description = "Python minor version installed on the workbench and symlinked to /usr/bin/python"

  validation {
    condition     = can(regex("^3\\.[0-9]+$", var.python_version))
    error_message = "python_version must be a 3.x minor version (e.g. 3.12)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench holding the step markers. The bootstrap writes one when it finishes and each SSM association waits for the previous step's marker and writes its own, which is how the four steps are ordered (rules.md D-5). Under /run so the markers do not survive a reboot - a restarted instance has not re-run the steps"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
# --- Load balancers ---
variable "load_balancer_listener_port" {
  type        = number
  default     = 80
  description = "Port every listener in the chain accepts on: the hub network load balancer, the app network load balancer and the application load balancer. One value because the chain forwards port to port - a mismatch anywhere leaves the targets below it unhealthy"

  validation {
    condition     = var.load_balancer_listener_port > 0 && var.load_balancer_listener_port <= 65535
    error_message = "load_balancer_listener_port must be a valid TCP port."
  }
}
variable "hub_nlb_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source ranges allowed to reach the public entry point. 0.0.0.0/0, as the _monolithic template had it - this is the one thing in the project that is meant to be public"

  validation {
    condition     = alltrue([for cidr in var.hub_nlb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "hub_nlb_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "nlb_health_check_interval" {
  type        = number
  default     = 30
  description = "Seconds between network load balancer target group health checks"

  validation {
    condition     = var.nlb_health_check_interval >= 5 && var.nlb_health_check_interval <= 300
    error_message = "nlb_health_check_interval must be between 5 and 300 seconds."
  }
}
variable "nlb_health_check_healthy_threshold" {
  type        = number
  default     = 3
  description = "Consecutive successes before a network load balancer target is in service"

  validation {
    condition     = var.nlb_health_check_healthy_threshold >= 2 && var.nlb_health_check_healthy_threshold <= 10
    error_message = "nlb_health_check_healthy_threshold must be between 2 and 10."
  }
}
variable "nlb_health_check_unhealthy_threshold" {
  type        = number
  default     = 3
  description = "Consecutive failures before a network load balancer target is out of service"

  validation {
    condition     = var.nlb_health_check_unhealthy_threshold >= 2 && var.nlb_health_check_unhealthy_threshold <= 10
    error_message = "nlb_health_check_unhealthy_threshold must be between 2 and 10."
  }
}
variable "nlb_deregistration_delay" {
  type        = number
  default     = 30
  description = "Seconds a network load balancer target group waits before completing a deregistration, as the _monolithic template had it. The elbv2 default is 300, which a destroy waits out per target"

  validation {
    condition     = var.nlb_deregistration_delay >= 0 && var.nlb_deregistration_delay <= 3600
    error_message = "nlb_deregistration_delay must be between 0 and 3600 seconds."
  }
}
variable "nlb_enable_cross_zone_load_balancing" {
  type        = bool
  default     = true
  description = "Whether a network load balancer node may send traffic to a target in another zone. True here, and it matters for the hub load balancer: its targets are addresses in the other VPC registered with AvailabilityZone=all, so a node in a zone with no local target has nothing to forward to otherwise. Off is the elbv2 default"
}
variable "alb_idle_timeout" {
  type        = number
  default     = 60
  description = "Seconds the application load balancer keeps an idle connection. The _monolithic template left this unset, taking the same default"

  validation {
    condition     = var.alb_idle_timeout >= 1 && var.alb_idle_timeout <= 4000
    error_message = "alb_idle_timeout must be between 1 and 4000 seconds."
  }
}
variable "alb_fixed_response_content_type" {
  type        = string
  default     = "text/plain"
  description = "Content type of the application load balancer's two fixed responses. text/plain as the _monolithic template had it, while the bodies below are HTML - so a browser shows the markup. Set it to text/html to have it rendered"

  validation {
    condition     = contains(["text/plain", "text/css", "text/html", "application/javascript", "application/json"], var.alb_fixed_response_content_type)
    error_message = "alb_fixed_response_content_type must be one of the five content types elbv2 accepts in a fixed response."
  }
}
variable "alb_not_found_status_code" {
  type        = string
  default     = "404"
  description = "Status code the application load balancer listener returns for a path no stack rule matches"

  validation {
    condition     = can(regex("^[2-5][0-9][0-9]$", var.alb_not_found_status_code))
    error_message = "alb_not_found_status_code must be a three digit HTTP status code as a string."
  }
}
variable "alb_not_found_message_body" {
  type        = string
  default     = "<center><h1>404 Not Found</h1></center>"
  description = "Body of the listener default action, as the _monolithic template wrote it"

  validation {
    condition     = length(var.alb_not_found_message_body) > 0 && length(var.alb_not_found_message_body) <= 1024
    error_message = "alb_not_found_message_body must be between 1 and 1024 characters."
  }
}
variable "alb_error_path" {
  type        = string
  default     = "/error"
  description = "Path the application load balancer answers with a fixed 500, so the 5xx alarm and the dashboard widget can be made to fire without breaking an application"

  validation {
    condition     = can(regex("^/", var.alb_error_path))
    error_message = "alb_error_path must start with '/'."
  }
}
variable "alb_error_rule_priority" {
  type        = number
  default     = 5
  description = "Listener rule priority of the error path. Has to differ from every stack's two priorities, which the cross-variable validation on app_stacks enforces"

  validation {
    condition     = var.alb_error_rule_priority >= 1 && var.alb_error_rule_priority <= 50000
    error_message = "alb_error_rule_priority must be between 1 and 50000."
  }
}
variable "alb_error_status_code" {
  type        = string
  default     = "500"
  description = "Status code returned on the error path"

  validation {
    condition     = can(regex("^[2-5][0-9][0-9]$", var.alb_error_status_code))
    error_message = "alb_error_status_code must be a three digit HTTP status code as a string."
  }
}
variable "alb_error_message_body" {
  type        = string
  default     = "<center><h1>500 Internal Server Error</h1></center>"
  description = "Body returned on the error path, as the _monolithic template wrote it"

  validation {
    condition     = length(var.alb_error_message_body) > 0 && length(var.alb_error_message_body) <= 1024
    error_message = "alb_error_message_body must be between 1 and 1024 characters."
  }
}
# --- Aurora ---
variable "rds_engine" {
  type        = string
  default     = "aurora-mysql"
  description = "Aurora engine, as the _monolithic template had it"

  validation {
    condition     = contains(["aurora-mysql", "aurora-postgresql"], var.rds_engine)
    error_message = "rds_engine must be aurora-mysql or aurora-postgresql."
  }
}
variable "rds_engine_version" {
  type        = string
  default     = "8.0.mysql_aurora.3.09.0"
  description = "Engine version, pinned as the _monolithic template had it"

  validation {
    condition     = length(var.rds_engine_version) > 0
    error_message = "rds_engine_version must not be empty."
  }
}
variable "rds_database_name" {
  type        = string
  default     = "day1"
  description = "Initial database. The schema-loading association creates its tables inside it and the application connects to it by name"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,63}$", var.rds_database_name))
    error_message = "rds_database_name must start with a letter and contain only letters, digits and underscores."
  }
}
variable "rds_port" {
  type        = number
  default     = 10101
  description = "Port Aurora listens on, as the _monolithic template moved it to. One value: the cluster, the security group rules, the credential secret and the mysql client all read it"

  validation {
    condition     = var.rds_port > 0 && var.rds_port <= 65535
    error_message = "rds_port must be a valid TCP port."
  }
}
variable "rds_username" {
  type        = string
  default     = "admin"
  description = "Aurora master user"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,15}$", var.rds_username))
    error_message = "rds_username must start with a letter, contain only letters, digits and underscores, and be 16 characters or fewer for MySQL."
  }
}
variable "rds_password" {
  type        = string
  default     = "dbpassword"
  sensitive   = true
  description = "Aurora master password, as the _monolithic template defaulted it. Never reaches an output or the README on the workbench - the outputs expose the secretsmanager get-secret-value command instead (rules.md H-2). Change it for anything that is not a demo"

  validation {
    condition     = length(var.rds_password) >= 8 && length(var.rds_password) <= 41
    error_message = "rds_password must be between 8 and 41 characters, the range RDS accepts for a MySQL master password."
  }
}
variable "rds_instance_class" {
  type        = string
  default     = "db.t4g.medium"
  description = "Instance class of each Aurora cluster instance"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.rds_instance_class))
    error_message = "rds_instance_class must be an RDS instance class (e.g. db.t4g.medium)."
  }
}
variable "rds_instance_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zone suffixes the Aurora cluster instances are placed in, one instance per entry. The _monolithic template declared two, in a and c, matching the internal subnets"

  validation {
    condition     = length(var.rds_instance_zone_suffixes) >= 1
    error_message = "rds_instance_zone_suffixes must contain at least one zone: a cluster with no instances has an endpoint that refuses every connection, which is what the original's aws_db_instance conversion produced."
  }
  validation {
    condition     = alltrue([for suffix in var.rds_instance_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "rds_instance_zone_suffixes must each be a single lowercase letter."
  }
  validation {
    # Cross-variable condition (rules.md B-1): an instance can only be placed in a zone the
    # subnet group covers, and RDS reports the mismatch as InvalidParameterValue naming the zone.
    condition     = alltrue([for suffix in var.rds_instance_zone_suffixes : contains(keys(var.app_internal_subnet_cidr_blocks), suffix)])
    error_message = "every zone in rds_instance_zone_suffixes must have an internal subnet in app_internal_subnet_cidr_blocks: the DB subnet group is built from those subnets, and RDS cannot place an instance in a zone the subnet group does not cover."
  }
}
variable "rds_backup_retention_period" {
  type        = number
  default     = 34
  description = "Days of automated backups retained, as the _monolithic template had it"

  validation {
    condition     = var.rds_backup_retention_period >= 1 && var.rds_backup_retention_period <= 35
    error_message = "rds_backup_retention_period must be between 1 and 35 days."
  }
}
variable "rds_backtrack_window" {
  type        = number
  default     = 10800
  description = "Seconds of Aurora MySQL backtrack window, as the _monolithic template had it. Zero disables it"

  validation {
    condition     = var.rds_backtrack_window >= 0 && var.rds_backtrack_window <= 259200
    error_message = "rds_backtrack_window must be between 0 and 259200 seconds."
  }
}
variable "rds_cloudwatch_logs_exports" {
  type        = list(string)
  default     = ["audit", "error", "general", "instance"]
  description = "Log types exported to CloudWatch Logs, as the _monolithic template had them. \"instance\" is a valid Aurora MySQL type - it is not valid for RDS for MySQL, which is the engine it reads like a mistake for"

  validation {
    condition     = alltrue([for log in var.rds_cloudwatch_logs_exports : contains(["audit", "error", "general", "instance", "slowquery", "iam-db-auth-error", "postgresql"], log)])
    error_message = "rds_cloudwatch_logs_exports must contain only log types RDS accepts for the chosen engine."
  }
}
variable "rds_database_insights_mode" {
  type        = string
  default     = "standard"
  description = "Database Insights mode, as the _monolithic template had it. standard pairs with a 7 day Performance Insights retention; advanced requires 465"

  validation {
    condition     = contains(["standard", "advanced"], var.rds_database_insights_mode)
    error_message = "rds_database_insights_mode must be standard or advanced."
  }
}
variable "rds_performance_insights_retention_period" {
  type        = number
  default     = 7
  description = "Days of Performance Insights data retained"

  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.rds_performance_insights_retention_period)
    error_message = "rds_performance_insights_retention_period must be 7, 731, or a multiple of 31 up to 713."
  }
  validation {
    # The same pairing the rds_cluster module checks, repeated here so it fails one layer earlier.
    # A module's variable validation only runs when the module's variables are evaluated, so
    # without this the mismatch is reported against a variable inside modules/rds_cluster rather
    # than against the two root values that produced it (rules.md B-1).
    condition     = var.rds_database_insights_mode == "advanced" ? var.rds_performance_insights_retention_period == 465 : true
    error_message = "rds_performance_insights_retention_period must be 465 when rds_database_insights_mode is advanced. Set the mode back to standard for a 7 day retention - RDS rejects the mismatch with a message about the retention period, which does not mention the mode that was actually chosen."
  }
}
variable "rds_monitoring_interval" {
  type        = number
  default     = 10
  description = "Seconds between Enhanced Monitoring samples, as the _monolithic template had it. Set on each cluster instance rather than on the cluster - see modules/rds_cluster. Zero disables it"

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.rds_monitoring_interval)
    error_message = "rds_monitoring_interval must be 0, 1, 5, 10, 15, 30 or 60."
  }
}
variable "rds_monitoring_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"]
  description = "Managed policies on the Enhanced Monitoring role. The AWS service-role policy for this purpose, kept rather than narrowed (rules.md A-5)"

  validation {
    condition     = alltrue([for arn in var.rds_monitoring_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "rds_monitoring_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "rds_auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "Whether RDS applies minor engine upgrades automatically, as the _monolithic template had it"
}
variable "rds_apply_immediately" {
  type        = bool
  default     = true
  description = "Whether Aurora modifications are applied immediately rather than in the maintenance window, as the _monolithic template had it on the instances"
}
variable "rds_skip_final_snapshot" {
  type        = bool
  default     = true
  description = "Whether terraform destroy skips the final snapshot. True: with it false the destroy fails at the cluster with InvalidParameterCombination after everything else is already gone. The _monolithic template never had to decide, because the CloudFormation default is the other way round"
}
variable "rds_secret_recovery_window_in_days" {
  type        = number
  default     = 0
  description = "Days Secrets Manager keeps the deleted credential secret. Zero so a destroy and re-apply works: the name is held against a new secret for the whole window otherwise, and the next apply fails with \"already scheduled for deletion\""

  validation {
    condition     = var.rds_secret_recovery_window_in_days == 0 || (var.rds_secret_recovery_window_in_days >= 7 && var.rds_secret_recovery_window_in_days <= 30)
    error_message = "rds_secret_recovery_window_in_days must be 0, or between 7 and 30."
  }
}
# --- ECS cluster and capacity ---
variable "container_instance_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "Public SSM parameter resolved to the ECS-optimized AMI. Read in the root for the same reason as the workbench AMI (rules.md D-6)"

  validation {
    condition     = can(regex("^/", var.container_instance_ami_ssm_parameter_name))
    error_message = "container_instance_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "container_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the ECS container instances, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.container_instance_type))
    error_message = "container_instance_type must be a valid EC2 instance type."
  }
}
variable "container_instance_root_device_name" {
  type        = string
  default     = "/dev/xvda"
  description = "Root device of the ECS-optimized AMI. A wrong value adds a second volume rather than resizing the root one, which is silent"

  validation {
    condition     = can(regex("^/dev/", var.container_instance_root_device_name))
    error_message = "container_instance_root_device_name must be a device path starting with /dev/."
  }
}
variable "container_instance_root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB per container instance. The _monolithic template declared no block device mapping, so each instance took the AMI default - the same 30"

  validation {
    condition     = var.container_instance_root_volume_size >= 30
    error_message = "container_instance_root_volume_size must be at least 30 GiB, the size of the ECS-optimized AMI snapshot."
  }
}
variable "container_instance_min_size" {
  type        = number
  default     = 3
  description = "Minimum container instances"

  validation {
    condition     = var.container_instance_min_size >= 0
    error_message = "container_instance_min_size must not be negative."
  }
}
variable "container_instance_max_size" {
  type        = number
  default     = 3
  description = "Maximum container instances. The _monolithic template set min, max and desired all to 3, so managed scaling had nothing to scale - kept, because the EC2 stack asks for three awsvpc tasks and each needs an interface on an instance"

  validation {
    condition     = var.container_instance_max_size >= 1
    error_message = "container_instance_max_size must be at least 1."
  }
}
variable "container_instance_desired_capacity" {
  type        = number
  default     = 3
  description = "Container instances the Auto Scaling group starts with"

  validation {
    condition     = var.container_instance_desired_capacity >= 0
    error_message = "container_instance_desired_capacity must not be negative."
  }
}
variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = "Container Insights setting. enhanced as the _monolithic template had it, and the per-task and per-container dashboard widgets depend on it: the ECS/ContainerInsights namespace they query is only populated in that mode, so on \"enabled\" those two widgets render as empty charts"

  validation {
    condition     = contains(["enabled", "enhanced", "disabled"], var.container_insights)
    error_message = "container_insights must be enabled, enhanced or disabled."
  }
}
variable "encrypt_ecs_managed_storage" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the ECS cluster encrypts Fargate ephemeral storage with this project's KMS key. False,
    which is a deliberate divergence: the _monolithic template passed the key and did not make it
    usable.

    A customer managed key used for ECS managed storage needs key policy statements granting
    fargate.amazonaws.com kms:GenerateDataKeyWithoutPlaintext and kms:CreateGrant, conditioned on
    the cluster account and name. The template created the key with no key policy, so it kept the
    default - account root plus IAM delegation - and the ECS service principal is not an IAM
    principal in the account, so nothing grants it.

    The red stack is the Fargate one, so that is where it lands: the service is created and every
    task it starts stops during provisioning with a KMS error in its stopped reason. Nothing fails
    at apply.

    Turning this on means adding those statements to modules/kms_key first. The cluster name is a
    local in main.tf, so the condition can be built from the same value the cluster is created
    with (rules.md B-5).
  DESC
}
variable "ecs_config_options" {
  type        = map(string)
  default     = {}
  description = "Extra lines appended to /etc/ecs/ecs.config on each container instance. ECS_CLUSTER is always written from the cluster name and must not appear here"

  validation {
    condition     = alltrue([for key in keys(var.ecs_config_options) : can(regex("^ECS_[A-Z0-9_]+$", key))])
    error_message = "ecs_config_options keys must be ECS agent variables (ECS_ prefixed, uppercase)."
  }
}
variable "capacity_distribution_strategy" {
  type        = string
  default     = "balanced-only"
  description = "How the Auto Scaling group spreads instances across zones, as the _monolithic template had it"

  validation {
    condition     = contains(["balanced-only", "balanced-best-effort"], var.capacity_distribution_strategy)
    error_message = "capacity_distribution_strategy must be balanced-only or balanced-best-effort."
  }
}
variable "managed_scaling_status" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS manages the Auto Scaling group's size, as the _monolithic template had it"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_scaling_status)
    error_message = "managed_scaling_status must be ENABLED or DISABLED."
  }
}
variable "managed_scaling_target_capacity" {
  type        = number
  default     = 100
  description = "Target utilization percentage ECS scales the group towards, as the _monolithic template had it"

  validation {
    condition     = var.managed_scaling_target_capacity >= 1 && var.managed_scaling_target_capacity <= 100
    error_message = "managed_scaling_target_capacity must be between 1 and 100."
  }
}
variable "managed_scaling_minimum_step_size" {
  type        = number
  default     = 1
  description = "Smallest number of instances ECS adds or removes in one action"

  validation {
    condition     = var.managed_scaling_minimum_step_size >= 1 && var.managed_scaling_minimum_step_size <= 10000
    error_message = "managed_scaling_minimum_step_size must be between 1 and 10000."
  }
}
variable "managed_scaling_maximum_step_size" {
  type        = number
  default     = 10000
  description = "Largest number of instances ECS adds or removes in one action, as the _monolithic template had it - the ceiling, bounded by max_size anyway"

  validation {
    condition     = var.managed_scaling_maximum_step_size >= 1 && var.managed_scaling_maximum_step_size <= 10000
    error_message = "managed_scaling_maximum_step_size must be between 1 and 10000."
  }
}
variable "managed_scaling_instance_warmup_period" {
  type        = number
  default     = 30
  description = "Seconds before a new instance counts towards the scaling metric, as the _monolithic template had it"

  validation {
    condition     = var.managed_scaling_instance_warmup_period >= 0 && var.managed_scaling_instance_warmup_period <= 10000
    error_message = "managed_scaling_instance_warmup_period must be between 0 and 10000 seconds."
  }
}
variable "additional_capacity_providers" {
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
  description = "Capacity providers attached alongside the EC2 one, as the _monolithic template had them. Needed because the red stack runs on Fargate"

  validation {
    condition     = alltrue([for provider in var.additional_capacity_providers : contains(["FARGATE", "FARGATE_SPOT"], provider)])
    error_message = "additional_capacity_providers may only contain FARGATE and FARGATE_SPOT."
  }
}
variable "container_instance_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "Managed policies on the container instance role, both kept from the _monolithic template: AWS service-role policies already scoped to what an ECS agent and the SSM agent do (rules.md A-5)"

  validation {
    condition     = length(var.container_instance_iam_policy_arns) > 0
    error_message = "container_instance_iam_policy_arns must contain at least one policy: without the container service policy an instance never joins the cluster."
  }
  validation {
    condition     = alltrue([for arn in var.container_instance_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "container_instance_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
# --- Task roles ---
variable "task_execution_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  description = "Managed policies on the task execution role. Only the AWS service-role policy: the _monolithic template also attached SecretsManagerReadWrite and PowerUserAccess, both replaced by a scoped inline policy (rules.md A-5)"

  validation {
    condition     = length(var.task_execution_policy_arns) > 0
    error_message = "task_execution_policy_arns must contain at least one policy: without the ECR permissions every task stops with CannotPullContainerError."
  }
  validation {
    condition     = alltrue([for arn in var.task_execution_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "task_execution_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "additional_task_policy_arns" {
  type        = list(string)
  default     = []
  description = "Extra managed policies on the task role, on top of the FireLens logs policy. Empty: the application containers make no AWS calls, and PowerUserAccess - what the _monolithic template attached - is replaced rather than extended (rules.md A-5)"

  validation {
    condition     = alltrue([for arn in var.additional_task_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "additional_task_policy_arns must contain valid IAM policy ARNs."
  }
}
# --- Application stacks ---
variable "app_stacks" {
  type = map(object({
    task_cpu                   = string
    launch_type                = string
    listener_rule_priority     = number
    health_check_rule_priority = number
    ecr_encryption_type        = string
  }))
  default = {
    green = {
      task_cpu                   = "1024"
      launch_type                = "EC2"
      listener_rule_priority     = 1
      health_check_rule_priority = 3
      ecr_encryption_type        = "AES256"
    }
    red = {
      task_cpu                   = "512"
      launch_type                = "FARGATE"
      listener_rule_priority     = 2
      health_check_rule_priority = 4
      ecr_encryption_type        = "KMS"
    }
  }
  description = <<-DESC
    The two application stacks, and the complete list of what they differ by.

    Roughly a third of the _monolithic template was the same fourteen resources written twice under
    a green_ and a red_ prefix - repository, task definition, service, two target groups, two
    listener rules, CodeDeploy application and deployment group, pipeline, two buckets, EventBridge
    rule and target. Finding out how the two actually differed meant diffing two resource bodies.
    This is that diff, and it is five fields.

    Everything else about a stack is either shared (container port, memory, image tag, desired
    count, health check path, deployment configuration, pipeline shape) or derived from the map key
    (every name, the container name, the path patterns, the log group and the log stream prefix).

    The keys are literals in configuration, so they are known at plan time and usable as for_each
    keys for both this and the ECR repository module (rules.md B-8). Adding a third stack means
    adding an entry here and nothing else - with two priorities nothing else uses.
  DESC

  validation {
    condition     = length(var.app_stacks) > 0
    error_message = "app_stacks must contain at least one stack."
  }
  validation {
    condition     = alltrue([for key in keys(var.app_stacks) : can(regex("^[a-z][a-z0-9]{0,11}$", key))])
    error_message = "app_stacks keys must start with a lowercase letter and contain only lowercase letters and digits, 12 characters or fewer: each key becomes part of a target group name, which elbv2 limits to 32 characters."
  }
  validation {
    condition     = alltrue([for stack in values(var.app_stacks) : contains(["256", "512", "1024", "2048", "4096", "8192", "16384"], stack.task_cpu)])
    error_message = "app_stacks task_cpu values must be one of the Fargate CPU values: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
  validation {
    condition     = alltrue([for stack in values(var.app_stacks) : contains(["EC2", "FARGATE"], stack.launch_type)])
    error_message = "app_stacks launch_type values must be EC2 or FARGATE."
  }
  validation {
    condition     = alltrue([for stack in values(var.app_stacks) : contains(["AES256", "KMS"], stack.ecr_encryption_type)])
    error_message = "app_stacks ecr_encryption_type values must be AES256 or KMS."
  }
  validation {
    # Every listener rule priority across every stack, plus the error rule, has to be distinct:
    # elbv2 rejects a duplicate priority on one listener, and the message names only the rule that
    # arrived second - which is whichever one Terraform happened to create later, so the error
    # moves between applies.
    condition = length(distinct(concat(
      [for stack in values(var.app_stacks) : stack.listener_rule_priority],
      [for stack in values(var.app_stacks) : stack.health_check_rule_priority],
      [var.alb_error_rule_priority],
    ))) == 2 * length(var.app_stacks) + 1
    error_message = "every listener_rule_priority and health_check_rule_priority in app_stacks must be distinct from each other and from alb_error_rule_priority: elbv2 allows one rule per priority on a listener."
  }
}
variable "container_port" {
  type        = number
  default     = 8080
  description = "Port both applications listen on. Shared, which the duplicated _monolithic code made look like it might differ per stack. Also the port the ECS service security group opens and the port both target groups forward to"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "task_memory" {
  type        = string
  default     = "1024"
  description = "Task-level memory in MiB, the same for both stacks in the _monolithic template"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB as a string."
  }
}
variable "cpu_architecture" {
  type        = string
  default     = "X86_64"
  description = "Runtime platform architecture. Has to match the images the build step produces - an arm64 image on an X86_64 platform fails at task start with an exec format error, which reads like a corrupt binary"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}
variable "image_tag" {
  type        = string
  default     = "v1.0.0"
  description = "Tag each task definition starts on. The build step pushes this and deploy_image_tag, and the pipeline deploys the other one - so the blue/green switch is visible as a version change in the application response"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,128}$", var.image_tag))
    error_message = "image_tag must be 1-128 characters of letters, digits, underscores, dots and hyphens."
  }
}
variable "service_desired_count" {
  type        = number
  default     = 3
  description = "Tasks each service runs, as the _monolithic template had it for both"

  validation {
    condition     = var.service_desired_count >= 1
    error_message = "service_desired_count must be at least 1: a blue/green deployment has nothing to replace at zero."
  }
}
variable "availability_zone_rebalancing" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS redistributes tasks across zones as capacity changes, as the _monolithic template had it for both services. Supported for Fargate and for EC2 capacity providers; the EC2 case only rebalances across instances that already exist"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.availability_zone_rebalancing)
    error_message = "availability_zone_rebalancing must be ENABLED or DISABLED."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the target group health check, the container health check and the health check listener rule all use. One value for three places (rules.md B-5)"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/'."
  }
}
variable "target_group_health_check_interval" {
  type        = number
  default     = 30
  description = "Seconds between application target group health checks"

  validation {
    condition     = var.target_group_health_check_interval >= 5 && var.target_group_health_check_interval <= 300
    error_message = "target_group_health_check_interval must be between 5 and 300 seconds."
  }
}
variable "target_group_health_check_timeout" {
  type        = number
  default     = 5
  description = "Seconds an application target group health check may take"

  validation {
    condition     = var.target_group_health_check_timeout >= 2 && var.target_group_health_check_timeout <= 120
    error_message = "target_group_health_check_timeout must be between 2 and 120 seconds."
  }
}
variable "target_group_health_check_healthy_threshold" {
  type        = number
  default     = 3
  description = "Consecutive successes before an application target is in service"

  validation {
    condition     = var.target_group_health_check_healthy_threshold >= 2 && var.target_group_health_check_healthy_threshold <= 10
    error_message = "target_group_health_check_healthy_threshold must be between 2 and 10."
  }
}
variable "target_group_health_check_unhealthy_threshold" {
  type        = number
  default     = 3
  description = "Consecutive failures before an application target is out of service"

  validation {
    condition     = var.target_group_health_check_unhealthy_threshold >= 2 && var.target_group_health_check_unhealthy_threshold <= 10
    error_message = "target_group_health_check_unhealthy_threshold must be between 2 and 10."
  }
}
variable "target_group_health_check_matcher" {
  type        = string
  default     = "200"
  description = "HTTP status codes counted as healthy on an application target group"

  validation {
    condition     = can(regex("^[0-9]{3}(-[0-9]{3})?(,[0-9]{3}(-[0-9]{3})?)*$", var.target_group_health_check_matcher))
    error_message = "target_group_health_check_matcher must be a status code, a range, or a comma separated list of either."
  }
}
variable "container_health_check_interval" {
  type        = number
  default     = 30
  description = "Seconds between the container's own health check command, as the _monolithic template had it"

  validation {
    condition     = var.container_health_check_interval >= 5 && var.container_health_check_interval <= 300
    error_message = "container_health_check_interval must be between 5 and 300 seconds."
  }
}
variable "container_health_check_timeout" {
  type        = number
  default     = 5
  description = "Seconds the container health check command may take, as the _monolithic template had it"

  validation {
    condition     = var.container_health_check_timeout >= 2 && var.container_health_check_timeout <= 60
    error_message = "container_health_check_timeout must be between 2 and 60 seconds."
  }
}
variable "container_health_check_retries" {
  type        = number
  default     = 5
  description = "Consecutive container health check failures before ECS replaces the task, as the _monolithic template had it"

  validation {
    condition     = var.container_health_check_retries >= 1 && var.container_health_check_retries <= 10
    error_message = "container_health_check_retries must be between 1 and 10."
  }
}
variable "container_health_check_start_period" {
  type        = number
  default     = 5
  description = "Grace seconds before a failed container health check counts, as the _monolithic template had it. Short - a container still starting is replaced rather than waited for, and the replacement starts the same clock"

  validation {
    condition     = var.container_health_check_start_period >= 0 && var.container_health_check_start_period <= 300
    error_message = "container_health_check_start_period must be between 0 and 300 seconds."
  }
}
variable "target_group_deregistration_delay" {
  type        = number
  default     = 30
  description = "Seconds each application target group waits before completing a deregistration, as the _monolithic template had it. Paid on every blue/green switch"

  validation {
    condition     = var.target_group_deregistration_delay >= 0 && var.target_group_deregistration_delay <= 3600
    error_message = "target_group_deregistration_delay must be between 0 and 3600 seconds."
  }
}
variable "app_log_retention_in_days" {
  type        = number
  default     = 7
  description = "Retention on each stack's application log group. The _monolithic template created no groups, relying on the FireLens plugin to create them at runtime - so they had no retention and survived destroy"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.app_log_retention_in_days)
    error_message = "app_log_retention_in_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "log_exclude_pattern" {
  type        = string
  default     = "health"
  description = "Pattern FireLens drops matching lines on, as the _monolithic template had it. Removes the container health check request, which fires on every task every interval and would otherwise be most of the log - and would also break the dashboard widgets, which count GET and POST per minute"

  validation {
    condition     = length(var.log_exclude_pattern) > 0
    error_message = "log_exclude_pattern must not be empty: an empty pattern matches every line, so the log group stays empty with nothing reporting why."
  }
}
variable "fluent_bit_image" {
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
  description = "FireLens sidecar image, as the _monolithic template had it. The stable tag is a moving target - pin a version for anything reproducible"

  validation {
    condition     = length(var.fluent_bit_image) > 0
    error_message = "fluent_bit_image must not be empty."
  }
}
variable "fluent_bit_log_group_name" {
  type        = string
  default     = "firelens"
  description = "Log group the FireLens sidecars' own awslogs driver writes to, as the _monolithic template had it. Shared by both stacks, so it is created by the ECS agent rather than by Terraform - two stack modules declaring one group would fail the second apply"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.fluent_bit_log_group_name))
    error_message = "fluent_bit_log_group_name must be 1-512 characters of letters, digits and the set _./#- that CloudWatch Logs accepts."
  }
}
# --- ECR ---
variable "ecr_image_tag_mutability" {
  type        = string
  default     = "IMMUTABLE"
  description = "Whether a tag can be moved to another image, as the _monolithic template had it. IMMUTABLE is why the build step checks for a tag before pushing: an SSM association re-runs when its parameters change, and a second push of an existing tag is rejected"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE", "MUTABLE_WITH_EXCLUSION", "IMMUTABLE_WITH_EXCLUSION"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability must be MUTABLE, IMMUTABLE, MUTABLE_WITH_EXCLUSION or IMMUTABLE_WITH_EXCLUSION."
  }
}
variable "ecr_scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR scans an image on push, as the _monolithic template had it for both repositories"
}
variable "ecr_force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes each repository with its images. True: the build step pushes two tags into each, and ECR refuses to delete a non-empty repository - which the _monolithic template would have hit with RepositoryNotEmptyException"
}
# --- Delivery ---
variable "deployment_config_name" {
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
  description = "CodeDeploy deployment configuration for both stacks, as the _monolithic template had it. A canary or linear configuration shifts traffic in stages instead, which makes the switch easier to watch"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.deployment_config_name))
    error_message = "deployment_config_name must be 1-100 characters from the set CodeDeploy accepts."
  }
}
variable "deployment_ready_action_on_timeout" {
  type        = string
  default     = "CONTINUE_DEPLOYMENT"
  description = "What CodeDeploy does once the replacement task set is ready, as the _monolithic template had it - shift immediately, no manual approval"

  validation {
    condition     = contains(["CONTINUE_DEPLOYMENT", "STOP_DEPLOYMENT"], var.deployment_ready_action_on_timeout)
    error_message = "deployment_ready_action_on_timeout must be CONTINUE_DEPLOYMENT or STOP_DEPLOYMENT."
  }
}
variable "termination_wait_time_in_minutes" {
  type        = number
  default     = 0
  description = "Minutes the original task set is kept after traffic shifts, as the _monolithic template had it. Zero removes the window in which a rollback is instant"

  validation {
    condition     = var.termination_wait_time_in_minutes >= 0 && var.termination_wait_time_in_minutes <= 2880
    error_message = "termination_wait_time_in_minutes must be between 0 and 2880."
  }
}
variable "auto_rollback_events" {
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
  description = "Events that trigger an automatic rollback, as the _monolithic template had them"

  validation {
    condition     = length(var.auto_rollback_events) > 0
    error_message = "auto_rollback_events must contain at least one event."
  }
  validation {
    condition     = alltrue([for event in var.auto_rollback_events : contains(["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"], event)])
    error_message = "auto_rollback_events must contain only DEPLOYMENT_FAILURE, DEPLOYMENT_STOP_ON_ALARM or DEPLOYMENT_STOP_ON_REQUEST."
  }
}
variable "code_deploy_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"]
  description = "Managed policies on each stack's CodeDeploy role. The AWS service-role policy for ECS blue/green, kept as the _monolithic template attached it (rules.md A-5)"

  validation {
    condition     = length(var.code_deploy_policy_arns) > 0
    error_message = "code_deploy_policy_arns must contain at least one policy: CodeDeploy validates the role at CreateDeploymentGroup."
  }
  validation {
    condition     = alltrue([for arn in var.code_deploy_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "code_deploy_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "pipeline_execution_mode" {
  type        = string
  default     = "QUEUED"
  description = "How CodePipeline handles a second execution while one is running, as the _monolithic template had it. SUPERSEDED would cancel a blue/green switch in flight"

  validation {
    condition     = contains(["QUEUED", "SUPERSEDED", "PARALLEL"], var.pipeline_execution_mode)
    error_message = "pipeline_execution_mode must be QUEUED, SUPERSEDED or PARALLEL."
  }
}
variable "source_object_key" {
  type        = string
  default     = "artifact.zip"
  description = "Object key that starts a pipeline run. Read in four places - the pipeline source action, the EventBridge rule pattern, the CloudTrail data event selector and the helper script that uploads it - all from here (rules.md B-5)"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.source_object_key))
    error_message = "source_object_key must be an object key without a leading slash."
  }
}
variable "task_definition_template_path" {
  type        = string
  default     = "taskdef.json"
  description = "Name of the task definition template inside the artefact. The pipeline reads it and the artefact-building association writes it"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.task_definition_template_path))
    error_message = "task_definition_template_path must be a path inside the artefact without a leading slash."
  }
}
variable "app_spec_template_path" {
  type        = string
  default     = "appspec.yaml"
  description = "Name of the CodeDeploy appspec inside the artefact"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.app_spec_template_path))
    error_message = "app_spec_template_path must be a path inside the artefact without a leading slash."
  }
}
variable "image_detail_file_name" {
  type        = string
  default     = "imageDetail.json"
  description = "Name of the image detail file inside the artefact. CodePipeline reads the image URI from it and substitutes it for the placeholder in the task definition template"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.image_detail_file_name))
    error_message = "image_detail_file_name must be a path inside the artefact without a leading slash."
  }
}
variable "image_placeholder_name" {
  type        = string
  default     = "IMAGE1_NAME"
  description = "Placeholder CodePipeline substitutes in the task definition template. The template file carries it wrapped in angle brackets; this is the name without them"

  validation {
    condition     = can(regex("^[A-Z0-9_]+$", var.image_placeholder_name))
    error_message = "image_placeholder_name must be uppercase letters, digits and underscores."
  }
}
variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the source, artifact store and CloudTrail buckets before deleting them. True: all three fill up on their own, and S3 refuses to delete a non-empty bucket - the _monolithic template set none of them, so its destroy stopped with BucketNotEmpty five times over. Versioning is on for the source buckets, so this deletes every version and is irreversible"
}
# --- CloudTrail ---
variable "cloudtrail_include_management_events" {
  type        = bool
  default     = false
  description = "Whether the trail also records management events. False: the trail exists only so S3 write events reach EventBridge, and the _monolithic template left the default on - recording every API call in the region to notice two PutObject calls"
}
# --- Observability ---
variable "metric_period" {
  type        = number
  default     = 60
  description = "Period in seconds for every dashboard widget, as the _monolithic template had it"

  validation {
    condition     = contains([1, 5, 10, 30], var.metric_period) || var.metric_period % 60 == 0
    error_message = "metric_period must be 1, 5, 10, 30, or a multiple of 60."
  }
}
variable "high_utilization_annotation" {
  type        = number
  default     = 80
  description = "Percentage the service CPU widget draws its annotation line at, as the _monolithic template had it"

  validation {
    condition     = var.high_utilization_annotation > 0 && var.high_utilization_annotation <= 100
    error_message = "high_utilization_annotation must be between 1 and 100."
  }
}
variable "alarm_period" {
  type        = number
  default     = 300
  description = "Evaluation period in seconds for both alarms, as the _monolithic template had it - and what its descriptions mean by \"within 5 minutes\""

  validation {
    condition     = contains([10, 30], var.alarm_period) || var.alarm_period % 60 == 0
    error_message = "alarm_period must be 10, 30, or a multiple of 60 seconds."
  }
}
variable "alarm_evaluation_periods" {
  type        = number
  default     = 1
  description = "Periods that must breach before an alarm fires, as the _monolithic template had it"

  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "alarm_evaluation_periods must be at least 1."
  }
}
variable "alarm_4xx_threshold" {
  type        = number
  default     = 10
  description = "4xx responses in one period that trigger the alarm, as the _monolithic template had it. Reachable by hand: any path no listener rule matches returns the default 404"

  validation {
    condition     = var.alarm_4xx_threshold > 0
    error_message = "alarm_4xx_threshold must be greater than zero."
  }
}
variable "alarm_5xx_threshold" {
  type        = number
  default     = 5
  description = "5xx responses in one period that trigger the alarm, as the _monolithic template had it. Reachable through the error path on the listener, which is what that rule is for"

  validation {
    condition     = var.alarm_5xx_threshold > 0
    error_message = "alarm_5xx_threshold must be greater than zero."
  }
}
# --- Bootstrap steps on the workbench ---
variable "source_repository_url" {
  type        = string
  default     = "https://github.com/iamhansko/aws-cloudformation-templates.git"
  description = "Repository the application binaries and the SQL schema are cloned from, as the _monolithic template had it. The binaries are 8 MB each, so they are fetched on the instance rather than uploaded through Terraform"

  validation {
    condition     = can(regex("^https://", var.source_repository_url))
    error_message = "source_repository_url must be an https clone URL: the workbench has no SSH key for a git host and an ssh:// clone would hang on the host key prompt."
  }
}
variable "source_repository_path" {
  type        = string
  default     = "025_cross_vpc_ecs_bluegreen/src"
  description = "Path inside the clone holding the four binaries and the SQL file. The _monolithic template cloned from 024_cross_vpc_ecs_bluegreen/src; the upstream repository has since renumbered this project to 025 and reused 024 for another one, so the old path no longer exists and the image build step fails at the copy. If the upstream renumbers again, list its top-level directories and update this. The same four binaries are also in this project's own src/ directory for reference; nothing in the configuration reads them, because an 8 MB file is not something to put through a Terraform provider"

  validation {
    condition     = can(regex("^[^/][^ ]*[^/]$", var.source_repository_path))
    error_message = "source_repository_path must be a relative path inside the clone, with no leading or trailing slash."
  }
}
variable "image_versions" {
  type        = list(string)
  default     = ["1.0.0", "1.0.1"]
  description = "Application versions built and pushed into each repository. Two, as the _monolithic template had it: the task definition starts on the first and the pipeline deploys the second, which is what makes the blue/green switch visible in the response"

  validation {
    condition     = length(var.image_versions) >= 1
    error_message = "image_versions must contain at least one version."
  }
  validation {
    condition     = alltrue([for version in var.image_versions : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", version))])
    error_message = "image_versions must contain three-part versions (e.g. 1.0.0): each one names a binary in the source repository as <stack>_<version>."
  }
}
variable "deploy_image_version" {
  type        = string
  default     = "1.0.1"
  description = "Version the pipeline deploys, written into imageDetail.json by the artefact-building association. Has to be one of image_versions, or the deployment pulls a tag that was never pushed and the replacement task set never becomes healthy"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.deploy_image_version))
    error_message = "deploy_image_version must be a three-part version (e.g. 1.0.1)."
  }
  validation {
    # Cross-variable condition (rules.md B-1). The failure otherwise is late and indirect: the
    # pipeline succeeds at the source stage, CodeDeploy starts a deployment, the replacement tasks
    # fail to pull and the deployment rolls back after its timeout.
    condition     = contains(var.image_versions, var.deploy_image_version)
    error_message = "deploy_image_version must be one of image_versions: the build step only pushes those tags, and a deployment naming any other one fails at the image pull rather than at apply."
  }
}
variable "image_base_image" {
  type        = string
  default     = "ubuntu:latest"
  description = "Base image of the Dockerfile the build step writes, as the _monolithic template had it"

  validation {
    condition     = length(var.image_base_image) > 0
    error_message = "image_base_image must not be empty."
  }
}
variable "container_user_uid" {
  type        = number
  default     = 2000
  description = "UID of the unprivileged user the application container runs as, as the _monolithic template had it"

  validation {
    condition     = var.container_user_uid >= 1000 && var.container_user_uid <= 65533
    error_message = "container_user_uid must be between 1000 and 65533: below 1000 collides with the base image's system accounts."
  }
}
variable "sql_file_name" {
  type        = string
  default     = "day1_table_v1.sql"
  description = "SQL file in the source repository that creates the schema. The _monolithic template wrote the same statements inline in its association as well, so the schema existed in two places; here the cloned file is the only copy and the step fails loudly if it is missing"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.sql_file_name))
    error_message = "sql_file_name must be a plain file name with no path separators."
  }
}
variable "ssm_wait_timeout_seconds" {
  type        = number
  default     = 900
  description = "Seconds Terraform waits for each SSM association to report success, as the _monolithic template had it. Has to exceed what the step itself can take - the marker wait plus the work - or the association is reported Failed with no explanation while the command is still running"

  validation {
    condition     = var.ssm_wait_timeout_seconds >= 60 && var.ssm_wait_timeout_seconds <= 3600
    error_message = "ssm_wait_timeout_seconds must be between 60 and 3600 seconds."
  }
}
variable "marker_wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds between checks of the previous step's marker file, as the _monolithic template had it"

  validation {
    condition     = var.marker_wait_interval_seconds >= 1 && var.marker_wait_interval_seconds <= 60
    error_message = "marker_wait_interval_seconds must be between 1 and 60 seconds."
  }
}
variable "marker_wait_attempts" {
  type        = number
  default     = 60
  description = "Checks of the previous marker before a step gives up with a message. The _monolithic template looped forever, so a step whose predecessor never finished was reported as a plain association timeout with nothing saying which step was stuck"

  validation {
    condition     = var.marker_wait_attempts >= 1
    error_message = "marker_wait_attempts must be at least 1."
  }
  validation {
    condition     = var.marker_wait_attempts * var.marker_wait_interval_seconds < var.ssm_wait_timeout_seconds
    error_message = "marker_wait_attempts times marker_wait_interval_seconds must be less than ssm_wait_timeout_seconds, so a stuck step fails with its own message rather than being cut off by the association timeout - which reports only 'unexpected state Failed'."
  }
}
variable "database_wait_attempts" {
  type        = number
  default     = 60
  description = "Connection attempts the schema step makes before giving up. Replaces the _monolithic template's \"sleep 300\", which was a guess in both directions: too short and the step failed, too long and every apply paid five minutes it did not need"

  validation {
    condition     = var.database_wait_attempts >= 1
    error_message = "database_wait_attempts must be at least 1."
  }
}
variable "database_wait_interval_seconds" {
  type        = number
  default     = 15
  description = "Seconds between Aurora connection attempts in the schema step"

  validation {
    condition     = var.database_wait_interval_seconds >= 1 && var.database_wait_interval_seconds <= 60
    error_message = "database_wait_interval_seconds must be between 1 and 60 seconds."
  }
}
variable "load_balancer_interface_wait_attempts" {
  type        = number
  default     = 30
  description = "Attempts the workbench makes to find the app network load balancer's network interfaces before giving up. They appear a little after the load balancer itself, and the _monolithic template read them once with no retry - an empty result there left the hub target group with no targets at all, so the public entry point returned a connection reset with nothing logged"

  validation {
    condition     = var.load_balancer_interface_wait_attempts >= 1
    error_message = "load_balancer_interface_wait_attempts must be at least 1."
  }
}
variable "load_balancer_interface_wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds between attempts to find the app network load balancer's network interfaces"

  validation {
    condition     = var.load_balancer_interface_wait_interval_seconds >= 1 && var.load_balancer_interface_wait_interval_seconds <= 60
    error_message = "load_balancer_interface_wait_interval_seconds must be between 1 and 60 seconds."
  }
}
