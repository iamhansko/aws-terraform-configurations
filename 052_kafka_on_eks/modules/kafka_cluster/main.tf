# The Kafka cluster itself: the blueprint's kafka-manifests/kafka-cluster.yaml and kafka-rebalance.yaml,
# plus the example topic from examples/kafka-topics.yaml. The 052 workbench used to kubectl apply the two
# directories after the nested Terraform run; here every object is a kubectl_manifest declared as an HCL
# object with the manifest's own field names (rules.md E-1/E-3).
#
# KRaft with node pools, as the blueprint had it: three controllers and three brokers, each in a pool of
# its own, with the Kafka resource carrying everything they share.

# Created here, as the workbench's "kubectl create namespace kafka" did - and waited on when it is
# deleted. Deleting the namespace deletes the brokers' and controllers' volume claims, which the node
# pools keep after the Kafka resource is gone (deleteClaim: false). wait = true holds terraform destroy
# until the namespace is empty, so those claims are deleted while the EBS CSI driver that removes their
# volumes is still running; without it the volumes outlive the cluster (rules.md D-7).
resource "kubectl_manifest" "namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.namespace }
  })
  wait = true
}

# The JMX exporter rules the brokers' metricsConfig points at. The rule files are vendored byte for byte
# from the blueprint's ConfigMap rather than inlined as HCL strings: they are long, full of $1-style
# capture references and escaped regexes, and a file() read keeps them exactly as upstream wrote them.
# The ZooKeeper and Cruise Control entries are unused by a KRaft cluster whose Cruise Control has no
# metricsConfig; they are carried because the blueprint's ConfigMap carried them.
resource "kubectl_manifest" "metrics_config" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = local.metrics_config_name
      namespace = var.namespace
      labels    = { app = "strimzi" }
    }
    data = {
      for file_name in local.metrics_files : file_name => file("${path.module}/metrics/${file_name}")
    }
  })

  depends_on = [kubectl_manifest.namespace]
}

locals {
  metrics_config_name = "kafka-metrics"
  metrics_files       = ["kafka-metrics-config.yml", "zookeeper-metrics-config.yml", "cruise-control-config.yml"]
  # Both pools carry the cluster's name as a label, which is how Strimzi assigns a pool to a cluster -
  # and the brokers' anti-affinity below matches on the pool names, so the names live in one place.
  node_pools = {
    controller = {
      replicas = var.controller_replicas
      roles    = ["controller"]
      size     = var.controller_volume_size
    }
    broker = {
      replicas = var.broker_replicas
      roles    = ["broker"]
      size     = var.broker_volume_size
    }
  }
}

resource "kubectl_manifest" "node_pool" {
  for_each = local.node_pools

  yaml_body = yamlencode({
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaNodePool"
    metadata = {
      name      = each.key
      namespace = var.namespace
      labels    = { "strimzi.io/cluster" = var.cluster_name }
    }
    spec = {
      replicas = each.value.replicas
      roles    = each.value.roles
      storage = {
        type = "jbod"
        volumes = [{
          id            = 0
          type          = "persistent-claim"
          size          = each.value.size
          kraftMetadata = "shared"
          # false, as the blueprint had it: the claims survive the Kafka resource. The namespace's
          # wait above is what removes them on terraform destroy.
          deleteClaim = false
        }]
      }
    }
  })

  depends_on = [kubectl_manifest.namespace]
}

