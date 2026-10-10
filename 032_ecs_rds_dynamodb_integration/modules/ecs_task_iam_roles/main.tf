# The task role and the task execution role, one pair shared by all three task definitions.
#
# Shared rather than one pair per application, which is what the _monolithic template declared and is kept.
# The alternative is better isolation and is worth naming, because the split is not arbitrary:
#
#   per application   the policy names only what that application touches. Here that would give the product
#                     role the DynamoDB statement and leave the user and stress roles with no policy at all
#   shared            the policy is the union of what the applications touch, which is a wildcard by the
#                     second application unless they happen to touch disjoint, individually nameable things
#
# This project is close to the first case - only the product application calls an AWS API at all - so a
# per-application pair would be strictly tighter. It is not done because the union here is still two named
# resources rather than a wildcard: one table ARN on the task role, one secret ARN on the execution role.
# The cost of sharing is therefore that the user and stress tasks can read a table they never read; the
# benefit is one pair of roles to read instead of three, which is the trade the template made. A caller that
# wants the tighter shape instantiates this module per application and passes empty lists.
#
# The two roles look identical and are not interchangeable. The task role is assumed by the process inside
# the container; the execution role is assumed by the ECS agent on the task's behalf, before the container
# exists, to pull the image and inject secrets. Both are trusted by ecs-tasks.amazonaws.com, which is why
# swapping their policies produces a task that either cannot start or starts without what it expected.
resource "aws_iam_role" "ecs_task_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# AdministratorAccess replaced, which is rules.md A-5's second case: the template attached it in Terraform
# rather than hiding it in a bootstrap script, so narrowing it changes what the original did and the reason
# belongs here.
#
# AdministratorAccess on the task role means every one of the three containers could do anything in the
# account. What the task role is actually used by:
#
#   product   PutItem and GetItem against the one DynamoDB table, through aws-sdk-go-v2 with the task role's
#             credentials from the container credential endpoint. This is the only AWS API call any of the
#             three applications makes
#   user      nothing. It reaches MySQL over the network with a username and a password; RDS IAM
#             authentication is not enabled, so no AWS permission is involved in connecting
#   stress    nothing. It generates random bytes
#
# The awslogs driver is not on this list on purpose, and it is the easiest thing to get wrong here: log
# streams are opened by the agent before the container starts, so that permission belongs to the execution
# role (and on EC2 launch type the container instance role also carries it).
#
# Getting this narrowing wrong is quiet in one direction. Too little and the product application's handlers
# return "Internal Server Error" with an AccessDeniedException only in its own log; nothing in ECS or
# Terraform reports it.
resource "aws_iam_role_policy" "ecs_task_role_dynamodb" {
  count = length(var.dynamodb_table_arns) > 0 ? 1 : 0

  name = "DynamoDbTableAccessPolicy"
  role = aws_iam_role.ecs_task_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        # Exactly the two calls src/product/main.go makes. Query, Scan and DescribeTable used to be here as a
        # way to read the table by hand from the task while GetItem was broken by the key schema mismatch -
        # see modules/dynamodb_table. GetItem now works, the container image has no AWS CLI to run them
        # with, and the README's scan runs on the workbench under its own role, so they were granting
        # nothing anybody used. A GetItem with ConsistentRead needs no permission beyond GetItem.
        "dynamodb:PutItem",
        "dynamodb:GetItem",
      ]
      Resource = var.dynamodb_table_arns
    }]
  })
}
# Left empty by default, which is rules.md A-5's shape for an extension point: the switch to add something
# is open and its default does not add anything. A variable whose default is a broad policy stays broad
# however the description reads.
resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  for_each   = toset(var.additional_task_policy_arns)
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = each.value
}
resource "aws_iam_role" "ecs_task_execution_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# AmazonECSTaskExecutionRolePolicy stays - it is the AWS service-role policy for exactly this role and
# covers the ECR authorization token, the image layer pulls and the awslogs driver's streams. The second
# policy the template attached does not:
#
#   CloudWatchFullAccessV2   full CloudWatch, Logs, X-Ray, Application Insights, RUM and Synthetics on every
#                            resource in the account, plus logs:DeleteLogGroup. On a role whose job is to
#                            start a container, and whose log permissions are already in the policy above
#
# It is replaced by the statements below (rules.md A-5, second case: the template attached it in Terraform).
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  for_each   = toset(var.execution_policy_arns)
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = each.value
}
resource "aws_iam_role_policy" "ecs_task_execution_role" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  name = "TaskSecretInjectionPolicy"
  role = aws_iam_role.ecs_task_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # The user task definition's MYSQL_PASSWORD is a key selector on this one secret ARN, so one resource
      # entry covers it. No kms:Decrypt statement: the secret is encrypted with the AWS managed
      # aws/secretsmanager key, whose policy already allows Secrets Manager to decrypt on a caller's behalf.
      # A customer managed key would need one, and the failure without it names the secret rather than the
      # key - which sends you to check the secret's own policy, where nothing is wrong.
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.secret_arns
    }]
  })
}
