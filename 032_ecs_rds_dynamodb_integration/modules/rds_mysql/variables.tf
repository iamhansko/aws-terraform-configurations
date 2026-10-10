variable "identifier" {
  type        = string
  default     = "apdev-rds-instance"
  description = "Identifier of the primary instance, as the _monolithic template had it - including the \"apdev\" spelling, which is reproduced rather than corrected because it is the name the template created and the DynamoDB table next to it says \"appdev\". A fixed identifier, so a second copy in one account fails with DBInstanceAlreadyExists"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.identifier)) && !can(regex("--|-$", var.identifier))
    error_message = "identifier must be 1-63 characters, start with a lowercase letter, contain only lowercase letters, digits and hyphens, and must not contain two consecutive hyphens or end with one."
  }
}
variable "replica_identifier" {
  type        = string
  default     = "apdev-rds-replica"
  description = "Identifier of the read replica, as the template had it"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.replica_identifier)) && !can(regex("--|-$", var.replica_identifier))
    error_message = "replica_identifier must be 1-63 characters, start with a lowercase letter, contain only lowercase letters, digits and hyphens, and must not contain two consecutive hyphens or end with one."
  }
}
variable "create_read_replica" {
  type        = bool
  default     = true
  description = "Whether to create the read replica. True, because the template declared one - see main.tf for why what it declared was not actually a replica. Nothing in this project reads from it, so false is a legitimate way to halve the database cost of the demo"
}
variable "engine" {
  type        = string
  default     = "mysql"
  description = "Database engine. mysql, as the template had it, and this module is MySQL-specific in more than name: the gp3 storage bounds below are MySQL's, and the schema step in the root speaks the MySQL protocol"
  validation {
    condition     = var.engine == "mysql"
    error_message = "engine must be mysql. The gp3 IOPS and throughput validations in this module encode MySQL's thresholds (400 GiB, 12,000-64,000 IOPS, 500-4,000 MiB/s), which differ for Oracle and SQL Server, and the root's schema step connects with a MySQL client."
  }
}
variable "engine_version" {
  type        = string
  default     = "8.0.42"
  description = "Engine version, as the template pinned it. Pinned rather than a major-only \"8.0\", so an apply months from now creates the same version - with allow_major_version_upgrade true, a floating version is how an instance quietly moves major release"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must look like 8.0 or 8.0.42."
  }
}
variable "instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = <<-DESC
    Instance class for the primary, as the template had it.

    Kept, and worth reading next to the storage settings. db.t3.micro is the smallest class RDS offers and
    its EBS bandwidth is a small fraction of the 500 MiB/s the volume is provisioned for, so the striped
    gp3 performance this configuration pays for cannot be driven by the instance attached to it. AWS
    documents this directly - a DB instance may not be able to use provisioned IOPS and throughput when
    its class has lower limits.

    It is not an error and it is not corrected here: the combination is what the template declared, and for
    a demo whose load is a handful of curl requests the class is the right size and the storage figures are
    the thing that is oversized. Lowering the storage instead is the move that breaks, because 400 GiB is
    the threshold the provisioned values require - see allocated_storage.
  DESC
  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be a valid RDS instance class (e.g. db.t3.micro)."
  }
}
variable "replica_instance_class" {
  type        = string
  default     = null
  description = "Instance class for the read replica, or null to use the primary's. A replica's class is independent of its source, so a smaller one is allowed"
  validation {
    condition     = var.replica_instance_class == null || can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.replica_instance_class))
    error_message = "replica_instance_class must be a valid RDS instance class (e.g. db.t3.micro), or null."
  }
}
variable "db_name" {
  type        = string
  default     = "dev"
  description = "Initial database created on the primary, as the template's RdsDatabase parameter had it. The user application connects to this database and the root's schema step creates its table inside it - one value behind all three (rules.md B-5)"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,63}$", var.db_name))
    error_message = "db_name must be 1-64 characters, start with a letter and contain only letters, digits and underscores. MySQL rejects a hyphen here."
  }
}
variable "username" {
  type        = string
  default     = "admin"
  description = "Master username, as the template's RdsUsername parameter had it"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,15}$", var.username))
    error_message = "username must be 1-16 characters, start with a letter and contain only letters, digits and underscores."
  }
}
variable "master_password" {
  type        = string
  default     = null
  sensitive   = true
  description = <<-DESC
    Master password. Null generates one and stores it in Secrets Manager, which is the default.

    The template had default = "dbpassword" here with sensitive = true. The default is what is dropped: a
    secret with a default is the secret everybody runs with, and sensitive = true only hides it from
    terraform output - it does not keep it out of state, and it did not stop the template from putting the
    same string into three task definitions as a plaintext environment variable.

    Passing a value here is supported for a caller who has a password already. It still ends up in state and
    in the secret; what it does not do is sit in the configuration as a default.
  DESC
  validation {
    condition     = var.master_password == null || can(regex("^[^/@\" ]{8,41}$", var.master_password))
    error_message = "master_password must be 8-41 characters and must not contain '/', '@', '\"' or a space, which RDS rejects for a MySQL master password at apply with InvalidParameterValue."
  }
}
variable "generated_password_length" {
  type        = number
  default     = 32
  description = "Length of the generated password when master_password is null"
  validation {
    condition     = var.generated_password_length >= 16 && var.generated_password_length <= 41
    error_message = "generated_password_length must be between 16 and 41. RDS caps a MySQL master password at 41 characters, and below 16 there is no reason to generate rather than choose."
  }
}
variable "port" {
  type        = number
  default     = 3306
  description = "Port the instance listens on, as the template had it. The same value opens the security group rule and is passed to the application as MYSQL_PORT (rules.md B-5)"
  validation {
    condition     = var.port > 0 && var.port <= 65535
    error_message = "port must be a valid TCP port."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC ID the database security group is created in"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets for the DB subnet group. At least two, in different Availability Zones"
  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least two valid subnet IDs. RDS rejects a DB subnet group whose subnets do not span two Availability Zones, and multi_az has nowhere to put the standby."
  }
}
variable "subnet_group_name" {
  type        = string
  default     = "rds-subnet-group"
  description = "Name of the DB subnet group, as the template had it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._-]{1,255}$", var.subnet_group_name))
    error_message = "subnet_group_name must be 1-255 characters of letters, digits, spaces, dots, underscores and hyphens."
  }
}
variable "subnet_group_description" {
  type        = string
  default     = "RDS SubnetGroup"
  description = "Description of the DB subnet group, as the template had it"
  validation {
    condition     = length(var.subnet_group_description) > 0
    error_message = "subnet_group_description must not be empty."
  }
}
variable "security_group_name" {
  type        = string
  default     = "rds-sg"
  description = "Name of the database security group, as the template named it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security Group"
  description = "Description attached to the database security group, as the template had it. Changing it replaces the group, and every rule and instance referencing it with it (rules.md F-1)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces part-way through apply (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on the MySQL port, keyed by a caller-chosen label. A map rather than a list because these IDs are other modules' outputs and unknown at plan time, and for_each needs statically known keys (rules.md B-8). The key appears in each rule's description, so the plan shows which source it is"
  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels that end up in a security group rule description, so each must be letters, digits, dots, underscores or hyphens - an apostrophe or other character outside that set is rejected by EC2 (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups values must be valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "all_traffic_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on every protocol and port, keyed by a caller-chosen label. Empty: the template's equivalent rule named the VPC's default security group, which nothing in this project joins - see main.tf"
  validation {
    condition     = alltrue([for label in keys(var.all_traffic_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "all_traffic_source_security_groups keys must be letters, digits, dots, underscores or hyphens, because they end up in a security group rule description (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.all_traffic_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "all_traffic_source_security_groups values must be valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "storage_type" {
  type        = string
  default     = "gp3"
  description = "Storage type, as the template had it. gp2 is accepted and ignores iops and storage_throughput; io1 and io2 have different ranges and ratio rules that the validations here do not encode, so they are rejected rather than silently mis-validated"
  validation {
    condition     = contains(["gp2", "gp3"], var.storage_type)
    error_message = "storage_type must be gp2 or gp3. io1 and io2 are valid for RDS but have different IOPS ranges and IOPS-to-storage ratios than the ones this module validates against, so using them here would mean validations that pass on an invalid combination."
  }
}
variable "allocated_storage" {
  type        = number
  default     = 400
  description = <<-DESC
    Storage in GiB, as the template had it.

    400 is not a size choice here, it is a threshold. For MySQL on gp3, storage below 400 GiB has no
    provisionable IOPS or throughput at all - the volume is fixed at 3,000 IOPS and 125 MiB/s, and naming
    either value is rejected. At 400 GiB RDS stripes the volume across four, the baseline becomes
    12,000 IOPS / 500 MiB/s, and both become settable.

    So the obvious economy on a db.t3.micro - reduce the storage - is the one change that makes this
    instance fail to create, and it fails at apply with InvalidParameterCombination rather than at plan.
    That is what the precondition on the instance exists to catch; see main.tf for why it is not a
    validation here.
  DESC
  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "allocated_storage must be between 20 and 65536 GiB for MySQL on General Purpose SSD."
  }
}
variable "max_allocated_storage" {
  type        = number
  default     = 1000
  description = "Upper bound for storage autoscaling, as the template had it. Null disables autoscaling. The IOPS-to-storage ratio limit applies to this value too, not just to allocated_storage, so a high ceiling with high IOPS is rejected"
  validation {
    condition     = var.max_allocated_storage == null || var.max_allocated_storage <= 65536
    error_message = "max_allocated_storage must be 65536 GiB or less, or null to disable storage autoscaling."
  }
}
variable "iops" {
  type        = number
  default     = 12000
  description = "Provisioned IOPS, as the template had it. 12,000 is the floor of the provisionable range for MySQL gp3 above the 400 GiB threshold, not a tuned number - it is the baseline a striped volume gets anyway. Null leaves the volume at its baseline and is the only valid setting below 400 GiB"
  validation {
    condition     = var.iops == null || (var.iops >= 12000 && var.iops <= 64000)
    error_message = "iops must be between 12000 and 64000, or null. That is the provisionable range for MySQL on gp3 at or above the 400 GiB threshold; below the threshold the only valid value is null."
  }
  validation {
    # storage_type is a safe variable to reference from here: nothing in its own validations refers back to
    # this one. The storage-size and throughput constraints are not, which is why they are preconditions on
    # the instance instead - see main.tf.
    condition     = var.iops == null || var.storage_type == "gp3"
    error_message = "iops may only be set when storage_type is gp3. On gp2 the volume's IOPS are a function of its size and RDS rejects the parameter."
  }
}
variable "storage_throughput" {
  type        = number
  default     = 500
  description = "Provisioned storage throughput in MiB/s, as the template had it. 500 is the floor of the provisionable range above the threshold, and the baseline of a striped volume. Null leaves the volume at its baseline"
  validation {
    condition     = var.storage_throughput == null || (var.storage_throughput >= 500 && var.storage_throughput <= 4000)
    error_message = "storage_throughput must be between 500 and 4000 MiB/s, or null. That is the provisionable range for MySQL on gp3 at or above the 400 GiB threshold; below the threshold the only valid value is null."
  }
  validation {
    condition     = var.storage_throughput == null || var.storage_type == "gp3"
    error_message = "storage_throughput may only be set when storage_type is gp3."
  }
}
variable "storage_encrypted" {
  type        = bool
  default     = true
  description = "Whether the volume is encrypted at rest with the default RDS KMS key. On, where the template left it off. Encryption cannot be turned on for an existing instance - it is a snapshot-and-restore - so the cost of leaving it off is paid later, and the default key adds no permissions to manage"
}
variable "multi_az" {
  type        = bool
  default     = true
  description = "Whether the primary has a synchronous standby in the second Availability Zone, as the template had it. The standby cannot be read from and is never connected to; it exists so a zone failure or a patching event becomes a failover behind the same endpoint. This is a separate mechanism from the read replica and keeping both is deliberate - see main.tf"
}
variable "replica_multi_az" {
  type        = bool
  default     = false
  description = "Whether the read replica itself has a standby. False, as the template declared it: it would double the cost of a copy that nothing in this project reads"
}
variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Days of automated backups kept on the primary, as the template had it. Also load-bearing: RDS refuses to create a read replica of a source with automated backups turned off"
  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35 days."
  }
  validation {
    condition     = var.backup_retention_period >= 1 || !var.create_read_replica
    error_message = "backup_retention_period must be at least 1 when create_read_replica is true. RDS rejects CreateDBInstanceReadReplica against a source with automated backups disabled, and the error names the source rather than this setting."
  }
}
variable "replica_backup_retention_period" {
  type        = number
  default     = 7
  description = "Days of automated backups kept on the read replica. Matching the primary, as the template declared on both resources. Zero turns them off on the replica only, which is supported for MySQL"
  validation {
    condition     = var.replica_backup_retention_period >= 0 && var.replica_backup_retention_period <= 35
    error_message = "replica_backup_retention_period must be between 0 and 35 days."
  }
}
variable "monitoring_interval" {
  type        = number
  default     = 60
  description = "Enhanced Monitoring sampling interval in seconds, as the template had it. This module always attaches a monitoring role, so zero is not accepted - RDS rejects a role with an interval of zero"
  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be 1, 5, 10, 15, 30 or 60. Zero disables Enhanced Monitoring, which RDS rejects while monitoring_role_arn is set - and this module always sets it, because the template created the role."
  }
}
variable "monitoring_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"]
  description = "Managed policy ARNs on the Enhanced Monitoring role, as the template attached. The AWS service-role policy for exactly this purpose, already scoped to the RDSOSMetrics log group (rules.md A-5)"
  validation {
    condition     = length(var.monitoring_policy_arns) > 0
    error_message = "monitoring_policy_arns must contain at least one policy. Without it RDS accepts the role and the monitoring agent then publishes nothing, with no error logged anywhere."
  }
  validation {
    condition     = alltrue([for arn in var.monitoring_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "monitoring_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "database_insights_mode" {
  type        = string
  default     = "standard"
  description = "Database Insights mode, as the template had it. advanced is not accepted here: it additionally requires Performance Insights enabled with a 465 day retention, which this module does not declare, and RDS reports that mismatch as an error about the retention period rather than about the mode"
  validation {
    condition     = var.database_insights_mode == "standard"
    error_message = "database_insights_mode must be standard. advanced requires performance_insights_enabled = true and performance_insights_retention_period = 465, neither of which this module sets - add them before allowing it."
  }
}
variable "auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "Whether RDS applies minor engine upgrades during the maintenance window, as the template had it"
}
variable "allow_major_version_upgrade" {
  type        = bool
  default     = true
  description = "Whether a change to engine_version across a major release is allowed rather than rejected, as the template had it. It permits the upgrade; it does not perform one. engine_version is pinned to a full version for this reason - a floating version with this set true is how an instance moves major release without anyone deciding to"
}
variable "apply_immediately" {
  type        = bool
  default     = true
  description = "Whether modifications are applied at once rather than in the next maintenance window, as the template had it. True suits a demo and means a plan that changes an instance setting takes effect, and can restart the database, as soon as it is applied"
}
variable "deletion_protection" {
  type        = bool
  default     = false
  description = "Whether RDS refuses to delete the instance. False, as the template left it. True makes terraform destroy fail at this resource with everything around it already gone, and the only fix is to turn it off and apply before destroying"
}
variable "skip_final_snapshot" {
  type        = bool
  default     = true
  description = "Whether destroy skips the final snapshot. True, which the template did not set - the provider defaults it to false, and with it false destroy fails here with \"FinalDBSnapshotIdentifier is required when SkipFinalSnapshot is false\". Never true for a database holding anything worth keeping"
}
variable "credentials_secret_name_prefix" {
  type        = string
  default     = "apdev-rds-credentials-"
  description = "Prefix for the generated Secrets Manager secret name. A prefix rather than a fixed name, so two copies of this project in one account do not collide on it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]{1,480}$", var.credentials_secret_name_prefix))
    error_message = "credentials_secret_name_prefix must be 1-480 characters of letters, digits and the characters / _ + = . @ -, leaving room for the generated suffix."
  }
}
variable "secret_recovery_window_in_days" {
  type        = number
  default     = 0
  description = "Days Secrets Manager keeps a deleted secret recoverable. Zero deletes it at once, which is what lets this project be destroyed and applied again - a recovery window keeps the name reserved and the next apply fails on a name it cannot reuse. Never zero for a secret worth keeping"
  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0, or between 7 and 30. Secrets Manager accepts nothing in between."
  }
}
