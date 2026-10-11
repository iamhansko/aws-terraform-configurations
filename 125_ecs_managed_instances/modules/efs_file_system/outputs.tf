output "file_system_id" {
  value       = aws_efs_file_system.file_system.id
  description = "ID of the file system"
}
output "file_system_arn" {
  value       = aws_efs_file_system.file_system.arn
  description = "ARN of the file system, for scoping a task role's elasticfilesystem:Client* actions"
}
output "access_point_id" {
  value       = aws_efs_access_point.access_point.id
  description = "ID of the access point the task mounts through"
}
output "access_point_arn" {
  value       = aws_efs_access_point.access_point.arn
  description = "ARN of the access point, which the task role's policy pins its mount to"
}
output "client_security_group_id" {
  value       = aws_security_group.client.id
  description = "Security group that grants NFS into the mount targets to whatever carries it. Attach it to the tasks that mount this file system"
}
output "mount_target_ids" {
  value       = { for zone, target in aws_efs_mount_target.mount_target : zone => target.id }
  description = "Mount target per zone. A consumer that has to wait for these should depend on this module as a whole"
}
output "mount_targets_command" {
  value       = "aws efs describe-mount-targets --file-system-id ${aws_efs_file_system.file_system.id} --query 'MountTargets[].[AvailabilityZoneName,LifeCycleState,IpAddress]' --output table"
  description = "Whether a mount target exists and is available in each zone. A task placed in a zone without one fails with a mount timeout"
}
