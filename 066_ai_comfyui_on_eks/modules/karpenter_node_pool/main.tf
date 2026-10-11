# One Karpenter pool: an EC2NodeClass describing how a node is built, and a NodePool describing which shapes
# may be chosen and what the nodes are labelled with.
#
# Replaces manifests/Karpenter/karpenter_v1.yaml from the blueprint, which deploy_infra.sh applied with
# kubectl after rewriting three of its lines with sed - the instance profile name, the security group Name tag
# pattern and the subnet Name tag pattern (rules.md E-1).
#
# Declared as raw manifests through alekc/kubectl rather than typed resources (rules.md E-3), and alekc/kubectl
# specifically, because this is applied in the same terraform apply as the cluster and the CRDs themselves
# (rules.md E-2).
resource "kubectl_manifest" "ec2_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = var.name
    }
    spec = merge({
      # alias pins the AMI family and lets EKS resolve the current release.
      amiSelectorTerms = [{ alias = var.ami_alias }]
      # The role name, not an instance profile. The blueprint used instanceProfile on purpose - with role:,
      # Karpenter creates profiles CloudFormation does not know about and the stack's role deletion failed.
      # Here the same profiles are created and deleted by Karpenter itself, under the IAM statements the
      # karpenter module grants for exactly that, and the EC2NodeClass finalizer is what removes them on
      # destroy - which is why the wait below matters.
      role = var.node_iam_role_name
      # Subnets and groups by ID rather than by the Name tag patterns the blueprint matched
      # (ComfyUI-on-EKS-Cluster/ComfyuiVPC/private*, eks-cluster-sg-ComfyUI-on-EKS-Cluster*). The caller
      # knows exactly which subnets and which group the nodes belong in, and a pattern that stops matching
      # after a rename fails as "no subnets found" at provisioning time (rules.md B-6).
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
      },
      # Only emitted when the caller asked for them (rules.md B-4).
      var.instance_store_policy == null ? {} : { instanceStorePolicy = var.instance_store_policy },
      var.user_data == null ? {} : { userData = var.user_data },
    )
  })

  # Karpenter puts the karpenter.k8s.aws/termination finalizer on every EC2NodeClass, and removing it is how
  # the instance profiles Karpenter created from spec.role get deleted. Without wait, destroy sends the DELETE,
  # moves straight on, and uninstalls the controller while the class is still Terminating - the profile is
  # left behind holding the node role, and the role's deletion then fails with DeleteConflict (rules.md D-7).
  wait = true

  timeouts {
    delete = var.delete_timeout
  }

  # The CRD this instantiates ships with the Karpenter chart, so the release has to be installed first - and
  # nothing in this module's inputs expresses that. The ordering is stated on the module block in the root,
  # so this module never learns that a Helm release exists (rules.md D-4).
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
        # The labels are what a workload's nodeSelector matches to land on this pool. The blueprint's pool had
        # none and its Deployment relied on the GPU request alone; the caller hands these to the workload as
        # its selector, so the two cannot disagree (rules.md B-5).
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
              values   = ["linux"]
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
          taints = [
            for taint in var.taints : {
              key    = taint.key
              value  = taint.value
              effect = taint.effect
            }
          ]
        })
      }
      # A hard ceiling on what this pool may provision. The blueprint's pool had none; on a GPU pool that
      # ceiling is the difference between a demo and a bill.
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

  # Deleting a NodePool makes Karpenter drain and terminate every node it launched, and the NodeClaims carry
  # Karpenter's termination finalizer. Waiting here keeps destroy from removing the controller - or the
  # EC2NodeClass these nodes were built from - while GPU instances are still being torn down (rules.md D-7).
  wait = true

  timeouts {
    delete = var.delete_timeout
  }

  # nodeClassRef.name is a literal string, so nothing else tells Terraform the EC2NodeClass must exist first
  # (rules.md E-2). Deleting the NodePool before the EC2NodeClass also lets Karpenter drain its nodes while it
  # still knows how they were built (rules.md D-4).
  depends_on = [kubectl_manifest.ec2_node_class]
}
