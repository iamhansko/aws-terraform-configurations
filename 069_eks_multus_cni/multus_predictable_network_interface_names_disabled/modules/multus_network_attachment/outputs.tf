output "name" {
  value       = var.name
  description = "Name of the attachment, which is the string a pod's k8s.v1.cni.cncf.io/networks annotation has to carry"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the attachment lives in. A pod in another namespace has to write the annotation as <namespace>/<name> or Multus will not find it (rules.md B-5)"
}
output "master_interface" {
  value       = var.master_interface
  description = "The host interface the attachment uses, re-exposed because it is the one value that differs between this project's two Multus variants and the thing to check first when a pod will not start"
}
output "pod_range_cidr" {
  value       = local.pod_range_cidr
  description = "The block this attachment hands addresses out of, derived from the subnet rather than given. The caller reserves exactly this block in the VPC by reading it from here, so the two cannot name different blocks - and if they did, the VPC would eventually assign an ENI an address Multus had already given a pod (rules.md B-5)"
}
output "range_start" {
  value       = local.range_start
  description = "First address host-local will hand out"
}
output "range_end" {
  value       = local.range_end
  description = "Last address host-local will hand out. One below the block's end, because AWS reserves the final address of every subnet"
}
output "cni_config" {
  value       = local.cni_config
  description = "The CNI configuration as a typed object, before it is serialised into the CRD's string field. Re-exposed so a caller can see what was actually sent without reading it back out of the cluster"
}
output "check_command" {
  value       = "kubectl -n ${var.namespace} get network-attachment-definitions ${var.name} -o jsonpath='{.spec.config}'"
  description = "The configuration as the cluster holds it. Worth comparing against the node's actual interfaces: the attachment is accepted whatever master it names, and only a pod asking for it finds out"
}
output "config_revision" {
  value       = substr(sha1(jsonencode(local.cni_config)), 0, 12)
  description = "A short digest of the CNI configuration above, for a caller to put on its pod template. Multus reads a NetworkAttachmentDefinition when it plumbs a pod and never again, so editing this attachment leaves every running pod on the configuration it was created with - the object says one subnet and the interfaces in the pods say another, and nothing reports the difference. A pod template carrying this value changes whenever the configuration does, which is what makes Kubernetes replace those pods (rules.md B-5)"
}
