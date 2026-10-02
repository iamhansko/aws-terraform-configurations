# One Karpenter NodePool and the EC2NodeClass it provisions from.
#
# Split out of the karpenter module because this project needs two pools - one spot, one
# on-demand - and the controller can only be installed once. The controller module owns the
# release and the node IAM role; this owns the pair of objects that describe a single kind of
# capacity, so it can be instantiated as many times as there are kinds (rules.md A-1/C-2).
#
# The _monolithic template wrote both pairs as single-quoted shell strings inside an SSM
# Association and applied them with kubectl, so neither was in state: no diff in plan, nothing
# removed on destroy, and a YAML indentation error would have appeared only in the
# association's output (rules.md E-1/E-2).
# EC2NodeClass and NodePool are CRDs the Helm release installs, so they are
# declared as raw manifests through alekc/kubectl rather than typed resources
# (rules.md E-3). alekc/kubectl specifically, because this module is applied in
# the same terraform apply as the cluster and the CRDs themselves, and
# hashicorp/kubernetes would need both to already exist at plan time to resolve
# the schema (rules.md E-2).
resource "kubectl_manifest" "ec2_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = var.node_class_name
    }
    spec = {
      # alias pins the AMI family and lets EKS resolve the current release,
      # replacing the amiFamily field that Karpenter v0 used.
      amiSelectorTerms = [{ alias = var.ami_alias }]
      # Karpenter derives the instance profile from this role name.
      # Injected rather than read from a sibling resource: the role belongs to the
      # controller module, and Karpenter derives the instance profile from its name
      # (rules.md B-6).
      role                       = var.node_role_name
      subnetSelectorTerms        = [{ tags = var.subnet_selector_tags }]
      securityGroupSelectorTerms = [{ tags = var.security_group_selector_tags }]
      blockDeviceMappings = [{
        deviceName = var.root_volume_device_name
        ebs = {
          volumeSize          = var.root_volume_size
          volumeType          = "gp3"
          encrypted           = true
          deleteOnTermination = true
        }
      }]
      tags = var.node_tags
    }
  })

  # The CRD this manifest instantiates ships with the Karpenter chart, which a different
  # module installs - so the caller has to order this module after it. Nothing here can
  # express that dependency (rules.md D-2/E-2).
}
resource "kubectl_manifest" "node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = var.node_pool_name
    }
    spec = {
      template = merge(
        # Only emitted when the caller asked for labels, so a pool with none
        # does not carry an empty metadata block (rules.md B-4). These labels are
        # what a workload's nodeSelector matches to land on Karpenter capacity.
        length(var.node_labels) > 0 ? { metadata = { labels = var.node_labels } } : {},
        {
          spec = {
            requirements = concat([
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
              {
                key      = "karpenter.k8s.aws/instance-category"
                operator = "In"
                values   = var.instance_categories
              },
              {
                # Excludes the smallest sizes, whose per-node pod and ENI limits
                # make them a poor fit for anything but toy workloads.
                key      = "karpenter.k8s.aws/instance-generation"
                operator = "Gt"
                values   = [tostring(var.minimum_instance_generation)]
              },
              ],
              # Narrows the choice to exact shapes when the caller pinned some.
              # It intersects with the category and generation requirements
              # above rather than replacing them, so a pinned type has to
              # satisfy those too.
              length(var.instance_types) > 0 ? [{
                key      = "node.kubernetes.io/instance-type"
                operator = "In"
                values   = var.instance_types
              }] : [],
              var.additional_requirements,
            )
            nodeClassRef = {
              group = "karpenter.k8s.aws"
              kind  = "EC2NodeClass"
              name  = var.node_class_name
            }
            expireAfter = var.node_expire_after
          }
        },
      )
      # A hard ceiling on what this pool may provision, so a runaway workload
      # cannot scale the account's EC2 spend without bound.
      limits = {
        cpu    = tostring(var.cpu_limit)
        memory = var.memory_limit
      }
      disruption = {
        consolidationPolicy = var.consolidation_policy
        consolidateAfter    = var.consolidate_after
      }
    }
  })

  # nodeClassRef.name is a literal string, so nothing else tells Terraform the
  # EC2NodeClass must exist first (rules.md E-2). Deleting the NodePool before
  # the EC2NodeClass also lets Karpenter drain its nodes while it still knows
  # how they were built (rules.md D-4).
  depends_on = [kubectl_manifest.ec2_node_class]
}
