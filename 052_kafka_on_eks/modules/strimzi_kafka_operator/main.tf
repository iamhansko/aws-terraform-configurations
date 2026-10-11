# The Strimzi cluster operator, which is what turns the Kafka and KafkaNodePool resources in
# modules/kafka_cluster into brokers, controllers, the entity operator, Cruise Control and the Kafka
# exporter.
#
# The blueprint installed this through aws-ia/eks-data-addons (enable_strimzi_kafka_operator) with
# helm-values/strimzi-kafka-values.yaml. The release name, repository, chart, namespace and values below
# are that module's defaults and that file's contents, so the operator is the one the blueprint ran.
# The values are an HCL object rendered with yamlencode rather than --set entries, so every value keeps
# its type on the way into the chart (rules.md E-7).
locals {
  values = {
    replicas = var.replica_count
    # Every namespace, as the blueprint had it. The Kafka cluster lives in its own namespace, not the
    # operator's, so a narrower watch list would have to name it - and the chart documents that setting
    # watchNamespaces to the release namespace itself fails on duplicate RoleBindings.
    watchNamespaces   = []
    watchAnyNamespace = true
    # The operator image tag follows the chart version rather than being a second setting. The
    # blueprint pinned both to 0.46.0 in two places; they are only correct together.
    defaultImageRegistry   = "quay.io"
    defaultImageRepository = "strimzi"
    defaultImageTag        = var.chart_version
    # The core node group, not a Karpenter pool: the operator has to be running before the Kafka
    # brokers exist, so it cannot depend on capacity provisioned for them.
    nodeSelector = var.node_selector
    resources = {
      limits = {
        memory = var.memory_limit
        cpu    = var.cpu_limit
      }
      requests = {
        memory = var.memory_request
        cpu    = var.cpu_request
      }
    }
    livenessProbe = {
      initialDelaySeconds = 10
      periodSeconds       = 30
    }
    readinessProbe = {
      initialDelaySeconds = 10
      periodSeconds       = 30
    }
  }
}
resource "helm_release" "strimzi_kafka_operator" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "strimzi-kafka-operator"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Blocks until the operator Deployment is Available, so the Kafka resources applied after this module
  # meet a running operator rather than sitting unreconciled.
  wait          = true
  wait_for_jobs = true
  timeout       = var.timeout_seconds
  max_history   = 3

  values = [yamlencode(local.values)]

  # Not atomic, unlike the blueprint's release: an atomic install that fails rolls itself back and takes
  # its own release history with it, which is the only record of why it failed (rules.md E-7).
}
