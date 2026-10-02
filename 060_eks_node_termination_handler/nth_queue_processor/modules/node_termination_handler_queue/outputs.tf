output "release_name" {
  value       = helm_release.node_termination_handler.name
  description = "Name of the release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the handler runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "chart_version" {
  value       = var.chart_version
  description = "Version installed, pinned where the _monolithic template left it floating"
}
output "iam_role_arn" {
  value       = aws_iam_role.node_termination_handler_iam_role.arn
  description = "ARN of the IRSA role the handler assumes. Queue mode needs credentials where IMDS mode needs none, and this role is the whole of that difference on the IAM side"
}
output "managed_tag" {
  value       = var.managed_tag
  description = "The instance tag the handler requires before it will drain a node, re-exposed so a caller can check it against what the node groups actually tag (rules.md B-5). A mismatch means no node is ever drained, with no error anywhere"
}
output "status_command" {
  value       = "kubectl -n ${var.namespace} get deployment ${var.release_name} -o wide"
  description = "A Deployment, not a DaemonSet - which is the visible difference from IMDS mode. Its replica count has nothing to do with the node count: one pod reading the queue covers the whole cluster"
}
output "log_command" {
  value       = "kubectl -n ${var.namespace} logs -l app.kubernetes.io/name=aws-node-termination-handler --tail 200 --all-containers"
  description = "What the handler read from the queue and what it did about it. An AccessDenied on ReceiveMessage here means the IRSA role is not being assumed; a message logged as skipped means the instance was missing the managed tag"
}
output "drain_event_command" {
  value       = "kubectl get events --all-namespaces --field-selector reason=NodeNotSchedulable --sort-by=.lastTimestamp"
  description = "The cordon the handler applied, as a Kubernetes event. Only present because emit_kubernetes_events is on - with the chart's default it is off, and the only record of a drain is the handler's own log"
}
