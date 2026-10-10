variable "name_prefix" {
  type        = string
  default     = "gamelift-flexmatch-workshop-user-"
  description = "Prefix for the generated secret name. A prefix rather than a fixed name, so a second copy of this project in one account does not collide - and the generated suffix is what the _monolithic template got for free by leaving the name unset, where the provider named it terraform-<timestamp>"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]{1,460}$", var.name_prefix))
    error_message = "name_prefix must be 1-460 characters from the set Secrets Manager accepts for a secret name (letters, digits and /_+=.@-), leaving room for the generated suffix inside the 512 character limit."
  }
}
variable "username" {
  type        = string
  default     = "gamelift"
  description = "Account name stored in the secret under \"username\", and the Windows local account the instance creates with this password. One value feeds both, so the credential pair cannot disagree with the account that exists"

  validation {
    # New-LocalUser rejects a name longer than 20 characters, and rejects the
    # characters below outright. Both failures land inside the userdata's try
    # block, so apply reports the instance as created and the only symptom is RDP
    # refusing a password that looks correct.
    condition     = can(regex("^[^\"/\\\\\\[\\]:;|=,+*?<>@ ]{1,20}$", var.username))
    error_message = "username must be 1-20 characters and must not contain a space, @, or any of \" / \\ [ ] : ; | = , + * ? < >, because New-LocalUser rejects those and the failure only surfaces on the instance."
  }
}
variable "password_length" {
  type        = number
  default     = 20
  description = "Length of the generated password, as the _monolithic template's GenerateSecretString PasswordLength had it"

  validation {
    # The lower bound is the Windows default complexity policy's minimum; below
    # it New-LocalUser fails with "The password does not meet the password policy
    # requirements", again inside the try block.
    condition     = var.password_length >= 14 && var.password_length <= 128
    error_message = "password_length must be between 14 and 128. Below 14 risks the Windows local password policy rejecting the value when New-LocalUser runs on the instance, which fails silently from Terraform's point of view."
  }
}
variable "password_override_special" {
  type        = string
  default     = "!#$%&'()*+,-.:;<=>?[]^_`{|}~"
  description = <<-DESC
    Punctuation the generated password may draw from.

    This is Secrets Manager's default punctuation set with @ / \ and " removed, which is what the
    _monolithic template's GenerateSecretString asked for with ExcludeCharacters: "@/\. Space is absent
    from the set as well, which is what its IncludeSpace: false meant.

    Those exclusions are not cosmetic. The password is interpolated into a JSON secret string and then
    parsed back on the instance by ConvertFrom-Json, where a backslash or a double quote has to be escaped
    to survive; and it is passed to ConvertTo-SecureString in a PowerShell argument, where a space splits
    the argument. Each of those produces a password on the instance that does not match the one in the
    secret, with nothing to say so.

    < > and & are kept, as the template kept them, and they do survive that round trip - but jsonencode
    stores them as \u003c, \u003e and \u0026, so the raw secret string is not the password whenever one
    of them is drawn. Read the password through the get_password_command output, which decodes it.
  DESC

  validation {
    condition     = length(var.password_override_special) > 0 && !can(regex("[\"\\\\ ]", var.password_override_special))
    error_message = "password_override_special must be non-empty and must not contain a double quote, a backslash or a space - see the description for what each of those breaks on the instance."
  }
}
variable "recovery_window_in_days" {
  type        = number
  default     = 0
  description = "How long Secrets Manager keeps the secret recoverable after destroy. Zero deletes it immediately, which is what a demo wants - the default of 30 leaves the name taken, so re-running this project inside the window fails with InvalidRequestException: scheduled for deletion"

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 for immediate deletion, or between 7 and 30 - Secrets Manager accepts nothing in between."
  }
}
