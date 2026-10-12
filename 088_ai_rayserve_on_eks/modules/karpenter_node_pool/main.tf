# One Karpenter pool: an EC2NodeClass describing how a node is built, and a NodePool
# describing which shapes may be chosen and what the nodes are labelled with.
#
# Its own module, instantiated once per pool, because this project has three pools that
# differ in substance rather than in name - instance family, disk layout, instance store
# policy, and whether the nodes carry the nvidia.com/gpu taint. A single module with all
# three inlined would have to satisfy the union of their requirements, which is how a
# "GPU" flag ends up meaning four different things.
#
# Declared as raw manifests through alekc/kubectl rather than typed resources
# (rules.md E-3). alekc/kubectl specifically, because this is applied in the same
# terraform apply as the cluster and the CRDs themselves, and hashicorp/kubernetes would
# need both to already exist at plan time to resolve the schema (rules.md E-2).
#
# The _monolithic template produced these by echoing YAML into three files from a shell
# script an SSM Association ran, with subnet IDs, the cluster security group ID and the
# instance profile name substituted into the middle of the text (rules.md E-1).
resource "kubectl_manifest" "ec2_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = var.name
    }
    spec = merge({
      # alias pins the AMI family and lets EKS resolve the current release. This
      # replaces the amiFamily field Karpenter v0 used, which the _monolithic
      # template's manifests still carried alongside amiSelectorTerms - in v1 amiFamily
      # is no longer a field, so the API server rejected those manifests outright.
      amiSelectorTerms = [{ alias = var.ami_alias }]
      # The role name, not the instance profile name. Karpenter creates and manages the
      # instance profile itself from this, so the _monolithic template's explicit
      # instanceProfile field - which pointed at a profile Terraform created - is not
      # only unnecessary but a second owner of the same thing.
      role = var.node_iam_role_name
      # Subnets and groups by ID, as the _monolithic template selected them. Tags would
      # be the looser choice; IDs are the honest one here, because the caller already
      # knows exactly which subnets the nodes belong in (rules.md B-6/B-8: the IDs
      # arrive as inputs, and they are values rather than for_each keys).
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
      tags = merge({ Name = var.name }, var.node_tags)
      }, var.instance_store_policy == null ? {} : {
      # Only emitted when the caller asked for it. RAID0 stripes the instance's NVMe
      # disks and points containerd at them, which is what keeps a multi-gigabyte model
      # image off the EBS root volume - and it is meaningless on a family with no
      # instance store, where Karpenter would reject it (rules.md B-4).
      instanceStorePolicy = var.instance_store_policy
    })
  })

  # The CRD this instantiates ships with the Karpenter chart, so the release has to be
  # installed first - and nothing in this module's inputs expresses that. The ordering is
  # stated on the module block in the root rather than injected here as a dependency
  # variable, so this module never learns that a Helm release exists (rules.md D-4).
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
        # The labels are what a workload's nodeSelector matches to land on this pool
        # rather than on another. Always emitted here, unlike the single-pool copies of
        # this module elsewhere: with three pools a workload that cannot name one gets
        # whichever pool happens to fit, which is the bug this project would show as a
        # Ray head scheduled onto a GPU node.
        metadata = { labels = var.node_labels }
        spec = merge({
          requirements = concat([
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = var.instance_families
            },
            {
              key      = "karpenter.k8s.aws/instance-size"
              operator = "In"
              values   = var.instance_sizes
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = var.node_architectures
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              # linux, which the _monolithic template's pools left unstated. Karpenter
              # would happily consider a Windows shape without it.
              values = ["linux"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.capacity_types
            },
            ],
            var.additional_requirements,
          )
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = var.name
          }
          expireAfter = var.node_expire_after
          }, length(var.taints) == 0 ? {} : {
          # Only on the GPU pools. A taint here is what stops every unrelated pod from
          # landing on a g5 instance, and the workload's toleration is what lets the Ray
          # workers through (rules.md B-4).
          taints = [
            for taint in var.taints : {
              key    = taint.key
              value  = taint.value
              effect = taint.effect
            }
          ]
        })
      }
      # A hard ceiling on what this pool may provision. On a GPU pool that ceiling is
      # the difference between a demo and a bill.
      limits = {
        cpu    = tostring(var.cpu_limit)
        memory = var.memory_limit
      }
      disruption = {
        consolidationPolicy = var.consolidation_policy
        consolidateAfter    = var.consolidate_after
        budgets             = [for budget in var.disruption_budgets : { nodes = budget }]
      }
    }
  })

  # nodeClassRef.name is a literal string, so nothing else tells Terraform the
  # EC2NodeClass must exist first (rules.md E-2). Deleting the NodePool before the
  # EC2NodeClass also lets Karpenter drain its nodes while it still knows how they were
  # built (rules.md D-4).
  depends_on = [kubectl_manifest.ec2_node_class]
}
