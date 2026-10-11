variable "name_prefix" {
  type        = string
  default     = "shlink-configuration-"
  description = "Prefix for the secret's generated name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]{1,480}$", var.name_prefix))
    error_message = "name_prefix must be letters, digits and /_+=.@- only."
  }
}
variable "recovery_window_in_days" {
  type        = number
  default     = 0
  description = "Days a destroyed secret stays restorable. 0 deletes it at once, so destroy-and-reapply leaves nothing behind"

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 or between 7 and 30."
  }
}
variable "short_domain" {
  type        = string
  description = "Host name the short URLs are issued under and the API is served from, e.g. shlink.example.com. Shlink's DEFAULT_DOMAIN, and the host of SHLINK_SERVER_URL"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.short_domain))
    error_message = "short_domain must be a lowercase DNS host name such as shlink.example.com."
  }
}
variable "server_name" {
  type        = string
  default     = "shlink"
  description = "Name the web client shows for this server, as the _monolithic template had it"

  validation {
    condition     = length(var.server_name) > 0
    error_message = "server_name must not be empty."
  }
}
variable "timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone Shlink reports visits in, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$", var.timezone))
    error_message = "timezone must be an IANA timezone name such as Asia/Seoul or UTC."
  }
}
