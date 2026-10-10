resource "aws_security_group" "rds_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress blocks (rules.md F-2).
#
# The _monolithic template gave this group two inline ingress blocks and no egress block, which in Terraform
# revokes the allow-all outbound rule EC2 attaches to a new group. A database is the case where that is
# least obvious, because every connection to it is inbound - what actually breaks is Enhanced Monitoring,
# whose agent on the instance publishes outward to the RDSOSMetrics log group. The role and the policy below
# are then correct and the metrics simply never appear, with nothing reporting an error.
resource "aws_vpc_security_group_egress_rule" "rds_egress" {
  security_group_id = aws_security_group.rds_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# A map keyed by a caller-chosen label rather than a list, because these IDs are other modules' outputs and
# unknown at plan time - a set whose members are unknown cannot provide for_each keys (rules.md B-8).
# each.key goes into the description so a plan shows which source each rule came from.
#
# The _monolithic template's two ingress blocks were:
#
#   all traffic from the VPC's default security group
#   TCP 3306 from the bastion security group
#
# and between them they left the three ECS services unable to reach the database. The tasks run with
# awsvpc networking in the ECS service security group, which is not the VPC default group - nothing in this
# project joins the default group, so that first rule admits nothing at all. The user application would have
# got "dial tcp <endpoint>:3306: i/o timeout" from sql.Open's first query, for a configuration where
# everything else was correct. The root passes both the workbench and the task security group in here.
resource "aws_vpc_security_group_ingress_rule" "rds_port_source_group_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.rds_security_group.id
  description                  = "MySQL port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
}
# The template's first rule, kept as an extension point with an empty default. It granted all traffic from
# the VPC default security group; nothing in this project is in that group, so reproducing it as a rule
# would add an edge that admits nothing while implying something uses it.
resource "aws_vpc_security_group_ingress_rule" "rds_all_traffic_source_group_ingress" {
  for_each = var.all_traffic_source_security_groups

  security_group_id            = aws_security_group.rds_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = var.subnet_group_name
  description = var.subnet_group_description
  subnet_ids  = var.subnet_ids
  tags = {
    Name = var.subnet_group_name
  }
}
resource "aws_iam_role" "rds_monitoring_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["monitoring.rds.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# AmazonRDSEnhancedMonitoringRole stays as the template attached it, and rules.md A-5 is the reason rather
# than an exception to it: it is the AWS service-role policy documented for exactly this purpose and already
# scoped to the RDSOSMetrics log group. Replacing it with a hand-written policy would be guessing at the
# agent's call list, and the failure mode of guessing wrong is metrics that never arrive with nothing
# logged anywhere.
#
# for_each rather than one attachment per policy (rules.md B-7); toset is safe because the ARNs are
# configuration literals, known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "rds_monitoring_iam_role" {
  for_each   = toset(var.monitoring_policy_arns)
  role       = aws_iam_role.rds_monitoring_iam_role.name
  policy_arn = each.value
}
# The master password, generated rather than typed.
#
# This is a change from what the _monolithic template did and the reason is worth stating. There the
# password was var.rds_password with default = "dbpassword" and sensitive = true, and the task definitions
# then passed it to the containers as a plain environment variable. Two separate problems with that, and
# sensitive = true solves neither:
#
#   - "dbpassword" is the password unless somebody remembers to override it, and nothing makes them
#   - a plaintext Environment entry in a task definition is readable by anyone who can call
#     ecs:DescribeTaskDefinition, which is a much wider set of principals than those who can read a secret,
#     and it is permanent: every registered revision keeps its copy
#
# So: generated here by default, stored in Secrets Manager, and injected into the container through the task
# definition's secrets list rather than its environment list - which also lets the task execution role be
# narrowed to GetSecretValue on this one ARN instead of carrying CloudWatchFullAccessV2 (rules.md A-5).
#
# A caller who wants the template's behaviour back passes master_password explicitly. The variable has no
# default, so that is a decision rather than a leftover.
resource "random_password" "master_password" {
  count = var.master_password == null ? 1 : 0
  # 32 characters and an explicit override_special. RDS rejects a MySQL master password containing '/', '@',
  # '"' or a space, and random_password's default special set includes all four - so left at the default,
  # roughly one apply in ten fails at CreateDBInstance with InvalidParameterValue.
  length           = var.generated_password_length
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}
locals {
  master_password = var.master_password == null ? random_password.master_password[0].result : var.master_password
  # The document shape the credential is stored in. username/password/host/port/dbname rather than a bare
  # string, so the one retrieval command in the root's outputs gives a person everything needed to connect,
  # and so the task definition can select a single key out of it with a ":password::" suffix.
  #
  # host and port come from the primary instance, which means this secret cannot be written until the
  # instance exists - that is the intended order, and it is why the secret version is declared after it.
  credentials = {
    username = var.username
    password = local.master_password
    host     = aws_db_instance.rds_instance_primary.address
    port     = aws_db_instance.rds_instance_primary.port
    dbname   = var.db_name
    engine   = var.engine
  }
}
resource "aws_secretsmanager_secret" "credentials" {
  name_prefix = var.credentials_secret_name_prefix
  description = "MySQL master credential and endpoint for ${var.identifier}, read by the user service's task definition and by the schema step on the workbench"
  # Zero rather than the 30 day default. A recovery window keeps the name reserved after destroy, so the
  # next apply of this project fails with InvalidRequestException on a name it cannot reuse - and
  # name_prefix does not help, because the prefix is what collides. Never zero for a secret worth keeping.
  recovery_window_in_days = var.secret_recovery_window_in_days
}
resource "aws_secretsmanager_secret_version" "credentials" {
  secret_id     = aws_secretsmanager_secret.credentials.id
  secret_string = jsonencode(local.credentials)
}
# The primary instance.
#
# The storage combination here - gp3, 400 GiB, 12,000 IOPS, 500 MiB/s - is reproduced from the template
# unchanged, and it is valid, but only just. Those are not arbitrary numbers and the variables carry the
# bounds as validations, because every one of these is rejected at apply with an InvalidParameterCombination
# that plan does not see:
#
#   - for MySQL, gp3 below 400 GiB has no provisionable IOPS or throughput at all. The volume is a fixed
#     3,000 IOPS / 125 MiB/s and naming either value is an error. 400 GiB is exactly the threshold at which
#     RDS stripes across four volumes and the two become settable, so dropping allocated_storage - the
#     obvious saving on a db.t3.micro - breaks the instance rather than shrinking it
#   - above the threshold the provisionable ranges are 12,000-64,000 IOPS and 500-4,000 MiB/s. The
#     template's values are the floor of both, so they are also the only values that work without raising
#     the other
#   - storage throughput may not exceed a quarter of IOPS, and IOPS may not exceed 500x allocated storage.
#     With storage autoscaling on, that second ratio applies to max_allocated_storage too
#
# What is worth knowing and is not an error: db.t3.micro cannot use any of it. The instance class caps EBS
# bandwidth far below 500 MiB/s, so the provisioned performance is paid for and not delivered - gp3 at
# 400 GiB with the baseline is already more than this class can drive. That is the template's choice and it
# is kept; see the instance_class variable.
resource "aws_db_instance" "rds_instance_primary" {
  identifier     = var.identifier
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class
  db_name        = var.db_name
  username       = var.username
  password       = local.master_password
  port           = var.port

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  iops                  = var.iops
  storage_throughput    = var.storage_throughput
  storage_encrypted     = var.storage_encrypted

  # Multi-AZ and a read replica, both, which is what the template declared and is a deliberate pair rather
  # than a redundancy. They are different mechanisms for different problems:
  #
  #   multi_az            a synchronous standby in the other zone that cannot be read from and is never
  #                       connected to. It exists so a zone failure or a patching event becomes a failover
  #                       behind the same endpoint
  #   the read replica    an asynchronous copy with its own endpoint that can be read from, for moving read
  #                       traffic off the primary
  #
  # Keeping both is therefore correct. What is odd about the template is that nothing in it ever connects to
  # the replica - the user task definition only receives the primary's address - so the replica is created
  # and never used. That is reproduced, with the replica's endpoint exposed as an output so it is at least
  # reachable by hand.
  multi_az = var.multi_az

  backup_retention_period = var.backup_retention_period
  monitoring_interval     = var.monitoring_interval
  monitoring_role_arn     = aws_iam_role.rds_monitoring_iam_role.arn
  database_insights_mode  = var.database_insights_mode

  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade
  apply_immediately           = var.apply_immediately
  deletion_protection         = var.deletion_protection
  # skip_final_snapshot, which the template did not set. The provider defaults it to false, and with it
  # false terraform destroy fails here with "InvalidParameterCombination: FinalDBSnapshotIdentifier is
  # required when SkipFinalSnapshot is false" - by which point everything else is already gone. In
  # CloudFormation the equivalent default is the other way round, so the template never had to decide.
  skip_final_snapshot = var.skip_final_snapshot

  # The gp3 storage combination rules, checked at plan rather than at CreateDBInstance.
  #
  # These are preconditions and not variable validations, and the reason is a hard limitation rather than a
  # preference. Each of these constraints is about a *pair* of the four storage variables, so writing them
  # as cross-variable validations (rules.md B-1) makes those variables reference each other: the size rule
  # needs iops, the ratio rule needs allocated_storage, the throughput rule needs iops. Terraform builds a
  # graph of those references and rejects the result outright:
  #
  #   Error: Cycle: module.rds_mysql.var.max_allocated_storage (validation),
  #     module.rds_mysql.var.storage_throughput (validation),
  #     module.rds_mysql.var.allocated_storage (validation), module.rds_mysql.var.iops (validation)
  #
  # A cross-variable validation therefore only works while the references form a DAG, and these do not.
  # lifecycle preconditions have no such restriction - they are evaluated once the values are known, not as
  # part of the variable graph - and they still run at plan, which is the property that matters. The
  # per-variable range checks stay in variables.tf, where they belong; only the combinations moved here.
  # rules.md I-2 uses a precondition for the same reason, there because a validation cannot read a data
  # source.
  lifecycle {
    precondition {
      condition     = (var.iops == null && var.storage_throughput == null) || var.allocated_storage >= 400
      error_message = "allocated_storage must be at least 400 GiB when iops or storage_throughput is set. Below that threshold MySQL's gp3 volume is fixed at 3,000 IOPS and 125 MiB/s and RDS rejects CreateDBInstance with InvalidParameterCombination. To run with less storage, set iops and storage_throughput to null and accept the fixed baseline."
    }
    precondition {
      condition     = var.max_allocated_storage == null || var.max_allocated_storage >= var.allocated_storage
      error_message = "max_allocated_storage must be at least allocated_storage, or null. RDS rejects a ceiling below the current size."
    }
    precondition {
      condition     = var.iops == null || var.iops <= 500 * var.allocated_storage
      error_message = "iops must not exceed 500 times allocated_storage. RDS enforces that ratio for gp3 on every engine and rejects the combination at apply."
    }
    precondition {
      condition     = var.iops == null || var.max_allocated_storage == null || var.iops <= 500 * var.max_allocated_storage
      error_message = "iops must not exceed 500 times max_allocated_storage. With storage autoscaling on, the IOPS-to-storage ratio applies to the ceiling as well as to the current size."
    }
    precondition {
      condition     = var.storage_throughput == null || (var.iops != null && var.storage_throughput * 4 <= var.iops)
      error_message = "storage_throughput must not exceed a quarter of iops, and iops must be set when it is. RDS caps the throughput-to-IOPS ratio at 0.25 for every supported engine."
    }
    precondition {
      # MySQL and MariaDB raise the minimum throughput once IOPS go past 32,000: at 40,000 IOPS the floor
      # is 625 MiB/s, which is iops/64. The other engines do not do this.
      condition     = var.iops == null || var.iops <= 32000 || (var.storage_throughput != null && var.storage_throughput * 64 >= var.iops)
      error_message = "storage_throughput must be at least iops/64 once iops exceeds 32000. For MySQL, RDS raises the minimum throughput above that point - 40000 IOPS requires at least 625 MiB/s - and rejects a lower value at apply."
    }
  }

  # RDS will not create a read replica of a source with no automated backups, and the replica below reads
  # this instance. backup_retention_period carries that as a validation, but the ordering also has to hold:
  # the monitoring role needs its policy before RDS accepts monitoring_role_arn, and monitoring_role_arn
  # references the role rather than the attachment (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.rds_monitoring_iam_role]
}
# The read replica, which in the template was a second standalone instance by accident.
#
# The CloudFormation resource was a replica - it carried SourceDBInstanceIdentifier: !Ref RdsInstancePrimary
# - and the conversion could not map that property, so it left a comment where the line should have been:
#
#   # TODO cfn2tf: unmapped CloudFormation property 'SourceDBInstanceIdentifier' of AWS::RDS::DBInstance
#
# What remained is an aws_db_instance with storage settings, an identifier of "apdev-rds-replica", and no
# engine, no username, no password and no subnet group. That is not a second database: it is a resource the
# provider rejects at plan, because engine is required unless replicate_source_db or snapshot_identifier is
# set. So the template as converted could not be applied at all, and the "two instances or one?" question
# answers itself - it was always one instance and one replica.
#
# replicate_source_db restores that. The arguments that disappear with it are not omissions:
#
#   engine, engine_version    inherited from the source; setting them is rejected
#   username, password        a replica has no master user of its own
#   db_name                   likewise - it replicates the source's databases
#   db_subnet_group_name      a same-region replica inherits the source's subnet group
#
# allocated_storage, iops and storage_throughput are settable on a replica and are kept at the source's
# values. They are independent of the source, so a cheaper replica is possible, but a replica with less
# storage than its source is rejected.
resource "aws_db_instance" "rds_instance_replica" {
  count = var.create_read_replica ? 1 : 0

  identifier          = var.replica_identifier
  replicate_source_db = aws_db_instance.rds_instance_primary.identifier
  instance_class      = var.replica_instance_class == null ? var.instance_class : var.replica_instance_class

  vpc_security_group_ids = [aws_security_group.rds_security_group.id]

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  iops                  = var.iops
  storage_throughput    = var.storage_throughput

  # false where the primary is true. A Multi-AZ read replica is supported and doubles the replica's cost for
  # a copy nothing reads; the template declared no multi_az on this resource, so false is also faithful.
  multi_az = var.replica_multi_az

  backup_retention_period = var.replica_backup_retention_period
  monitoring_interval     = var.monitoring_interval
  monitoring_role_arn     = aws_iam_role.rds_monitoring_iam_role.arn
  database_insights_mode  = var.database_insights_mode

  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade
  apply_immediately           = var.apply_immediately
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring_iam_role]
}
