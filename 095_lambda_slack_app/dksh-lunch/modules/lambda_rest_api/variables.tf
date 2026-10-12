variable "name" {
  type        = string
  description = "Name of the REST API, and the prefix of its usage plan and API key"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.name))
    error_message = "name must be 1-100 characters of letters, digits, hyphens and underscores."
  }
}
variable "description" {
  type        = string
  default     = ""
  description = "Description of the REST API"

  validation {
    condition     = length(var.description) <= 1024
    error_message = "description must be 1024 characters or fewer."
  }
}
variable "stage_name" {
  type        = string
  description = "Stage the API is deployed to, and the first segment of every path in its URL"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,128}$", var.stage_name))
    error_message = "stage_name must be 1-128 characters of letters, digits and underscores."
  }
}
variable "routes" {
  type = map(object({
    path        = string
    http_method = string
  }))
  description = "Routes to the function, keyed by a label. path is relative to the stage, without slashes at either end, one or two segments deep"

  validation {
    condition     = length(var.routes) > 0
    error_message = "routes must contain at least one route."
  }
  validation {
    condition     = alltrue([for route in values(var.routes) : can(regex("^[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)?$", route.path))])
    error_message = "each route path must be one or two segments of letters, digits, dots, underscores and hyphens, without leading or trailing slashes, e.g. kakao or slack/events."
  }
  validation {
    condition     = alltrue([for route in values(var.routes) : contains(["ANY", "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"], route.http_method)])
    error_message = "each route http_method must be ANY, GET, POST, PUT, PATCH, DELETE, HEAD or OPTIONS."
  }
  validation {
    # API Gateway refuses a second method of the same verb on one resource, and only at apply.
    condition     = length(distinct([for route in values(var.routes) : "${route.path} ${route.http_method}"])) == length(var.routes)
    error_message = "routes must not repeat a path and method pair."
  }
}
variable "function_name" {
  type        = string
  description = "Name of the function the routes invoke, which the invoke permission names"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "function_invoke_arn" {
  type        = string
  description = "The function's invoke ARN, which the integrations call - invoke_arn, not the function ARN"

  validation {
    # The function ARN is the usual mistake here, and API Gateway rejects it only when the integration is created.
    condition     = can(regex("^arn:aws[a-z-]*:apigateway:[a-z0-9-]+:lambda:path/", var.function_invoke_arn))
    error_message = "function_invoke_arn must be a Lambda invoke ARN (arn:aws:apigateway:<region>:lambda:path/...), the function's invoke_arn attribute."
  }
}
variable "api_key_required" {
  type        = bool
  default     = false
  description = "Whether every route requires an x-api-key header. True creates the usage plan and the key that make one valid, as SAM's Auth.ApiKeyRequired with UsagePlan.CreateUsagePlan PER_API did"
}
