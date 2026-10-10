# The game's user pool and the app client its server signs players in through.
#
# The server calls Cognito itself - SignUp, InitiateAuth with USER_PASSWORD_AUTH, AdminConfirmSignUp - so there
# is no hosted domain and no OAuth flow here, only the client those API calls name.
resource "aws_cognito_user_pool" "pool" {
  name = var.name
  # Players sign in with their email address; preferred_username is the name the game shows.
  username_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  # Both standard attributes, made required. The constraints are the values Cognito stores for a standard
  # string attribute whether or not they are given; stating them keeps every plan after the first from
  # proposing to replace the pool over a schema it cannot change in place.
  dynamic "schema" {
    for_each = toset(["email", "preferred_username"])
    content {
      name                     = schema.value
      attribute_data_type      = "String"
      required                 = true
      mutable                  = true
      developer_only_attribute = false
      string_attribute_constraints {
        min_length = "0"
        max_length = "2048"
      }
    }
  }
  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }
}
resource "aws_cognito_user_pool_client" "client" {
  name                          = var.client_name
  user_pool_id                  = aws_cognito_user_pool.pool.id
  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows           = ["USER_PASSWORD_AUTH"]
  access_token_validity         = 1
  id_token_validity             = 1
  refresh_token_validity        = 30
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}
