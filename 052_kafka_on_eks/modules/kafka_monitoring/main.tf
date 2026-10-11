# What turns the Kafka cluster's metrics into Grafana dashboards: the blueprint's monitoring-manifests/
# directory - four PodMonitors and four dashboard ConfigMaps - which the 052 workbench used to kubectl
# apply. Prometheus selects every PodMonitor in the cluster (modules/kube_prometheus_stack sets
# podMonitorSelectorNilUsesHelmValues to false), and Grafana's dashboard sidecar loads every ConfigMap
# in its namespace that carries the grafana_dashboard label.
locals {
  # The relabelings the blueprint applied to the Kafka pods' metrics, so dashboards can group by node and
  # pod. Written once and used by the one PodMonitor that needs them.
  kafka_resources_relabelings = [
    {
      separator   = ";"
      regex       = "__meta_kubernetes_pod_label_(strimzi_io_.+)"
      replacement = "$1"
      action      = "labelmap"
    },
    {
      sourceLabels = ["__meta_kubernetes_namespace"]
      separator    = ";"
      regex        = "(.*)"
      targetLabel  = "namespace"
      replacement  = "$1"
      action       = "replace"
    },
    {
      sourceLabels = ["__meta_kubernetes_pod_name"]
      separator    = ";"
      regex        = "(.*)"
      targetLabel  = "kubernetes_pod_name"
      replacement  = "$1"
      action       = "replace"
    },
    {
      sourceLabels = ["__meta_kubernetes_pod_node_name"]
      separator    = ";"
      regex        = "(.*)"
      targetLabel  = "node_name"
      replacement  = "$1"
      action       = "replace"
    },
    {
      sourceLabels = ["__meta_kubernetes_pod_host_ip"]
      separator    = ";"
      regex        = "(.*)"
      targetLabel  = "node_ip"
      replacement  = "$1"
      action       = "replace"
    },
  ]
  # One entry per blueprint PodMonitor file. All four live in the Kafka namespace, as the blueprint put
  # them; each one's namespaceSelector says where the pods it scrapes actually are - which for the
  # cluster operator is the operator's own namespace.
  pod_monitors = {
    "kafka-resources-metrics" = {
      selector = {
        matchExpressions = [{
          key      = "strimzi.io/kind"
          operator = "In"
          values   = ["Kafka", "KafkaConnect", "KafkaMirrorMaker", "KafkaMirrorMaker2"]
        }]
      }
      namespaces = [var.kafka_namespace]
      endpoint = {
        path        = "/metrics"
        port        = "tcp-prometheus"
        relabelings = local.kafka_resources_relabelings
      }
    }
    "cluster-operator-metrics" = {
      selector   = { matchLabels = { "strimzi.io/kind" = "cluster-operator" } }
      namespaces = [var.operator_namespace]
      endpoint   = { path = "/metrics", port = "http" }
    }
    "entity-operator-metrics" = {
      selector   = { matchLabels = { "app.kubernetes.io/name" = "entity-operator" } }
      namespaces = [var.kafka_namespace]
      endpoint   = { path = "/metrics", port = "healthcheck" }
    }
    # Matches nothing in this project, which deploys no KafkaBridge. Carried because the blueprint's
    # directory had it, and it costs nothing until a bridge exists.
    "bridge-metrics" = {
      selector   = { matchLabels = { "strimzi.io/kind" = "KafkaBridge" } }
      namespaces = [var.kafka_namespace]
      endpoint   = { path = "/metrics", port = "rest-api" }
    }
  }
  # ConfigMap name => the dashboard file it carries, as the blueprint named them. The JSON is vendored
  # byte for byte from those ConfigMaps. The ZooKeeper dashboard has nothing to show on a KRaft cluster;
  # it is carried because the blueprint applied it.
  dashboards = {
    "strimzi-exporter-dashboard"  = "strimzi-exporter.json"
    "strimzi-kafka-dashboard"     = "strimzi-kafka.json"
    "strimzi-operators-dashboard" = "strimzi-operators.json"
    "strimzi-zookeeper-dashboard" = "strimzi-zookeeper.json"
  }
}

resource "kubectl_manifest" "pod_monitor" {
  for_each = local.pod_monitors

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = each.key
      namespace = var.kafka_namespace
      labels    = { app = "strimzi" }
    }
    spec = {
      selector            = each.value.selector
      namespaceSelector   = { matchNames = each.value.namespaces }
      podMetricsEndpoints = [each.value.endpoint]
    }
  })
}

resource "kubectl_manifest" "dashboard" {
  for_each = local.dashboards

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = each.key
      namespace = var.grafana_namespace
      labels    = { (var.dashboard_label_key) = var.dashboard_label_value }
    }
    data = {
      (each.value) = file("${path.module}/dashboards/${each.value}")
    }
  })

  # Server-side apply, so no kubectl.kubernetes.io/last-applied-configuration annotation is written. A
  # client-side apply copies the whole object into that annotation, and these dashboards run to 69 KB -
  # a fair share of the 256 KiB the API server allows for all of an object's annotations together.
  server_side_apply = true
}
