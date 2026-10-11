variable "name" {
  type        = string
  description = "Name of the REST API"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9 ._-]{0,127}$", var.name))
    error_message = "name must be 1-128 characters of letters, digits, spaces, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "description" {
  type        = string
  default     = "MCP server on Lambda over streamable HTTP, behind a TOKEN authorizer"
  description = "Description of the REST API"

  validation {
    condition     = length(var.description) > 0
    error_message = "description must not be empty."
  }
}
variable "endpoint_type" {
  type        = string
  default     = "EDGE"
  description = "Endpoint type of the API. EDGE, which is what an AWS::Serverless::Api without an EndpointConfiguration gets"

  validation {
    # PRIVATE is left out: it needs an execute-api VPC endpoint and a resource policy, neither of which exists.
    condition     = contains(["EDGE", "REGIONAL"], var.endpoint_type)
    error_message = "endpoint_type must be EDGE or REGIONAL."
  }
}
variable "stage_name" {
  type        = string
  default     = "Prod"
  description = "Stage the API is deployed to, and the first segment of the MCP URL's path. Prod, the StageName the SAM template set"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,128}$", var.stage_name))
    error_message = "stage_name must be 1-128 characters of letters, digits and underscores."
  }
}
variable "path_part" {
  type        = string
  default     = "mcp"
  description = "Path the MCP endpoint is served on, below the stage. mcp, the Path of the SAM function's Api event"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.path_part))
    error_message = "path_part must be a single path segment of letters, digits, dots, underscores and hyphens."
  }
}
variable "authorizer_function_name" {
  type        = string
  description = "Name of the TOKEN authorizer function, which API Gateway is given permission to invoke"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.authorizer_function_name))
    error_message = "authorizer_function_name must be a Lambda function name."
  }
}
variable "authorizer_invoke_arn" {
  type        = string
  description = "Invoke ARN of the TOKEN authorizer function"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:apigateway:", var.authorizer_invoke_arn))
    error_message = "authorizer_invoke_arn must be a Lambda invoke ARN (arn:aws:apigateway:<region>:lambda:path/...)."
  }
}
variable "server_function_name" {
  type        = string
  description = "Name of the MCP server function, which API Gateway is given permission to invoke"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.server_function_name))
    error_message = "server_function_name must be a Lambda function name."
  }
}
variable "server_invoke_arn" {
  type        = string
  description = "Invoke ARN of the MCP server function"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:apigateway:", var.server_invoke_arn))
    error_message = "server_invoke_arn must be a Lambda invoke ARN (arn:aws:apigateway:<region>:lambda:path/...)."
  }
}
variable "authorization_header" {
  type        = string
  default     = "Authorization"
  description = "Request header carrying the bearer token. Authorization, the Identity.Header the SAM template set"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.authorization_header))
    error_message = "authorization_header must be an HTTP header name."
  }
}
variable "identity_validation_expression" {
  type        = string
  default     = "^Bearer [^ ]+$"
  description = "Regular expression API Gateway matches the header against before invoking the authorizer. A request that does not match is answered 401 without a Lambda invocation. The default is the shape the authorizer's own first check accepts"

  validation {
    condition     = length(var.identity_validation_expression) > 0
    error_message = "identity_validation_expression must not be empty."
  }
}
variable "authorizer_result_ttl_in_seconds" {
  type        = number
  default     = 300
  description = "How long API Gateway caches the authorizer's policy for a token. 300, the ReauthorizeEvery the SAM template set. The authorizer returns a policy for the whole stage because of this cache - a policy for one method would be reused for the others"

  validation {
    condition     = var.authorizer_result_ttl_in_seconds >= 0 && var.authorizer_result_ttl_in_seconds <= 3600 && floor(var.authorizer_result_ttl_in_seconds) == var.authorizer_result_ttl_in_seconds
    error_message = "authorizer_result_ttl_in_seconds must be an integer between 0 and 3600."
  }
}
