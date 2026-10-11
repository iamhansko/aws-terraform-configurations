variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, AWS_DEFAULT_REGION, profile)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like an AWS region (e.g. ap-northeast-2), or null."
  }
}

# --- The network ---
#
# The blueprint's VPC layout (vpc.tf and the CIDR variables in its variables.tf), built from plain
# resources in modules/network. Every one of these has a default, so an apply needs no network input.
variable "network_name_prefix" {
  type        = string
  default     = "kafka-on-eks"
  description = "Prefix of the Name tags on the network this project builds, e.g. <prefix>-vpc, <prefix>-public-a, <prefix>-data-plane-b"

  validation {
    condition     = length(var.network_name_prefix) > 0 && length(var.network_name_prefix) <= 240
    error_message = "network_name_prefix must be 1-240 characters, so the longest Name tag built from it stays within the 256 characters EC2 allows for a tag value."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.1.0.0/16"
  description = "Primary CIDR block of the VPC, 10.1.0.0/16 as the blueprint had it. The public and the RFC 1918 private subnets are carved from it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.1.0.0/16)."
  }
  validation {
    # try(), because every validation block is evaluated and a value with no "/" is the first one's to report.
    condition     = try(tonumber(split("/", var.vpc_cidr_block)[1]) >= 16 && tonumber(split("/", var.vpc_cidr_block)[1]) <= 28, true)
    error_message = "vpc_cidr_block must be between /16 and /28, the sizes AWS accepts for a VPC CIDR block."
  }
}
variable "secondary_cidr_block" {
  type        = string
  default     = "100.64.0.0/16"
  description = "Secondary CIDR block associated with the VPC, 100.64.0.0/16 (RFC 6598) as the blueprint had it. The data plane subnets come from it, and with them every node and pod address"

  validation {
    condition     = can(cidrhost(var.secondary_cidr_block, 0))
    error_message = "secondary_cidr_block must be a valid IPv4 CIDR block (e.g. 100.64.0.0/16)."
  }
  validation {
    condition     = try(tonumber(split("/", var.secondary_cidr_block)[1]) >= 16 && tonumber(split("/", var.secondary_cidr_block)[1]) <= 28, true)
    error_message = "secondary_cidr_block must be between /16 and /28, the sizes AWS accepts for a VPC CIDR block."
  }
}
variable "public_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.1.0.0/26", "10.1.0.64/26"]
  description = "CIDR blocks of the two public subnets, zone a first: the NAT gateway, the Grafana ALB and the workbench instance"

  validation {
    condition     = length(var.public_subnet_cidr_blocks) == 2 && alltrue([for c in var.public_subnet_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "public_subnet_cidr_blocks must contain exactly two valid IPv4 CIDR blocks, one per availability zone."
  }
}
variable "private_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
  description = "CIDR blocks of the two RFC 1918 private subnets, zone a first. Nothing in this project is placed in them; they are the blueprint's"

  validation {
    condition     = length(var.private_subnet_cidr_blocks) == 2 && alltrue([for c in var.private_subnet_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "private_subnet_cidr_blocks must contain exactly two valid IPv4 CIDR blocks, one per availability zone."
  }
}
variable "data_plane_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["100.64.0.0/17", "100.64.128.0/17"]
  description = "CIDR blocks of the two data plane subnets, zone a first, inside secondary_cidr_block. The EKS control plane ENIs, the core node group and every Karpenter node are placed here"

  validation {
    condition     = length(var.data_plane_subnet_cidr_blocks) == 2 && alltrue([for c in var.data_plane_subnet_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "data_plane_subnet_cidr_blocks must contain exactly two valid IPv4 CIDR blocks, one per availability zone."
  }
}

# --- The cluster ---
variable "cluster_name" {
  type        = string
  default     = "kafka-on-eks"
  description = "Name of the EKS cluster, and the stem of the names derived from it: the Karpenter interruption queue (karpenter-<name>), the Grafana admin secret (<name>-grafana) and the Amazon Managed Prometheus workspace alias (amp-ws-<name>). The blueprint appended a hash of the account ID; this project does not, so one account and region holds one copy of it"

  validation {
    # EKS allows 100 characters. What bounds this to 70 is the interruption queue: karpenter-<name>, and
    # SQS caps a queue name at 80.
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,69}$", var.cluster_name))
    error_message = "cluster_name must start with a letter and be 1-70 letters, digits, hyphens or underscores. EKS accepts up to 100 characters, but the Karpenter interruption queue is named karpenter-<cluster_name> and SQS caps queue names at 80."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version of the cluster. 1.34 rather than the blueprint's 1.33: 1.33 left EKS standard support on 2026-07-29 and is billed at the extended support rate since, while 1.34 is in standard support until 2026-12-02. Karpenter needs 1.6 or later for 1.34, which the pinned chart is. Keep kubectl_download_version within one minor of this"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; modules/eks_cluster holds the list of versions this project accepts."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server has a public endpoint. True, as the blueprint had it, and pinned true: every Kubernetes object and Helm release in this project is applied by providers running on the machine executing terraform"

  validation {
    # Not a free choice. This root declares kubectl and helm providers, and those run wherever terraform
    # runs. With a private-only endpoint they cannot connect, plan still passes, and the failure appears
    # mid-apply as a dial timeout that looks exactly like the destroy-ordering problem of rules.md D-4
    # (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its manifests and Helm releases are applied by providers running on the machine executing terraform. To run with a private endpoint, drop those providers and apply everything from the workbench through SSM Associations instead, as 041_eks_private_cluster does."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoint. Has to include wherever terraform runs. Narrow this for anything longer lived than a demo"

  validation {
    condition     = length(var.public_access_cidrs) > 0 && alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain at least one valid IPv4 CIDR block."
  }
}
variable "cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
  description = "Control plane log types sent to CloudWatch Logs - api, audit and authenticator, the eks module's default the blueprint ran with. EKS creates the log group itself, so it outlives terraform destroy"

  validation {
    condition = alltrue([for t in var.cluster_log_types : contains([
      "api", "audit", "authenticator", "controllerManager", "scheduler"
    ], t)])
    error_message = "cluster_log_types must be a subset of: api, audit, authenticator, controllerManager, scheduler."
  }
}

# --- The core node group ---
#
# The blueprint's one managed node group, which runs everything that has to exist before Karpenter can
# provision anything: Karpenter itself, CoreDNS, the EBS CSI controller, the Strimzi operator and the AWS
# Load Balancer Controller.
variable "core_node_group_name" {
  type        = string
  default     = "core-node-group"
  description = "Name of the managed node group, core-node-group as the blueprint named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$", var.core_node_group_name))
    error_message = "core_node_group_name must be 1-63 letters, digits, hyphens or underscores, starting with a letter or digit."
  }
}
variable "core_node_ami_type" {
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
  description = "AMI type of the core node group. ARM, as the blueprint had it, because every type in core_node_instance_types is Graviton - changing one means changing the other, and EKS rejects the pair at apply rather than plan"

  validation {
    condition = contains([
      "AL2023_x86_64_STANDARD", "AL2023_ARM_64_STANDARD", "BOTTLEROCKET_ARM_64", "BOTTLEROCKET_x86_64",
    ], var.core_node_ami_type)
    error_message = "core_node_ami_type must be one of AL2023_x86_64_STANDARD, AL2023_ARM_64_STANDARD, BOTTLEROCKET_ARM_64 or BOTTLEROCKET_x86_64."
  }
}
variable "core_node_instance_types" {
  type        = list(string)
  default     = ["m6g.xlarge", "m6gd.xlarge", "m7g.xlarge", "c6g.xlarge", "c6gd.xlarge", "c7g.xlarge"]
  description = "Instance types the core node group may launch, the blueprint's list"

  validation {
    condition     = length(var.core_node_instance_types) > 0 && alltrue([for t in var.core_node_instance_types : can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", t))])
    error_message = "core_node_instance_types must be a non-empty list of valid EC2 instance types (e.g. m6g.xlarge)."
  }
}
variable "core_node_min_size" {
  type        = number
  default     = 3
  description = "Minimum size of the core node group, 3 as the blueprint had it"

  validation {
    condition     = var.core_node_min_size >= 1
    error_message = "core_node_min_size must be at least 1: Karpenter, CoreDNS and the Strimzi operator have nowhere else to run."
  }
}
variable "core_node_desired_size" {
  type        = number
  default     = 3
  description = "Desired size of the core node group, 3 as the blueprint had it. Nothing scales this group after creation"

  validation {
    # EKS rejects a desired size outside min..max at apply time, after the cluster already exists.
    condition     = var.core_node_min_size <= var.core_node_desired_size && var.core_node_desired_size <= var.core_node_max_size
    error_message = "core_node_desired_size must lie between core_node_min_size and core_node_max_size."
  }
}
variable "core_node_max_size" {
  type        = number
  default     = 9
  description = "Maximum size of the core node group, 9 as the blueprint had it"

  validation {
    condition     = var.core_node_max_size >= 1
    error_message = "core_node_max_size must be at least 1."
  }
}
variable "core_node_labels" {
  type = map(string)
  default = {
    WorkerType    = "ON_DEMAND"
    NodeGroupType = "core"
  }
  description = "Kubernetes labels on the core nodes, the blueprint's. The Strimzi operator's nodeSelector is built from these (plus kubernetes.io/os), so the selector cannot name labels the nodes do not carry"

  validation {
    condition     = length(var.core_node_labels) > 0 && alltrue([for key in keys(var.core_node_labels) : length(key) > 0])
    error_message = "core_node_labels must contain at least one label, with non-empty keys - the Strimzi operator is pinned to the core nodes by them."
  }
}
variable "core_node_root_volume_size" {
  type        = number
  default     = 1000
  description = "Root volume size of each core node in GiB, 1000 as the blueprint had it. Three nodes means 3000 GiB of gp3 billed for as long as the cluster runs - far more than these nodes use, kept because it is the blueprint's figure"

  validation {
    condition     = var.core_node_root_volume_size >= 20 && var.core_node_root_volume_size <= 16384
    error_message = "core_node_root_volume_size must be between 20 and 16384 GiB."
  }
}

# --- Addons ---
variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas"

  validation {
    condition     = var.coredns_replica_count > 0
    error_message = "coredns_replica_count must be greater than zero."
  }
}
variable "metrics_server_replica_count" {
  type        = number
  default     = 2
  description = "Number of metrics-server replicas, two as the blueprint's Helm values had them"

  validation {
    condition     = var.metrics_server_replica_count > 0
    error_message = "metrics_server_replica_count must be greater than zero."
  }
}
variable "ebs_volume_release_wait" {
  type        = string
  default     = "120s"
  description = "How long terraform destroy keeps the EBS CSI driver installed after the Kafka and Prometheus namespaces are gone. Deleting a namespace deletes its volume claims, but the EBS volumes behind them are deleted afterwards and asynchronously, by this driver, once each volume has detached - and the driver is the next thing destroy would remove. Without the wait those volumes are left behind, still billed, with nothing in the cluster that remembers them. Has no effect on apply"

  validation {
    condition     = can(regex("^[0-9]+(s|m)$", var.ebs_volume_release_wait))
    error_message = "ebs_volume_release_wait must be a duration in seconds or minutes, such as 120s or 2m."
  }
}

# --- Karpenter ---
variable "karpenter_chart_version" {
  type        = string
  default     = "1.6.2"
  description = "Version of the Karpenter Helm chart, 1.6.2 as the blueprint pinned it. Its compatibility matrix puts Kubernetes 1.34 at 1.6 or later"

  validation {
    # modules/karpenter_node_pool writes karpenter.sh/v1 and karpenter.k8s.aws/v1, which only a 1.x chart
    # installs. A 0.x chart would accept the release and then reject every pool.
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+$", var.karpenter_chart_version))
    error_message = "karpenter_chart_version must be a 1.x.y version, because the node pools are written against the karpenter.sh/v1 and karpenter.k8s.aws/v1 APIs that only the 1.x charts install."
  }
}
variable "karpenter_namespace" {
  type        = string
  default     = "karpenter"
  description = "Namespace of the Karpenter controller, karpenter as eks-blueprints-addons installed it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.karpenter_namespace))
    error_message = "karpenter_namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "karpenter_node_pools" {
  type = map(object({
    instance_categories   = list(string)
    node_architectures    = list(string)
    capacity_types        = list(string)
    node_labels           = map(string)
    instance_store_policy = optional(string)
    cpu_limit             = optional(number, 1000)
    consolidation_policy  = optional(string, "WhenEmptyOrUnderutilized")
    consolidate_after     = optional(string, "30s")
    disruption_budgets    = optional(list(string), ["10%"])
  }))
  default = {
    # General workloads. The karpenter-resources chart wrote NodeGroupType twice for this pool - "default"
    # from its own template, then "apps" from the blueprint's values - and the later key won, so "apps" is
    # the label the blueprint's nodes actually carried.
    default = {
      instance_categories   = ["c", "m", "r"]
      node_architectures    = ["amd64", "arm64"]
      capacity_types        = ["spot", "on-demand"]
      node_labels           = { NodePool = "default", NodeGroupType = "apps", type = "karpenter" }
      instance_store_policy = "RAID0"
    }
    # The Kafka brokers and controllers, which require NodeGroupType=kafka. On-demand only, so a spot
    # reclaim never takes a broker and its partitions down with it.
    kafka = {
      instance_categories   = ["c", "m", "r"]
      node_architectures    = ["arm64"]
      capacity_types        = ["on-demand"]
      node_labels           = { NodePool = "kafka", NodeGroupType = "kafka", type = "karpenter" }
      instance_store_policy = "RAID0"
    }
  }
  description = "Karpenter pools, keyed by pool name: the blueprint's two karpenter-resources releases. Every pool gets the data plane subnets, the cluster security group and Bottlerocket nodes"

  validation {
    condition     = length(var.karpenter_node_pools) > 0 && alltrue([for name in keys(var.karpenter_node_pools) : can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", name))])
    error_message = "karpenter_node_pools must contain at least one pool, and its keys become NodePool and EC2NodeClass names, so each must be a valid lowercase RFC 1123 subdomain."
  }
  validation {
    condition     = alltrue([for pool in values(var.karpenter_node_pools) : length(pool.instance_categories) > 0 && length(pool.node_labels) > 0])
    error_message = "Every pool needs at least one instance category - with none it may launch any instance type in the region - and at least one node label, which is what a workload selects it by."
  }
  validation {
    condition = alltrue([for pool in values(var.karpenter_node_pools) :
      length(pool.node_architectures) > 0 && length(setsubtract(pool.node_architectures, ["amd64", "arm64"])) == 0 &&
      length(pool.capacity_types) > 0 && length(setsubtract(pool.capacity_types, ["spot", "on-demand", "reserved"])) == 0
    ])
    error_message = "Every pool needs node_architectures from amd64/arm64 and capacity_types from spot/on-demand/reserved, at least one of each."
  }
  validation {
    condition     = alltrue([for pool in values(var.karpenter_node_pools) : pool.instance_store_policy == null || pool.instance_store_policy == "RAID0"])
    error_message = "instance_store_policy must be RAID0 or null; RAID0 is the only value Karpenter defines."
  }
}
variable "kafka_node_label_key" {
  type        = string
  default     = "NodeGroupType"
  description = "Node label the Kafka pods' node affinity requires, NodeGroupType as the blueprint's Kafka resource had it. Its value is read from the pool named by kafka_node_pool"

  validation {
    condition     = length(var.kafka_node_label_key) > 0
    error_message = "kafka_node_label_key must not be empty."
  }
}
variable "kafka_node_pool" {
  type        = string
  default     = "kafka"
  description = "Which Karpenter pool the Kafka pods are pinned to. The affinity value is that pool's own kafka_node_label_key label, so the two cannot drift apart (rules.md B-5)"

  validation {
    condition     = contains(keys(var.karpenter_node_pools), var.kafka_node_pool)
    error_message = "kafka_node_pool must name one of the pools in karpenter_node_pools. Otherwise every Kafka pod stays Pending while Karpenter provisions nothing, and the apply waits for the full kafka_ready_timeout before it fails."
  }
  validation {
    # try(), so a missing pool is reported once, by the block above, rather than as an index error here.
    condition     = try(contains(keys(var.karpenter_node_pools[var.kafka_node_pool].node_labels), var.kafka_node_label_key), true)
    error_message = "The pool named by kafka_node_pool must carry a kafka_node_label_key label, because the Kafka pods' node affinity requires exactly that label."
  }
  validation {
    # Another pool with the same label and value would also satisfy the affinity - and the default pool
    # allows spot, which would put brokers where a two-minute reclaim notice takes them away.
    condition = try(length([
      for name, pool in var.karpenter_node_pools : name
      if name != var.kafka_node_pool && lookup(pool.node_labels, var.kafka_node_label_key, null) == var.karpenter_node_pools[var.kafka_node_pool].node_labels[var.kafka_node_label_key]
    ]) == 0, true)
    error_message = "No pool other than kafka_node_pool may carry the same kafka_node_label_key value, or the Kafka pods' affinity matches that pool too."
  }
}

# --- Strimzi and the Kafka cluster ---
variable "strimzi_chart_version" {
  type        = string
  default     = "0.46.0"
  description = "Version of the strimzi-kafka-operator chart, which is also the operator version and the tag prefix of the quay.io/strimzi/kafka client image in the README's commands. 0.46.0, as the blueprint pinned it"

  validation {
    condition     = can(regex("^0\\.[0-9]+\\.[0-9]+$", var.strimzi_chart_version))
    error_message = "strimzi_chart_version must be a 0.x.y semantic version, as Strimzi releases are numbered."
  }
}
variable "kafka_namespace" {
  type        = string
  default     = "kafka"
  description = "Namespace of the Kafka cluster, kafka as the blueprint's manifests had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.kafka_namespace))
    error_message = "kafka_namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "kafka_cluster_name" {
  type        = string
  default     = "cluster"
  description = "Name of the Kafka resource, cluster as the blueprint named it. Strimzi derives every object name from it, e.g. the cluster-kafka-bootstrap Service"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.kafka_cluster_name))
    error_message = "kafka_cluster_name must be a valid lowercase RFC 1123 label."
  }
}
variable "kafka_version" {
  type        = string
  default     = "3.9.0"
  description = "Kafka version the brokers run, 3.9.0 as the blueprint had it. Has to be on the operator release's supported list: Strimzi 0.46.0 supports 3.9.0 and 4.0.0 (its kafka-versions.yaml)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kafka_version))
    error_message = "kafka_version must be a three-part version such as 3.9.0."
  }
  validation {
    # The operator accepts the resource and then refuses to reconcile it, with the reason only in the
    # Kafka resource's status - and the apply waits on that status for the whole kafka_ready_timeout.
    # Checked for the pinned operator release only; another release has its own list.
    condition     = var.strimzi_chart_version != "0.46.0" || contains(["3.9.0", "4.0.0"], var.kafka_version)
    error_message = "kafka_version must be 3.9.0 or 4.0.0 with Strimzi 0.46.0, the two versions that release supports. To run another Kafka version, change strimzi_chart_version to a release that lists it in its kafka-versions.yaml."
  }
}
variable "kafka_metadata_version" {
  type        = string
  default     = "3.9-IV0"
  description = "KRaft metadata version, 3.9-IV0 as the blueprint had it. May not be newer than kafka_version supports"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+-IV[0-9]+$", var.kafka_metadata_version))
    error_message = "kafka_metadata_version must look like 3.9-IV0."
  }
}
variable "kafka_controller_replicas" {
  type        = number
  default     = 3
  description = "Number of KRaft controllers, three as the blueprint had it. Each one requests the same 58Gi and six vCPUs a broker does, and needs a node to itself"

  validation {
    condition     = var.kafka_controller_replicas >= 1 && var.kafka_controller_replicas % 2 == 1
    error_message = "kafka_controller_replicas must be an odd number of at least 1, so the KRaft quorum has a majority."
  }
}
variable "kafka_broker_replicas" {
  type        = number
  default     = 3
  description = "Number of brokers, three as the blueprint had it. Each one requests 58Gi and six vCPUs and needs a node to itself"

  validation {
    condition     = var.kafka_broker_replicas >= 3
    error_message = "kafka_broker_replicas must be at least 3, because the cluster's default.replication.factor and offsets.topic.replication.factor are 3."
  }
}
variable "kafka_broker_volume_size" {
  type        = string
  default     = "100Gi"
  description = "Size of each broker's volume, 100Gi as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.kafka_broker_volume_size))
    error_message = "kafka_broker_volume_size must be a quantity such as 100Gi."
  }
}
variable "kafka_controller_volume_size" {
  type        = string
  default     = "100Gi"
  description = "Size of each controller's volume, 100Gi as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.kafka_controller_volume_size))
    error_message = "kafka_controller_volume_size must be a quantity such as 100Gi."
  }
}
variable "kafka_ready_timeout" {
  type        = string
  default     = "45m"
  description = "How long terraform apply waits for the Kafka resource to report Ready. It covers Karpenter launching a node per Kafka pod, the image pulls and the quorum forming. If it runs out, the resource is tainted: terraform untaint keeps the cluster rather than letting the next apply recreate it"

  validation {
    condition     = can(regex("^[0-9]+(m|h)$", var.kafka_ready_timeout))
    error_message = "kafka_ready_timeout must be a duration in minutes or hours, such as 45m."
  }
}
variable "kafka_topics" {
  type = map(object({
    partitions = number
    replicas   = number
  }))
  default = {
    "test-topic" = { partitions = 12, replicas = 3 }
  }
  description = "KafkaTopic resources, keyed by topic name: the blueprint's example topic. The README's producer and consumer commands use the first one. A topic created by hand with kubectl carries the Topic Operator's finalizer too, and has to be deleted before terraform destroy"

  validation {
    condition     = length(var.kafka_topics) > 0
    error_message = "kafka_topics must declare at least one topic; the producer and consumer commands in the outputs use the first."
  }
  validation {
    condition     = alltrue([for name in keys(var.kafka_topics) : can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", name))])
    error_message = "kafka_topics keys become Kubernetes object names and topic names, so each must be a valid lowercase RFC 1123 subdomain."
  }
  validation {
    # A replication factor above the broker count is accepted by the API server and refused by Kafka; the
    # KafkaTopic just reports NotReady, and nothing in the apply notices.
    condition     = alltrue([for t in values(var.kafka_topics) : t.partitions >= 1 && t.replicas >= 1 && t.replicas <= var.kafka_broker_replicas])
    error_message = "Every topic needs at least one partition and between 1 and kafka_broker_replicas replicas - Kafka cannot place more replicas of a partition than there are brokers."
  }
}

# --- Monitoring ---
variable "kube_prometheus_stack_chart_version" {
  type        = string
  default     = "48.1.1"
  description = "Version of the kube-prometheus-stack chart, 48.1.1 as the blueprint pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kube_prometheus_stack_chart_version))
    error_message = "kube_prometheus_stack_chart_version must be a three-part semantic version."
  }
}
variable "enable_amazon_prometheus" {
  type        = bool
  default     = true
  description = "Whether Prometheus remote-writes to an Amazon Managed Service for Prometheus workspace and Grafana gets it as a data source. True, the blueprint's default. The workspace is billed per sample ingested, on top of the cluster"
}
variable "prometheus_storage_size" {
  type        = string
  default     = "50Gi"
  description = "Size of Prometheus's local volume, 50Gi as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.prometheus_storage_size))
    error_message = "prometheus_storage_size must be a quantity such as 50Gi."
  }
}

