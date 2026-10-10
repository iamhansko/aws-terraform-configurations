# Where the logs go, and the permission to put them there.
#
# This module exists because the _monolithic template had no answer to the first question that holds up.
# Its task definition pointed FireLens at the log group "/logging/cloudwatch" and the log router's own
# awslogs driver at "/fluentbit/cloudwatch", and nothing in the configuration created either one. Both
# relied on being created at runtime - the application group by the cloudwatch_logs plugin's
# auto_create_group option, the router's group by the awslogs driver's awslogs-create-group - which
# worked, and cost three things:
#
#   - no retention. Both groups keep every record forever, and nothing says so anywhere.
#   - nothing in Terraform state. terraform destroy tears down the cluster, the service, the images and
#     the VPC, and leaves both log groups and all their data behind in the account. For a project whose
#     entire output is log data, that is the one resource that outlives the demo.
#   - a permission that has to be broader than the work. CreateLogGroup is an account-level action, so
#     granting it cannot be scoped to the group being created.
#
# Declaring the groups here removes all three, and removes the dependency on CreateLogGroup from both
# credential paths - see the policy below and the auto_create_group variable.
#
# This module is given depends_on by its caller, which defers this data source to apply (rules.md D-6).
# Harmless here: the region ends up as a string in a container definition and in a policy document, not
# as a resource address or a for_each key.
data "aws_region" "current" {}
# The application's logs. Nothing writes to this group directly: the application container prints JSON to
# stdout, the fluentd docker log driver hands each line to the Fluent Bit sidecar over a Unix socket, and
# Fluent Bit's cloudwatch_logs output plugin - configured from the options this module hands back - is
# what calls PutLogEvents against this group.
resource "aws_cloudwatch_log_group" "application_logs" {
  name              = var.application_log_group_name
  retention_in_days = var.retention_in_days
}
# The log router's own stdout, which is a different thing and is worth keeping separate.
#
# Fluent Bit writes its startup banner, the output plugins it loaded and every delivery error here, and it
# reaches this group by the ordinary awslogs driver rather than through itself. That makes this the only
# channel that can report "the log pipeline is broken": when the application group is empty, this group is
# where the reason is.
resource "aws_cloudwatch_log_group" "log_router_logs" {
  name              = var.log_router_log_group_name
  retention_in_days = var.retention_in_days
}
locals {
  # The group ARN and the ARN with the stream wildcard. aws_cloudwatch_log_group.arn comes back without
  # the ":*" suffix the API returns, and the stream-level actions below need it, so both forms are listed.
  application_log_group_resources = [
    aws_cloudwatch_log_group.application_logs.arn,
    "${aws_cloudwatch_log_group.application_logs.arn}:*",
  ]
  # Attached to the task role, because the task role is the one Fluent Bit itself uses. That distinction
  # is the easiest thing to get wrong here and the _monolithic template got it right by attaching
  # CloudWatchFullAccessV2 to both roles - which is also how it stopped being a useful statement about
  # what either role needs.
  #
  # A for with an if rather than concat(..., cond ? [...] : []), which would ask Terraform to unify a
  # one-element tuple of objects with an empty one. The filter form has no unification in it at all.
  log_router_statements = [
    for statement in [
      {
        include = true
        body = {
          Sid    = "WriteApplicationLogStreams"
          Effect = "Allow"
          Action = [
            "logs:CreateLogStream",
            "logs:DescribeLogStreams",
            "logs:PutLogEvents",
          ]
          Resource = local.application_log_group_resources
        }
      },
      {
        # Only when the plugin is the one creating the group. CreateLogGroup is an account-level action,
        # so listing a log group ARN as its resource narrows nothing - which is the second cost of
        # relying on auto_create_group rather than declaring the group.
        include = var.auto_create_group
        body = {
          Sid      = "CreateApplicationLogGroup"
          Effect   = "Allow"
          Action   = ["logs:CreateLogGroup"]
          Resource = local.application_log_group_resources
        }
      },
    ] : statement.body if statement.include
  ]
}
# The replacement for CloudWatchFullAccessV2 on the task role (rules.md A-5).
#
# What that managed policy grants is logs:*, cloudwatch:*, xray:*, rum:*, synthetics:*,
# application-signals:*, sns:Subscribe and a set of conditioned iam:PassRole statements, all on "*". What
# the log router needs is three logs actions on one log group. The gap between those two is not visible in
# a plan - it is one policy ARN either way - which is exactly the case rules.md A-5 is about.
#
# name_prefix rather than name, so two copies of this project in one account do not collide with
# EntityAlreadyExists.
resource "aws_iam_policy" "log_router" {
  name_prefix = var.policy_name_prefix
  description = "Lets the FireLens log router write to the ${aws_cloudwatch_log_group.application_logs.name} log group"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.log_router_statements
  })
}
