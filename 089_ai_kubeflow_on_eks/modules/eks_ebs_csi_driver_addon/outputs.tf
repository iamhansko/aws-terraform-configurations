output "ebs_csi_driver_addon_arn" {
  value       = aws_eks_addon.ebs_csi_driver.arn
  description = "ARN of the addon. aws_eks_addon exposes no status attribute, so this is the only thing worth taking as an output (rules.md E-5)"
}
output "role_arn" {
  value       = aws_iam_role.ebs_csi_driver.arn
  description = "ARN of the driver's IAM role. Reusable across clusters because Pod Identity puts nothing cluster-specific in the trust policy - pass it to a second cluster's addon rather than creating a second role"
}
output "role_name" {
  value       = aws_iam_role.ebs_csi_driver.name
  description = "Name of that role, generated unless role_name was set, so two deployments in one account do not collide"
}
output "service_account" {
  value       = var.service_account_name
  description = "The service account the Pod Identity association binds, re-exposed so a caller checking the association names the same value the module used (rules.md B-5)"
}
output "pod_identity_check_command" {
  value       = "aws eks list-pod-identity-associations --cluster-name ${var.cluster_name} --query 'associations[].{Namespace:namespace,ServiceAccount:serviceAccount}' --output table"
  description = "Every Pod Identity association on this cluster. The driver's is created by the addon rather than by an aws_eks_pod_identity_association resource, so this is where to confirm it exists - it will not appear as a separate resource in terraform state"
}
output "volume_check_command" {
  value       = "kubectl get pvc,pv --all-namespaces"
  description = "Whether claims are being bound. A PVC stuck Pending with no PV is the driver not provisioning, which is either this addon missing or its role lacking the managed policy - and from the Deployment's side it looks identical to a pod that is simply slow to start"
}