# --- The AWS Load Balancer Controller and the Grafana ALB ---
variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Version of the aws-load-balancer-controller chart. 1.14.1 installs controller v2.14.1, whose iam_policy.json is the one vendored in modules/aws_load_balancer_controller"

  validation {
    # The policy and the controller have to come from the same release, or the controller asks for
    # permissions the policy does not grant - which shows as AccessDenied in its log while the Ingress
    # simply never gets an address.
    condition     = can(regex("^1\\.14\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a 1.14.x version, matching the v2.14.1 IAM policy vendored in modules/aws_load_balancer_controller/iam_policy.json. To move to another minor, replace that file with the iam_policy.json of the controller release the chart installs."
  }
}
variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the controller uses one shared backend security group as the source of the node-side rules it writes"

  validation {
    # The Ingress names its own frontend security group and does not set
    # manage-backend-security-group-rules, so the controller writes no node-side rule at all and this
    # project declares it (aws_vpc_security_group_ingress_rule.grafana_alb_to_pods). That is the second
    # row of the table in rules.md G-2, the row that requires false (rules.md B-1).
    condition     = var.enable_backend_security_group == false
    error_message = "enable_backend_security_group must be false in this variant. The Grafana Ingress names its own frontend security group and does not set manage-backend-security-group-rules, so the node-side rule is declared in Terraform (grafana_alb_to_pods). To let the controller manage it instead, add that annotation and set this to true (rules.md G-2)."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller's chart installs the mservice.elbv2.k8s.aws webhook, which intercepts every Service created in the cluster"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. Nothing here creates a Service of type LoadBalancer, while the webhook's failurePolicy: Fail applies to every Service in the cluster and fails any release creating Services - Strimzi's, kube-prometheus-stack's - whenever the controller has no Ready pod (rules.md G-4)."
  }
}
variable "grafana_alb_scheme" {
  type        = string
  default     = "internet-facing"
  description = "Scheme of the ALB in front of Grafana. internet-facing, as 052's post-install step created it; internal keeps it inside the VPC, reachable from the workbench"

  validation {
    condition     = contains(["internet-facing", "internal"], var.grafana_alb_scheme)
    error_message = "grafana_alb_scheme must be internet-facing or internal."
  }
}
variable "grafana_listener_port" {
  type        = number
  default     = 80
  description = "Port the Grafana ALB listens on, plain HTTP. The same value opens the frontend security group and sets the Ingress's listen-ports, so the two cannot disagree (rules.md B-5)"

  validation {
    condition     = var.grafana_listener_port > 0 && var.grafana_listener_port <= 65535
    error_message = "grafana_listener_port must be a valid TCP port."
  }
}
variable "grafana_alb_security_group_name" {
  type        = string
  default     = "kafka-on-eks-grafana-alb-sg"
  description = "Name of the Grafana ALB's frontend security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.grafana_alb_security_group_name)) && !startswith(var.grafana_alb_security_group_name, "sg-")
    error_message = "grafana_alb_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "grafana_allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the Grafana ALB accepts its listener port from 0.0.0.0/0, as the ALB 052's post-install step created did (the controller's own frontend group opened the listener to everyone). Grafana asks for a password, but the ALB serves it over plain HTTP. Set false and list your own networks in grafana_ingress_cidr_blocks instead"
}
variable "grafana_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed to reach the Grafana ALB, in addition to (or, with grafana_allow_inbound_from_anywhere false, instead of) 0.0.0.0/0. The workbench's security group is always allowed, which is what reaches an internal ALB"

  validation {
    condition     = alltrue([for cidr in var.grafana_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "grafana_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
  validation {
    # An internet-facing ALB is reached through its public addresses, where the workbench's
    # security-group rule never matches. With neither of the other two sources it accepts nothing, and
    # every Terraform resource still reports success.
    condition     = var.grafana_alb_scheme == "internal" || var.grafana_allow_inbound_from_anywhere || length(var.grafana_ingress_cidr_blocks) > 0
    error_message = "An internet-facing Grafana ALB needs grafana_allow_inbound_from_anywhere = true or at least one grafana_ingress_cidr_blocks entry; with neither, nobody can reach it. To keep it closed to the internet, set grafana_alb_scheme = \"internal\" and reach it from the workbench."
  }
}

# --- The workbench ---
variable "instance_name" {
  type        = string
  default     = "kafka-on-eks-vscode"
  description = "Name tag for the workbench instance"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "key_name" {
  type        = string
  default     = "kafka-on-eks-key"
  description = "Name of the EC2 key pair created for the workbench instance"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "security_group_name" {
  type        = string
  default     = "kafka-on-eks-vscode-sg"
  description = "Name of the workbench instance's security group. Named per project rather than the _monolithic template's plain \"vscode-sg\""

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the workbench, t3.medium as the _monolithic template had it. x86, because the tools the user data downloads are amd64 builds"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size of the workbench in GiB. 30 rather than the 50 the previous version needed for its nested Terraform run and provider binaries, which no longer happens on this instance"

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB; docker images and the code-server install need the room."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.104.1"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.104.1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) from 0.0.0.0/0, as the _monolithic template's InboundFromAnywhere parameter did. code-server here runs with auth: none and the instance role behind it is AdministratorAccess, so this is an unauthenticated editor with administrator credentials on the public internet - set false and reach it through SSM Session Manager port forwarding instead"
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date> in the amazon-eks S3 bucket layout. Has to stay within one minor of kubernetes_version"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
  validation {
    # kubectl supports one minor of skew either way. Outside it commands mostly work, which is worse
    # than failing: the ones that do not fail in ways that look like cluster problems. try(), so a
    # malformed value is reported by the block above.
    condition     = try(abs(tonumber(split(".", var.kubectl_download_version)[1]) - tonumber(split(".", var.kubernetes_version)[1])) <= 1, true)
    error_message = "kubectl_download_version must be within one minor version of kubernetes_version, the skew kubectl supports."
  }
}
variable "eks_node_viewer_version" {
  type        = string
  default     = "v0.7.4"
  description = "Version of eks-node-viewer installed on the workbench, as the _monolithic template pinned it, for watching the Karpenter nodes the Kafka pods land on"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.eks_node_viewer_version))
    error_message = "eks_node_viewer_version must be a v-prefixed semantic version (e.g. v0.7.4)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench holding the bootstrap marker files the README association polls for (rules.md D-5/H-2). Under /run, so the markers vanish on reboot rather than making a stale file look like a completed bootstrap"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association waits for success. Its command blocks on the user data marker, so this has to cover the whole workbench bootstrap"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}
