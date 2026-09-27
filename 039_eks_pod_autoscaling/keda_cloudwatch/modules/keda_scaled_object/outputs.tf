output "name" {
  value       = var.name
  description = "Name of the ScaledObject"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the ScaledObject and TriggerAuthentication live in, re-exposed so the caller does not restate it (rules.md B-5)"
}
output "trigger_authentication_name" {
  value       = var.trigger_authentication_name
  description = "Name of the TriggerAuthentication the trigger references"
}
output "replica_range" {
  value       = "${var.min_replica_count}-${var.max_replica_count}"
  description = "Replica range KEDA keeps the target within. The floor is 1 rather than 0 on purpose: with no pod there is no request to serve, so the metric would stay at zero and nothing would scale back up"
}
output "metric_expression" {
  value       = local.metric_expression
  description = "The CloudWatch Metrics Insights query the scaler runs. Worth reading closely: the identifier in the WHERE clause is the load balancer's arn_suffix, and a query that matches nothing returns no datapoints, which with ignoreNullValues true is treated as no load rather than as an error"
}
output "target_metric_value" {
  value       = var.target_metric_value
  description = "Requests per period each replica is expected to absorb. KEDA divides the observed value by this, so it is read together with the period below"
}
output "metric_stat_period" {
  value       = var.metric_stat_period
  description = "Seconds each aggregation covers, which is what makes the target value a rate rather than a bare number"
}
output "hpa_command" {
  value       = "kubectl -n ${var.namespace} get hpa keda-hpa-${var.name} --watch"
  description = "Command watching the HorizontalPodAutoscaler KEDA creates from this ScaledObject. KEDA does not scale the workload itself - it publishes an external metric and lets an HPA act on it, which is why the replica count moves on the HPA's schedule rather than on pollingInterval"
}
output "scaled_object_command" {
  value       = "kubectl -n ${var.namespace} get scaledobject ${var.name} -o wide"
  description = "Command showing whether KEDA accepted this object. READY false with ACTIVE unknown usually means authentication failed rather than that the metric is low - the reason is in the operator's log"
}
# The labelSelector is not optional. KEDA's metrics apiserver resolves an external
# metric by the scaledobject.keda.sh/name label rather than by the path alone, so the
# same request without it answers "the server could not find the requested resource" -
# which reads like the metric does not exist, when in fact the scaler is working and
# the query is simply incomplete. It is the selector the HPA KEDA generates carries in
# spec.metrics[0].external.metric.selector, so this mirrors what the HPA asks for.
output "metric_value_command" {
  value       = "kubectl get --raw '/apis/external.metrics.k8s.io/v1beta1/namespaces/${var.namespace}/s0-aws-cloudwatch?labelSelector=scaledobject.keda.sh%2Fname%3D${var.name}'"
  description = "Command reading the metric value KEDA is publishing, straight from the external metrics API. The most direct answer to whether the CloudWatch query is returning anything, without reading logs. The labelSelector is required: KEDA's metrics apiserver matches on the scaledobject.keda.sh/name label, and the same path without it returns NotFound as though no metric existed"
}
