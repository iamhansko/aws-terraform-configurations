resource "aws_efs_file_system" "efs_file_system" {
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode
  encrypted        = var.encrypted
  tags = {
    Name = var.name
  }
}
resource "aws_security_group" "efs_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks. Inline
# blocks are authoritative over the whole group, so anything Terraform does not
# know about gets reverted on the next apply; standalone resources are the
# provider's current recommendation and the safe default (rules.md F-2).
resource "aws_vpc_security_group_ingress_rule" "efs_source_group_ingress" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.efs_security_group.id
  description                  = "NFS from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.nfs_port
  to_port                      = var.nfs_port
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_ingress_rule" "efs_cidr_ingress" {
  for_each          = toset(var.ingress_cidr_blocks)
  security_group_id = aws_security_group.efs_security_group.id
  description       = "NFS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.nfs_port
  to_port           = var.nfs_port
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_egress_rule" "efs_egress" {
  security_group_id = aws_security_group.efs_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# One mount target per availability zone. A pod can only reach the file system
# through the mount target in its own zone, so a zone without one silently
# fails to mount rather than falling back to another zone's target.
resource "aws_efs_mount_target" "efs_mount_target" {
  for_each        = var.mount_target_subnet_ids
  file_system_id  = aws_efs_file_system.efs_file_system.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_security_group.id]
}
