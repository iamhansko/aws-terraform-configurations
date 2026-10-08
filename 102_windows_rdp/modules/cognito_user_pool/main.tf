# The pool and its app client are one module rather than two.
#
# They are a single component the way an IRSA role and its Helm release are
# (rules.md C-2): the client is meaningless without the pool, user_pool_id is the
# only way to attach one, and nothing in this project would ever create a second
# client against a pool it does not own. Splitting them would mean a module whose
# entire interface is "give me a pool id".
resource "aws_cognito_user_pool" "user_pool" {
  name = var.name

  admin_create_user_config {
    allow_admin_create_user_only = var.allow_admin_create_user_only
  }
  password_policy {
    minimum_length    = var.password_policy.minimum_length
    require_lowercase = var.password_policy.require_lowercase
    require_numbers   = var.password_policy.require_numbers
    require_symbols   = var.password_policy.require_symbols
    require_uppercase = var.password_policy.require_uppercase
  }
  # A dynamic block over a map whose keys are configuration literals, rather than
  # the two hand-written schema blocks the conversion produced. The keys are the
  # attribute names, which is what makes the plan readable - a schema block
  # identified only by its position in a list is impossible to match against a
  # plan diff.
  dynamic "schema" {
    for_each = var.schema_attributes
    content {
      name                = schema.key
      attribute_data_type = schema.value.attribute_data_type
      required            = schema.value.required
      mutable             = schema.value.mutable
    }
  }
  username_attributes = var.username_attributes
  username_configuration {
    case_sensitive = var.username_case_sensitive
  }
  user_pool_add_ons {
    advanced_security_mode = var.advanced_security_mode
  }

  lifecycle {
    # A pool's schema, username_attributes and username_configuration are all
    # immutable in Cognito, so changing any of them is a replacement - and a
    # replacement discards every registered player. The game server reads the
    # pool id out of its environment, which the userdata baked in at launch, so a
    # replaced pool also leaves the running server pointed at a pool that no
    # longer exists until the instance is rebuilt.
    #
    # Terraform will say "forces replacement" in the plan. This precondition
    # exists for the case where it does not get read.
    precondition {
      condition     = length(var.schema_attributes) > 0 && length(var.username_attributes) > 0
      error_message = "schema_attributes and username_attributes must both be non-empty. Emptying either one is a pool replacement that discards every registered player and strands the running game server on a pool id that no longer resolves."
    }
  }
}
resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id                  = aws_cognito_user_pool.user_pool.id
  name                          = var.client_name
  generate_secret               = var.generate_secret
  prevent_user_existence_errors = var.prevent_user_existence_errors
  explicit_auth_flows           = var.explicit_auth_flows
  access_token_validity         = var.token_validity.access_token_validity
  id_token_validity             = var.token_validity.id_token_validity
  refresh_token_validity        = var.token_validity.refresh_token_validity

  # Required whenever any of the three validity numbers above is set. Omit it and
  # Cognito reads all three in minutes, so the 1 that was meant to be an hour
  # becomes a token that expires a minute after it is issued - which shows up as
  # players being logged out mid-game, not as an error.
  token_validity_units {
    access_token  = var.token_validity.access_token_units
    id_token      = var.token_validity.id_token_units
    refresh_token = var.token_validity.refresh_token_units
  }
}
