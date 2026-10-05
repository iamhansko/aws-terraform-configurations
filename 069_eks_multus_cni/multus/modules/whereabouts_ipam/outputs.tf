output "ipam_type" {
  value       = "whereabouts"
  description = "The value an attachment's ipam.type has to carry to use this plugin. Re-exposed so the attachment names what was installed rather than a string of its own: an attachment asking for an IPAM plugin that is not on the node leaves pods in ContainerCreating, and the reason is only in the pod's events (rules.md B-5)"
}
output "name" {
  value       = var.name
  description = "Name of the DaemonSet, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace it runs in, re-exposed for the same reason"
}
output "image" {
  value       = var.image
  description = "The pinned image actually installed, worth being able to read without describing the DaemonSet"
}
output "daemon_set_check_command" {
  value       = "kubectl -n ${var.namespace} get daemonset ${var.name}"
  description = "DESIRED greater than READY means some node has not finished installing the plugin binary, and a pod scheduled there will fail to get a secondary address rather than getting a duplicate one"
}
output "allocations_command" {
  value       = "kubectl get ippools.whereabouts.cni.cncf.io -A -o custom-columns='POOL:.metadata.name,RANGE:.spec.range,ALLOCATED:.spec.allocations'"
  description = "The allocation store, which is the whole reason this plugin is here. One IPPool per range with the addresses handed out of it - cluster-wide, so a second node reads the same object rather than starting again at the bottom of the range. The pool name is the range with dots and the slash replaced, not the attachment's name"
}
output "reservations_command" {
  value       = "kubectl get overlappingrangeipreservations.whereabouts.cni.cncf.io -A"
  description = "The per-address reservations whereabouts writes when ranges can overlap. Empty is normal here, because each attachment in this project gets a range of its own"
}
output "log_command" {
  value       = "kubectl -n ${var.namespace} logs ds/${var.name} --tail 100"
  description = "Where an exhausted range, a failed lease or an address that could not be reclaimed is reported. None of those appear on the pod, the attachment or the IPPool"
}