resource "kubectl_manifest" "kafka" {
  yaml_body = yamlencode({
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "Kafka"
    metadata = {
      name      = var.cluster_name
      namespace = var.namespace
      annotations = {
        "strimzi.io/kraft"      = "enabled"
        "strimzi.io/node-pools" = "enabled"
      }
    }
    spec = {
      kafka = {
        version         = var.kafka_version
        metadataVersion = var.metadata_version
        listeners = [
          {
            name = "plain"
            port = 9092
            type = "internal"
            tls  = false
          },
          {
            name = "tls"
            port = 9093
            type = "internal"
            tls  = true
          },
        ]
        config = {
          "offsets.topic.replication.factor"         = 3
          "transaction.state.log.replication.factor" = 3
          "transaction.state.log.min.isr"            = 2
          "default.replication.factor"               = 3
          "min.insync.replicas"                      = 2
        }
        # Inherited by both pools, neither of which sets its own - so every controller as well as every
        # broker requests this much. That is the blueprint's sizing and the reason the kafka Karpenter
        # pool launches six large nodes.
        resources = var.kafka_resources
        jvmOptions = {
          "-Xmx" = var.jvm_max_heap
          "-Xms" = var.jvm_initial_heap
        }
        # Ignored while node pools are enabled - each pool's storage above is what is provisioned. Kept
        # because the blueprint's resource carried it; Strimzi reports it in the resource's warnings
        # rather than rejecting it.
        storage = {
          type = "jbod"
          volumes = [{
            id          = 0
            type        = "persistent-claim"
            size        = "1000Gi"
            class       = "gp3"
            deleteClaim = false
          }]
        }
        template = {
          pod = {
            tolerations = [{
              key      = "dedicated"
              operator = "Equal"
              value    = "kafka"
              effect   = "NoSchedule"
            }]
            affinity = {
              # Only nodes from the Karpenter pool labelled for Kafka. The label value comes from that
              # pool's own labels in the root, so the affinity cannot name a pool that does not exist
              # (rules.md B-5) - which would leave every broker Pending with Karpenter provisioning
              # nothing.
              nodeAffinity = {
                requiredDuringSchedulingIgnoredDuringExecution = {
                  nodeSelectorTerms = [{
                    matchExpressions = [{
                      key      = var.node_selector_key
                      operator = "In"
                      values   = [var.node_selector_value]
                    }]
                  }]
                }
              }
              # One Kafka pod per node, brokers and controllers alike.
              podAntiAffinity = {
                requiredDuringSchedulingIgnoredDuringExecution = [{
                  labelSelector = {
                    matchExpressions = [{
                      key      = "strimzi.io/pool-name"
                      operator = "In"
                      values   = keys(local.node_pools)
                    }]
                  }
                  topologyKey = "kubernetes.io/hostname"
                }]
              }
            }
            topologySpreadConstraints = [{
              labelSelector = {
                matchExpressions = [{
                  key      = "strimzi.io/pool-name"
                  operator = "In"
                  values   = keys(local.node_pools)
                }]
              }
              maxSkew           = 1
              topologyKey       = "topology.kubernetes.io/zone"
              whenUnsatisfiable = "ScheduleAnyway"
            }]
          }
        }
        metricsConfig = {
          type = "jmxPrometheusExporter"
          valueFrom = {
            configMapKeyRef = {
              name = local.metrics_config_name
              key  = "kafka-metrics-config.yml"
            }
          }
        }
        rack = {
          topologyKey = "topology.kubernetes.io/zone"
        }
      }
      entityOperator = {
        topicOperator = {}
        userOperator  = {}
      }
      cruiseControl = {}
      kafkaExporter = {
        topicRegex = ".*"
        groupRegex = ".*"
      }
    }
  })

  # The topic and the rebalance below are acted on by components that exist only once the cluster is up:
  # the topic by the Topic Operator, the rebalance by Cruise Control. kubectl_manifest returns as soon as
  # the API server accepts the object, so without this both would be created against a cluster that has
  # no brokers yet (rules.md D-8). It also means terraform apply ends with Kafka actually serving.
  wait_for {
    condition {
      type   = "Ready"
      status = "True"
    }
  }
  timeouts {
    # Six nodes from Karpenter, image pulls and a KRaft quorum forming. If this runs out the resource is
    # tainted and the next apply would recreate the cluster - "terraform untaint" keeps it instead.
    create = var.ready_timeout
  }

  # Pools before the cluster they belong to, and - in reverse on destroy - the cluster before its pools,
  # so Strimzi tears the brokers down as one cluster rather than reacting to pools vanishing under it.
  depends_on = [kubectl_manifest.node_pool, kubectl_manifest.metrics_config]
}

# Cruise Control's proposal for rebalancing partitions across brokers, as the blueprint applied it. It
# only produces a proposal: nothing moves until the resource is annotated strimzi.io/rebalance=approve,
# which the README's commands show.
resource "kubectl_manifest" "rebalance" {
  yaml_body = yamlencode({
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaRebalance"
    metadata = {
      name      = var.rebalance_name
      namespace = var.namespace
      labels    = { "strimzi.io/cluster" = var.cluster_name }
    }
    spec = {
      goals = var.rebalance_goals
    }
  })

  depends_on = [kubectl_manifest.kafka]
}

# The blueprint's example topic. Declared here rather than left as a command to run, because of how the
# Topic Operator deletes topics: it puts strimzi.io/topic-operator on every KafkaTopic and removes it
# only after deleting the topic in Kafka. A topic created by hand is still there when terraform destroy
# deletes the Kafka resource, the Topic Operator goes with it, and the finalizer can never be removed -
# so the namespace above never finishes deleting. Declared here, it is deleted first, while the Topic
# Operator is running, and wait = true holds the destroy until it is really gone (rules.md D-7).
resource "kubectl_manifest" "topic" {
  for_each = var.topics

  yaml_body = yamlencode({
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaTopic"
    metadata = {
      name      = each.key
      namespace = var.namespace
      labels    = { "strimzi.io/cluster" = var.cluster_name }
    }
    spec = {
      replicas   = each.value.replicas
      partitions = each.value.partitions
    }
  })
  wait = true

  depends_on = [kubectl_manifest.kafka]
}
