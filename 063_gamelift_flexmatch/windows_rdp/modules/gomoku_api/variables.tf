variable "api_name" {
  type        = string
  default     = "GomokuAPI"
  description = "Name of the REST API, as the _monolithic template had it. Names are not unique in API Gateway, so a second copy does not collide - it just makes two APIs of the same name"

  validation {
    condition     = length(var.api_name) > 0 && length(var.api_name) <= 1024
    error_message = "api_name must be 1-1024 characters."
  }
}
variable "endpoint_type" {
  type        = string
  default     = "REGIONAL"
  description = "Endpoint type of the API, as the _monolithic template had it"

  validation {
    condition     = contains(["REGIONAL", "EDGE", "PRIVATE"], var.endpoint_type)
    error_message = "endpoint_type must be REGIONAL, EDGE or PRIVATE."
  }
}
variable "stage_name" {
  type        = string
  default     = "prod"
  description = "Stage the deployment is published to. prod is what the game clients' config.ini and the leaderboard's main.js are written against; the userdata templates both from this value, so changing it moves all three together"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,128}$", var.stage_name))
    error_message = "stage_name must be 1-128 characters of letters, digits, hyphens and underscores."
  }
}
variable "routes" {
  type = map(object({
    path_part     = string
    http_method   = string
    function_name = string
    invoke_arn    = string
  }))
  description = "One entry per route, keyed by a caller-chosen label: the path segment under the API root, the method, and the function behind it. A map with literal keys because the function names and ARNs come from other modules and are unknown at plan time (rules.md B-8)"

  validation {
    condition     = length(var.routes) > 0
    error_message = "routes must contain at least one route - a deployment of an API with no methods is refused."
  }
  validation {
    condition     = alltrue([for r in values(var.routes) : contains(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"], r.http_method)])
    error_message = "routes http_method must be one of GET, POST, PUT, PATCH, DELETE or HEAD. OPTIONS is added to every route by this module for CORS."
  }
  validation {
    condition     = alltrue([for r in values(var.routes) : can(regex("^[a-zA-Z0-9._-]+$", r.path_part))])
    error_message = "routes path_part must be a single path segment of letters, digits, dots, hyphens and underscores."
  }
  validation {
    # Two routes on one path would each create an aws_api_gateway_resource for
    # it, and the second CreateResource is a ConflictException.
    condition     = length(distinct([for r in values(var.routes) : r.path_part])) == length(var.routes)
    error_message = "routes path_part values must be unique - this module creates one resource per route."
  }
}
variable "cors_allow_origin" {
  type        = string
  default     = "*"
  description = "Value of Access-Control-Allow-Origin on every route and preflight. * because the leaderboard is served from an S3 website endpoint whose host name is generated, and the API needs no credentials"

  validation {
    condition     = length(var.cors_allow_origin) > 0 && !strcontains(var.cors_allow_origin, "'")
    error_message = "cors_allow_origin must be non-empty and must not contain a single quote - it is wrapped in single quotes as an API Gateway static mapping value."
  }
}
variable "cors_allow_headers" {
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
  description = "Headers the preflights allow. The list the API Gateway console's Enable CORS writes, which is what the upstream workshop's deployment guide tells you to click"

  validation {
    condition     = length(var.cors_allow_headers) > 0 && alltrue([for h in var.cors_allow_headers : can(regex("^[A-Za-z0-9-]+$", h))])
    error_message = "cors_allow_headers must be a non-empty list of header names (letters, digits and hyphens)."
  }
}
