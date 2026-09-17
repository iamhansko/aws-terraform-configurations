variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster Karpenter provisions nodes for"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in the controller's IRSA trust policy"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policy's sub/aud condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace Karpenter's controller and service account are installed into. Baked into the IRSA trust policy's sub condition, so it must match the Helm release's namespace"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "create_namespace" {
  type        = bool
  default     = false
  description = "Whether the Helm release creates its namespace. False by default because kube-system always exists; set true when installing into a dedicated karpenter namespace"
}
variable "service_account_name" {
  type        = string
  default     = "karpenter"
  description = "Kubernetes service account name the Karpenter controller runs as, annotated with the IRSA role ARN"

  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "release_name" {
  type        = string
  default     = "karpenter"
  description = "Name of the Helm release"

  validation {
    condition     = length(var.release_name) > 0
    error_message = "release_name must not be empty."
  }
}
variable "chart_repository" {
  type        = string
  default     = "oci://public.ecr.aws/karpenter"
  description = "OCI registry hosting the Karpenter chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "1.8.3"
  description = "Version of the Karpenter Helm chart. The chart also installs the NodePool and EC2NodeClass CRDs, so the apiVersions this module writes (karpenter.sh/v1, karpenter.k8s.aws/v1) must match the major version installed here"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 1.8.3)."
  }
}
variable "replica_count" {
  type        = number
  default     = 2
  description = "Number of Karpenter controller replicas, run as a leader-elected pair"

  validation {
    condition     = var.replica_count > 0
    error_message = "replica_count must be greater than zero."
  }
}
variable "controller_cpu_request" {
  type        = string
  default     = "1"
  description = "CPU request for the Karpenter controller pod"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.controller_cpu_request))
    error_message = "controller_cpu_request must be a Kubernetes CPU quantity (e.g. 1 or 500m)."
  }
}
variable "controller_memory_request" {
  type        = string
  default     = "1Gi"
  description = "Memory request for the Karpenter controller pod"

  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.controller_memory_request))
    error_message = "controller_memory_request must be a Kubernetes binary quantity (e.g. 1Gi)."
  }
}
variable "controller_cpu_limit" {
  type        = string
  default     = "1"
  description = "CPU limit for the Karpenter controller pod"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.controller_cpu_limit))
    error_message = "controller_cpu_limit must be a Kubernetes CPU quantity (e.g. 1 or 500m)."
  }
}
variable "controller_memory_limit" {
  type        = string
  default     = "1Gi"
  description = "Memory limit for the Karpenter controller pod"

  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.controller_memory_limit))
    error_message = "controller_memory_limit must be a Kubernetes binary quantity (e.g. 1Gi)."
  }
}
variable "interruption_queue_name" {
  type        = string
  default     = null
  description = "Name of an SQS queue receiving EC2 spot interruption and rebalance events, so Karpenter can drain a node before it is reclaimed. When null the setting is omitted and Karpenter runs without interruption handling, which is acceptable for on-demand-only pools"

  validation {
    condition     = var.interruption_queue_name == null || can(regex("^[A-Za-z0-9_-]{1,80}$", var.interruption_queue_name))
    error_message = "interruption_queue_name must be a valid SQS queue name, or null."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the controller's Deployment to become Available before failing the apply"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = []
  description = "Extra Helm values appended to the release's set list, for chart settings this module does not expose as named variables"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : length(entry.name) > 0])
    error_message = "additional_set_values entries must each have a non-empty name."
  }
}
variable "controller_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "IAM managed policy ARNs attached to the Karpenter controller's IRSA role. AdministratorAccess keeps the demo unblocked, but Karpenter publishes a least-privilege policy (see the getting-started CloudFormation template at https://karpenter.sh); use that for anything longer lived"

  validation {
    condition     = alltrue([for arn in var.controller_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "controller_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "node_iam_role_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the role Karpenter-provisioned nodes run as. When null, a unique name is generated, which avoids collisions if this project is deployed twice in one account"

  validation {
    condition     = var.node_iam_role_name == null || can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.node_iam_role_name))
    error_message = "node_iam_role_name must be a valid IAM role name (64 characters or fewer), or null."
  }
}
variable "node_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "IAM managed policy ARNs attached to the role Karpenter-provisioned nodes run as"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "node_class_name" {
  type        = string
  default     = "default"
  description = "Name of the EC2NodeClass describing how Karpenter builds instances"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.node_class_name))
    error_message = "node_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "node_pool_name" {
  type        = string
  default     = "default"
  description = "Name of the NodePool describing what Karpenter is allowed to provision"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.node_pool_name))
    error_message = "node_pool_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ami_alias" {
  type        = string
  default     = "al2023@latest"
  description = "EC2NodeClass amiSelectorTerms alias, e.g. al2023@latest or bottlerocket@latest. Replaces the amiFamily field Karpenter used before v1"

  validation {
    condition     = can(regex("^(al2023|al2|bottlerocket|windows2019|windows2022)@[a-zA-Z0-9.-]+$", var.ami_alias))
    error_message = "ami_alias must look like al2023@latest or bottlerocket@v1.19.0."
  }
}
variable "subnet_selector_tags" {
  type        = map(string)
  description = "Tags that identify the subnets Karpenter launches nodes into. Passed in rather than discovered, so this module never has to know which network module created them (rules.md B-6)"

  validation {
    condition     = length(var.subnet_selector_tags) > 0
    error_message = "subnet_selector_tags must contain at least one tag, otherwise the selector matches every subnet in the VPC."
  }
}
variable "security_group_selector_tags" {
  type        = map(string)
  description = "Tags that identify the security groups attached to Karpenter-provisioned nodes. EKS tags the cluster security group with aws:eks:cluster-name, which is the usual choice here"

  validation {
    condition     = length(var.security_group_selector_tags) > 0
    error_message = "security_group_selector_tags must contain at least one tag, otherwise the selector matches every security group in the VPC."
  }
}
variable "node_architectures" {
  type        = list(string)
  default     = ["amd64"]
  description = "CPU architectures Karpenter may provision. Must match the architecture implied by ami_alias"

  validation {
    condition     = length(var.node_architectures) > 0 && alltrue([for a in var.node_architectures : contains(["amd64", "arm64"], a)])
    error_message = "node_architectures must be a non-empty subset of: amd64, arm64."
  }
}
variable "capacity_types" {
  type        = list(string)
  default     = ["on-demand"]
  description = "Capacity types Karpenter may provision. Adding spot lets it pick the cheaper option, but then interruption_queue_name should be set so nodes are drained before reclamation"

  validation {
    condition     = length(var.capacity_types) > 0 && alltrue([for c in var.capacity_types : contains(["on-demand", "spot", "reserved"], c)])
    error_message = "capacity_types must be a non-empty subset of: on-demand, spot, reserved."
  }
}
variable "instance_categories" {
  type        = list(string)
  default     = ["c", "m", "r", "t"]
  description = "EC2 instance categories Karpenter may pick from. Keeping this broad is the point of Karpenter: it chooses the cheapest shape that fits the pending pods"

  validation {
    condition     = length(var.instance_categories) > 0
    error_message = "instance_categories must contain at least one category."
  }
}
variable "minimum_instance_generation" {
  type        = number
  default     = 2
  description = "Instance generations at or below this are excluded, since the oldest families have low per-node pod and ENI limits"

  validation {
    condition     = var.minimum_instance_generation >= 1
    error_message = "minimum_instance_generation must be at least 1."
  }
}
variable "node_labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to every node this NodePool provisions (NodePool.spec.template.metadata.labels). A workload pins itself to Karpenter-provisioned capacity by matching these in a nodeSelector, and the map is re-exposed as an output so that selector references one source of truth (rules.md B-5). When empty the labels block is omitted entirely"

  validation {
    condition     = alltrue([for key in keys(var.node_labels) : can(regex("^([a-z0-9]([-a-z0-9.]*[a-z0-9])?/)?[a-zA-Z0-9]([-a-zA-Z0-9_.]*[a-zA-Z0-9])?$", key))])
    error_message = "node_labels keys must be valid Kubernetes label keys, optionally prefixed with a DNS subdomain (e.g. node-auto-scaling or example.com/pool)."
  }
}
variable "instance_types" {
  type        = list(string)
  default     = []
  description = "Exact EC2 instance types Karpenter may provision (node.kubernetes.io/instance-type). Empty by default, because letting Karpenter pick the cheapest shape that fits the pending pods is the point of it. Pinning one small type instead makes a scale-up demo legible: a pod requesting 1 vCPU no longer fits several to a node, so each replica forces another node"

  validation {
    condition     = alltrue([for type in var.instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", type))])
    error_message = "instance_types must contain valid EC2 instance types (e.g. t3.small)."
  }
}
variable "additional_requirements" {
  type = list(object({
    key      = string
    operator = string
    values   = list(string)
  }))
  default     = []
  description = "Extra NodePool requirements appended to the built-in set, for constraints this module does not expose as named variables (e.g. karpenter.k8s.aws/instance-size)"

  validation {
    condition = alltrue([for req in var.additional_requirements : length(req.key) > 0 && contains([
      "In", "NotIn", "Exists", "DoesNotExist", "Gt", "Lt"
    ], req.operator)])
    error_message = "additional_requirements entries must each have a non-empty key and an operator of: In, NotIn, Exists, DoesNotExist, Gt, Lt."
  }
}
variable "cpu_limit" {
  type        = number
  default     = 1000
  description = "Maximum total vCPU this NodePool may provision, a hard ceiling on runaway scale-up"

  validation {
    condition     = var.cpu_limit > 0
    error_message = "cpu_limit must be greater than zero."
  }
}
variable "memory_limit" {
  type        = string
  default     = "1000Gi"
  description = "Maximum total memory this NodePool may provision"

  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes binary quantity (e.g. 1000Gi)."
  }
}
variable "consolidation_policy" {
  type        = string
  default     = "WhenEmptyOrUnderutilized"
  description = "When Karpenter may replace or remove nodes. WhenEmptyOrUnderutilized also repacks partly used nodes onto cheaper shapes; WhenEmpty only removes nodes with no workload pods left"

  validation {
    condition     = contains(["WhenEmpty", "WhenEmptyOrUnderutilized"], var.consolidation_policy)
    error_message = "consolidation_policy must be either WhenEmpty or WhenEmptyOrUnderutilized."
  }
}
variable "consolidate_after" {
  type        = string
  default     = "1m"
  description = "How long a node must stay consolidatable before Karpenter acts, damping churn from short-lived pods"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.consolidate_after))
    error_message = "consolidate_after must be a duration such as 30s, 1m or 1h."
  }
}
variable "node_expire_after" {
  type        = string
  default     = "720h"
  description = "Maximum node lifetime before Karpenter recycles it, which is how nodes pick up new AMI releases"

  validation {
    condition     = var.node_expire_after == "Never" || can(regex("^[0-9]+(s|m|h)$", var.node_expire_after))
    error_message = "node_expire_after must be a duration such as 720h, or the literal Never."
  }
}
variable "root_volume_device_name" {
  type        = string
  default     = "/dev/xvda"
  description = "Root block device name for provisioned nodes. AL2023 uses /dev/xvda; Bottlerocket uses /dev/xvdb for its data volume"

  validation {
    condition     = can(regex("^/dev/", var.root_volume_device_name))
    error_message = "root_volume_device_name must be a device path starting with /dev/."
  }
}
variable "root_volume_size" {
  type        = string
  default     = "50Gi"
  description = "Root EBS volume size for provisioned nodes"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.root_volume_size))
    error_message = "root_volume_size must be a binary quantity such as 50Gi."
  }
}
variable "node_tags" {
  type        = map(string)
  default     = {}
  description = "Extra AWS tags applied to the instances, volumes and network interfaces Karpenter creates"

  validation {
    condition     = alltrue([for key in keys(var.node_tags) : length(key) > 0])
    error_message = "node_tags must not contain empty AWS tag keys."
  }
}
