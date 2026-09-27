output "release_name" {
  value       = helm_release.vertical_pod_autoscaler.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = helm_release.vertical_pod_autoscaler.namespace
  description = "Namespace the VPA components run in, re-exposed so a caller building a kubectl command does not restate it (rules.md B-5)"
}
output "chart_version" {
  value       = helm_release.vertical_pod_autoscaler.version
  description = "Chart version installed, re-exposed so the pinned value is visible without reading the module (rules.md B-5)"
}
output "components_command" {
  value       = "kubectl -n ${helm_release.vertical_pod_autoscaler.namespace} get deploy"
  description = "Command listing the three VPA components. The recommender writes recommendations, the updater evicts pods that are far from them, and the admission controller rewrites requests on replacement pods - a VPA in Auto mode needs all three"
}
output "crd_command" {
  value       = "kubectl get crd verticalpodautoscalers.autoscaling.k8s.io"
  description = "Command confirming the CRD exists. It ships in the chart's crds/ directory, so helm installs it ahead of the templates - the ordering hack/vpa-up.sh had to arrange by hand"
}
