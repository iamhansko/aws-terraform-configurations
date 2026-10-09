variable "cluster_identifier" {
  type        = string
  description = "Identifier of the Aurora cluster. Region-wide within the account, so a second copy of this project collides here with DBClusterAlreadyExistsFault"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.cluster_identifier)) && !can(regex("--|-$", var.cluster_identifier))
    error_message = "cluster_identifier must start with a letter, contain only lowercase letters, digits and hyphens, be 63 characters or fewer, and must not contain two consecutive hyphens or end with one."
  }
}
variable "engine" {
  type        = string
  description = "Aurora engine. The _monolithic template used aurora-mysql, which is also what makes backtrack_window and the audit log export valid"

  validation {
    condition     = contains(["aurora-mysql", "aurora-postgresql"], var.engine)
    error_message = "engine must be aurora-mysql or aurora-postgresql."
  }
}
variable "engine_version" {
  type        = string
  description = "Engine version of the cluster"

  validation {
    condition     = length(var.engine_version) > 0
    error_message = "engine_version must not be empty: an unpinned Aurora version means the cluster that gets built depends on the day it was applied."
  }
}
variable "database_name" {
  type        = string
  description = "Initial database created in the cluster. The schema the SSM association loads is created inside it, and the application connects to it by name"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,63}$", var.database_name))
    error_message = "database_name must start with a letter and contain only letters, digits and underscores, 64 characters or fewer."
  }
}
variable "port" {
  type        = number
  description = "Port the cluster listens on, also the port opened in the security group and the port written into the credential secret. The _monolithic template moved it off 3306 to 10101 and then wrote 10101 again as a literal inside the secret"

  validation {
    condition     = var.port > 0 && var.port <= 65535
    error_message = "port must be a valid TCP port."
  }
}
variable "master_username" {
  type        = string
  description = "Master user of the cluster"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,15}$", var.master_username))
    error_message = "master_username must start with a letter, contain only letters, digits and underscores, and be 16 characters or fewer for MySQL."
  }
}
variable "master_password" {
  type        = string
  sensitive   = true
  description = "Master password. Written into the credential secret below and never into an output or the README on the workbench - the root exposes the secretsmanager get-secret-value command instead (rules.md H-2)"

  validation {
    condition     = length(var.master_password) >= 8 && length(var.master_password) <= 41
    error_message = "master_password must be between 8 and 41 characters, the range RDS accepts for a MySQL master password."
  }
  validation {
    condition     = !can(regex("[/@\"' ]", var.master_password))
    error_message = "master_password must not contain a slash, an at sign, a quote, an apostrophe or a space: RDS rejects those outright, and the schema-loading association passes this value to a mysql client on a command line where a quote would break the quoting."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Internal subnets forming the DB subnet group. These have no route to the internet, which is the point of the tier"

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets in different availability zones: RDS rejects a single-zone subnet group at CreateDBSubnetGroup."
  }
  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "subnet_group_name" {
  type        = string
  description = "Name of the DB subnet group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._-]{1,255}$", var.subnet_group_name))
    error_message = "subnet_group_name must be 1-255 characters of letters, digits, spaces, dots, underscores and hyphens."
  }
}
variable "subnet_group_description" {
  type        = string
  description = "Description of the DB subnet group"

  validation {
    condition     = length(var.subnet_group_description) > 0
    error_message = "subnet_group_description must not be empty."
  }
}
variable "kms_key_arn" {
  type        = string
  description = "Customer managed key used for storage encryption, for the Performance Insights store and for the credential secret. An ARN rather than a key ID because the RDS and Secrets Manager APIs return ARNs, and a configured ID then differs from what is read back on every plan"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (e.g. arn:aws:kms:ap-northeast-2:123456789012:key/...)."
  }
}
variable "instance_class" {
  type        = string
  description = "Instance class of each cluster instance"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be an RDS instance class (e.g. db.t4g.medium)."
  }
}
variable "instance_identifier_prefix" {
  type        = string
  description = "Prefix for each cluster instance identifier; the zone suffix is appended"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,50}$", var.instance_identifier_prefix))
    error_message = "instance_identifier_prefix must start with a letter and contain only lowercase letters, digits and hyphens."
  }
}
variable "instance_availability_zones" {
  type        = map(string)
  description = "Availability zone of each cluster instance, keyed by zone suffix. Keys are configuration values so they are known at plan time and safe as for_each keys (rules.md B-8), and the key is also what distinguishes the two instance identifiers"

  validation {
    condition     = length(var.instance_availability_zones) >= 1
    error_message = "instance_availability_zones must contain at least one instance: an Aurora cluster with no instances has an endpoint that refuses every connection, which is exactly the failure the _monolithic template produced."
  }
  validation {
    condition     = alltrue([for zone in values(var.instance_availability_zones) : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9][a-z]$", zone))])
    error_message = "instance_availability_zones values must be full availability zone names (e.g. ap-northeast-2a)."
  }
}
variable "availability_zones" {
  type        = list(string)
  description = "Zones the cluster may place instances in. RDS treats this as a hint and returns three whatever is asked for, which is why the cluster ignores changes to it - see the lifecycle block in main.tf"

  validation {
    condition     = alltrue([for zone in var.availability_zones : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9][a-z]$", zone))])
    error_message = "availability_zones must contain full availability zone names (e.g. ap-northeast-2a)."
  }
}
variable "backup_retention_period" {
  type        = number
  description = "Days of automated backups retained"

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}
variable "backtrack_window" {
  type        = number
  description = "Seconds of backtrack window. Aurora MySQL only, and incompatible with a cluster that has Backtrack unsupported features in use - zero disables it"

  validation {
    condition     = var.backtrack_window >= 0 && var.backtrack_window <= 259200
    error_message = "backtrack_window must be between 0 and 259200 seconds (72 hours)."
  }
}
variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "Log types exported to CloudWatch Logs. The _monolithic template exported audit, error, general and instance"

  validation {
    condition     = alltrue([for log in var.enabled_cloudwatch_logs_exports : contains(["audit", "error", "general", "instance", "slowquery", "iam-db-auth-error", "postgresql"], log)])
    error_message = "enabled_cloudwatch_logs_exports must contain only log types RDS accepts: Aurora MySQL takes audit, error, general, instance, slowquery and iam-db-auth-error; Aurora PostgreSQL takes instance, postgresql and iam-db-auth-error."
  }
}
variable "database_insights_mode" {
  type        = string
  description = "Database Insights mode. standard pairs with a 7 day Performance Insights retention and advanced requires 465, which the cross-variable validation on performance_insights_retention_period enforces"

  validation {
    condition     = contains(["standard", "advanced"], var.database_insights_mode)
    error_message = "database_insights_mode must be standard or advanced."
  }
}
variable "performance_insights_retention_period" {
  type        = number
  description = "Days of Performance Insights data retained"

  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "performance_insights_retention_period must be 7, 731, or a multiple of 31 up to 713."
  }
  validation {
    # Cross-variable condition (rules.md B-1): the constraint is about the pair. RDS rejects the
    # mismatch with a message about the retention period, so the mode - which is what was actually
    # chosen - is not mentioned anywhere in it.
    condition     = var.database_insights_mode == "advanced" ? var.performance_insights_retention_period == 465 : true
    error_message = "performance_insights_retention_period must be 465 when database_insights_mode is advanced. Set it to 7 for standard mode, or raise the retention if advanced mode is what is wanted."
  }
}
variable "monitoring_interval" {
  type        = number
  description = "Seconds between Enhanced Monitoring samples, set on each cluster instance. Zero disables it"

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be 0, 1, 5, 10, 15, 30 or 60, the only values RDS accepts."
  }
}
variable "monitoring_role_name_prefix" {
  type        = string
  description = "Prefix for the generated Enhanced Monitoring role name. A prefix rather than the template's fixed RdsEnhancedMonitoringRole, which is account-wide and collides with a second copy of this project"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.monitoring_role_name_prefix))
    error_message = "monitoring_role_name_prefix must be 1-38 characters from the set IAM accepts in a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "monitoring_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs on the Enhanced Monitoring role. The AWS service-role policy for this purpose, kept rather than narrowed - see the attachment in main.tf for why (rules.md A-5)"

  validation {
    condition     = alltrue([for arn in var.monitoring_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "monitoring_policy_arns must contain valid IAM policy ARNs."
  }
  validation {
    condition     = var.monitoring_interval == 0 || length(var.monitoring_policy_arns) > 0
    error_message = "monitoring_policy_arns must contain at least one policy when monitoring_interval is non-zero: RDS validates the role at CreateDBInstance and rejects one that cannot write the metrics. Set monitoring_interval to 0 to turn Enhanced Monitoring off instead."
  }
}
variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Whether RDS applies minor engine upgrades automatically during the maintenance window"
}
variable "apply_immediately" {
  type        = bool
  description = "Whether modifications are applied immediately rather than in the next maintenance window. The _monolithic template set this on the instances, which suits a demo and makes a change visible rather than pending"
}
variable "skip_final_snapshot" {
  type        = bool
  description = "Whether terraform destroy skips the final snapshot. True here: with it false the destroy fails at the cluster with InvalidParameterCombination after everything else is already gone, and the _monolithic template never had to decide because the CloudFormation default is the other way round. Never true for a cluster holding anything worth keeping"
}
variable "secret_name" {
  type        = string
  description = "Name of the credential secret. The two task definitions reference it by ARN with a key suffix, so the name only has to be stable, but it is account-wide and collides with a second copy of this project"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]{1,512}$", var.secret_name))
    error_message = "secret_name must be 1-512 characters of letters, digits and the set /_+=.@- that Secrets Manager accepts."
  }
}
variable "secret_description" {
  type        = string
  description = "Description of the credential secret"

  validation {
    condition     = length(var.secret_description) > 0
    error_message = "secret_description must not be empty."
  }
}
variable "secret_recovery_window_in_days" {
  type        = number
  description = "Days Secrets Manager keeps the deleted secret before destroying it. Zero so a destroy and re-apply works - the name is held against a new secret for the whole window otherwise"

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0, or between 7 and 30 - Secrets Manager accepts nothing in between."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on the database port, keyed by a caller-chosen label. A map rather than a list because these IDs are another module's output and unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys land in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "all_traffic_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on every protocol and port, keyed by a caller-chosen label. The root passes the app VPC default security group here, reproducing the _monolithic template"

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
  description = "Name of the database security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  description = "Description of the database security group"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty."
  }
  validation {
    # rules.md F-1. "the cluster's security group" is the natural way to write this one and EC2
    # rejects it at apply, by which point the VPCs, the subnets and the subnet group exist.
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
