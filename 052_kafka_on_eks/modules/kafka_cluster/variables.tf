variable "namespace" {
  type        = string
  default     = "kafka"
  description = "Namespace of the Kafka cluster, kafka as the blueprint's manifests had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "cluster_name" {
  type        = string
  default     = "cluster"
  description = "Name of the Kafka resource, cluster as the blueprint named it. Strimzi derives every object name from it - the bootstrap Service is <name>-kafka-bootstrap and the pods are <name>-<pool>-<id>"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be a valid lowercase RFC 1123 label."
  }
}
variable "kafka_version" {
  type        = string
  default     = "3.9.0"
  description = "Kafka version the brokers run, 3.9.0 as the blueprint had it. Has to be one the Strimzi operator release supports"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kafka_version))
    error_message = "kafka_version must be a three-part version such as 3.9.0."
  }
}
variable "metadata_version" {
  type        = string
  default     = "3.9-IV0"
  description = "KRaft metadata version, 3.9-IV0 as the blueprint had it. Belongs with kafka_version: it may not be newer than the Kafka release supports"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+-IV[0-9]+$", var.metadata_version))
    error_message = "metadata_version must look like 3.9-IV0."
  }
}
variable "controller_replicas" {
  type        = number
  default     = 3
  description = "Number of KRaft controllers, three as the blueprint had it - the smallest quorum that survives losing one"

  validation {
    condition     = var.controller_replicas >= 1 && var.controller_replicas % 2 == 1
    error_message = "controller_replicas must be an odd number of at least 1, so the KRaft quorum has a majority."
  }
}
variable "broker_replicas" {
  type        = number
  default     = 3
  description = "Number of brokers, three as the blueprint had it. The cluster config asks for replication factor 3 and min.insync.replicas 2, so fewer than three brokers cannot host a topic"

  validation {
    condition     = var.broker_replicas >= 3
    error_message = "broker_replicas must be at least 3, because default.replication.factor and offsets.topic.replication.factor are 3."
  }
}
variable "controller_volume_size" {
  type        = string
  default     = "100Gi"
  description = "Size of each controller's volume, 100Gi as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.controller_volume_size))
    error_message = "controller_volume_size must be a quantity such as 100Gi."
  }
}
variable "broker_volume_size" {
  type        = string
  default     = "100Gi"
  description = "Size of each broker's volume, 100Gi as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.broker_volume_size))
    error_message = "broker_volume_size must be a quantity such as 100Gi."
  }
}
variable "kafka_resources" {
  type = object({
    requests = object({ memory = string, cpu = string })
    limits   = object({ memory = string, cpu = string })
  })
  default = {
    requests = { memory = "58Gi", cpu = "6" }
    limits   = { memory = "64Gi", cpu = "8" }
  }
  description = "Requests and limits of every Kafka pod - brokers and controllers both, because neither pool overrides them. The blueprint's figures: each pod needs a node with roughly 64 GiB of memory to itself, so the six pods mean six such nodes"
}
variable "jvm_max_heap" {
  type        = string
  default     = "6g"
  description = "JVM -Xmx of the Kafka pods, 6g as the blueprint had it. Far below the memory request on purpose: Kafka leans on the page cache, which is the rest"

  validation {
    condition     = can(regex("^[0-9]+[kmgKMG]$", var.jvm_max_heap))
    error_message = "jvm_max_heap must be a JVM size such as 6g."
  }
}
variable "jvm_initial_heap" {
  type        = string
  default     = "4g"
  description = "JVM -Xms of the Kafka pods, 4g as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+[kmgKMG]$", var.jvm_initial_heap))
    error_message = "jvm_initial_heap must be a JVM size such as 4g."
  }
}
variable "node_selector_key" {
  type        = string
  description = "Node label key the Kafka pods' node affinity requires"

  validation {
    condition     = length(var.node_selector_key) > 0
    error_message = "node_selector_key must not be empty."
  }
}
variable "node_selector_value" {
  type        = string
  description = "Value node_selector_key must have. Passed from the Karpenter pool's labels, so the affinity matches the pool that can provision for it (rules.md B-5)"

  validation {
    condition     = length(var.node_selector_value) > 0
    error_message = "node_selector_value must not be empty."
  }
}
variable "ready_timeout" {
  type        = string
  default     = "45m"
  description = "How long terraform apply waits for the Kafka resource to report Ready. Long, because it covers Karpenter launching six large nodes, the image pulls and the quorum forming"

  validation {
    condition     = can(regex("^[0-9]+(m|h)$", var.ready_timeout))
    error_message = "ready_timeout must be a duration in minutes or hours, such as 45m."
  }
}
variable "rebalance_name" {
  type        = string
  default     = "my-rebalance"
  description = "Name of the KafkaRebalance resource, my-rebalance as the blueprint named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.rebalance_name))
    error_message = "rebalance_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "rebalance_goals" {
  type = list(string)
  default = [
    "RackAwareGoal",
    "ReplicaCapacityGoal",
    "DiskCapacityGoal",
    "NetworkInboundCapacityGoal",
    "NetworkOutboundCapacityGoal",
    "CpuCapacityGoal",
    "ReplicaDistributionGoal",
    "DiskUsageDistributionGoal",
    "NetworkInboundUsageDistributionGoal",
    "NetworkOutboundUsageDistributionGoal",
    "TopicReplicaDistributionGoal",
    "LeaderReplicaDistributionGoal",
    "LeaderBytesInDistributionGoal",
  ]
  description = "Cruise Control goals of the rebalance proposal, the blueprint's list"

  validation {
    condition     = length(var.rebalance_goals) > 0 && alltrue([for g in var.rebalance_goals : can(regex("^[A-Za-z]+Goal$", g))])
    error_message = "rebalance_goals must be a non-empty list of Cruise Control goal names such as RackAwareGoal."
  }
}
variable "topics" {
  type = map(object({
    partitions = number
    replicas   = number
  }))
  default = {
    "test-topic" = { partitions = 12, replicas = 3 }
  }
  description = "KafkaTopic resources, keyed by topic name. The blueprint's example topic by default. Topics created by hand with kubectl carry the Topic Operator's finalizer too and have to be deleted before terraform destroy, or the namespace never finishes deleting"

  validation {
    condition     = alltrue([for name in keys(var.topics) : can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", name))])
    error_message = "topics keys become Kubernetes object names, so each must be a valid lowercase RFC 1123 subdomain."
  }
  validation {
    condition     = alltrue([for t in values(var.topics) : t.partitions >= 1 && t.replicas >= 1])
    error_message = "every topic needs at least one partition and one replica."
  }
}
