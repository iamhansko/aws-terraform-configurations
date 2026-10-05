locals {
  # The block Multus hands addresses out of. Carved by the network module, which owns the subnet,
  # rather than here: the caller's VPC reservation has to name the same block and has to be created
  # before any node attaches an ENI in that subnet, which it cannot be if the value comes from this
  # module - this one is ordered after multus_cni, and therefore after the node group
  # (rules.md B-5/D-2). The variable's validation checks it really is inside subnet_cidr, which is
  # the safety the old newbits/index interface gave for free.
  pod_range_cidr = var.pod_range_cidr
  # host-local hands out addresses between these two inclusive. The first address of the block is
  # skipped because an ipvlan l3 attachment on a subnet whose own network address sits below it has
  # nothing useful to do with it, and the last is skipped because AWS reserves the final address of
  # every subnet - the _monolithic template's range ran to .255 and so could hand out an address the
  # VPC will not route.
  range_start = cidrhost(local.pod_range_cidr, 1)
  range_end   = cidrhost(local.pod_range_cidr, -2)
  # The CNI configuration, as an object rather than a string with holes punched in it. The
  # _monolithic template built this by echoing a YAML document containing a JSON document, with
  # Terraform interpolations inside both - so a missing brace or an unquoted address was a runtime
  # surprise on the bastion rather than a plan-time error (rules.md E-3).
  cni_config = merge(
    {
      cniVersion = var.cni_version
      name       = var.name
      type       = var.cni_type
      master     = var.master_interface
      mode       = var.cni_mode
      ipam = merge(
        {
          # Named by the module that installed the plugin rather than written here, so an attachment
          # cannot ask for an IPAM plugin that is not on the node - which leaves pods in
          # ContainerCreating with the reason only in their events (rules.md B-5).
          type = var.ipam_type
          # This attachment's own block, not the whole subnet the ENI sits in.
          #
          # The IPAM plugin writes whatever it is given here onto the pod interface as its prefix,
          # and ipvlan turns that into a link route. Handing every attachment the full subnet
          # therefore installs the same route once per interface - net1 and net2 both claiming
          # 10.0.5.0/24 - and the kernel picks one of them for the whole range. Traffic for the
          # second network then leaves through the first network's ENI and the peer never answers:
          # the interface is up, has the right address, and reaches nothing.
          #
          # Narrowed to the block this attachment hands out, the routes do not overlap and each range
          # goes out of the interface that actually carries it. The blocks are still inside the
          # reserved range, so the VPC reservation is unaffected.
          #
          # "range", not "subnet": that is the key whereabouts reads, and host-local reads the other
          # one. Getting it wrong is not a validation error anywhere - the plugin simply has no range
          # and fails the pod.
          range = var.pod_range_cidr
          # Stated rather than left to inference. whereabouts would derive the same two values from
          # the range, skipping its network and broadcast addresses, but these are also what the
          # caller's output reports as the range in use - so they are one value rather than two that
          # agree by coincidence (rules.md B-5). Note the snake_case: host-local spells the same two
          # keys rangeStart and rangeEnd.
          range_start = local.range_start
          range_end   = local.range_end
        },
        var.gateway == null ? {} : { gateway = var.gateway },
      )
    },
  )
}
# The object a pod's k8s.v1.cni.cncf.io/networks annotation names.
#
# It says: put an ipvlan interface on the host's <master_interface>, and give it an address out of
# <pod_range_cidr>. Nothing validates the interface name or the address range - a pod asking for an
# attachment whose master does not exist on its node stays in ContainerCreating, and the reason is
# in the pod's events and the Multus log rather than anywhere on this object.
#
# The CRD this instantiates comes from the multus_cni module, so the caller has to order this after
# it (rules.md D-2/E-2): applied first, it fails with "no matches for kind".
resource "kubectl_manifest" "network_attachment_definition" {
  yaml_body = yamlencode({
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      # A string, because that is what the CRD's schema declares the field as - so the
      # configuration is JSON inside YAML by design rather than by accident.
      config = jsonencode(local.cni_config)
    }
  })
}
