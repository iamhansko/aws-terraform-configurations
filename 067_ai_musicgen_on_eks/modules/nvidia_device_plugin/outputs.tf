output "release_name" {
  value       = helm_release.nvidia_device_plugin.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the plugin runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "chart_version" {
  value       = var.chart_version
  description = "The pinned chart version, re-exposed because the time-slicing configuration format belongs to the plugin version rather than to Kubernetes"
}
output "time_slicing_replicas" {
  value       = var.time_slicing_replicas
  description = "How many slices each GPU is advertised as, or null when time slicing is off. Re-exposed because this single number is the entire difference between this project's two clusters, and nothing in the cluster states it in one place (rules.md B-5)"
}
output "daemon_set_check_command" {
  value       = "kubectl -n ${var.namespace} get daemonset -l app.kubernetes.io/name=nvidia-device-plugin"
  description = "Whether the plugin is running on the GPU nodes. DESIRED zero means no node matched it, which on an AL2023 NVIDIA node group means the nodes have not joined yet rather than that anything is misconfigured"
}
output "advertised_gpu_command" {
  value       = "kubectl get nodes -o custom-columns=NODE:.metadata.name,GPUS:.status.allocatable.nvidia\\.com/gpu"
  description = "What each node says it has. This is the number the whole project is about: without time slicing it is the physical GPU count, and with it the count multiplied by the replica setting - and a node showing none at all is the plugin not running rather than a node without a GPU"
}
output "config_map_check_command" {
  value       = var.time_slicing_replicas == null ? "kubectl -n ${var.namespace} get configmap | grep -c ${var.config_map_name} || echo 'no time-slicing config map, which is correct for this cluster'" : "kubectl -n ${var.namespace} get configmap ${var.config_map_name} -o jsonpath='{.data.time-slicing\\.conf}'"
  description = "The time-slicing configuration as the cluster holds it, or a note that this cluster deliberately has none. Worth reading on the time-slicing cluster: the plugin is pointed at this config map by name, and it treats a missing one as no sharing rather than as an error"
}
output "plugin_log_command" {
  value       = "kubectl -n ${var.namespace} logs ds/${var.release_name}-nvidia-device-plugin --tail 50"
  description = "The plugin's own log, which states the sharing configuration it loaded. This is the only place that distinguishes \"time slicing is off\" from \"the config map was not found\""
}
