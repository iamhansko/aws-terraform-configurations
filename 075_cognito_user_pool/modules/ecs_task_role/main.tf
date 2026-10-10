# The one task role both services run as, as the _monolithic template had it: the game server and the item
# image service both call Bedrock, and which of the rest each needs is decided in their code rather than here.
resource "aws_iam_role" "task" {
  name_prefix = var.name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "task" {
  name = "TaskPolicy"
  role = aws_iam_role.task.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem",
          "dynamodb:Query", "dynamodb:Scan", "dynamodb:BatchGetItem", "dynamodb:BatchWriteItem",
        ]
        Resource = var.dynamodb_table_arns
      },
      {
        # Any model, as the _monolithic template had it. Which models the services use is in their
        # configuration, not here, and an invocation of a model the account has not enabled fails in Bedrock
        # with AccessDeniedException whatever this policy says.
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:SignUp", "cognito-idp:InitiateAuth", "cognito-idp:GetUser",
          "cognito-idp:AdminConfirmSignUp", "cognito-idp:AdminGetUser", "cognito-idp:AdminUpdateUserAttributes",
        ]
        Resource = var.user_pool_arn
      },
      # The image bucket only. The _monolithic template granted these three on "*", which is every bucket in
      # the account - including the client bucket, so a compromised task could rewrite the game client every
      # player loads.
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.image_bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${var.image_bucket_arn}/*"
      },
    ]
  })
}
