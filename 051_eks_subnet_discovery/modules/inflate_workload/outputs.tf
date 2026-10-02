output "namespace" {
  value       = var.namespace
  description = "Namespace the pressure workload runs in, re-exposed so the root's commands and outputs read one value (rules.md B-5)"
}
output "name" {
  value       = var.name
  description = "Name of the Deployment, re-exposed for the same reason as namespace (rules.md B-5)"
}
output "replicas" {
  value       = var.replicas
  description = "How many pods were asked for. Worth reading next to the address counts below: if this number is comfortably under what the nodes' own subnets hold, nothing has run dry and discovery has had no reason to do anything yet"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.name} --timeout=10m"
  description = "Waits for every pod to be running. Run this before reading anything into the address counts: a pod still waiting for an address looks exactly like one that was never scheduled"
}
output "pod_status_command" {
  value       = "kubectl -n ${var.namespace} get pods -o wide --sort-by .status.podIP"
  description = "Every pressure pod with its address and its node, sorted so the two address ranges appear as two blocks. Pods on the same node with addresses in different ranges is discovery working"
}
output "address_distribution_command" {
  value       = "kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{\"\\n\"}{end}' | grep . | cut -d. -f1,2 | sort | uniq -c"
  description = "The headline number: a count of every pod address in the cluster grouped by its first two octets. One group means the nodes' subnets still had room; two means the CNI found the tagged subnets and started allocating out of them"
}
output "pending_pods_command" {
  value       = "kubectl -n ${var.namespace} get pods --field-selector status.phase=Pending -o wide"
  description = "Pods that never got an address. Empty is the expected result, and the failure this whole project exists to prevent: pods stuck here while the nodes have CPU and memory to spare is what address exhaustion looks like from Kubernetes"
}
output "cni_log_command" {
  value       = "kubectl -n kube-system logs -l k8s-app=aws-node -c aws-node --tail 200 | grep -i -e subnet -e 'no free ip'"
  description = "The CNI's own account of which subnets it considered and which it chose. This is where a tag typo shows up - the agent simply never mentions the subnet you expected"
}
