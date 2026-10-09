# The masking function: its code package, its role, and the permission that lets S3 invoke it.
#
# The permission belongs with the function rather than with the bucket. aws_lambda_permission is a resource
# policy on the function - it is the function saying who may call it - and a function deployed without one is
# a function S3 cannot reach. Keeping them together means there is no way to create one without the other.
#
# This data source is read at plan time because this module carries no depends_on. A module blocked behind
# depends_on has its data sources deferred to apply along with its resources (rules.md D-6) - harmless for an
# account id, which feeds neither a for_each key nor a resource address, but worth knowing before anyone adds
# an ordering edge to this module block.
data "aws_caller_identity" "current" {}
# source_dir, where the _monolithic template used source_file.
#
# A single file is correct until the handler grows a second one, and then the second one is quietly missing
# from the package: the function deploys, and every invocation fails with ModuleNotFoundError for a file that
# is sitting right next to index.py in the repository. Zipping the directory makes adding a file a change in
# the plan.
data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.source_directory
  output_path = "${path.module}/build/${var.function_name}.zip"
}
resource "aws_iam_role" "function" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# One resource with for_each over the policy list, rather than the _0 and _1 attachment resources the
# conversion produced for the two policies the template attached (rules.md B-7). A caller can now add or drop
# a policy without this module changing.
#
# toset is safe because the ARNs are literal strings in configuration and so are known at plan time. The same
# expression over a list of IDs coming from another module would fail with "Invalid for_each argument", and
# the fix there is a map with caller-chosen keys (rules.md B-8) - that case does occur in this repository, in
# the boto3_sqs_client variant's security group sources.
resource "aws_iam_role_policy_attachment" "function" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.function.name
  policy_arn = each.value
}
# Only created when the caller actually has statements to add: IAM rejects a policy document with an empty
# Statement array, so a count of zero is the difference between "no inline policy" and a failed apply.
resource "aws_iam_role_policy" "function" {
  count = length(var.additional_policy_statements) > 0 ? 1 : 0

  name = "additional"
  role = aws_iam_role.function.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.additional_policy_statements
  })
}
resource "aws_lambda_function" "function" {
  function_name    = var.function_name
  role             = aws_iam_role.function.arn
  runtime          = var.runtime
  handler          = var.handler
  timeout          = var.timeout
  memory_size      = var.memory_size
  filename         = data.archive_file.source.output_path
  source_code_hash = data.archive_file.source.output_base64sha256

  dynamic "environment" {
    for_each = length(var.environment_variables) == 0 ? [] : [var.environment_variables]
    content {
      variables = environment.value
    }
  }

  # role is an ARN reference, so the graph orders this after the role itself and after nothing else -
  # Terraform has no way to know the policies have to be attached first (rules.md D-1). Without this the
  # attachments can land after the function, and the window is not theoretical: an upload during it invokes a
  # function whose role cannot read the object or write a log line, so it fails with AccessDenied and leaves
  # nothing behind to say why.
  depends_on = [aws_iam_role_policy_attachment.function, aws_iam_role_policy.function]
}
# What makes the bucket able to invoke this function at all. Without it the bucket's notification
# configuration is rejected outright: S3 test-invokes the target while PutBucketNotificationConfiguration is
# being applied, and the apply fails with "Unable to validate the following destination configurations".
#
# source_account alongside source_arn, as the template had it. The ARN of a bucket contains no account id, so
# source_arn alone is a name-based condition - and bucket names are global. Pinning the account closes the
# gap where someone else's bucket of the same name, created after this one is deleted, could invoke this
# function.
resource "aws_lambda_permission" "allow_s3_invoke" {
  function_name  = aws_lambda_function.function.function_name
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_arn     = var.source_bucket_arn
  source_account = data.aws_caller_identity.current.account_id
}
locals {
  # Not a declared resource. Lambda creates this group on the function's first invocation, with retention set
  # to never expire, and the name is not a choice - the runtime writes to exactly this path. The _monolithic
  # template did not declare it either, so this is reproduced rather than improved, and the consequences are
  # that the group outlives terraform destroy and keeps the demo's log lines forever.
  #
  # Declaring an aws_cloudwatch_log_group with this exact name would make retention settable and would let
  # destroy take the logs with it. The boto3_sqs_client variant next door does declare one, because a single
  # run of its load generator produces tens of thousands of log lines and keeping those forever is a real
  # cost. Here the volume is one log entry per uploaded file, so the original's behaviour is reproduced rather
  # than improved - the trade being that these logs survive terraform destroy.
  log_group_name = "/aws/lambda/${var.function_name}"
}
