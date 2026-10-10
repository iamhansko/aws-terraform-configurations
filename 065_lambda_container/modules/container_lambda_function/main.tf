locals {
  # The name Lambda would give the group itself. Declaring the group under that name is what makes the
  # function write into it rather than create its own.
  log_group_name = "/aws/lambda/${var.function_name}"
}
resource "aws_iam_role" "execution" {
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
# for_each over the ARN list (rules.md B-7); literal ARNs, so toset is safe (rules.md B-8).
resource "aws_iam_role_policy_attachment" "execution" {
  for_each   = toset(concat(var.managed_policy_arns, var.additional_policy_arns))
  role       = aws_iam_role.execution.name
  policy_arn = each.value
}
# In place of the AmazonS3FullAccess the _monolithic template attached (rules.md A-5).
#
# The handler makes exactly one AWS call - put_object of one key into one bucket - and full S3 access let it
# read, overwrite and delete every object in every bucket in the account. This is that one call, on that one
# key. The original's breadth is one entry in additional_policy_arns away.
resource "aws_iam_role_policy" "write_result" {
  name = "WriteResultObject"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PutResultObject"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${var.result_bucket_arn}/${var.result_object_key}"
    }]
  })
}
# Declared rather than left for the function to create on its first invocation. A group Lambda creates itself
# is outside Terraform: it never expires and survives terraform destroy, one per function name ever used.
resource "aws_cloudwatch_log_group" "function" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days
}
# What lets the Lambda service pull this function's image, as the _monolithic template granted it.
#
# Same-account Lambda can add this statement to the repository by itself during CreateFunction, if the caller
# happens to hold ecr:SetRepositoryPolicy - and then the repository carries a policy Terraform does not know
# about. Declaring it keeps the policy in state. The aws:sourceArn condition, which the template did not have,
# limits the grant to functions in this account, as the Lambda documentation's example does.
#
# Account-wide (function:*) rather than this one function's ARN. The policy has to exist before CreateFunction,
# because Lambda pulls the image then, so it cannot read the function's ARN; and a pattern assembled from the
# name would make a typo in the region or account fail as an image pull error that names neither.
resource "aws_ecr_repository_policy" "lambda_pull" {
  repository = var.ecr_repository_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "LambdaECRImageRetrievalPolicy"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      Condition = {
        StringLike = {
          "aws:sourceArn" = "arn:${var.partition}:lambda:${var.region}:${var.account_id}:function:*"
        }
      }
    }]
  })
}
resource "aws_lambda_function" "function" {
  function_name = var.function_name
  role          = aws_iam_role.execution.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  timeout       = var.timeout
  memory_size   = var.memory_size
  # x86_64, fixed, because the image is built natively on the workbench, which is an x86_64 instance. An arm64
  # function running that image does not fail at create - it fails at every invocation with an exec format
  # error. The _monolithic template expressed the same thing as docker buildx --platform linux/amd64.
  architectures = ["x86_64"]
  environment {
    variables = var.environment_variables
  }
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.function.name
  }

  # Three things CreateFunction needs that no value reference here orders it after (rules.md D-1):
  #   - the role's policies. The role ARN orders this after the role only, and IAM is checked at create
  #   - the repository policy, because Lambda pulls the image during CreateFunction, not at first invoke
  #   - the log group, so the first invocation writes into the group with a retention rather than creating
  #     one without
  # The image itself has to be in the repository too, and that is the caller's edge: the root passes image_uri
  # out of a waiter's invocation result, so this resource cannot be created before the waiter has seen the tag.
  depends_on = [
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.write_result,
    aws_ecr_repository_policy.lambda_pull,
    aws_cloudwatch_log_group.function,
  ]
}
