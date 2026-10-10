variable "name" {
  type        = string
  default     = "PetStore"
  description = "Name of the REST API, as the _monolithic template had it"

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 1024
    error_message = "name must be 1-1024 characters."
  }
}
variable "description" {
  type        = string
  default     = "Sample API that integrates via HTTP with our demo Pet Store Endpoints"
  description = "Description of the REST API, as the _monolithic template had it"
}
variable "stage_name" {
  type        = string
  default     = "Prod"
  description = "Stage name, as the _monolithic template had it. The workshop's web app configuration hardcodes /Prod/pets, so changing this also needs web-ui-js/cognito-env-tmpl.js changed"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,128}$", var.stage_name))
    error_message = "stage_name must be 1-128 characters of letters, digits, hyphens and underscores."
  }
}
variable "authorizer_name" {
  type        = string
  default     = "Builder-Class"
  description = "Name of the Cognito authorizer, as the _monolithic template had it"

  validation {
    condition     = length(var.authorizer_name) > 0
    error_message = "authorizer_name must not be empty."
  }
}
variable "user_pool_arn" {
  type        = string
  description = "User pool whose tokens the authorizer accepts"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:cognito-idp:[a-z0-9-]+:[0-9]{12}:userpool/.+$", var.user_pool_arn))
    error_message = "user_pool_arn must be a Cognito user pool ARN."
  }
}
variable "authorization_scopes" {
  type        = list(string)
  description = "OAuth scopes of which the access token must carry at least one. A group name works here too once a pre token generation trigger adds the user's groups to the token's scopes"

  validation {
    condition     = length(var.authorization_scopes) > 0
    error_message = "authorization_scopes must name at least one scope - without one, the authorizer accepts ID tokens and the scopes this project demonstrates are never checked."
  }
}
variable "optional_query_parameters" {
  type        = list(string)
  default     = []
  description = "Query string parameters the GET method declares as optional, as the _monolithic template had them"

  validation {
    condition     = alltrue([for name in var.optional_query_parameters : can(regex("^[A-Za-z0-9_.-]+$", name))])
    error_message = "optional_query_parameters must be plain parameter names."
  }
}
variable "backend_url" {
  type        = string
  default     = null
  description = "HTTP endpoint the GET is proxied to. Null answers it with a MOCK integration inside API Gateway instead"

  validation {
    condition     = var.backend_url == null || can(regex("^https?://", coalesce(var.backend_url, "http://x")))
    error_message = "backend_url must be an http or https URL, or null for a MOCK integration."
  }
}
variable "cors_allow_origin" {
  type        = string
  default     = null
  description = "Origin allowed to call the API from a browser, which adds an OPTIONS preflight and the Access-Control-Allow-Origin header on the GET. Null adds neither - a browser page on another origin then cannot read the response"

  validation {
    condition     = var.cors_allow_origin == null || length(coalesce(var.cors_allow_origin, "x")) > 0
    error_message = "cors_allow_origin must be an origin such as https://example.com or *, or null."
  }
}
