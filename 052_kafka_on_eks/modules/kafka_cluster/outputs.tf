output "namespace" {
  value       = kubectl_manifest.namespace.name
  description = "Namespace of the Kafka cluster, read from the Namespace object so the PodMonitors that scrape it are created after it exists"
}
output "cluster_name" {
  value       = var.cluster_name
  description = "Name of the Kafka resource (rules.md B-5)"
}
output "kafka_version" {
  value       = var.kafka_version
  description = "Kafka version the brokers run, re-exposed so the client image in the README's commands matches it"
}
output "bootstrap_server" {
  value       = "${var.cluster_name}-kafka-bootstrap.${var.namespace}.svc:9092"
  description = "Plain-text bootstrap address inside the cluster. Strimzi names the Service <cluster>-kafka-bootstrap; derived here because that convention belongs to the operator (rules.md B-5)"
}
output "broker_pod_selector" {
  value       = "strimzi.io/cluster=${var.cluster_name},strimzi.io/pool-name=${one([for name, pool in local.node_pools : name if contains(pool.roles, "broker")])}"
  description = "Label selector matching this cluster's broker pods. By pool rather than by pod name: with node pools Strimzi assigns the node IDs in the pod names, so nothing guarantees a <cluster>-broker-0 exists"
}
output "topic_names" {
  value       = keys(var.topics)
  description = "Topics this module declares"
}
output "pods_command" {
  value       = "kubectl -n ${var.namespace} get kafka,kafkanodepool,pods -o wide"
  description = "The Kafka resource, its pools and their pods with the nodes they landed on"
}
output "ready_command" {
  value       = "kubectl -n ${var.namespace} get kafka ${var.cluster_name} -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason} {.message}{\"\\n\"}{end}'"
  description = "The Kafka resource's conditions. Ready=True is what the apply waited for; anything else carries the operator's reason"
}
output "rebalance_name" {
  value       = var.rebalance_name
  description = "Name of the KafkaRebalance resource"
}
