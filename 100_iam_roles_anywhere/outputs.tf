# These outputs carry their value expressions directly rather than projecting a local.outputs map.
#
# That map exists to keep a root's outputs and the README written onto a VS Code instance from
# drifting apart, so it applies only to roots that declare module "vscode_ec2" (rules.md H-2).
# There is no such instance here. The one instance this project builds is a build step - it
# exports a certificate, uploads it, and is terminated by a Lambda before the apply returns - so
# there is nowhere to render a README onto and no second copy of these values to keep in step.
#
# The credential test scripts below are built from the locals in main.tf rather than written out
# five times, which is what keeps the four POSIX variants identical apart from their download URL.
#
# Nothing here returns key material. Two of the objects in the bucket are private keys, and an
# output - or a CI log that captured one - is not where they should end up, so the certificate and
# the key are handed over as a console link and a download command instead, and the test scripts
# fetch them with aws s3 cp at run time.
# CloudFormation output: CertificatePemFileDownload
output "certificate_download_url" {
  # https:// included. The converted output omitted the scheme, so the value could not be opened as
  # a link and had to be edited by hand first.
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/s3/object/${module.artifact_bucket.bucket_name}?region=${data.aws_region.current.region}&prefix=${module.certificate_export_ec2.exported_object_keys.certificate}"
  description = "Console link to download the end-entity certificate the private CA issued. The test scripts download it themselves with aws s3 cp; this is for a machine that has no AWS credentials to do that with - put the file next to the script and it is used as is"
}
# CloudFormation output: DecryptedPriateKeyPemFileDownload
output "decrypted_key_download_url" {
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/s3/object/${module.artifact_bucket.bucket_name}?region=${data.aws_region.current.region}&prefix=${module.certificate_export_ec2.exported_object_keys.decrypted_key}"
  description = "Console link to download the unencrypted private key for that certificate. Anyone holding both files can obtain this role's credentials, so treat this bucket as a secret store until the stack is destroyed"
}
output "download_certificate_command" {
  value       = "aws s3 cp s3://${module.artifact_bucket.bucket_name}/${module.certificate_export_ec2.exported_object_keys.certificate} . --region ${data.aws_region.current.region} && aws s3 cp s3://${module.artifact_bucket.bucket_name}/${module.certificate_export_ec2.exported_object_keys.decrypted_key} . --region ${data.aws_region.current.region}"
  description = "The same two aws s3 cp calls the test scripts make in their first step, on their own. It needs ordinary AWS credentials - reading the bucket is the very access the certificate is standing in for - so the scripts use whatever credentials the shell already has for these two calls only, and clear them before anything is tested"
}
output "artifact_bucket_name" {
  value       = module.artifact_bucket.bucket_name
  description = "Bucket the exported certificate and keys were uploaded to"
}
output "artifact_objects_command" {
  value       = module.artifact_bucket.list_objects_command
  description = "What is actually in that bucket. Four objects is the expected answer; fewer means the export did not finish, which the apply should already have failed on at the terminator Lambda's wait"
}
output "certificate_authority_arn" {
  value       = module.private_certificate_authority.certificate_authority_arn
  description = "The private CA acting as the trust root. It is registered as the trust anchor's source, and it is also the resource in this project billed by the month from the moment it is created"
}
output "certificate_authority_status_command" {
  value       = module.private_certificate_authority.status_command
  description = "Whether the CA actually came up usable, which Terraform cannot report: importing the certificate is what activates it and that resource has no status attribute. ACTIVE is expected - PENDING_CERTIFICATE means everything downstream of it failed"
}
output "client_certificate_arn" {
  value       = module.client_certificate.certificate_arn
  description = "The end-entity certificate the CA issued and the instance exported. Exportable only because a private CA issued it - a public ACM certificate cannot be exported at all, which is what makes this project possible"
}
output "client_certificate_status_command" {
  value       = module.client_certificate.status_command
  description = "Whether ACM issued the certificate. ISSUED and Type PRIVATE are expected"
}
output "trust_anchor_arn" {
  value       = module.roles_anywhere_profile.trust_anchor_arn
  description = "Trust anchor the certificate is presented to. The role's trust policy names this ARN in an ArnEquals condition, so a certificate from any other anchor cannot assume the role"
}
output "profile_arn" {
  value       = module.roles_anywhere_profile.profile_arn
  description = "IAM Roles Anywhere profile that lists the assumable role and caps the session length"
}
output "role_arn" {
  value       = module.roles_anywhere_profile.role_arn
  description = "Role the session assumes. Its permissions are exactly AmazonS3ReadOnlyAccess, which is what the test script's allow and deny checks assert"
}
output "session_duration_seconds" {
  value       = module.roles_anywhere_profile.session_duration_seconds
  description = "Longest session this deployment can issue, applied to both the profile and the role's MaxSessionDuration. The credential helper still requests 3600 unless given --session-duration"
}
output "roles_anywhere_status_command" {
  value       = module.roles_anywhere_profile.status_command
  description = "Whether the anchor and the profile came up enabled, and what session length the profile allows. Either one disabled makes CreateSession fail with nothing in the console looking wrong"
}
output "issued_sessions_command" {
  value       = module.roles_anywhere_profile.issued_sessions_command
  description = "Which certificate subjects have presented themselves and when. Empty means no certificate has ever been exchanged for a session, which separates a configuration nobody exercised from one that is failing"
}
output "export_instance_state_command" {
  value       = module.certificate_export_ec2.instance_state_command
  description = "Whether the export instance is gone. terminated is expected after a successful apply; running means the Lambda did not do its job and a host is still holding the private key it exported"
}
output "terminated_instances" {
  value       = module.instance_terminator_lambda.terminated_instances
  description = "What the terminator Lambda verified in S3 and then shut down, read back from the invocation's return value: how long it waited for the export, when each object was written, and the instance it terminated. This is the only place the termination is visible to Terraform - the instance is still recorded in state as running, because Terraform did not terminate it"
}
output "terminator_lambda_log_command" {
  value       = module.instance_terminator_lambda.log_command
  description = "The Lambda's log, which starts with the event it was handed. Where a Runtime.HandlerNotFound or an UnauthorizedOperation appears in full rather than as the single line an apply prints"
}
output "credential_test_linux_x86_64" {
  value       = local.posix_credential_test["linux_x86_64"]
  description = "Full IAM Roles Anywhere credential test for Linux x86-64: downloads the certificate and key with aws s3 cp using the shell's existing AWS credentials, then clears those credentials, verifies the key matches the certificate, exchanges it for a session, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
output "credential_test_linux_aarch64" {
  value       = local.posix_credential_test["linux_aarch64"]
  description = "Full IAM Roles Anywhere credential test for Linux Aarch64: downloads the certificate and key with aws s3 cp using the shell's existing AWS credentials, then clears those credentials, verifies the key matches the certificate, exchanges it for a session, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
output "credential_test_macos_x86_64" {
  value       = local.posix_credential_test["macos_x86_64"]
  description = "Full IAM Roles Anywhere credential test for macOS x86-64: downloads the certificate and key with aws s3 cp using the shell's existing AWS credentials, then clears those credentials, verifies the key matches the certificate, exchanges it for a session, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
output "credential_test_macos_aarch64" {
  value       = local.posix_credential_test["macos_aarch64"]
  description = "Full IAM Roles Anywhere credential test for macOS Aarch64: downloads the certificate and key with aws s3 cp using the shell's existing AWS credentials, then clears those credentials, verifies the key matches the certificate, exchanges it for a session, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
output "credential_test_windows_x86_64" {
  value       = local.windows_credential_test
  description = "Full IAM Roles Anywhere credential test for Windows x86-64 as a PowerShell script: downloads the certificate and key with aws s3 cp using the shell's existing AWS credentials, then clears those credentials, exchanges the certificate for a session, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
