variable "name" {
  type        = string
  description = "Name of the table. Table names are unique per account and region, so this is derived from the project name - the SAM template derived it from the stack name, <stack>-mcp-sessions"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.name))
    error_message = "name must be 3-255 characters of letters, digits, underscores, dots and hyphens."
  }
}
variable "purpose_tag" {
  type        = string
  default     = "MCP Session Management"
  description = "Value of the Purpose tag, as the _monolithic template set it"

  validation {
    condition     = length(var.purpose_tag) > 0 && length(var.purpose_tag) <= 256
    error_message = "purpose_tag must be 1-256 characters."
  }
}
