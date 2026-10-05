output "name" {
  value       = var.name
  description = "Base name of the Deployments. Each one is <name>-<attachment key>"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace they run in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "deployment_names" {
  value       = [for key in sort(keys(var.network_attachments)) : "${var.name}-${key}"]
  description = "The Deployments created, one per attachment. One pod each by default, so this is also the list of pods that hold a dedicated secondary ENI"
}
output "network_attachments" {
  value       = var.network_attachments
  description = "Which attachment each Deployment asks for, re-exposed so a mismatch with the attachments that actually exist is visible in terraform output rather than only as pods stuck in ContainerCreating (rules.md B-5)"
}
output "group_selector" {
  value       = "${local.group_label}=${var.name}"
  description = "Label selector matching every pod this module creates, across all of the Deployments. The app label cannot be used for that - it differs per Deployment, because a Deployment whose selector matched another one's pods would fight it for ownership"
}
output "rollout_status_command" {
  value       = join(" && ", [for key in sort(keys(var.network_attachments)) : "kubectl -n ${var.namespace} rollout status deployment ${var.name}-${key} --timeout=10m"])
  description = "Waits for every pod. A timeout here usually means Multus could not satisfy that Deployment's attachment - the node does not have the master interface, or the DaemonSet has not finished installing its shim on that node"
}
output "pod_status_command" {
  value       = "kubectl -n ${var.namespace} get pods -l ${local.group_label}=${var.name} -o wide"
  description = "Every demo pod and its node. Stuck in ContainerCreating is the Multus case; Running with one interface would be the EKS multi-NIC case, which is a different project"
}
output "pod_events_command" {
  value       = "kubectl -n ${var.namespace} describe pods -l ${local.group_label}=${var.name}"
  description = "Where a failed attachment is actually reported. Neither the Deployment, the attachment nor the DaemonSet says anything about it"
}
output "interface_list_command" {
  value       = "for p in $(kubectl -n ${var.namespace} get pods -l ${local.group_label}=${var.name} -o name); do echo \"-- $p\"; kubectl -n ${var.namespace} exec $${p#pod/} -- ip -4 -brief address; done"
  description = "The demo. Each pod should show loopback, eth0 from the VPC CNI, and exactly one net1 from Multus - one secondary interface per pod, on that pod's own ENI"
}
output "network_status_command" {
  value       = "kubectl -n ${var.namespace} get pods -l ${local.group_label}=${var.name} -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.metadata.annotations.k8s\\.v1\\.cni\\.cncf\\.io/network-status}{\"\\n\"}{end}'"
  description = "What Multus wrote back onto each pod: every interface it attached, with its address and the MAC of the ENI behind it. This is the authoritative answer, and it is an annotation Multus adds rather than anything Terraform declared"
}
output "dedicated_eni_check_command" {
  value       = "kubectl -n ${var.namespace} get pods -l ${local.group_label}=${var.name} -o jsonpath='{range .items[*]}{.metadata.annotations.k8s\\.v1\\.cni\\.cncf\\.io/network-status}{\"\\n\"}{end}' | grep -oE '\"mac\": *\"([0-9a-f]{2}:){5}[0-9a-f]{2}\"' | sort | uniq -c"
  description = "The one-line answer to whether each pod got an ENI of its own: one line per MAC, each with a count of 1. An ipvlan interface inherits its master's MAC, so these are the node's secondary ENIs - compare them with the MAC column of the ENI table. A count above one means that ENI is shared by two pods. The pattern matches real MACs only, because the VPC CNI's own entry in the same annotation reports a mac of \"0\" and would otherwise be counted too"
}
output "connectivity_check_command" {
  value       = local.connectivity_check_command
  description = "Sends traffic over the secondary network, which no other check here does - the rest read configuration, annotations or EC2 state, and every one of those can be correct while the interface reaches nothing. Pings between two pods of one Deployment over the secondary interface, because only those two share a range: another attachment's address is off-segment, leaves through eth0 and is dropped by the dedicated security group. At one pod per attachment there is no peer, so the command scales the Deployment to two, pings, and scales back - which also exercises the sidecar's preStop hook, since the ENI gains an address and then loses it again. Pods on one node never put the packet on the wire and ipvlan answers in tens of microseconds; pods on different nodes cross the VPC, and then this is the check that the sidecar's address registration actually works"
}
