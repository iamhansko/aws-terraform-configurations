# One Karpenter pool: an EC2NodeClass describing how a node is built, and a NodePool describing which
# shapes may be chosen and what the nodes are labelled with.
#
# These replace the blueprint's karpenter-resources Helm chart (aws-ia/terraform-aws-eks-data-addons
# v1.35.0, helm-charts/karpenter-resources), which rendered exactly this pair from a values document
# per pool. The fields and defaults below are that chart's, so a pool declared here is the pool the
# blueprint got - the differences are called out where they occur.
#
# Declared as raw manifests through alekc/kubectl rather than typed resources (rules.md E-3), because
# they are applied in the same terraform apply as the cluster and the CRDs themselves (rules.md E-2).
resource "kubectl_manifest" "ec2_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = var.name
    }
    spec = merge({
      # The alias alone. The chart also wrote amiFamily: Bottlerocket next to it, which v1 accepts
      # but derives from the alias anyway.
      amiSelectorTerms = [{ alias = var.ami_alias }]
      # The role name, not an instance profile: Karpenter creates and manages the instance profile
      # itself from this.
      role = var.node_iam_role_name
      # Subnets and groups by ID, where the chart selected them by the karpenter.sh/discovery tag.
      # The tag matched every private subnet - the RFC 1918 /24s as well as the data plane /17s the
      # blueprint meant the nodes for - and every group the eks module tagged. The caller knows
      # exactly which ones it means, so it says so (rules.md B-6).
      subnetSelectorTerms        = [for id in var.subnet_ids : { id = id }]
      securityGroupSelectorTerms = [for id in var.security_group_ids : { id = id }]
      blockDeviceMappings = [
        for mapping in var.block_device_mappings : {
          deviceName = mapping.device_name
          ebs = {
            volumeSize          = mapping.volume_size
            volumeType          = mapping.volume_type
            encrypted           = mapping.encrypted
            deleteOnTermination = mapping.delete_on_termination
          }
        }
      ]
      detailedMonitoring = var.detailed_monitoring
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = var.metadata_hop_limit
        httpTokens              = "required"
      }
      tags = merge({ Name = "karpenter-${var.name}" }, var.node_tags)
      }, var.instance_store_policy == null ? {} : {
      # Only emitted when asked for. RAID0 stripes the instance's NVMe disks and points containerd and
      # the kubelet at them, and is meaningless on a type with no instance store (rules.md B-4).
      instanceStorePolicy = var.instance_store_policy
    })
  })

  # Karpenter puts karpenter.k8s.aws/termination on every EC2NodeClass and removes it only once no
  # NodeClaim refers to the class and the instance profile it created is gone. Without wait the
  # DELETE returns at once, the controller is uninstalled next, and the class - with an orphaned
  # instance profile behind it - is left Terminating (rules.md D-7).
  wait = true

  # The CRD this instantiates ships with the Karpenter chart, so the release has to be installed first.
  # That ordering is stated on the module block in the root, so this module never learns a Helm
  # release exists (rules.md D-4).
}

locals {
  # Only the requirements the caller asked for. The chart wrote exactly the list it was given, so an
  # empty list here means "no constraint on this key", not "a key with no allowed values" - which
  # Karpenter would read as a pool that can launch nothing.
  requirements = concat(
    [
      for requirement in [
        { key = "karpenter.k8s.aws/instance-category", values = var.instance_categories },
        { key = "karpenter.k8s.aws/instance-family", values = var.instance_families },
        { key = "karpenter.k8s.aws/instance-size", values = var.instance_sizes },
        { key = "kubernetes.io/arch", values = var.node_architectures },
        # linux, which the blueprint's pools left unstated. Karpenter would otherwise consider a
        # Windows shape if the node class allowed one.
        { key = "kubernetes.io/os", values = ["linux"] },
        { key = "karpenter.sh/capacity-type", values = var.capacity_types },
      ] : { key = requirement.key, operator = "In", values = requirement.values }
      if length(requirement.values) > 0
    ],
    var.additional_requirements,
  )
}

resource "kubectl_manifest" "node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = var.name
    }
    spec = {
      template = {
        # The labels are what a workload's affinity matches to land on this pool - the Kafka brokers
        # require NodeGroupType=kafka, and nothing else can provision the 58Gi nodes they ask for.
        metadata = { labels = var.node_labels }
        spec = merge({
          requirements = local.requirements
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = var.name
          }
          expireAfter            = var.node_expire_after
          terminationGracePeriod = var.termination_grace_period
          }, length(var.taints) == 0 ? {} : {
          taints = [
            for taint in var.taints : {
              key    = taint.key
              value  = taint.value
              effect = taint.effect
            }
          ]
        })
      }
      # A hard ceiling on what this pool may provision.
      limits = {
        cpu    = tostring(var.cpu_limit)
        memory = var.memory_limit
      }
      disruption = {
        consolidationPolicy = var.consolidation_policy
        consolidateAfter    = var.consolidate_after
        budgets             = [for budget in var.disruption_budgets : { nodes = budget }]
      }
      weight = var.weight
    }
  })

  # Waits for the pool's nodes to be gone. A NodePool's NodeClaims carry karpenter.sh/termination and
  # are owned by the pool, and wait = true deletes in the foreground - so the DELETE does not return
  # until Karpenter has drained and terminated every instance it launched for this pool. Without it
  # the controller can be uninstalled while those instances are still running, and nothing is left
  # that would ever terminate them (rules.md D-7).
  wait = true

  # nodeClassRef.name is a literal string, so nothing else tells Terraform the EC2NodeClass must exist
  # first (rules.md E-2). The same edge deletes the NodePool - and with it the nodes - before the class
  # they were built from (rules.md D-4).
  depends_on = [kubectl_manifest.ec2_node_class]
}
