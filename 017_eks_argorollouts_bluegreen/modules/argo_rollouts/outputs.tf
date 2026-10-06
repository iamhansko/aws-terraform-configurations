output "namespace" {
  value       = var.namespace
  description = "Namespace the controller runs in, re-exposed so the caller's verification commands do not restate it (rules.md B-5)"
}
output "release_name" {
  value       = helm_release.argo_rollouts.name
  description = "Name of the Helm release"
}
output "chart_version" {
  value       = helm_release.argo_rollouts.version
  description = "Chart version actually installed"
}
output "controller_version" {
  value       = helm_release.argo_rollouts.metadata.app_version
  description = "Controller version this chart actually installed, read from the release metadata rather than restated - it is the chart's appVersion, which is not the chart version (chart 2.40.4 carries controller v1.8.3). The caller pins the kubectl plugin separately, in user data that runs before this release exists, so the two cannot be derived from each other and are instead printed side by side for comparison (rules.md B-5)"
}
output "controller_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment/${var.release_name}"
  description = "Command confirming the controller is Available. Nothing reconciles a Rollout object until it is (rules.md H-2)"
}
output "dashboard_command" {
  value       = "kubectl argo rollouts dashboard -n ${var.namespace}"
  description = "Command opening the Argo Rollouts dashboard on localhost:3100. Run it on the bastion and reach it through the CloudFront distribution or an SSM port-forward"
}
