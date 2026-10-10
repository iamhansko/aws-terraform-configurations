variable "name" {
  type        = string
  default     = "BuilderClass01"
  description = "Name of the user pool, as the _monolithic template had it. Not unique - a second pool of the same name is a second pool"

  validation {
    condition     = can(regex("^[\\w\\s+=,.@-]{1,128}$", var.name))
    error_message = "name must be 1-128 characters of letters, digits, spaces and _+=,.@-."
  }
}
variable "user_pool_tier" {
  type        = string
  default     = "ESSENTIALS"
  description = "Feature plan of the pool, as the _monolithic template had it. ESSENTIALS is the lowest tier with managed login branding and access token customization, both of which this project uses"

  validation {
    condition     = contains(["ESSENTIALS", "PLUS"], var.user_pool_tier)
    error_message = "user_pool_tier must be ESSENTIALS or PLUS - LITE has neither managed login branding nor V2_0 pre token generation, and the pool would be created and then reject them."
  }
}
variable "deletion_protection" {
  type        = string
  default     = "INACTIVE"
  description = "Whether the pool refuses deletion, as the _monolithic template had it. ACTIVE makes terraform destroy fail until it is switched off"

  validation {
    condition     = contains(["ACTIVE", "INACTIVE"], var.deletion_protection)
    error_message = "deletion_protection must be ACTIVE or INACTIVE."
  }
}
variable "mfa_configuration" {
  type        = string
  default     = "OPTIONAL"
  description = "MFA mode. OPTIONAL with an authenticator app (TOTP) as the factor, as the _monolithic template meant it - the workshop page enrols a user in TOTP"

  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.mfa_configuration)
    error_message = "mfa_configuration must be OFF, ON or OPTIONAL."
  }
}
variable "pre_token_generation_lambda" {
  type = object({
    arn           = string
    function_name = string
  })
  default     = null
  description = "Lambda function Cognito calls before issuing tokens, as a V2_0 trigger (access token customization). Null attaches none"
}
variable "resource_server" {
  type = object({
    identifier = string
    name       = string
    scopes     = map(string)
  })
  default = {
    identifier = "petstore"
    name       = "petstoreAPI"
    scopes = {
      read = "Get All Pets"
    }
  }
  description = "The resource server and its scopes (scope name to description), as the _monolithic template had them. The client is allowed every scope here, as <identifier>/<scope>"

  validation {
    condition     = can(regex("^[\\x21\\x23-\\x2E\\x30-\\x5B\\x5D-\\x7E]{1,256}$", var.resource_server.identifier))
    error_message = "resource_server.identifier must be 1-256 printable characters without spaces, quotes, slashes or backslashes."
  }
  validation {
    condition     = length(var.resource_server.scopes) > 0 && alltrue([for name in keys(var.resource_server.scopes) : can(regex("^[\\x21\\x23-\\x2E\\x30-\\x5B\\x5D-\\x7E]{1,256}$", name))])
    error_message = "resource_server.scopes must name at least one scope, each without spaces, quotes, slashes or backslashes."
  }
}
variable "client_name" {
  type        = string
  default     = "petstore-client"
  description = "Name of the app client, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[\\w\\s+=,.@-]{1,128}$", var.client_name))
    error_message = "client_name must be 1-128 characters of letters, digits, spaces and _+=,.@-."
  }
}
variable "callback_urls" {
  type        = list(string)
  description = "Where Cognito may redirect after sign-in. The workshop web app's /callback page, whose address is its REST API's and known before the web app's function exists"

  validation {
    # Cognito accepts http only for localhost; a plain-http callback anywhere else is rejected at apply. The
    # check is on the configured values, so an address still unknown at plan is checked at apply instead.
    condition     = length(var.callback_urls) > 0 && alltrue([for url in var.callback_urls : startswith(url, "https://") || startswith(url, "http://localhost")])
    error_message = "callback_urls must contain at least one https URL (http is accepted only for localhost)."
  }
}
variable "standard_oauth_scopes" {
  type        = list(string)
  default     = ["openid", "profile"]
  description = "OpenID Connect scopes the client may request, in addition to the resource server's, as the _monolithic template had them"

  validation {
    condition     = length(setsubtract(var.standard_oauth_scopes, ["openid", "profile", "email", "phone", "aws.cognito.signin.user.admin"])) == 0
    error_message = "standard_oauth_scopes may contain only openid, profile, email, phone and aws.cognito.signin.user.admin."
  }
}
variable "domain_prefix" {
  type        = string
  description = "Prefix of the hosted domain, <prefix>.auth.<region>.amazoncognito.com. Unique across every AWS account in the region, so the caller makes it unique"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", var.domain_prefix)) && !can(regex("aws|amazon|cognito", var.domain_prefix))
    error_message = "domain_prefix must be 1-63 lowercase letters, digits and hyphens, must not begin or end with a hyphen, and must not contain aws, amazon or cognito, which Cognito reserves."
  }
}
variable "branding_settings_path" {
  type        = string
  description = "Path to the managed login branding settings document (JSON)"

  validation {
    condition     = endswith(var.branding_settings_path, ".json")
    error_message = "branding_settings_path must point at a .json file."
  }
}
variable "branding_background_image_path" {
  type        = string
  description = "Path to the PNG used as the managed login page background in light mode"

  validation {
    condition     = endswith(lower(var.branding_background_image_path), ".png")
    error_message = "branding_background_image_path must point at a .png file - the asset is declared with extension PNG."
  }
}
variable "groups" {
  type        = list(string)
  default     = []
  description = "User groups to create. A pre token generation trigger can add a user's groups to the access token as scopes, which is what the workshop's API authorizer checks"

  validation {
    condition     = alltrue([for name in var.groups : can(regex("^[\\p{L}\\p{M}\\p{S}\\p{N}\\p{P}]{1,128}$", name))])
    error_message = "groups must contain names of 1-128 printable characters without spaces."
  }
}

