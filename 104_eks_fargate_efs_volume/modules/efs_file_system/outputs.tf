output "file_system_id" {
  value       = aws_efs_file_system.efs_file_system.id
  description = "ID of the EFS file system, which a StorageClass using the EFS CSI driver passes as its fileSystemId parameter"
}
output "file_system_arn" {
  value       = aws_efs_file_system.efs_file_system.arn
  description = "ARN of the EFS file system"
}
output "dns_name" {
  value       = aws_efs_file_system.efs_file_system.dns_name
  description = "DNS name of the EFS file system, for mounting it directly from an instance"
}
output "security_group_id" {
  value       = aws_security_group.efs_security_group.id
  description = "ID of the mount targets' security group"
}
output "mount_target_ids" {
  value       = { for label, mount_target in aws_efs_mount_target.efs_mount_target : label => mount_target.id }
  description = "Mount target IDs keyed by the same labels mount_target_subnet_ids used"
}
