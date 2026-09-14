variable "control_identifier" {
  type        = string
  description = "ARN of the control to enable. Either a Control Catalog ARN (arn:aws:controlcatalog:::control/<id>) or a regional Control Tower ARN (arn:aws:controltower:<region>::control/<NAME>). Only Strongly recommended and Elective controls may be enabled this way, plus the OU-level Region deny control"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:(controlcatalog|controltower):", var.control_identifier))
    error_message = "control_identifier must be a controlcatalog or controltower control ARN."
  }
}
variable "target_identifier" {
  type        = string
  description = "ARN of the organizational unit the control is enabled on. Pass an organization module's organizational_unit_arns entry rather than a literal, so the two cannot drift apart"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:organizations::[0-9]{12}:ou/o-[0-9a-z]+/ou-", var.target_identifier))
    error_message = "target_identifier must be an Organizations OU ARN (e.g. arn:aws:organizations::123456789012:ou/o-abc123/ou-abc1-11111111)."
  }
}
variable "parameters" {
  type        = map(string)
  default     = {}
  description = "Control parameters, keyed by parameter name, with each value a JSON document the caller produced with jsonencode. For the OU Region deny control that is AllowedRegions (a JSON array of Region codes) and ExemptedActions (a JSON array of IAM action patterns such as bedrock:*)"

  validation {
    condition     = alltrue([for key in keys(var.parameters) : length(key) > 0])
    error_message = "parameters must not contain empty parameter names."
  }

  validation {
    condition     = alltrue([for value in values(var.parameters) : can(jsondecode(value))])
    error_message = "parameters values must each be a valid JSON document, e.g. jsonencode([\"ap-northeast-2\"]). Control Tower rejects a bare unquoted string."
  }
}
