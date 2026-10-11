output "namespace" {
  value       = helm_release.strimzi_kafka_operator.namespace
  description = "Namespace the operator runs in, read from the release so the PodMonitor that scrapes it names the namespace it was actually installed into (rules.md B-5)"
}
output "release_name" {
  value       = helm_release.strimzi_kafka_operator.name
  description = "Name of the Helm release"
}
output "version" {
  value       = helm_release.strimzi_kafka_operator.version
  description = "Chart version installed, which is also the operator version and the tag of the quay.io/strimzi/kafka image the client commands run"
}
output "operator_log_command" {
  value       = "kubectl -n ${helm_release.strimzi_kafka_operator.namespace} logs deploy/strimzi-cluster-operator --tail 100"
  description = "The operator's log, where a Kafka or KafkaNodePool resource it cannot reconcile is explained"
}
