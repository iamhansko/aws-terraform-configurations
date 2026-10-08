output "trust_anchor_arn" {
  value       = aws_rolesanywhere_trust_anchor.trust_anchor.arn
  description = "ARN of the trust anchor the certificate is presented to. The role's trust policy names this in an ArnEquals condition, so a certificate from any other anchor cannot assume the role"
}
output "profile_arn" {
  value       = aws_rolesanywhere_profile.profile.arn
  description = "ARN of the profile, which lists the assumable role and caps the session length. The credential helper needs this and the trust anchor ARN and the role ARN - all three, which is why all three are outputs"
}
output "role_arn" {
  value       = aws_iam_role.vended_role.arn
  description = "ARN of the role a session assumes"
}
output "role_name" {
  value       = aws_iam_role.vended_role.name
  description = "Generated name of that role. Published because the test scripts match the identity they get back against it, and a name written down a second time is a name that can disagree (rules.md B-5)"
}
output "session_duration_seconds" {
  value       = var.session_duration_seconds
  description = "The session limit that was applied to both the profile and the role, handed back so a caller printing it is printing what was configured rather than its own copy of the number (rules.md B-5)"
}
output "role_policy_arns" {
  value       = var.role_policy_arns
  description = "Policies attached to the vended role, handed back so a caller can state what a session is expected to be allowed without repeating the list (rules.md B-5)"
}
# Whether a certificate can actually be exchanged for credentials is not something Terraform can
# report: it depends on the CA being ACTIVE, the certificate chaining to it, the trust policy, the
# profile and the role's session limit all agreeing. The credential test scripts the root builds
# are the real check; these two are the quick look at the AWS side of it.
output "status_command" {
  value       = "aws rolesanywhere get-trust-anchor --trust-anchor-id ${aws_rolesanywhere_trust_anchor.trust_anchor.id} --query 'trustAnchor.{name:name,enabled:enabled,type:source.sourceType}'; aws rolesanywhere get-profile --profile-id ${aws_rolesanywhere_profile.profile.id} --query 'profile.{name:name,enabled:enabled,duration:durationSeconds,roles:roleArns}'"
  description = "Whether the anchor and the profile came up enabled, and what session length the profile allows. enabled false on either one makes CreateSession fail with nothing in the console looking wrong"
}
output "issued_sessions_command" {
  value       = "aws rolesanywhere list-subjects --query 'subjects[].{x509Subject:x509Subject,lastSeen:lastSeenAt,enabled:enabled}'"
  description = "Which certificate subjects have actually presented themselves, with the last time each did. Empty means no certificate has ever been exchanged for a session, which distinguishes a configuration that was never exercised from one that is failing"
}
