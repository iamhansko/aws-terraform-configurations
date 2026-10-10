variable "name" {
  type        = string
  description = "Name of the user pool. CloudFormation generated the _monolithic template's; the caller derives one from the project name"

  validation {
    condition     = can(regex("^[\\w\\s+=,.@-]{1,128}$", var.name))
    error_message = "name must be 1-128 characters of letters, digits, spaces and _+=,.@-."
  }
}
variable "client_name" {
  type        = string
  description = "Name of the app client"

  validation {
    condition     = can(regex("^[\\w\\s+=,.@-]{1,128}$", var.client_name))
    error_message = "client_name must be 1-128 characters of letters, digits, spaces and _+=,.@-."
  }
}
