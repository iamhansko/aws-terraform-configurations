resource "aws_codecommit_repository" "target" {
  repository_name = var.target_account_repository
  description     = "Mirror target for CodeCommit repository replication from account ${var.source_account_id}"
}

resource "aws_iam_role" "cross_account_role" {
  name = var.cross_account_role_name

  # The source CodeBuild role does not exist when this root is applied first. IAM validates an ARN used as
  # Principal at role creation, so the always-existing source account root is the Principal; ArnEquals then
  # restricts successful assumptions to the one exact future CodeBuild role. The role name is the value the
  # two independent states agree in advance to break their cycle (rules.md I-2).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:${var.partition}:iam::${var.source_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnEquals = {
          "aws:PrincipalArn" = "arn:${var.partition}:iam::${var.source_account_id}:role/${var.source_codebuild_role_name}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "target_repository" {
  name = "CodeCommitReplicationTarget"
  role = aws_iam_role.cross_account_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codecommit:GitPull", "codecommit:GitPush"]
      Resource = aws_codecommit_repository.target.arn
    }]
  })

  # State the IAM binding order explicitly rather than relying only on the role/name references (rules.md D-1).
  depends_on = [aws_iam_role.cross_account_role, aws_codecommit_repository.target]
}
