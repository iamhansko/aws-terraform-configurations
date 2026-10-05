# Every value here is a projection of local.outputs in main.tf, which the README written onto
# the VS Code instance renders from the same map - so no value expression exists twice, and an
# output cannot be added without also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an
# output's description ("Variables not allowed"), so the wording is a literal on both sides.
#
# github_token has no output in either form, and neither does the Secret it ends up in. Two
# reasons, and the second is the one that bites:
#
#   1. Every output here is also rendered into a README on an instance whose code-server has no
#      authentication in front of it (rules.md H-2), and nothing operational needs either value.
#      An authentication failure is reported on the GitRepository, which step 2 reads.
#   2. git_password is marked sensitive, so anything derived from it - including a conditional
#      that merely compares it against null - is sensitive too. An output carrying such a value
#      is rejected with "Output refers to sensitive values" even when the value itself is only a
#      Kubernetes object name, and marking the output sensitive to satisfy that would export the
#      taint rather than remove it. The module decides on the username instead, which is not
#      sensitive and which its validation keeps equivalent.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. Its terminal has kubectl and the flux CLI already pointed at the cluster"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply"
}
output "metrics_server" {
  value       = local.outputs.metrics_server.value
  description = "The metrics-server EKS addon version, and the command that says whether the metrics API podinfo's HorizontalPodAutoscaler needs is answering"
}
output "flux_version" {
  value       = local.outputs.flux_version.value
  description = "The pinned chart that installed the Flux controllers, and the namespace they run in"
}
output "gitops_repository" {
  value       = local.outputs.gitops_repository.value
  description = "The repository created in your GitHub account that this cluster follows, with its branch, path and poll interval"
}
output "gitops_repository_files" {
  value       = local.outputs.gitops_repository_files.value
  description = "The files Terraform committed into that repository: the podinfo GitRepository and Kustomization, plus the kustomization.yaml listing them"
}
output "gitops_chain" {
  value       = local.outputs.gitops_chain.value
  description = "The two-stage chain from Terraform to podinfo, written out in one line"
}
output "controllers_check_command" {
  value       = local.outputs.controllers_check_command.value
  description = "1. The Flux controllers, which have to be Available before anything else here means anything"
}
output "git_source_check_command" {
  value       = local.outputs.git_source_check_command.value
  description = "2. Your repository's fetch status and the commit currently in hand, where an authentication failure also surfaces"
}
output "kustomization_check_command" {
  value       = local.outputs.kustomization_check_command.value
  description = "3. Whether the files in your repository were applied, which means the podinfo pair rather than podinfo itself"
}
output "podinfo_objects_check_command" {
  value       = local.outputs.podinfo_objects_check_command.value
  description = "4. The podinfo GitRepository and Kustomization that arrived through Git rather than through Terraform"
}
output "podinfo_workload_check_command" {
  value       = local.outputs.podinfo_workload_check_command.value
  description = "5. The Deployment, Service and HorizontalPodAutoscaler podinfo brought, three hops from this configuration"
}
output "reconcile_watch_command" {
  value       = local.outputs.reconcile_watch_command.value
  description = "6. Both reconciliation loops as they run"
}
output "drift_test_command" {
  value       = local.outputs.drift_test_command.value
  description = "7. Changes podinfo by hand and asks Flux to reconcile, which reverts it"
}
output "podinfo_patch_demo" {
  value       = local.outputs.podinfo_patch_demo.value
  description = "8. The edit URL and the spec.patches block to append, which raises the HorizontalPodAutoscaler's floor through Git instead of by hand"
}
output "podinfo_patch_verify_command" {
  value       = local.outputs.podinfo_patch_verify_command.value
  description = "9. Reads MINPODS off the HorizontalPodAutoscaler and asks for an immediate reconciliation, to confirm the committed patch took effect"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
