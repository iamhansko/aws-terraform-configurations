output "ebs_csi_driver_addon_arn" {
  value       = aws_eks_addon.ebs_csi_driver.arn
  description = "ARN of the addon. aws_eks_addon exposes no status attribute, so this is the only thing worth taking as an output (rules.md E-5)"
}
output "role_arn" {
  value       = aws_iam_role.ebs_csi_driver.arn
  description = "ARN of the driver's IAM role. Tied to this cluster through the OIDC provider in its trust policy"
}
output "role_name" {
  value       = aws_iam_role.ebs_csi_driver.name
  description = "Name of that role, generated unless role_name was set, so two deployments in one account do not collide"
}
output "service_account" {
  value       = var.service_account_name
  description = "The service account the role's trust policy names, re-exposed so a caller checking the annotation names the same value the module used (rules.md B-5)"
}
output "irsa_check_command" {
  value       = "kubectl -n kube-system get serviceaccount ${var.service_account_name} -o jsonpath='{.metadata.annotations.eks\\.amazonaws\\.com/role-arn}' ; echo"
  description = "Prints the role ARN EKS wrote onto the controller's service account. Empty means the addon was installed without service_account_role_arn, and the controller is running on the node role's permissions, which cannot create volumes"
}
output "volume_check_command" {
  value       = "kubectl get pvc,pv --all-namespaces"
  description = "Whether claims are being bound. A PVC stuck Pending with no PV is the driver not provisioning, which is either this addon missing or its role lacking the managed policy"
}
