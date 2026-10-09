# The task role and the task execution role, shared by both application stacks.
#
# A separate module, and not part of modules/app_stack, because the _monolithic template declared
# one of each and both task definitions pointed at them. Giving each stack its own pair would be
# better isolation and would let each policy name one stack's resources - which is exactly what
# modules/app_stack does do for its CodeDeploy, CodePipeline and EventBridge roles. The split is
# not arbitrary:
#
#   per stack    the policy names resources only that stack has - its pipeline ARN, its two
#                buckets, its deployment group. A shared role would need a union of them, which
#                is a wildcard by the second stack.
#   shared       the policy names resources both stacks use - the one credential secret, the one
#                KMS key, the one log group prefix. Splitting it would produce two identical
#                policies and two more roles to read.
#
# Both roles here are the second case.
resource "aws_iam_role" "ecs_task_role" {
  name_prefix = var.task_role_name_prefix
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
# PowerUserAccess replaced, which is a narrowing of what the _monolithic template did in Terraform
# rather than a reconstruction of something it hid in a script - so rules.md A-5's second case
# applies and the reason belongs here.
#
# PowerUserAccess is every action on every service except IAM and Organizations. What the task role
# is actually used by, in this project, is the FireLens sidecar: the awsfirelens log driver on the
# application container hands its output to the fluent-bit container, and fluent-bit calls
# CloudWatch Logs with the task role's credentials, not the execution role's. That is the whole
# list - the application binaries make no AWS calls at all, and the database credential arrives as
# an environment variable injected by the execution role before the container starts.
#
# Getting this wrong is quiet. Without the log permissions the tasks run and serve traffic
# normally, fluent-bit retries in the background, and the two log widgets on the dashboard stay
# empty with no error anywhere a person would look.
resource "aws_iam_role_policy" "ecs_task_role" {
  name = "FireLensCloudWatchLogsPolicy"
  role = aws_iam_role.ecs_task_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        # CreateLogGroup because the cloudwatch output plugin is configured with
        # auto_create_group, and PutRetentionPolicy because it sets one on a group it created.
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:PutRetentionPolicy",
        "logs:DescribeLogStreams",
      ]
      Resource = var.log_group_arn_patterns
    }]
  })
}
# Left empty by default, which is rules.md A-5's shape for an extension point: the switch to turn
# something on is open, and its default does not turn it on. A variable whose default is a broad
# policy stays broad no matter what the description says.
resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  for_each   = toset(var.additional_task_policy_arns)
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = each.value
}
resource "aws_iam_role" "ecs_task_execution_role" {
  name_prefix = var.execution_role_name_prefix
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
# AmazonECSTaskExecutionRolePolicy stays - it is the AWS service-role policy for exactly this role
# and covers the ECR authorization token, the layer pulls and the awslogs driver. The other two the
# _monolithic template attached do not:
#
#   SecretsManagerReadWrite   read and write on every secret in the account, plus
#                             secretsmanager:DeleteSecret. The role reads one secret.
#   PowerUserAccess           every action on every service except IAM and Organizations, on a
#                             role whose job is to start a container.
#
# Both are replaced by the inline policy below (rules.md A-5, second case: the template attached
# these in Terraform, so narrowing them changes what the original did).
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  for_each   = toset(var.execution_policy_arns)
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = each.value
}
resource "aws_iam_role_policy" "ecs_task_execution_role" {
  name = "TaskSecretsAndLogGroupPolicy"
  role = aws_iam_role.ecs_task_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # The three secret references in each task definition - DB_URL, DB_USER and DB_PASSWD -
        # are all key selectors on this one secret ARN, so one resource covers all six.
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.secret_arns
      },
      {
        # Required because the secret is encrypted with a customer managed key. Without it the
        # GetSecretValue succeeds at the IAM layer and fails at the KMS layer, and the task's
        # stopped reason names the secret rather than the key - so the obvious next step is to
        # check the secret policy, which is not the problem.
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [var.kms_key_arn]
      },
      {
        # The log_router container's own awslogs driver is configured with
        # awslogs-create-group, and creating a group is not in
        # AmazonECSTaskExecutionRolePolicy. Without this the sidecar fails to start and the
        # application container goes with it, because both are marked essential.
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup"]
        Resource = var.log_group_arn_patterns
      },
    ]
  })
}
