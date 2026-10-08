output "release_name" {
  value       = helm_release.nvidia_device_plugin.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the plugin runs in, re-exposed so a caller's diagnostic commands read one value (rules.md B-5)"
}
output "chart_version" {
  value       = var.chart_version
  description = "The pinned chart version, re-exposed because the node affinity terms a GPU node has to match belong to the chart version rather than to Kubernetes"
}
output "gpu_feature_discovery_enabled" {
  value       = var.enable_gpu_feature_discovery
  description = "Whether node-feature-discovery came along with the chart. Re-exposed because it decides which of the DaemonSet's node affinity terms is the one being satisfied, and that is not visible anywhere in the cluster (rules.md B-5)"
}
output "daemon_set_check_command" {
  value       = "kubectl -n ${var.namespace} get daemonset -l app.kubernetes.io/name=nvidia-device-plugin"
  description = "The first thing to read when no GPU is advertised. DESIRED 0 means no node matched the DaemonSet's node affinity, which is a node labelling problem rather than a driver or AMI problem - and it is the one state that still lets the Helm release report success"
}
output "plugin_pod_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app.kubernetes.io/name=nvidia-device-plugin -o wide"
  description = "Where the plugin is actually running. One pod per GPU node, on the node whose GPU it is advertising"
}
output "plugin_log_command" {
  value       = "kubectl -n ${var.namespace} logs ds/${var.release_name}-nvidia-device-plugin --tail 50"
  description = "The plugin's own log. It states the devices it found, so it distinguishes \"the plugin is not running\" from \"the plugin ran and the driver showed it no GPU\""
}
