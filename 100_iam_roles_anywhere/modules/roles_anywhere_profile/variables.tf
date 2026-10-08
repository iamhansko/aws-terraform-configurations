variable "certificate_authority_arn" {
  type        = string
  description = "ARN of the private CA registered as the trust anchor's source. Injected rather than looked up (rules.md B-6). Creating a trust anchor makes Roles Anywhere read this CA's certificate, so the CA has to be ACTIVE by then - a well-formed ARN does not tell this module that, which is why the caller also orders it after the CA module (rules.md D-2)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm-pca:", var.certificate_authority_arn))
    error_message = "certificate_authority_arn must be an AWS Private CA certificate authority ARN (e.g. arn:aws:acm-pca:ap-northeast-2:111122223333:certificate-authority/...)."
  }
}
variable "trust_anchor_name" {
  type        = string
  default     = "iam-ra-ta"
  description = "Name of the trust anchor, as the _monolithic template had it. Account-wide and region-wide: a second copy of this project in the same account and region fails on it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.:/=+@-]{1,255}$", var.trust_anchor_name))
    error_message = "trust_anchor_name must be 1-255 characters of letters, digits and _.:/=+@- which is what IAM Roles Anywhere accepts for a trust anchor name."
  }
}
variable "profile_name" {
  type        = string
  default     = "iam-ra-profile"
  description = "Name of the profile, as the _monolithic template had it. Account-wide and region-wide, like the trust anchor name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.:/=+@-]{1,255}$", var.profile_name))
    error_message = "profile_name must be 1-255 characters of letters, digits and _.:/=+@- which is what IAM Roles Anywhere accepts for a profile name."
  }
}
variable "enabled" {
  type        = bool
  default     = true
  description = "Whether the trust anchor and the profile are enabled, as the _monolithic template had both. One variable for both, because a disabled anchor with an enabled profile and the reverse are the same outcome: CreateSession is refused. Disabling either leaves everything looking correct in the console and the credential helper reporting only that the session was denied"
}
variable "session_duration_seconds" {
  type        = number
  default     = 43200
  description = <<-DESC
    Longest session this deployment hands out, applied to the profile's duration_seconds and to the
    role's max_session_duration.

    One variable for both on purpose. IAM Roles Anywhere issues the smaller of the two, so the pair
    is what sets the limit and either one alone sets nothing. The _monolithic template put 43200 on
    the profile and left the role at the IAM default of 3600, which made the profile's 12 hours
    unreachable - and nothing reports that, because both values are individually valid, until a
    client asks for the longer window and gets AccessDeniedException (rules.md B-5).

    The credential helper still requests 3600 unless it is given --session-duration.
  DESC

  validation {
    # 900 is the IAM floor for a role's MaxSessionDuration and 43200 the ceiling for both it and a
    # Roles Anywhere profile's duration.
    condition     = var.session_duration_seconds >= 900 && var.session_duration_seconds <= 43200
    error_message = "session_duration_seconds must be between 900 and 43200, the range IAM accepts for a role's MaxSessionDuration and a Roles Anywhere profile's duration."
  }
}
variable "role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
  description = <<-DESC
    Managed policies attached to the role the certificate vends, as the _monolithic template had
    them.

    AmazonS3ReadOnlyAccess alone, and it is narrow on purpose rather than by omission: the point of
    the demo is that a certificate produces a session with exactly these permissions and no others,
    and the test scripts assert both halves of that - s3:ListBucket succeeds, s3:PutObject and
    ec2:DescribeInstances are denied. Widening this makes those deny checks fail and report the
    role as broader than intended, which is the check working.
  DESC

  validation {
    condition     = length(var.role_policy_arns) > 0 && alltrue([for arn in var.role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "role_policy_arns must be a non-empty list of IAM policy ARNs (e.g. arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess). A role with no policy at all authenticates and can then do nothing, which the test scripts report as an AccessDenied that looks like a broken profile."
  }
}
