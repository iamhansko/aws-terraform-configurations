variable "function_name" {
  type        = string
  description = "Name of the function the URL invokes"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "invoke_mode" {
  type        = string
  default     = "BUFFERED"
  description = "BUFFERED returns the whole response at once, as the SAM template had it; RESPONSE_STREAM streams it"

  validation {
    condition     = contains(["BUFFERED", "RESPONSE_STREAM"], var.invoke_mode)
    error_message = "invoke_mode must be BUFFERED or RESPONSE_STREAM."
  }
}
variable "cors" {
  type = object({
    allow_origins = list(string)
    allow_methods = list(string)
  })
  default     = null
  description = "CORS configuration for browser callers, or null for none. Kakao's servers call the skill directly, so CORS changes nothing for them"

  validation {
    condition     = var.cors == null || try(length(var.cors.allow_origins) > 0 && length(var.cors.allow_methods) > 0, false)
    error_message = "cors must name at least one origin and one method, or be null."
  }
}
