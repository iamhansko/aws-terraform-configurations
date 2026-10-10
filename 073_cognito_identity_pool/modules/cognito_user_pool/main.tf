data "aws_region" "current" {}
# The user pool, its one app client, the resource server whose scope the API checks, the hosted domain and its
# managed login branding, and the groups.
#
# One module because these are one thing from the outside: the client names the resource server's scope, the
# branding names the client, and the domain is meaningless without both. What is not here is anything that
# consumes the pool - the API's authorizer, the identity pool - which take its ARN or ID as an input.
resource "aws_cognito_user_pool" "pool" {
  name                = var.name
  user_pool_tier      = var.user_pool_tier
  deletion_protection = var.deletion_protection
  mfa_configuration   = var.mfa_configuration
  # The second factor OPTIONAL refers to. The _monolithic template's EnabledMfas came through the conversion
  # as a commented-out TODO, which left mfa_configuration = "OPTIONAL" with no factor enabled - a pool Cognito
  # refuses to create.
  dynamic "software_token_mfa_configuration" {
    for_each = var.mfa_configuration == "OFF" ? [] : [1]
    content {
      enabled = true
    }
  }
  # Password as the first factor, which the conversion also dropped (SignInPolicy, a TODO). It is Cognito's
  # default, stated so the choice-based sign-in the client allows (ALLOW_USER_AUTH) has nothing else to offer.
  sign_in_policy {
    allowed_first_auth_factors = ["PASSWORD"]
  }
  auto_verified_attributes = ["email"]
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }
  # email only. The _monolithic template declared all twenty standard attributes, exported from a console
  # pool; every pool has them regardless, and declaring the unchanged ones only adds places for the provider
  # to see a difference in a schema that cannot be changed after creation. email is the one that differs from
  # its default, by being required.
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints {
      min_length = "0"
      max_length = "2048"
    }
  }
  username_configuration {
    case_sensitive = false
  }
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }
  # The pre token generation trigger, in Terraform where the _monolithic template set it from the workbench
  # with `aws cognito-idp update-user-pool --lambda-config ...`.
  #
  # That call was not a narrow change. UpdateUserPool resets every setting the request leaves out to its
  # default, so it also switched off email auto-verification and the MFA configuration - which is why the
  # original carried commented-out commands to put them back and an output linking to the console page for
  # re-enabling account confirmation by hand. Declared here, the trigger is part of the pool and nothing else
  # moves.
  dynamic "lambda_config" {
    for_each = var.pre_token_generation_lambda == null ? [] : [var.pre_token_generation_lambda]
    content {
      pre_token_generation_config {
        lambda_arn     = lambda_config.value.arn
        lambda_version = "V2_0"
      }
    }
  }
}
# Cognito invokes the trigger as cognito-idp.amazonaws.com, and only this pool may.
resource "aws_lambda_permission" "pre_token_generation" {
  count         = var.pre_token_generation_lambda == null ? 0 : 1
  statement_id  = "AllowCognitoPreTokenGeneration"
  action        = "lambda:InvokeFunction"
  function_name = var.pre_token_generation_lambda.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.pool.arn
}
resource "aws_cognito_resource_server" "resource_server" {
  user_pool_id = aws_cognito_user_pool.pool.id
  identifier   = var.resource_server.identifier
  name         = var.resource_server.name
  dynamic "scope" {
    for_each = var.resource_server.scopes
    content {
      scope_name        = scope.key
      scope_description = scope.value
    }
  }
}
resource "aws_cognito_user_pool_client" "client" {
  name                   = var.client_name
  user_pool_id           = aws_cognito_user_pool.pool.id
  auth_session_validity  = 3
  refresh_token_validity = 5
  access_token_validity  = 60
  id_token_validity      = 60
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
  explicit_auth_flows                           = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_AUTH", "ALLOW_USER_SRP_AUTH"]
  supported_identity_providers                  = ["COGNITO"]
  callback_urls                                 = var.callback_urls
  allowed_oauth_flows                           = ["code", "implicit"]
  allowed_oauth_scopes                          = concat(var.standard_oauth_scopes, local.custom_scopes)
  allowed_oauth_flows_user_pool_client          = true
  prevent_user_existence_errors                 = "ENABLED"
  enable_token_revocation                       = true
  enable_propagate_additional_user_context_data = false
  # A client may only name custom scopes that exist, and the scope names are strings here rather than
  # references to the resource server (rules.md D-1).
  depends_on = [aws_cognito_resource_server.resource_server]
}
locals {
  custom_scopes = [for name in keys(var.resource_server.scopes) : "${var.resource_server.identifier}/${name}"]
}
# Managed login (version 2), which is what the branding below styles. The classic hosted UI ignores it.
resource "aws_cognito_user_pool_domain" "domain" {
  domain                = var.domain_prefix
  user_pool_id          = aws_cognito_user_pool.pool.id
  managed_login_version = 2
}
# The branding document and its background image as files, where the _monolithic template inlined both: a
# 550 KB PNG as one base64 string and the settings as 440 lines of HCL, between them 99 percent of a
# 768 KB .tf file. filebase64() produces exactly the string the template carried.
resource "aws_cognito_managed_login_branding" "branding" {
  user_pool_id = aws_cognito_user_pool.pool.id
  client_id    = aws_cognito_user_pool_client.client.id
  asset {
    bytes      = filebase64(var.branding_background_image_path)
    category   = "PAGE_BACKGROUND"
    color_mode = "LIGHT"
    extension  = "PNG"
  }
  # Re-encoded so the value is the same compact JSON whatever the file's formatting.
  settings   = jsonencode(jsondecode(file(var.branding_settings_path)))
  depends_on = [aws_cognito_user_pool_domain.domain]
}
# Literal names known at plan, so toset is safe (rules.md B-7/B-8).
#
# The groups only, never their members. Users come into the pool by signing up on the workshop's pages, and
# who joins which group is the participant's step - that membership turning into an access token scope is
# what the workshop demonstrates - so this module declares no aws_cognito_user_in_group.
resource "aws_cognito_user_group" "group" {
  for_each     = toset(var.groups)
  name         = each.value
  user_pool_id = aws_cognito_user_pool.pool.id
}
