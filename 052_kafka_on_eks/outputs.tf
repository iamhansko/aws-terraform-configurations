# Values are all projections of local.outputs in main.tf, so no expression is written twice and the
# README the SSM association writes cannot fall behind this file (rules.md B-5/H-2).
#
# description is the one thing that cannot come from the map: Terraform rejects an expression in an
# output's description with "Variables not allowed", so the wording exists literally in both places.
# The values do not.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here; the commands below are meant for its terminal unless they say otherwise. code-server runs with no authentication and the instance role behind it is AdministratorAccess, so do not leave it reachable from the internet longer than the demo needs"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster this project built"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "The workbench's user data already ran this. Run it on your own machine to use kubectl from there"
}
output "cluster_nodes_command" {
  value       = local.outputs.cluster_nodes_command.value
  description = "The core node group plus whatever Karpenter has launched, with the label each pool is selected by. Once the cluster is up there is one node per Kafka pod in the kafka pool"
}
output "node_pools_command" {
  value       = local.outputs.node_pools_command.value
  description = "The pools, their node classes and every NodeClaim Karpenter has made. A Kafka pod that stays Pending with no NodeClaim behind it points at the pool's requirements or limits"
}
output "kafka_pods_command" {
  value       = local.outputs.kafka_pods_command.value
  description = "The Kafka resource, its controller and broker pools, and their pods with the nodes they landed on - one node each"
}
output "kafka_ready_command" {
  value       = local.outputs.kafka_ready_command.value
  description = "Ready=True is what terraform apply waited for. Anything else carries the operator's reason"
}
output "list_topics_command" {
  value       = local.outputs.list_topics_command.value
  description = "First the KafkaTopic resources this project declared, then what Kafka itself reports from inside a broker - which includes the internal topics Kafka and Cruise Control create"
}
output "producer_command" {
  value       = local.outputs.producer_command.value
  description = "Run this in one terminal and the consumer below in another, then type lines here. The pod is removed when you exit"
}
output "consumer_command" {
  value       = local.outputs.consumer_command.value
  description = "--from-beginning, so lines produced before the consumer started show up too"
}
output "rebalance_status_command" {
  value       = local.outputs.rebalance_status_command.value
  description = "Cruise Control's proposal for moving partitions between brokers. It is only a proposal: the resource reaches ProposalReady and stops there until it is approved"
}
output "rebalance_approve_command" {
  value       = local.outputs.rebalance_approve_command.value
  description = "Starts moving partitions as proposed. Annotate with strimzi.io/rebalance=refresh instead to have Cruise Control compute a new proposal first"
}
output "grafana_url_command" {
  value       = local.outputs.grafana_url_command.value
  description = "The ALB the AWS Load Balancer Controller built for the grafana Ingress. The load balancer is not a Terraform resource, so the cluster is the only place its address exists (rules.md G-1). An empty host means the controller has not reconciled the Ingress yet - kubectl -n kube-system logs deploy/aws-load-balancer-controller has the reason"
}
output "grafana_password_command" {
  value       = local.outputs.grafana_password_command.value
  description = "The user name is admin. The password lives in Secrets Manager rather than in this README, so nothing writes it to this instance's disk. The Kafka dashboards are under Dashboards, fed by the PodMonitors this project created"
}
output "amp_workspace_endpoint" {
  value       = local.outputs.amp_workspace_endpoint.value
  description = "The workspace Prometheus remote-writes to, which Grafana also has as its AMP data source"
}
output "node_viewer_command" {
  value       = local.outputs.node_viewer_command.value
  description = "A live view of node capacity and price, with each node's pool. The Kafka pods take a node each, so this is where their cost shows"
}
output "operator_log_command" {
  value       = local.outputs.operator_log_command.value
  description = "Where a Kafka, KafkaNodePool, KafkaTopic or KafkaRebalance resource the operator cannot reconcile is explained"
}
output "teardown_command" {
  value       = local.outputs.teardown_command.value
  description = "Run it from the machine that ran terraform apply - not from this IDE, which has no copy of the state and is itself destroyed. First delete anything made by hand: kubectl get kafkatopic -A should list only the topics in kafka_topics, because a topic created with kubectl keeps the Kafka namespace from ever finishing deleting, and an Ingress or LoadBalancer Service created by hand leaves its load balancer behind. Destroy waits on purpose for the topics, the Grafana ALB, every Karpenter node and the EBS volumes to go before the controllers that remove them are uninstalled"
}
