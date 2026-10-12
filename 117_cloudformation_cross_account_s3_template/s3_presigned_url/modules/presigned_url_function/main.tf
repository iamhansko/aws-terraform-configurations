# A Lambda function that presigns one S3 object, and the one invocation that does it.
#
# Kept as a Lambda function because nothing in Terraform can produce a presigned URL - there is no data
# source for it - and because who signs is the point: the URL carries the signer's identity and expires no
# later than the signer's credentials do. A Lambda role session is short-lived, so a URL asked to last longer
# than that stops working early with "Request has expired", which is what the project's screenshots show.
data "archive_file" "presign" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/presign/index.py"
  output_path = "${path.module}/build/presign.zip"
}
resource "aws_iam_role" "presign" {
  name_prefix = "${trimsuffix(substr(var.function_name, 0, 30), "-")}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# Read on the one object, which is exactly what a URL signed by this role can do.
#
# The _monolithic template attached AmazonS3FullAccess here. Signing needs no permission at all - it is a
# local computation - but S3 evaluates the signer's permissions when the URL is used, so the role has to be
# allowed the GET. Full access meant the function could equally have produced a URL that deletes objects in
# any bucket in the account.
resource "aws_iam_role_policy" "presign" {
  name = "GetTemplateObject"
  role = aws_iam_role.presign.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = var.object_arn
    }]
  })
}
resource "aws_iam_role_policy_attachment" "presign_logs" {
  role       = aws_iam_role.presign.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# Declared so it is Terraform's and is deleted with the function, rather than created by Lambda on first run
# and left behind by every destroy.
resource "aws_cloudwatch_log_group" "presign" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_in_days
}
resource "aws_lambda_function" "presign" {
  function_name    = var.function_name
  runtime          = var.runtime
  handler          = "index.handler"
  role             = aws_iam_role.presign.arn
  timeout          = 30
  filename         = data.archive_file.presign.output_path
  source_code_hash = data.archive_file.presign.output_base64sha256
  # The role has to carry its policy before the first invocation, and role_arn alone does not order this
  # after it (rules.md D-1). The log group has to exist first or Lambda creates an unmanaged one.
  depends_on = [
    aws_iam_role_policy.presign,
    aws_iam_role_policy_attachment.presign_logs,
    aws_cloudwatch_log_group.presign,
  ]
}
# CREATE_ONLY, the default: the URL is produced once and kept in state. Re-running it is a deliberate act -
# see the root's regenerate command - because every run produces a different URL, and a plan that proposed a
# new one on every apply would make the output useless to copy.
resource "aws_lambda_invocation" "presign" {
  function_name = aws_lambda_function.presign.function_name
  input = jsonencode({
    S3Bucket    = var.bucket_name
    S3ObjectKey = var.object_key
    ExpiresIn   = var.expires_in_seconds
  })
  # A change to the handler produces a different URL, so it should produce a new invocation.
  triggers = {
    function_hash = data.archive_file.presign.output_base64sha256
  }
}
