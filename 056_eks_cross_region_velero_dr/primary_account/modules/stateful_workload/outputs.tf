output "name" {
  value       = var.name
  description = "Name of the StatefulSet"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace it runs in, re-exposed so the caller's backup command and diagnostic commands read one value (rules.md B-5)"
}
output "service_name" {
  value       = var.service_name
  description = "Name of the Service, re-exposed for the address lookup command"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status statefulset ${var.name} --timeout=10m"
  description = "Waits for the pods. A StatefulSet starts its pods one at a time and each waits for its volume, so this is slower than a Deployment of the same size - and it stalls indefinitely if the EBS CSI driver is missing"
}
output "volume_check_command" {
  value       = "kubectl -n ${var.namespace} get pvc,pv -o wide"
  description = "One claim per pod, each Bound to a volume. A claim stuck Pending is the EBS CSI driver or a StorageClass name that does not exist - and with WaitForFirstConsumer binding it stays Pending until its pod is scheduled, which is normal for a few seconds and a problem after a minute"
}
output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get service ${var.service_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "The NLB address. Empty means the AWS Load Balancer Controller has not reconciled the Service - and an address that resolves to a Classic Load Balancer means the in-tree provider claimed it instead, which happens when the aws-load-balancer-type annotation is missing (rules.md G-1)"
}
output "write_test_data_command" {
  value       = "kubectl -n ${var.namespace} exec ${var.name}-0 -- sh -c 'echo \"hello from ${var.name}-0 at $(date -u)\" > ${var.mount_path}/index.html'"
  description = "Puts something in the volume. Do this before taking the backup: without it the volume is empty, and a restore that produces an empty volume is indistinguishable from a restore that moved no data at all - which is exactly the failure worth catching"
}
output "read_test_data_command" {
  value       = "kubectl -n ${var.namespace} exec ${var.name}-0 -- cat ${var.mount_path}/index.html"
  description = "Reads it back. Run this on the restoring cluster after the restore: the same line appearing there is the proof that the data moved, not just the Kubernetes objects"
}
output "pod_placement_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o wide"
  description = "Which node and zone each pod is on. With WaitForFirstConsumer binding the volume follows the pod's zone, so two pods on one node means both volumes are in one zone"
}
