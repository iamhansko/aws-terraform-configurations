output "release_name" {
  value       = helm_release.gpu_operator.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the operator runs in, re-exposed so diagnostic commands read one value (rules.md B-5)"
}
output "advertised_gpu_command" {
  value       = "kubectl get nodes -o custom-columns=NODE:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,GPUS:.status.allocatable.nvidia\\.com/gpu"
  description = "What each node says it has. A GPU node showing <none> is the device plugin not running on it yet rather than a node without a GPU"
}
output "operator_pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -o wide"
  description = "The operator and its operands. On a GPU node the validator, device plugin and feature discovery pods should all reach Running or Completed"
}
