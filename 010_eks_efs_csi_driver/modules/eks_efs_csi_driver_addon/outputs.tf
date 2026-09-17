output "efs_csi_driver_addon_arn" {
  value       = aws_eks_addon.efs_csi_driver.arn
  description = "ARN of the aws-efs-csi-driver EKS addon"
}
output "controller_role_arn" {
  value       = aws_iam_role.efs_csi_driver_iam_role.arn
  description = "ARN of the IAM role the EFS CSI controller assumes through IRSA"
}
output "provisioner" {
  value       = "efs.csi.aws.com"
  description = "CSI driver name this addon registers, re-exposed so a StorageClass elsewhere references one source of truth rather than hardcoding the string again (rules.md B-5)"
}
