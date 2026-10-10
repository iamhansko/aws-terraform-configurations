# An identity pool that exchanges a user pool sign-in - or no sign-in at all - for temporary AWS credentials,
# and the two roles those credentials belong to.
resource "aws_cognito_identity_pool" "pool" {
  identity_pool_name               = var.name
  allow_classic_flow               = false
  allow_unauthenticated_identities = var.allow_unauthenticated_identities
  cognito_identity_providers {
    client_id               = var.user_pool_client_id
    provider_name           = var.user_pool_endpoint
    server_side_token_check = false
  }
}
locals {
  # Who may assume each role: only identities of this pool, and only in the matching state. Without the aud
  # condition, any identity pool in any account could hand out this role.
  assume_role = {
    for amr in ["authenticated", "unauthenticated"] : amr => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = "cognito-identity.amazonaws.com" }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals             = { "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.pool.id }
          "ForAnyValue:StringLike" = { "cognito-identity.amazonaws.com:amr" = amr }
        }
      }]
    })
  }
}
resource "aws_iam_role" "authenticated" {
  name_prefix        = "${substr(var.name, 0, 20)}-auth-"
  assume_role_policy = local.assume_role["authenticated"]
}
resource "aws_iam_role" "unauthenticated" {
  name_prefix        = "${substr(var.name, 0, 20)}-unauth-"
  assume_role_policy = local.assume_role["unauthenticated"]
}
# What a signed-in browser can do with the credentials: list the demo bucket, which is the workshop's Access
# S3 tab.
#
# The _monolithic template's policy was the old Amplify sample: cognito-identity:*, cognito-sync:* and
# mobileanalytics:PutEvents on "*", plus s3:List* on "*". The first three are not needed to obtain the
# credentials - GetId and GetCredentialsForIdentity are unauthenticated calls - and cognito-identity:* handed
# every signed-in visitor DeleteIdentityPool on this pool; Cognito Sync and Mobile Analytics are retired.
# s3:List* on "*" let them list every bucket in the account, which the page then displayed.
resource "aws_iam_role_policy" "authenticated" {
  name = "Cognito-authenticated"
  role = aws_iam_role.authenticated.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = var.listable_bucket_arns
    }]
  })
}
# Nothing for guests. The _monolithic template granted cognito-identity:GetCredentialsForIdentity, which is
# the call that obtains these credentials in the first place and needs no IAM permission. A role with no
# policy still exists, so unauthenticated identities still work - they can do nothing with what they get.
resource "aws_cognito_identity_pool_roles_attachment" "roles" {
  identity_pool_id = aws_cognito_identity_pool.pool.id
  roles = {
    authenticated   = aws_iam_role.authenticated.arn
    unauthenticated = aws_iam_role.unauthenticated.arn
  }
}
