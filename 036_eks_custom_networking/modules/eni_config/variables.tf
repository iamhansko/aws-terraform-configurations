variable "pod_subnets_by_az" {
  type        = map(string)
  description = "Pod subnet ID per availability zone. A map rather than a list because these become for_each keys and an ENIConfig is named after its zone, and because the IDs themselves are another module's output - unknown until apply - so only the keys can be statically known (rules.md B-8)"

  validation {
    condition     = length(var.pod_subnets_by_az) > 0
    error_message = "pod_subnets_by_az must contain at least one zone. With no ENIConfig at all, custom networking is enabled on the CNI and no pod can get an address."
  }
  validation {
    condition     = alltrue([for az in keys(var.pod_subnets_by_az) : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9][a-z]$", az))])
    error_message = "pod_subnets_by_az keys must be availability zone names such as ap-northeast-2a. The CNI matches an ENIConfig to a node by the value of the node's topology.kubernetes.io/zone label, so the name has to be exactly the zone."
  }
  validation {
    condition     = alltrue([for id in values(var.pod_subnets_by_az) : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "pod_subnets_by_az values must be valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to every pod ENI created from these ENIConfigs. Handed over as IDs, so this module never learns which of them is the cluster group and which is a pod group (rules.md B-6)"

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "security_group_ids must contain at least one group. An ENIConfig with no security groups produces pod ENIs in the VPC default group, which generally denies the traffic the pods need."
  }
}
