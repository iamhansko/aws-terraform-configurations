variable "name" {
  type        = string
  default     = "spirit-of-kiro-user-pool"
  description = "Name of the user pool"

  validation {
    condition     = can(regex("^[\\w\\s+=,.@-]{1,128}$", var.name))
    error_message = "name must be 1-128 characters from the set Cognito accepts for a user pool name (letters, digits, whitespace and +=,.@-)."
  }
}
variable "client_name" {
  type        = string
  default     = "spirit-of-kiro-client"
  description = "Name of the app client the game server authenticates through"

  validation {
    condition     = can(regex("^[\\w\\s+=,.@-]{1,128}$", var.client_name))
    error_message = "client_name must be 1-128 characters from the set Cognito accepts for an app client name (letters, digits, whitespace and +=,.@-)."
  }
}
variable "allow_admin_create_user_only" {
  type        = bool
  default     = false
  description = "Whether only an administrator may create users. False, as the _monolithic template had it, and the project depends on it: the game client signs players up itself, so flipping this to true makes every sign-up fail with NotAuthorizedException while the pool still looks correctly configured"
}
variable "username_attributes" {
  type        = list(string)
  default     = ["email"]
  description = "Attributes usable as the sign-in name, as the _monolithic template had it. Immutable after creation - changing it replaces the pool and every user in it"

  validation {
    condition     = length(var.username_attributes) > 0 && alltrue([for attribute in var.username_attributes : contains(["email", "phone_number"], attribute)])
    error_message = "username_attributes must be a non-empty subset of email and phone_number, the only two values Cognito accepts here."
  }
}
variable "username_case_sensitive" {
  type        = bool
  default     = false
  description = "Whether sign-in names are case sensitive. False, as the _monolithic template had it, so Player@example.com and player@example.com are the same account. Immutable after creation"
}
variable "advanced_security_mode" {
  type        = string
  default     = "OFF"
  description = "Threat protection level, as the _monolithic template had it. OFF is also the default, but it is declared explicitly because AUDIT and ENFORCED are billed per monthly active user"

  validation {
    condition     = contains(["OFF", "AUDIT", "ENFORCED"], var.advanced_security_mode)
    error_message = "advanced_security_mode must be OFF, AUDIT or ENFORCED."
  }
}
variable "password_policy" {
  type = object({
    minimum_length    = number
    require_lowercase = bool
    require_numbers   = bool
    require_symbols   = bool
    require_uppercase = bool
  })
  default = {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  description = "Password rules for pool users, as the _monolithic template had them. These govern the game's player accounts and have nothing to do with the RDP password the app_secret module generates - two separate credentials that are easy to conflate because both live in this project"

  validation {
    condition     = var.password_policy.minimum_length >= 6 && var.password_policy.minimum_length <= 99
    error_message = "password_policy.minimum_length must be between 6 and 99, the range Cognito accepts."
  }
}
variable "schema_attributes" {
  type = map(object({
    attribute_data_type = optional(string, "String")
    required            = optional(bool, true)
    mutable             = optional(bool, true)
  }))
  default = {
    email              = {}
    preferred_username = {}
  }
  description = <<-DESC
    Standard attributes declared on the pool, keyed by attribute name. The two defaults are what the
    _monolithic template declared.

    Keys are literal strings in configuration, so they are known at plan time and safe as the for_each of
    the dynamic schema block (rules.md B-8).

    Worth knowing before changing this: a pool's schema is append-only. Cognito has no API to remove an
    attribute or to change whether one is required, so dropping an entry here or flipping required
    produces a plan that replaces the entire pool - and with it every registered player.
  DESC

  validation {
    condition     = length(var.schema_attributes) > 0
    error_message = "schema_attributes must declare at least one attribute."
  }
  validation {
    condition     = alltrue([for attribute in values(var.schema_attributes) : contains(["String", "Number", "DateTime", "Boolean"], attribute.attribute_data_type)])
    error_message = "schema_attributes attribute_data_type must be String, Number, DateTime or Boolean."
  }
  validation {
    # A required attribute that is not mutable can never be filled in after
    # sign-up, so every sign-up that omits it fails permanently. Cognito accepts
    # the combination and only the sign-up call reports it.
    condition     = alltrue([for attribute in values(var.schema_attributes) : attribute.mutable || !attribute.required])
    error_message = "A schema attribute that is required must also be mutable, otherwise Cognito accepts the pool and rejects every sign-up that does not supply the attribute up front."
  }
}
variable "generate_secret" {
  type        = bool
  default     = false
  description = "Whether the app client gets a secret. False, as the _monolithic template had it, and correct for this client: the game client is browser JavaScript, which cannot hold a secret, and USER_PASSWORD_AUTH from a client with a secret requires a SECRET_HASH the browser cannot compute"
}
variable "prevent_user_existence_errors" {
  type        = string
  default     = "ENABLED"
  description = "Whether a failed sign-in says whether the account exists. ENABLED, as the _monolithic template had it, which returns the same error either way"

  validation {
    condition     = contains(["ENABLED", "LEGACY"], var.prevent_user_existence_errors)
    error_message = "prevent_user_existence_errors must be ENABLED or LEGACY."
  }
}
variable "explicit_auth_flows" {
  type        = list(string)
  default     = ["USER_PASSWORD_AUTH"]
  description = "Auth flows the client may use, as the _monolithic template had it. The game server calls InitiateAuth with USER_PASSWORD_AUTH; removing it makes every login fail with InvalidParameterException: USER_PASSWORD_AUTH flow not enabled for this client"

  validation {
    condition = length(var.explicit_auth_flows) > 0 && alltrue([for flow in var.explicit_auth_flows : contains([
      "ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH",
      "ALLOW_CUSTOM_AUTH", "ALLOW_ADMIN_USER_PASSWORD_AUTH", "ALLOW_USER_AUTH",
      "USER_PASSWORD_AUTH", "CUSTOM_AUTH_FLOW_ONLY", "ADMIN_NO_SRP_AUTH",
    ], flow)])
    error_message = "explicit_auth_flows must be a non-empty list of flows Cognito accepts, either the legacy names (USER_PASSWORD_AUTH, ADMIN_NO_SRP_AUTH, CUSTOM_AUTH_FLOW_ONLY) or the ALLOW_* names. Mixing the two families in one client is rejected by Cognito at apply time."
  }
}
variable "token_validity" {
  type = object({
    access_token_validity  = number
    access_token_units     = string
    id_token_validity      = number
    id_token_units         = string
    refresh_token_validity = number
    refresh_token_units    = string
  })
  default = {
    access_token_validity  = 1
    access_token_units     = "hours"
    id_token_validity      = 1
    id_token_units         = "hours"
    refresh_token_validity = 30
    refresh_token_units    = "days"
  }
  description = "Token lifetimes, as the _monolithic template had them. The numbers are meaningless without their units - the same 1 means one hour or one minute depending on the unit - so they are one object rather than six variables that can drift apart"

  validation {
    condition = alltrue([for units in [var.token_validity.access_token_units, var.token_validity.id_token_units, var.token_validity.refresh_token_units] :
    contains(["seconds", "minutes", "hours", "days"], units)])
    error_message = "token validity units must be seconds, minutes, hours or days."
  }
  validation {
    # Cognito's own bounds. An access or id token must be between 5 minutes and
    # 24 hours, and a refresh token between 60 minutes and 10 years, so the
    # checks below are expressed in the smallest shared unit.
    condition = alltrue([
      var.token_validity.access_token_validity > 0,
      var.token_validity.id_token_validity > 0,
      var.token_validity.refresh_token_validity > 0,
    ])
    error_message = "token validity values must all be greater than zero. Cognito rejects zero, and a refresh token shorter than the access token logs every player out an hour into the session."
  }
}
