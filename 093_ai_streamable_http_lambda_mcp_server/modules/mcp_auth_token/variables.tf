variable "parameter_name" {
  type        = string
  description = "Parameter Store name the token is stored under. The authorizer reads it by this name and the workbench writes it into the MCP client header file from it, so this parameter is the one place the token is kept"

  validation {
    condition     = can(regex("^/[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)*$", var.parameter_name))
    error_message = "parameter_name must be an absolute Parameter Store path such as /mcp-lambda-handler/mcp-auth-token: segments of letters, digits, underscores, dots and hyphens, separated by slashes."
  }
}
variable "length" {
  type        = number
  default     = 32
  description = "Length of the generated token. Letters and digits only, so 32 characters is about 190 bits"

  validation {
    condition     = var.length >= 20 && var.length <= 128 && floor(var.length) == var.length
    error_message = "length must be an integer between 20 and 128."
  }
}
