# Shlink's data directory: an encrypted EFS file system, one access point that pins the owner, a mount target
# per zone, and the security groups on both ends of the NFS connection.
#
# The client group is the part the _monolithic template did not have. It allowed NFS from the Shlink tasks'
# own security group, which works until you try to keep it in modules: the task group belongs to the service
# that mounts this file system, the service has to wait for the mount targets, and the mount targets' group
# has to name the task group - a cycle between the two modules. A group created here and attached to the tasks
# as an extra group breaks it, and states what the rule actually means: "whoever carries this group may mount".
resource "aws_efs_file_system" "file_system" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  tags = {
    Name = var.name
  }
  # The _monolithic template carried lifecycle { prevent_destroy = true } here - CloudFormation's
  # DeletionPolicy: Retain, translated. It is not the same thing. Retain lets the stack delete and leaves the
  # file system behind; prevent_destroy makes terraform destroy fail outright, for the whole root, and it
  # cannot be switched off with a variable. So it is gone, and keeping the data is left to the backup policy
  # below, whose recovery points outlive the file system - see the root's teardown output.
}
# Daily AWS Backup copies, as the _monolithic template had it. This is what survives a terraform destroy:
# the recovery points belong to the backup vault, not to the file system.
resource "aws_efs_backup_policy" "file_system" {
  file_system_id = aws_efs_file_system.file_system.id
  backup_policy {
    status = var.backup_enabled ? "ENABLED" : "DISABLED"
  }
}
# The one entry point the task uses. It forces every NFS operation to run as the POSIX user Shlink's image
# runs as, and creates the directory with that owner on first mount - without it the container cannot write
# to the root of a fresh file system, which is owned by root.
resource "aws_efs_access_point" "access_point" {
  file_system_id = aws_efs_file_system.file_system.id
  posix_user {
    uid = var.posix_uid
    gid = var.posix_gid
  }
  root_directory {
    path = var.root_directory_path
    creation_info {
      owner_uid   = var.posix_uid
      owner_gid   = var.posix_gid
      permissions = var.root_directory_permissions
    }
  }
  tags = {
    Name = var.name
  }
}
# --- Security groups --------------------------------------------------------------------------------------
resource "aws_security_group" "mount_target" {
  name        = "${var.name}-efs-mount-target"
  description = "NFS into the ${var.name} EFS mount targets"
  vpc_id      = var.vpc_id
  tags = {
    Name = "${var.name}-efs-mount-target"
  }
}
resource "aws_security_group" "client" {
  name        = "${var.name}-efs-client"
  description = "Carried by whatever may mount the ${var.name} EFS file system"
  vpc_id      = var.vpc_id
  tags = {
    Name = "${var.name}-efs-client"
  }
}
# Standalone rules (rules.md F-2). The client group is always a source; any further sources come in as a map
# keyed by a caller-chosen label, because their IDs are other modules' outputs (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "nfs_from_client" {
  security_group_id            = aws_security_group.mount_target.id
  description                  = "NFS from the EFS client security group"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.client.id
}
resource "aws_vpc_security_group_ingress_rule" "nfs_from_source" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.mount_target.id
  description                  = "NFS from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = each.value
}
# The client group needs no rules of its own: membership is the whole of its meaning. Whatever carries it
# reaches the mount targets through its other group's egress.
#
# --- Mount targets ----------------------------------------------------------------------------------------
#
# for_each over a map keyed by zone letter. The keys are known at plan and the subnet IDs are not, which is
# exactly the shape for_each needs (rules.md B-8). The _monolithic template declared one resource per zone.
resource "aws_efs_mount_target" "mount_target" {
  for_each        = var.subnet_ids_by_zone
  file_system_id  = aws_efs_file_system.file_system.id
  subnet_id       = each.value
  security_groups = [aws_security_group.mount_target.id]
}
