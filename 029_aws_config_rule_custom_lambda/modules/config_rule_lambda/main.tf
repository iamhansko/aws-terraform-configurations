# The custom rule and the function that implements it.
#
# One module rather than two, because the three resources here are a single thing split across three
# APIs: the rule names the function as its source_identifier, the function needs a resource policy
# naming the rule's service as an allowed caller, and PutConfigRule refuses to create the rule until
# that policy exists. Separating them would mean passing an ARN out and a permission back in for no
# gain (the same reasoning as rules.md C-2, where an IRSA role and the chart that assumes it stay
# together).
#
# What the rule evaluates, since it is not obvious from the Terraform:
# lambda_src/lambda_function/index.py reads the EC2 instance's configuration item, finds the instance
# profile attached to it, resolves that profile's single role, and requires the role's attached
# managed policies to be exactly {AmazonS3ReadOnlyAccess}. An instance with no profile, a profile
# with no policies, or a profile whose role carries anything else is NON_COMPLIANT. It then fixes
# what it found - see remediation_policy_actions in variables.tf.
#
# One exemption is hardcoded in the Python rather than expressed here: an instance whose Name tag is
# "governance-bastion" is skipped. That is the workbench this project builds, and the skip is what
# stops the rule from stripping AdministratorAccess off the role the demo is run with. The caller's
# vscode_instance_name variable holds that constraint as a validation.
#
# The handler does speak the evaluation protocol correctly for the notification it implements: it
# json.loads event['invokingEvent'], reads the configurationItem out of it, and reports through
# config:PutEvaluations with event['resultToken'] and an OrderingTimestamp taken from the item's
# configurationItemCaptureTime. It reads no ruleParameters, which is consistent - this rule declares
# no input_parameters, so the policy it requires is a literal in the Python rather than something
# Terraform can set. Two gaps are worth knowing about before trusting what the rule reports, and
# neither is fixable from Terraform:
#
#   An oversized notification carries no configurationItem, so the handler returns before evaluating
#   and before reporting. See rule_message_types in variables.tf.
#
#   The remediation path calls put_evaluations twice with the same result token: once with
#   NON_COMPLIANT, then it rewrites the role, then it falls through to the final call with COMPLIANT.
#   Both carry the same OrderingTimestamp, so the second overwrites the first - which means the
#   non-compliant verdict this demo is about is usually not visible through
#   get-compliance-details-by-config-rule at all. The log is where it can be seen.
#
# A third gap was fixed in the Python, so it is recorded here rather than rediscovered. The handler
# originally evaluated every configuration item it was given, including the ResourceDeleted one
# Config sends when an instance terminates. That item's configuration is null, the chained .get on it
# raised AttributeError outside the try block, and nothing was reported - so the terminated instance
# kept its last verdict, Config's evaluation status showed no failure, and the stack trace in the log
# was the only sign. Terminating the demo's test instances hit it every time. The handler now checks
# configurationItemStatus and eventLeftScope first, the way AWS's rule examples do, and reports
# NOT_APPLICABLE for anything deleted, unrecorded or out of scope without reading its configuration.
resource "aws_cloudwatch_log_group" "lambda_function" {
  count = var.create_log_group ? 1 : 0

  name              = var.log_group_name
  retention_in_days = var.log_retention_days
}
resource "aws_iam_role" "lambda_role" {
  name_prefix = var.role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The _monolithic template's inline policy, kept rather than narrowed, with the logs statement scoped
# to this function's own log group.
#
# This is the one role in the original that was not handed AdministratorAccess, so there is nothing to
# narrow in the sense rules.md A-5 is about - the original already listed the actions the handler
# makes. The two things worth stating are why the IAM actions cannot be scoped to a resource, and
# which of them are not evaluation permissions at all:
#
#   Resource = "*" on the IAM statement is not laziness. The rule evaluates every EC2 instance
#   recorded in the account, so the instance profile it is asked about - and the role inside it - can
#   be anything, including profiles created long after this apply. Scoping it to the fixtures this
#   project creates would make the rule work on them and fail with AccessDenied on everything else,
#   which the handler catches and reports as NON_COMPLIANT with an "Error occurred" annotation. That
#   is a rule that looks like it is working.
#
#   config:PutEvaluations takes no resource either; it is how a custom rule reports anything at all.
#
# The logs statement is the one divergence: the original granted logs:* on arn:aws:logs:*:*:*, and it
# is scoped here to the group the function is configured to write to, because logging_config pins the
# destination so no wider grant can be used. CreateLogGroup is kept in the action list so the function
# still works when create_log_group is false.
resource "aws_iam_role_policy" "lambda_role" {
  name = var.inline_policy_name
  role = aws_iam_role.lambda_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = concat(var.evaluation_policy_actions, var.remediation_policy_actions)
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:${var.log_group_name}",
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:${var.log_group_name}:*",
        ]
      },
    ]
  })
}
resource "aws_lambda_function" "lambda_function" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_role.arn
  runtime       = var.runtime
  handler       = var.handler
  timeout       = var.timeout_seconds
  # Built by the caller, for the two reasons in providers.tf.
  filename         = var.filename
  source_code_hash = var.source_code_hash
  logging_config {
    log_group = var.log_group_name
    # cfn2tf noted that log_format is required by the provider and absent from the CloudFormation
    # template, and chose Text. Kept: the handler's output is print() calls and f-strings, so JSON
    # structured logging would wrap each line in an envelope without making any of it queryable.
    log_format = "Text"
  }

  # role orders this after the role but not after its inline policy, and nothing else here refers to
  # it. The function is created and invoked by Config regardless; without the policy every invocation
  # raises AccessDenied on the first IAM call, which the handler catches and turns into a
  # NON_COMPLIANT verdict annotated "Error occurred" - a working-looking rule with wrong answers
  # (rules.md D-1). The log group edge is ordering only: Lambda does not check that the configured
  # group exists, so without this the first invocation can create it itself and the retention this
  # module sets would land on an already-created group.
  depends_on = [
    aws_iam_role_policy.lambda_role,
    aws_cloudwatch_log_group.lambda_function,
  ]
}
# The resource policy that lets AWS Config invoke the function.
#
# source_arn is a wildcard over config-rule ids rather than this rule's ARN, as in the original, and
# it has to be: the rule's id is generated by Config when the rule is created, and the rule cannot be
# created until this permission exists. Narrowing it would be a genuine cycle. source_account closes
# most of what the wildcard opens.
resource "aws_lambda_permission" "lambda_permission" {
  function_name  = aws_lambda_function.lambda_function.function_name
  action         = "lambda:InvokeFunction"
  principal      = "config.amazonaws.com"
  source_account = var.account_id
  source_arn     = "arn:aws:config:${var.region}:${var.account_id}:config-rule/*"
}
resource "aws_config_config_rule" "config_rule" {
  name = var.rule_name
  # Without a scope the rule is invoked for every recorded configuration item in the account. With
  # it, Config filters before invoking, which matters here because the recorder records everything
  # except four IAM types.
  scope {
    compliance_resource_types = var.rule_resource_types
  }
  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = aws_lambda_function.lambda_function.arn
    dynamic "source_detail" {
      for_each = toset(var.rule_message_types)
      content {
        event_source = "aws.config"
        message_type = source_detail.value
      }
    }
  }

  # PutConfigRule tries the function before accepting the rule and rejects it with
  # InsufficientPermissionsException ("the AWS Lambda function cannot be invoked") when the resource
  # policy is not there yet. source_identifier orders this after the function and after nothing else,
  # so the edge is explicit (rules.md D-1). The _monolithic template had this one.
  #
  # Not expressed here, because it crosses a module boundary: this rule also cannot be created before
  # a configuration recorder exists - PutConfigRule answers
  # NoAvailableConfigurationRecorderException. The caller orders this module after
  # modules/config_recorder for that reason (rules.md D-2).
  depends_on = [aws_lambda_permission.lambda_permission]
}
