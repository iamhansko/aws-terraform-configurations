variable "name" {
  type        = string
  default     = "GomokuAPI"
  description = "Name of the REST API, as the _monolithic template had it. Not unique and not referenced by anything - the clients reach the API by its generated ID"

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 1024
    error_message = "name must be 1-1024 characters."
  }
}
variable "stage_name" {
  type        = string
  default     = "prod"
  description = "Stage the deployment is published on. prod because both prebuilt game clients and the leaderboard page were written against .../prod; the root writes the real invoke URL into all three, so another name works too"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.stage_name)) && length(var.stage_name) <= 128
    error_message = "stage_name must be 1-128 letters, digits, hyphens or underscores."
  }
}
variable "routes" {
  type = map(object({
    path_part     = string
    http_method   = string
    function_name = string
    invoke_arn    = string
  }))
  description = "One top-level resource per entry, each with a Lambda (non-proxy AWS) integration on http_method and a CORS preflight on OPTIONS. Keyed by a caller-chosen label so the keys are known at plan while the function values are not (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.routes) : can(regex("^[a-zA-Z0-9_-]+$", label))])
    error_message = "routes keys must be labels of letters, digits, hyphens and underscores."
  }
  validation {
    condition     = alltrue([for route in values(var.routes) : can(regex("^[a-zA-Z0-9._-]+$", route.path_part)) && contains(["GET", "POST", "PUT", "PATCH", "DELETE"], route.http_method)])
    error_message = "Each route needs a single-segment path_part and an http_method of GET, POST, PUT, PATCH or DELETE (OPTIONS is added by this module)."
  }
  validation {
    condition     = length(distinct([for route in values(var.routes) : route.path_part])) == length(var.routes)
    error_message = "routes must not repeat a path_part - each entry creates its own resource under the root."
  }
}
variable "cors_allow_origin" {
  type        = string
  default     = "*"
  description = "Value of Access-Control-Allow-Origin on every response. * because the leaderboard page is served from an S3 website endpoint, a different origin from the API, and the browser drops the ranking response without it"

  validation {
    condition     = length(var.cors_allow_origin) > 0 && !strcontains(var.cors_allow_origin, "'")
    error_message = "cors_allow_origin must be non-empty and contain no single quote, because it is written into an API Gateway static mapping value as '<value>'."
  }
}
variable "cors_allow_headers" {
  type        = string
  default     = "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token"
  description = "Value of Access-Control-Allow-Headers on the OPTIONS preflight responses - the set API Gateway's own Enable CORS action writes"

  validation {
    condition     = length(var.cors_allow_headers) > 0 && !strcontains(var.cors_allow_headers, "'")
    error_message = "cors_allow_headers must be non-empty and contain no single quote."
  }
}
