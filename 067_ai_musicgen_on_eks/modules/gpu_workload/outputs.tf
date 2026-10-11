output "namespace" {
  value       = var.namespace
  description = "Namespace both pods run in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "smi_pod_name" {
  value       = var.smi_pod_name
  description = "Name of the nvidia-smi pod"
}
output "app_name" {
  value       = var.app_pod_name
  description = "Name of the application Deployment"
}
output "app_replicas" {
  value       = var.app_replicas
  description = "How many application pods were asked for, re-exposed because on a cluster without time slicing anything beyond the GPU count stays Pending - so this number and the advertised GPU count together explain what happened (rules.md B-5)"
}
output "gpu_request_total" {
  value       = var.app_replicas * var.gpu_request
  description = "How many nvidia.com/gpu the application asks for in total. Compare it against what the nodes advertise: more than that and the surplus pods stay Pending, which is the whole difference between this project's two clusters"
}
output "smi_output_command" {
  value       = "kubectl -n ${var.namespace} logs ${var.smi_pod_name}"
  description = "The GPU table from inside a container. This is the proof that the driver was injected - the image itself contains no NVIDIA tooling at all"
}
output "pod_status_command" {
  value       = "kubectl -n ${var.namespace} get pods -o wide"
  description = "Both workloads and the nodes they landed on. A Pending application pod with an available GPU node is the interesting case: it means the node has advertised fewer GPUs than the pods asked for"
}
output "pending_reason_command" {
  value       = "kubectl -n ${var.namespace} get pods --field-selector status.phase=Pending -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.status.conditions[?(@.type==\"PodScheduled\")].message}{\"\\n\"}{end}'"
  description = "Why a pod is Pending, in one line each. \"Insufficient nvidia.com/gpu\" is the answer that matters here - it is the scheduler saying the advertised count is exhausted, not that the node has no GPU"
}
output "app_rollout_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.app_pod_name} --timeout=30m"
  description = "Waits for the application. Thirty minutes on purpose: the image is about 2.1 GB of CUDA and cuDNN runtime and each node pulls it once. It holds no model weights - the application downloads those after the container starts, and with no readiness probe a finished rollout does not yet mean the interface answers"
}
output "port_forward_command" {
  value       = "kubectl -n ${var.namespace} port-forward deploy/${var.app_pod_name} ${var.app_port}:${var.app_port}"
  description = "How to reach the application's web interface, which nothing publishes. Run it on the workbench instance and open localhost on that port from the IDE's own browser preview - there is no Service and no load balancer here, and the _monolithic template did not have one either despite passing --ui-expose"
}
