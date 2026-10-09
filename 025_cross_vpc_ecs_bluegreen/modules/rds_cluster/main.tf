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
# The _monolithic template gave this group three inline ingress blocks and no egress block, which
# in Terraform revokes the allow-all outbound rule EC2 attaches to a new group - CloudFormation
# leaves it in place when a template names only SecurityGroupIngress, Terraform's
# attributes-as-blocks do not.
#
# A database with no outbound rule is the case where the consequence is least obvious, because the
# connections are all inbound. What breaks is Enhanced Monitoring and the Performance Insights
# upload: the monitoring agent on the instance publishes outward, so the role and the policy below
# are correct and the metrics simply never appear. Nothing reports an error.
resource "aws_vpc_security_group_ingress_rule" "rds_source_group_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.rds_security_group.id
  description                  = "Database port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_ingress_rule" "rds_all_traffic_source_group_ingress" {
  for_each = var.all_traffic_source_security_groups

  security_group_id            = aws_security_group.rds_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_egress_rule" "rds_egress" {
  security_group_id = aws_security_group.rds_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# The internal tier, which has no route to the internet in either direction. That is what makes
# this the most isolated thing in the project and it is also why the schema is created by an SSM
# association on the workbench rather than from anywhere else.
resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = var.subnet_group_name
  description = var.subnet_group_description
  subnet_ids  = var.subnet_ids
  tags = {
    Name = var.subnet_group_name
  }
}
resource "aws_iam_role" "rds_enhanced_monitoring_iam_role" {
  name_prefix = var.monitoring_role_name_prefix
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
# AmazonRDSEnhancedMonitoringRole stays as the _monolithic template had it, and rules.md A-5 is the
# reason rather than an exception to it: this is the AWS service-role policy documented for exactly
# this purpose, already scoped to the RDSOSMetrics log group. Replacing it with a hand-written
# policy would be guessing at the agent's call list, and the failure mode of guessing wrong is
# metrics that never arrive with nothing logged anywhere.
#
# for_each rather than one attachment per policy (rules.md B-7); toset is safe because the ARNs are
# configuration literals and known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring_iam_role" {
  for_each   = toset(var.monitoring_policy_arns)
  role       = aws_iam_role.rds_enhanced_monitoring_iam_role.name
  policy_arn = each.value
}
resource "aws_rds_cluster" "rds_cluster" {
  cluster_identifier = var.cluster_identifier
  engine             = var.engine
  engine_version     = var.engine_version
  database_name      = var.database_name
  port               = var.port

  # The password is passed in rather than managed by RDS, which is what the _monolithic template
  # did: manage_master_user_password would have RDS create and rotate its own secret, and the
  # application here reads the separate secret below instead - a JSON document with the URL, the
  # user and the password, which is the shape the task definition's three secret references expect.
  #
  # manage_master_user_password is therefore left unset rather than written as false, which is
  # where the _monolithic template differs. The provider declares it ConflictsWith master_password,
  # and ConflictsWith tests whether an argument is present in configuration, not whether it is
  # true - so "= false" next to a password fails plan with "conflicts with master_password". Unset
  # means the same false. terraform validate does not catch it: the password arrives through a
  # variable, which validate treats as unknown, and the check only runs once the value is known.
  master_username = var.master_username
  master_password = var.master_password

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]

  storage_encrypted = true
  # The ARN rather than the bare key ID the _monolithic template passed. Both are accepted by the
  # API, but it returns an ARN, so a configured ID leaves a difference between what is written and
  # what is read back on every plan.
  kms_key_id = var.kms_key_arn

  backup_retention_period = var.backup_retention_period
  backtrack_window        = var.backtrack_window
  # instance is a valid Aurora MySQL log type alongside audit, error and general - it is not valid
  # for RDS for MySQL, which is the engine it reads like a mistake for.
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Database Insights in standard mode requires Performance Insights on with a 7 day retention;
  # advanced mode requires 465. The variables carry that pairing as a cross-variable validation,
  # because RDS rejects the mismatch at apply with a message about the retention period rather
  # than about the mode.
  database_insights_mode                = var.database_insights_mode
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  availability_zones         = var.availability_zones

  # skip_final_snapshot, which the _monolithic template did not set.
  #
  # The provider defaults it to false, and with it false terraform destroy fails at the cluster
  # with "InvalidParameterCombination: FinalDBSnapshotIdentifier is required when
  # SkipFinalSnapshot is false". Everything else in the project is already gone by then, so the
  # destroy has to be re-run after setting this - and in CloudFormation the equivalent default is
  # the other way round, so the template never had to decide.
  skip_final_snapshot = var.skip_final_snapshot

  lifecycle {
    # availability_zones has to be ignored, and this is the reason rather than a convenience.
    #
    # RDS treats the list as a hint and returns the three zones the cluster may place instances
    # in, whatever subset was asked for. The _monolithic template asked for two. Terraform then
    # reads back three, sees a difference in an attribute marked ForceNew, and proposes destroying
    # and recreating the Aurora cluster on the very next plan - with no changes made by anyone.
    ignore_changes = [availability_zones]
  }

  # The monitoring role must carry its policy before an instance below starts publishing. Neither
  # the cluster nor the instances refer to the attachment, and a missing one does not fail the
  # create (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.rds_enhanced_monitoring_iam_role]
}
# aws_rds_cluster_instance, not aws_db_instance.
#
# This is the one place the conversion produced something that cannot work. CloudFormation models
# an Aurora writer and reader as AWS::RDS::DBInstance resources carrying DBClusterIdentifier, and
# the generator mapped them to aws_db_instance and dropped the cluster identifier - there is no
# such argument on that resource. What was left is two standalone MySQL instances with
# engine = "aurora-mysql", no cluster, no storage, no credentials:
#
#   resource "aws_db_instance" "rds_instance_a" {
#     identifier     = "rds-instance-a"
#     instance_class = "db.t4g.medium"
#     engine         = "aurora-mysql"
#     ...
#   }
#
# terraform validate passes that. The apply fails at CreateDBInstance, and the Aurora cluster that
# was created a moment earlier is left with no instances at all - so it exists, has an endpoint,
# and refuses every connection. The SSM association that creates the schema then waits out its
# timeout against it.
#
# allow_major_version_upgrade is also dropped here: it is an argument of aws_db_instance and of
# aws_rds_cluster, and not of a cluster instance. Keeping it would be an "Unsupported argument"
# error at validate.
resource "aws_rds_cluster_instance" "rds_cluster_instance" {
  for_each = var.instance_availability_zones

  identifier         = "${var.instance_identifier_prefix}-${each.key}"
  cluster_identifier = aws_rds_cluster.rds_cluster.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.rds_cluster.engine
  availability_zone  = each.value

  # Enhanced Monitoring is configured per instance for Aurora - the agent runs on the instance and
  # the metrics are published per instance. The _monolithic template set monitoring_interval and
  # monitoring_role_arn on the cluster, where the RDS API documents them for Multi-AZ DB clusters,
  # so they are moved to where they unambiguously apply.
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring_iam_role.arn

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  publicly_accessible        = false
  tags = {
    Name = "${var.instance_identifier_prefix}-${each.key}"
  }
}
resource "aws_secretsmanager_secret" "rds_secret" {
  name        = var.secret_name
  description = var.secret_description
  kms_key_id  = var.kms_key_arn
  # Zero, so a destroy and re-apply works. Secrets Manager keeps a deleted secret for a recovery
  # window of 7 to 30 days and holds the name against a new secret for the whole window, so the
  # provider default leaves the next apply failing with InvalidRequestException: "already
  # scheduled for deletion".
  recovery_window_in_days = var.secret_recovery_window_in_days
}
# The credential document the two task definitions read, with one key per secret reference they
# make: DB_URL, DB_USER and DB_PASSWD.
#
# jsonencode rather than the template's hand-assembled string:
#
#   secret_string = "{\"DB_URL\":\"${endpoint}:10101\",\"DB_USER\":\"${user}\",...}"
#
# which hardcoded the port that the cluster above takes as a variable - so changing the port left
# the application dialling the old one - and would produce a malformed document for any password
# containing a quote or a backslash. The task's own secret lookup then fails with a message about
# the key not existing rather than about the JSON.
resource "aws_secretsmanager_secret_version" "rds_secret" {
  secret_id = aws_secretsmanager_secret.rds_secret.id
  secret_string = jsonencode({
    DB_URL    = "${aws_rds_cluster.rds_cluster.endpoint}:${var.port}"
    DB_USER   = var.master_username
    DB_PASSWD = var.master_password
  })

  # The writer has to exist before anything reads this: the endpoint resolves as soon as the
  # cluster does, but it answers nothing until an instance is attached.
  depends_on = [aws_rds_cluster_instance.rds_cluster_instance]
}
