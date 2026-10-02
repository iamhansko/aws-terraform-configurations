output "chart_version" {
  value       = var.chart_version
  description = "Version the chart was installed at, re-exposed so the data plane version is visible in terraform output rather than only inside a release (rules.md B-5)"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Cilium runs in, re-exposed so the root's commands read one value (rules.md B-5)"
}
output "operator_role_arn" {
  value       = aws_iam_role.cilium_operator_iam_role.arn
  description = "ARN of the operator's IRSA role. The permissions it carries are wider than AmazonEKS_CNI_Policy, which is what the VPC CNI needs and is not enough for Cilium in ENI mode"
}
output "ipam_mode" {
  value       = var.ipam_mode
  description = "How pod addresses are allocated, re-exposed because it decides whether pod addresses are VPC addresses - and therefore whether a load balancer with target-type ip can reach them at all (rules.md B-5)"
}
output "kube_proxy_replacement" {
  value       = var.kube_proxy_replacement
  description = "Whether Cilium is implementing Services instead of kube-proxy. With no kube-proxy addon installed on this cluster, false here would leave Services unimplemented - reachable pod addresses and no ClusterIP routing"
}
output "status_command" {
  value       = "cilium status --wait"
  description = "The cilium CLI's own summary: agent and operator counts, IPAM mode, and whether kube-proxy replacement is active. The CLI is installed on the bastion by user data"
}
output "agent_status_command" {
  value       = "kubectl -n ${var.namespace} get daemonset ${var.release_name} -o wide && kubectl -n ${var.namespace} get deployment ${var.release_name}-operator"
  description = "The same two components straight from the API server, for when the CLI is not to hand. A DaemonSet with zero desired pods means no node has joined yet"
}
output "kube_proxy_absence_command" {
  value       = "kubectl -n kube-system get daemonset kube-proxy 2>&1 | tail -1 ; kubectl -n kube-system get daemonset aws-node 2>&1 | tail -1"
  description = "Both should report NotFound. This is the check that the _monolithic template would have failed: with bootstrap_self_managed_addons left at true, EKS installs vpc-cni and kube-proxy at cluster creation, and a cluster with both plus Cilium looks healthy while demonstrating nothing"
}
output "service_routing_command" {
  value       = "kubectl -n ${var.namespace} exec ds/${var.release_name} -c cilium-agent -- cilium-dbg service list | head -20"
  description = "The Service backends Cilium is routing, which is the work kube-proxy would otherwise be doing in iptables. An empty list with Services present means kube-proxy replacement is not actually in effect"
}
output "connectivity_test_command" {
  value       = "cilium connectivity test --test-namespace cilium-test"
  description = "Cilium's own end-to-end suite. It creates and deletes its own namespace, so it is left as a command rather than a Terraform resource - the objects are meant to be temporary, and Terraform owning them would mean a permanent diff"
}
