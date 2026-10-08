output "role_arn" {
  value       = aws_iam_role.pod.arn
  description = "ARN of the pod's IAM role. The caller uses it as the principal of the cluster access entry, which is a separate thing from this AWS identity (rules.md C-1)"
}

output "role_name" {
  value       = aws_iam_role.pod.name
  description = "Name of the pod's IAM role"
}

output "service_account_annotations" {
  # Only IRSA needs an annotation. Returning an empty map for Pod Identity lets the caller pass this
  # through unconditionally instead of branching at the call site (rules.md B-4).
  value       = local.use_irsa ? { "eks.amazonaws.com/role-arn" = aws_iam_role.pod.arn } : {}
  description = "Annotations the service account needs for this role to apply: the role ARN under IRSA, nothing under Pod Identity"
}

output "identity_mode" {
  value       = var.identity_mode
  description = "Which mechanism binds the role to the service account, re-exposed so the outputs show which one a given variant ended up using (rules.md B-5)"
}

output "identity_check_command" {
  value = local.use_irsa ? (
    "kubectl -n ${var.namespace} get serviceaccount ${var.service_account_name} -o jsonpath='{.metadata.annotations.eks\\.amazonaws\\.com/role-arn}{\"\\n\"}'"
    ) : (
    "aws eks list-pod-identity-associations --cluster-name ${var.cluster_name} --namespace ${var.namespace} --service-account ${var.service_account_name} --query 'associations[].associationArn' --output table"
  )
  description = "Confirms the binding exists. Under IRSA that is an annotation on the service account; under Pod Identity it is an association held by EKS and nothing in the manifest shows it"
}
