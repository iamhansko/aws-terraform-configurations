# IAM Roles Anywhere itself: the trust anchor that decides which certificates are believed, the
# role those certificates become, and the profile that ties the two together.
#
# All three in one module, because they are one component and they reference each other in a ring
# that only just avoids being a cycle (rules.md C-2). The order is forced and worth stating:
#
#   trust anchor  ->  role  ->  profile
#
# The role's trust policy names the trust anchor ARN in an ArnEquals condition, so the anchor has
# to exist first. The profile lists the role ARN, so the role has to exist before it. Nothing
# references the profile, which is what keeps this a chain rather than a loop - and it is also why
# the trust anchor cannot be narrowed to "only this profile" in its own configuration.
resource "aws_rolesanywhere_trust_anchor" "trust_anchor" {
  name    = var.trust_anchor_name
  enabled = var.enabled
  source {
    source_type = "AWS_ACM_PCA"
    source_data {
      acm_pca_arn = var.certificate_authority_arn
    }
  }
}
# The role a certificate turns into. No name argument, so Terraform generates one - deliberately,
# because an IAM role name is account-wide and a literal would collide with a second copy of this
# project in the same account. The generated name is published as an output, and the test scripts
# assert against it rather than against a name written down twice (rules.md B-5).
resource "aws_iam_role" "vended_role" {
  # Not conversion output. The _monolithic template left this at the IAM default of 3600 while
  # giving the profile 43200, so the profile's 12 hours were unreachable: Roles Anywhere issues
  # min(profile duration, role MaxSessionDuration), and asking for the longer window returns
  #
  #   AccessDeniedException: Unable to assume role ... The requested DurationSeconds exceeds the
  #   MaxSessionDuration set for this role.
  #
  # Both values come from one variable here so they cannot drift apart again - see the variable's
  # own description.
  max_session_duration = var.session_duration_seconds
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["rolesanywhere.amazonaws.com"]
      }
      # TagSession and SetSourceIdentity alongside AssumeRole, as the _monolithic template had it.
      # Roles Anywhere sets the certificate's subject fields as session tags and its serial number
      # as the source identity, so a policy allowing only sts:AssumeRole makes CreateSession fail -
      # and the message names the missing action rather than the certificate.
      Action = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
      Condition = {
        # What stops any other trust anchor in the account from vending this role. Without it, the
        # role trusts the Roles Anywhere service as a whole, so a certificate from an unrelated CA
        # registered by anyone with Roles Anywhere access would be accepted.
        ArnEquals = {
          "aws:SourceArn" = [aws_rolesanywhere_trust_anchor.trust_anchor.arn]
        }
      }
    }]
  })
}
# for_each over the policy list rather than one attachment resource per policy, so a caller can add
# or remove a policy without this module changing (rules.md B-7). toset is safe because these ARNs
# are literal strings in configuration and therefore known at plan time; a set built from another
# module's output would fail with "Invalid for_each argument" and would have to be a map with
# static keys instead (rules.md B-8).
resource "aws_iam_role_policy_attachment" "vended_role" {
  for_each   = toset(var.role_policy_arns)
  role       = aws_iam_role.vended_role.name
  policy_arn = each.value
}
resource "aws_rolesanywhere_profile" "profile" {
  name             = var.profile_name
  enabled          = var.enabled
  duration_seconds = var.session_duration_seconds
  role_arns        = [aws_iam_role.vended_role.arn]

  # The role ARN reference orders this after the role, but not after the policies attached to it,
  # and the gap is wide enough to matter. The profile is the last thing created here, so an
  # operator running the credential test the moment apply returns is the expected case - and a
  # session created before the attachment lands authenticates perfectly and then fails on
  #
  #   An error occurred (AccessDenied) when calling the ListObjectsV2 operation
  #
  # which reads as a broken profile rather than as a race (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.vended_role]
}
