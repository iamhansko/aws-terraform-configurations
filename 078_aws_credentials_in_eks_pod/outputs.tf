# Every value here is a projection of local.outputs in main.tf, which the README written onto the VS Code
# instance renders from the same map - so no value expression exists twice, and an output cannot be added
# without also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. Its kubeconfig has one context per cluster, named after the cluster"
}
output "clusters" {
  value       = local.outputs.clusters.value
  description = "The three clusters and how each one gives its pod credentials"
}
output "roles" {
  value       = local.outputs.roles.value
  description = "The roles each mechanism hands out, both scoped to reading one bucket - and the node role the IMDS pod ends up with instead"
}
output "demo_bucket" {
  value       = local.outputs.demo_bucket.value
  description = "The bucket every identity is measured against, and the object in it that makes a successful listing distinguishable from a swallowed denial"
}
output "identity_commands" {
  value       = local.outputs.identity_commands.value
  description = "1. Asks each pod who it is, which is the demo in three commands"
}
output "credential_source_commands" {
  value       = local.outputs.credential_source_commands.value
  description = "2. Asks each pod how the credentials arrived, rather than which ones"
}
output "bucket_access_commands" {
  value       = local.outputs.bucket_access_commands.value
  description = "3. Shows which identity can actually read the bucket, and which is denied"
}
output "node_role_grant_command" {
  value       = local.outputs.node_role_grant_command.value
  description = "4. Grants the bucket access to the shared node role, which makes the IMDS pod succeed and every other pod on every node succeed too"
}
output "imds_hop_limit_note" {
  value       = local.outputs.imds_hop_limit_note.value
  description = "5. The network setting the IMDS case depends on, and how to break it deliberately"
}
output "pod_status_commands" {
  value       = local.outputs.pod_status_commands.value
  description = "6. The pods on all three clusters, for when one is not running"
}
output "shell_command" {
  value       = local.outputs.shell_command.value
  description = "7. A shell inside one of the pods, with whatever identity it was given"
}
output "update_kubeconfig_commands" {
  value       = local.outputs.update_kubeconfig_commands.value
  description = "Re-points kubectl at all three clusters, with one distinct context each"
}
