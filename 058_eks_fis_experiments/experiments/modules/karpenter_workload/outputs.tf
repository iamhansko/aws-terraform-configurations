output "name" {
  value       = var.name
  description = "Name of the Deployment"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace it runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "node_selector" {
  value       = var.node_selector
  description = "The labels these pods require, re-exposed so a mismatch with what the node pool actually applies is visible in terraform output rather than only as pods stuck Pending (rules.md B-5)"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.name} --timeout=15m"
  description = "Waits for the pods. Long timeout on purpose: the first ones wait for Karpenter to provision a node, which means an EC2 launch and a kubelet join rather than a schedule onto existing capacity"
}
output "pod_placement_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o wide"
  description = "Which node each pod landed on. Every one should be on a Karpenter node - a pod that is Pending means no pool matched its selector, and Karpenter will not provision for a label no pool applies"
}
output "node_list_command" {
  value       = "kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type,node.kubernetes.io/instance-type"
  description = "Every node with the pool that provisioned it and whether it is spot or on-demand. This is the before-and-after view for an experiment: run it, start the experiment, run it again"
}
