output "release_name" {
  value       = helm_release.kyverno.name
  description = "Name of the Kyverno Helm release"
}
output "policies_release_name" {
  value       = helm_release.kyverno_policies.name
  description = "Name of the kyverno-policies Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Kyverno runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "pod_security_standard" {
  value       = var.pod_security_standard
  description = "Which Pod Security Standard profile the policies enforce, re-exposed so the caller's instructions match what was installed (rules.md B-5)"
}
output "validation_failure_action" {
  value       = var.validation_failure_action
  description = "Audit or Enforce. Re-exposed because it decides whether a violating pod is recorded or rejected, which is the difference between a working demo and a cluster that will not schedule anything (rules.md B-5)"
}
output "policies_check_command" {
  value       = "kubectl get clusterpolicy"
  description = "Command listing the ClusterPolicy objects the policies chart installed. The ACTION column shows Audit or Enforce and the READY column shows whether Kyverno has accepted each one"
}
output "policy_report_command" {
  value       = "kubectl get policyreport -A"
  description = "Command listing the PolicyReports Kyverno produced. This is the demo's payoff: every namespace gets a report counting passes and failures against the Pod Security Standard"
}
