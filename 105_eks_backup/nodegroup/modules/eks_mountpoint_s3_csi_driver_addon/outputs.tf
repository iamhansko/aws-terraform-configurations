output "mountpoint_s3_csi_driver_addon_arn" {
  value       = aws_eks_addon.mountpoint_s3_csi_driver.arn
  description = "ARN of the aws-mountpoint-s3-csi-driver EKS addon"
}
output "driver_role_arn" {
  value       = aws_iam_role.mountpoint_s3_csi_driver_iam_role.arn
  description = "ARN of the IAM role the Mountpoint S3 CSI driver assumes through IRSA"
}
output "policy_arn" {
  value       = aws_iam_policy.mountpoint_s3_csi_driver_policy.arn
  description = "ARN of the customer managed policy scoping the driver to the supplied buckets"
}
output "driver" {
  value       = "s3.csi.aws.com"
  description = "CSI driver name this addon registers, re-exposed so a PersistentVolume elsewhere references one source of truth rather than hardcoding the string again (rules.md B-5)"
}
output "allow_delete" {
  value       = var.allow_delete
  description = "Whether the driver's policy grants s3:DeleteObject, re-exposed so a PersistentVolume's allow-delete mount option is derived from the same switch instead of being set independently (rules.md B-5)"
}
