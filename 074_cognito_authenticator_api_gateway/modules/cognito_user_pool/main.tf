data "aws_region" "current" {}
# The user pool, its one app client, the resource server whose scope the API checks, and the hosted domain and
# its managed login branding.
#
# One module because these are one thing from the outside: the client names the resource server's scope, the
# branding names the client, and the domain is meaningless without both. What is not here is anything that
# consumes the pool - the API's authorizer - which takes its ARN as an input.
resource "aws_cognito_user_pool" "pool" {
  name                = var.name
  user_pool_tier      = var.user_pool_tier
  deletion_protection = var.deletion_protection
  mfa_configuration   = var.mfa_configuration
  # The second factor, when MFA is on. OFF here, as the _monolithic template had it; the block exists so that
  # turning MFA on does not produce a pool with mode OPTIONAL and no factor, which Cognito refuses to create.
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
