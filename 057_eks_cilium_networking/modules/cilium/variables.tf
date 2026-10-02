# There is deliberately no cluster_name variable here.
#
# One used to exist, described as being written into the release as the cluster name Cilium reports
# and as naming the operator's IAM role. It did neither - nothing in this module referenced it except
# its own validation - so the root passed a value that went nowhere and the description documented
# behaviour that was not there.
#
# Nothing needs it. The operator discovers the cluster name from the EC2 tags on the nodes once it can
# reach the EC2 API, which it logs on startup:
#
#   "Auto-detected EKS cluster name for ENI garbage collection" clusterName=cilium-cluster
#
# Removing the argument does not weaken ordering either. The value reference to
# module.eks_cluster.cluster_name was never what sequenced this module - the block carries
# depends_on = [module.network, module.eks_cluster] explicitly, and it still reads
# oidc_provider_arn and cluster_endpoint_host from the same module (rules.md D-2/D-3).
#
# If a future change needs the name - naming the IAM role, or setting the chart's cluster.name, or
# pinning eni.gcTags instead of relying on auto-detection - add it back then, pointed at whatever
# actually consumes it.
variable "k8s_service_host" {
  type        = string
  description = "API server host, without the https:// scheme, that the Cilium agent connects to. Required rather than optional because kube_proxy_replacement is on: with no kube-proxy there is no iptables rule translating the in-cluster kubernetes Service address, so an agent told to find the API server through that Service cannot start - and until the agent starts, nothing sets up the rule it was waiting for"

  validation {
    condition     = length(var.k8s_service_host) > 0 && !can(regex("^https?://", var.k8s_service_host))
    error_message = "k8s_service_host must be a bare host name with no scheme; pass the cluster module's cluster_endpoint_host rather than cluster_endpoint."
  }
}
variable "k8s_service_port" {
  type        = number
  default     = 443
  description = "Port of the API server endpoint"

  validation {
    condition     = var.k8s_service_port > 0 && var.k8s_service_port <= 65535
    error_message = "k8s_service_port must be a valid TCP port."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in the operator's IRSA trust policy"

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
variable "chart_version" {
  type        = string
  default     = "1.18.2"
  description = "Version of the cilium chart, as the _monolithic template had it. Pinned: a CNI is the one component where an unexpected upgrade takes the whole data plane with it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 1.18.2)."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://helm.cilium.io/"
  description = "Helm repository hosting the cilium chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace Cilium installs into. kube-system, because the agent is a node-level component that has to be scheduled onto nodes that are not Ready yet, and its service account name is baked into the operator's IRSA trust policy"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "release_name" {
  type        = string
  default     = "cilium"
  description = "Name of the Helm release"

  validation {
    condition     = length(var.release_name) > 0
    error_message = "release_name must not be empty."
  }
}
variable "operator_service_account_name" {
  type        = string
  default     = "cilium-operator"
  description = "Service account the Cilium operator runs as, annotated with the IRSA role ARN. This is the chart's own default name and appears verbatim in the trust policy's sub condition, so changing one without the other produces an operator whose AssumeRoleWithWebIdentity call is rejected - which shows up as pods stuck without addresses rather than as a permissions error"

  validation {
    condition     = length(var.operator_service_account_name) > 0
    error_message = "operator_service_account_name must not be empty."
  }
}
variable "ipam_mode" {
  type        = string
  default     = "eni"
  description = "How Cilium allocates pod addresses. eni means it attaches Elastic Network Interfaces and hands out real VPC addresses, the same model the VPC CNI uses - which is what makes pods reachable by an AWS load balancer with target-type ip. The alternative, cluster-pool, gives pods an overlay range that nothing outside the cluster can route to"

  validation {
    condition     = contains(["eni", "cluster-pool", "kubernetes", "multi-pool"], var.ipam_mode)
    error_message = "ipam_mode must be one of: eni, cluster-pool, kubernetes, multi-pool."
  }
}
variable "routing_mode" {
  type        = string
  default     = "native"
  description = "Whether pod traffic is encapsulated (tunnel) or routed as-is (native). native, because in ENI mode the addresses are already VPC addresses the network can route - tunnelling them would add encapsulation overhead to reach an address the VPC already knows"

  validation {
    condition     = contains(["native", "tunnel"], var.routing_mode)
    error_message = "routing_mode must be either native or tunnel."
  }
}
variable "kube_proxy_replacement" {
  type        = bool
  default     = true
  description = "Whether Cilium implements Service routing itself instead of kube-proxy. True, which is the second half of what this project demonstrates and the reason no kube-proxy addon is installed. It also makes k8s_service_host load-bearing: with no kube-proxy, nothing translates the in-cluster kubernetes Service address until Cilium is running"
}
variable "egress_masquerade_interfaces" {
  type        = string
  default     = null
  description = "Interface pattern Cilium masquerades pod egress behind. Null, because in ENI mode the chart renders enable-ipv4-masquerade: false - pod addresses are already VPC addresses the network routes, and the NAT gateway translates them on the way out, so there is nothing for Cilium to masquerade. Widely-quoted Cilium-on-EKS instructions still pass eth0 here; setting it while masquerading is off has no effect at all, which is worth knowing before concluding it fixed something. It only becomes load-bearing if masquerading is turned back on, and then a wrong interface produces pods that talk to each other and reach nothing outside the VPC"

  validation {
    condition     = var.egress_masquerade_interfaces == null || length(var.egress_masquerade_interfaces) > 0
    error_message = "egress_masquerade_interfaces must be a non-empty interface pattern, or null to leave it unset."
  }
}
variable "operator_replicas" {
  type        = number
  default     = 1
  description = "Number of Cilium operator replicas. One, because the chart's default of two cannot both be scheduled on a small node group with anti-affinity, leaving a permanently Pending pod that reads as a failed install"

  validation {
    condition     = var.operator_replicas >= 1
    error_message = "operator_replicas must be at least 1."
  }
}
variable "wait_for_release" {
  type        = bool
  default     = false
  description = "Whether the apply blocks until the agent and operator are running. False, and deliberately so: this release is installed before the node group exists, because a managed node group whose nodes have no CNI never reports its instances as joined and the create call fails. With no nodes there is nothing for the agent DaemonSet or the operator to be scheduled onto, so waiting here would block until the timeout every time. The node group's own creation is the real gate - if Cilium is broken, nodes never become Ready and that is where it surfaces (rules.md B-4)"
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the release may take when wait_for_release is true. Ignored otherwise"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
variable "region" {
  type        = string
  description = "AWS region the operator's EC2 calls are made against, set as AWS_REGION on the operator. Required rather than optional: in ENI mode every EC2 call needs a region, and nothing else supplies one - the EKS pod identity webhook would, but it skips variables the pod already declares and this chart declares AWS_DEFAULT_REGION itself as an optional reference to a secret that does not exist. Without it the operator dies in a poll-loop timeout that mentions neither the region nor EC2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region such as ap-northeast-2."
  }
}
