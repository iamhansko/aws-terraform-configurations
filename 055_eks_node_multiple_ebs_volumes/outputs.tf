# Every value here is a projection of local.outputs in main.tf. No output declares its
# own value expression: the same map is what the README on the VS Code instance is
# rendered from, so an output written directly here would be missing from that README and
# nothing would report it - the apply succeeds either way (rules.md H-2).
#
# description is the one exception. Terraform does not allow an expression there
# ("Variables not allowed"), so the wording exists as a literal in both places while the
# value still exists in only one.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The commands below are meant to be run from its terminal"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. No Terraform provider needed it during apply - nothing in this project creates Kubernetes objects"
}
output "container_volume" {
  value       = local.outputs.container_volume.value
  description = "The extra volume attached to every node and the directory it carries, which is the whole change this project makes"
}
output "device_naming_note" {
  value       = local.outputs.device_naming_note.value
  description = "Resolves the block device mapping name to the nvme path the kernel actually assigned, via the udev symlink amazon-ec2-utils creates"
}
output "node_id_command" {
  value       = local.outputs.node_id_command.value
  description = "Instance IDs for the node group, for the Session Manager commands that follow"
}
output "session_command" {
  value       = local.outputs.session_command.value
  description = "Opens a shell on a node through Session Manager, without the key pair and without an inbound rule"
}
output "mount_check_command" {
  value       = local.outputs.mount_check_command.value
  description = "Confirms the container runtime volume is mounted. No line means containerd is on the root volume, which looks normal from Kubernetes"
}
output "fstab_check_command" {
  value       = local.outputs.fstab_check_command.value
  description = "Confirms the mount survives a reboot. Without the fstab entry containerd silently returns to the root volume on the next boot"
}
output "sandbox_image_check_command" {
  value       = local.outputs.sandbox_image_check_command.value
  description = "Confirms the AMI's pre-imported pause image survived the move, which is what seeding the new filesystem rather than wiping it achieves"
}
output "cloud_init_log_command" {
  value       = local.outputs.cloud_init_log_command.value
  description = "What the setup did, and where the AL2 versus AL2023 ordering difference behind the bootcmd choice shows up"
}
output "disk_pressure_command" {
  value       = local.outputs.disk_pressure_command.value
  description = "The kubelet's image filesystem capacity, which is now the extra volume's rather than the root volume's"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl on the instance at the cluster. User data already ran this"
}
