output "namespace" {
  value       = var.namespace
  description = "Namespace the DaemonSet runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "name" {
  value       = var.name
  description = "Name shared by the service account, the cluster role and the DaemonSet's selector label"
}
output "image" {
  value       = var.image
  description = "The Multus image actually deployed, re-exposed because the _monolithic template installed whatever upstream's master branch held on the day the instance booted and there was nothing to read the version off"
}
output "master_cni_config_file" {
  value       = var.master_cni_config_file
  description = "The CNI configuration Multus delegates the primary interface to, re-exposed because getting it wrong takes the primary interface away from every pod on the node - so it is worth being able to see the configured value rather than assuming it (rules.md B-5)"
}
output "daemon_set_check_command" {
  value       = "kubectl -n ${var.namespace} get daemonset kube-multus-ds"
  description = "Whether Multus is running on every node. DESIRED greater than READY means some node's init container has not finished copying the shim, and pods scheduled there get no extra interfaces while reporting nothing"
}
output "crd_check_command" {
  value       = "kubectl get crd network-attachment-definitions.k8s.cni.cncf.io"
  description = "The CRD this module installs. A NetworkAttachmentDefinition applied before it exists fails with \"no matches for kind\", which is a timing problem rather than a manifest problem"
}
output "cni_config_check_command" {
  value       = "kubectl -n ${var.namespace} exec ds/kube-multus-ds -- ls -1 /host/etc/cni/net.d"
  description = "What the node's CNI directory holds. Multus writes a generated 00-multus.conf there that delegates to the master config; if it is missing, the daemon started but never generated its configuration and the node is still on the VPC CNI alone"
}
output "log_command" {
  value       = "kubectl -n ${var.namespace} logs ds/kube-multus-ds --tail 100"
  description = "The daemon's log. A pod that did not get its extra interface is explained here or in /var/log/multus.log on the node, and nowhere in the pod's own events"
}
