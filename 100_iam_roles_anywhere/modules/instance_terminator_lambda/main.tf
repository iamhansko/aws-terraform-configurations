# Terminates the export instance, so the demo does not leave a host running with a private key on
# its disk. One function, the role it runs as, and one invocation of it.
#
# Named for what it does. The _monolithic template called it CustomResourceLambdaFunction because
# that is what it was - a CloudFormation custom resource - and that is exactly the part of it that
# could not survive the conversion. The original handler imported cfnresponse, read
# event['RequestType'] and POSTed its result to event['ResponseURL']; cfnresponse is injected by
# AWS only into functions whose code was inlined as ZipFile, there is no ResponseURL outside a
# custom resource, and aws_lambda_invocation does a synchronous invoke and reads the return value.
# 102_windows_rdp hit the same defect and dropped its function entirely.
#
# Here it was repaired instead, because unlike that one this function does something that is still
# needed. lambda_src/custom_resource_lambda_function/index.py now imports only boto3, takes the
# instance ids and the objects to wait for from the event, waits until those objects are in S3,
# and returns what it verified and what it terminated - its docstring records each change. So the
# invocation below works, and the things it needs to keep working are: the handler matching
# index.lambda_handler, the input carrying instance_ids and wait_for_export, a timeout long enough
# to cover the bootstrap, and the function never again being asked to speak the custom resource
# protocol.
#
# The wait is in here, rather than in an SSM association the invocation depends on, because the
# association could not hold the apply - the root main.tf has the timeline from CloudTrail. The
# function that does the irreversible thing is the one place a wait cannot be skipped.
resource "aws_iam_role" "instance_terminator_lambda_iam_role" {
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
# The three calls the function makes.
#
# The _monolithic template granted ec2:* on *, which is the same A-5 judgement as the instance
# role: the template really did write it, so narrowing it is changing what the original did and the
# requirement is to say so (rules.md A-5). This function calls describe_instances and
# terminate_instances on EC2 and list_objects_v2 on S3, and nothing else - the source is in the
# repository - so the grant is those three calls.
#
# The EC2 resource stays *. DescribeInstances cannot be scoped to a resource at all, and
# TerminateInstances could be scoped to instance ARNs only by building one from a partition,
# region and account this module is not given. The S3 statement is scoped to the one bucket, and it
# is ListBucket alone: the function sees that the objects exist and when they were written, and
# never reads one - one of them is an unencrypted private key.
resource "aws_iam_role_policy" "instance_terminator_lambda_iam_role" {
  name = "wait-and-terminate-instances"
  role = aws_iam_role.instance_terminator_lambda_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeAndTerminate"
        Effect   = "Allow"
        Action   = var.policy_actions
        Resource = "*"
      },
      {
        Sid      = "SeeTheExportArrive"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.wait_bucket_arn
      },
    ]
  })
}
# for_each rather than one attachment per policy (rules.md B-7); toset is safe because these are
# configuration literals, known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "instance_terminator_lambda_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.instance_terminator_lambda_iam_role.name
  policy_arn = each.value
}
resource "aws_lambda_function" "instance_terminator" {
  function_name = var.function_name
  role          = aws_iam_role.instance_terminator_lambda_iam_role.arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.timeout_seconds
  # The zip and its hash are built by the caller, not here. archive_file resolves its source
  # against path.module, and the Python lives at the root of the project rather than inside this
  # module - so a data source here would look for modules/instance_terminator_lambda/lambda_src
  # and find nothing. Keeping it in the root also keeps it out of a module that carries depends_on,
  # which would defer the read to apply (rules.md D-6).
  filename         = var.filename
  source_code_hash = var.source_code_hash

  # Lambda checks that it can assume the role while creating the function, and a role whose trust
  # policy has not propagated yet is reported as
  #
  #   InvalidParameterValueException: The role defined for the function cannot be assumed by Lambda
  #
  # which is intermittent and reads like a misconfigured trust policy. The role ARN reference
  # orders this after the role but not after anything attached to it (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.instance_terminator_lambda_iam_role]
}
# The synchronous invoke that waits for the export and then shuts the instance down.
#
# Synchronous is what makes the wait hold the apply: the provider does not return until the
# function does, so for the length of the bootstrap this resource shows "Still creating..." and
# nothing ordered after it starts. When the export never arrives the function raises at its
# timeout, the apply fails here, and the instance is deliberately left running so its log can be
# read.
#
# The instance id and the objects to wait for travel in the input rather than in the function's
# source, where the template put the id with Fn::Sub. Terraform cannot interpolate into a file that
# archive_file zips, and baking resource attributes into the code would rebuild the deployment
# package every time the instance changed.
#
# Worth knowing about the next apply: the instance this terminated is gone, so Terraform plans to
# recreate it, recreating it changes the input here, and a changed input re-invokes this - which
# waits for the new instance's export (objects older than its launch do not count) and terminates
# it. That loop is the design working rather than drift.
resource "aws_lambda_invocation" "terminate_instances" {
  function_name = aws_lambda_function.instance_terminator.arn
  input = jsonencode({
    instance_ids = var.instance_ids
    wait_for_export = {
      bucket = var.wait_bucket_name
      keys   = var.wait_object_keys
    }
  })

  # The inline policy, not just the function. An invocation that races the policy runs the handler
  # against a role that cannot yet describe, list or terminate. The wait retries AccessDenied, so a
  # policy that is merely late costs a poll or two; one that is missing entirely ends in the
  # function's timeout, and the final call in
  #
  #   UnauthorizedOperation: You are not authorized to perform this operation
  #
  # Either is an ordering failure and not a configuration one (rules.md D-1).
  #
  # Nothing outside this module has to hold the invocation back any more. It used to wait on the
  # caller's SSM association, which was supposed to finish only after the upload and in practice
  # reported Success before its command had even been sent. The wait now lives in the function.
  depends_on = [aws_iam_role_policy.instance_terminator_lambda_iam_role]
}
