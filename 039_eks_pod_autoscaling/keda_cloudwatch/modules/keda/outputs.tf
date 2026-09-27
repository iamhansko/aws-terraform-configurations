output "release_name" {
  value       = helm_release.keda.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = helm_release.keda.namespace
  description = "Namespace KEDA runs in, re-exposed so a caller building a kubectl command does not restate it (rules.md B-5)"
}
output "chart_version" {
  value       = helm_release.keda.version
  description = "Chart version installed, re-exposed so the pinned value is visible without reading the module (rules.md B-5)"
}
output "operator_role_arn" {
  value       = aws_iam_role.keda_operator.arn
  description = "ARN of the role the operator assumes through IRSA. A TriggerAuthentication with identityOwner keda authenticates as this role, so a scaler's permissions are whatever is attached to it"
}
output "operator_role_name" {
  value       = aws_iam_role.keda_operator.name
  description = "Name of the operator's IAM role"
}
output "service_account_name" {
  value       = var.service_account_name
  description = "Service account annotated with the role ARN, re-exposed because it is half of the trust policy's subject (rules.md B-5)"
}
output "service_account_annotations_command" {
  value       = "kubectl -n ${helm_release.keda.namespace} get serviceaccount ${var.service_account_name} -o jsonpath='{.metadata.annotations}'"
  description = "Command showing the IRSA annotations the chart wrote. The role ARN here has to be a real ARN: the _monolithic template passed an unconverted CloudFormation reference, so this printed a literal placeholder and every AWS-backed scaler silently failed to authenticate"
}
output "operator_logs_command" {
  value       = "kubectl -n ${helm_release.keda.namespace} logs deploy/${helm_release.keda.name}-operator -f"
  description = "Command following the operator's log, where a scaler's authentication and metric queries either succeed or explain themselves. The first place to look when a ScaledObject has no metric value"
}
