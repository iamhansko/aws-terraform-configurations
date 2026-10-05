data "aws_region" "current" {}
# Both only for the resource ARN in the sidecar's IAM policy, which is scoped to this
# account's network interfaces in this partition rather than to "*".
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
module "network" {
  source = "./modules/network"

  vpc_name                 = "${var.cluster_name}-vpc"
  internet_gateway_name    = "${var.cluster_name}-igw"
  public_subnet_name       = "${var.cluster_name}-public"
  private_subnet_name      = "${var.cluster_name}-private"
  public_route_table_name  = "${var.cluster_name}-public-rt"
  private_route_table_name = "${var.cluster_name}-private-rt"
  nat_gateway_name         = "${var.cluster_name}-natgw"
  multus_subnet_name       = "${var.cluster_name}-multus"
  # How the Multus subnet is split: the upper half to pods, the lower half left for the primary
  # addresses of the ENIs the nodes attach there. The module carves the block and exposes it, so the
  # attachment and the VPC reservation below name one value rather than deriving it twice
  # (rules.md B-5).
  multus_pod_range_newbits = var.multus_pod_range_newbits
  multus_pod_range_index   = var.multus_pod_range_index
  # No subnet tags: nothing here creates a load balancer (rules.md G-1).
  #
  # The extra ENIs come out of a subnet of their own, which is what AWS's own Multus guidance does.
  # The _monolithic template took them out of the node's private subnet - its subnetListAZ1 named
  # that one subnet twice - and that has two consequences the module header spells out: a pod's net1
  # link route then covers the node's whole subnet and shadows the VPC CNI path for it, and the
  # node's own Multus ENIs can take addresses out of the range host-local hands to pods.
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network
  # module's resources (rules.md D-3).
  depends_on = [module.network]
}
# The security group the nodes attach their Multus ENIs with. A group of its own rather than the
# cluster security group, so the rules on the secondary network are not the rules on the primary one
# - which is what makes the second interface a separation boundary rather than just a second path.
module "multus_security_group" {
  source = "./modules/multus_security_group"

  vpc_id      = module.network.vpc_id
  name        = "${var.cluster_name}-multus-sg"
  description = "Security group for the secondary ENIs the ${var.cluster_name} nodes attach for Multus"
  # Nothing but the Multus network itself by default. The module always allows traffic between
  # members of this group, which is what Multus pods on different nodes need; anything else has to
  # be named here on purpose.
  ingress_source_security_groups = var.multus_ingress_source_security_groups
  ingress_cidr_blocks            = var.multus_ingress_cidr_blocks

  # Only the network module - this has to exist before the node group, because it is the node's own
  # bootstrap that creates the ENIs and names this group (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources
  # behind those outputs, not after the NAT gateways and route table associations that never surface
  # as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name
  # Left at the addon's defaults, and that is the point of this variant: Multus does not replace the
  # VPC CNI, it delegates the pod's primary interface to it. The multi_nic variant next door instead
  # sets ENABLE_MULTI_NIC and uses no Multus at all.

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this
  # addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any
  # capacity - and nodes need it to join Ready (rules.md C-4). Multus then names the configuration
  # file this addon writes, 10-aws.conflist, as the CNI it delegates to.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
locals {
  # Every interface the extra ENIs come up as, one per ENI the node attaches. Derived from the same
  # prefix, starting index and count the node bootstrap loops over, so an attachment cannot name an
  # interface the nodes do not have - which is the failure that leaves pods in ContainerCreating with
  # nothing explaining why (rules.md B-1/B-5).
  #
  # One attachment per interface, rather than one attachment on the first of them: multus_interface_count
  # ENIs are created, tagged, source/dest-checked and billed per node, and an interface no attachment
  # names is wired to nothing at all. Nothing reports that - the node comes up, the pods come up with
  # one extra interface, and the second ENI simply sits there.
  multus_interfaces       = [for i in range(var.multus_interface_count) : "${var.multus_interface_prefix}${var.multus_interface_start_index + i}"]
  multus_master_interface = local.multus_interfaces[0]
  # A block per attachment, carved out of the one the VPC reservation covers.
  #
  # They cannot share a range. host-local keys its allocation store by the network's name, so two
  # attachments pointed at the same range each start at the bottom of it and hand the same address to
  # net1 and net2 of the same pod. Splitting the reserved block is what keeps the two apart, and
  # ceil(log(count, 2)) is the number of bits that fits count of them - zero bits for a single
  # interface, which leaves the block whole.
  multus_pod_range_newbits = ceil(log(var.multus_interface_count, 2))
  multus_attachments = {
    for index, interface in local.multus_interfaces : interface => {
      name           = "${interface}-nad"
      pod_range_cidr = cidrsubnet(module.network.multus_pod_range_cidr, local.multus_pod_range_newbits, index)
    }
  }
  # Pulled from the region the cluster is in rather than the us-west-2 registry the upstream manifest
  # hardcodes, so every node pull stays inside the region.
  multus_image = "${var.multus_image_registry_account}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/eks/multus-cni:${var.multus_image_version}"
  # What each node does on boot, in this order: tell nodeadm's interface manager that a CNI owns the
  # extra interfaces, set the interface naming and the sysctl values, then create
  # var.multus_interface_count ENIs in its own subnet, tag them so the VPC CNI leaves them alone and
  # attach them at device indexes 1 upward. Then reboot, because the naming and the sysctl values
  # only take effect from a clean start.
  #
  # The host-side configuration deliberately comes before the ENIs rather than after them. Done the
  # other way round, a transient failure anywhere in the ENI loop aborts the script under
  # set -euo pipefail and leaves interfaces attached but unmarked and the reboot never taken - a
  # node that never reports Ready, and therefore a cluster where the Multus DaemonSet has nowhere to
  # run. Ordering it this way, plus the trap that reboots on any exit, means a partial failure costs
  # an interface rather than the node.
  #
  # The _monolithic template put this in a launch template too, so the shape is the same - what
  # changes is that the subnet and security group are Terraform references rather than strings echoed
  # into a file, and that the loop count, the interface names and the reboot are all derived from the
  # same variables the attachment reads.
  node_user_data = <<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==BOUNDARY=="

    --==BOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    set -o xtrace
    set -euo pipefail

    TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    REGION=${data.aws_region.current.region}
    SUBNET_ID=${module.network.multus_subnet_a_id}
    SECURITY_GROUP_ID=${module.multus_security_group.security_group_id}

    # Reboots however this script ends, including on a set -euo pipefail abort partway through.
    #
    # Everything that matters below only takes effect from a clean boot - the interface names, the
    # grub change and the sysctl drop-in - and a node that attached its ENIs and then failed before
    # rebooting is the state README.md records as fatal: nodeadm finds the secondary links still
    # "configured", never reports the node Ready, and so the Multus DaemonSet has no node to land
    # on. That surfaces as "Multus is not installed" with nothing pointing at the node bootstrap,
    # and it is non-deterministic, because what aborts the script is a transient dnf or EC2 API
    # failure. Rebooting regardless makes the worst case a node carrying fewer extra interfaces
    # than asked for rather than a node that never joins at all.
    #
    # cloud-init runs this part once per instance rather than once per boot, so this cannot loop.
    trap reboot EXIT

    # The host-side configuration is done first, before any ENI exists, so that "every attached
    # secondary ENI already has its marker" holds at every instant rather than only at the end of a
    # fully successful run. Nothing here has to wait for the interfaces: the marker names are
    # derived from the same two variables the attachment reads, not discovered from the host.
    #
    # The markers tell nodeadm's interface manager that these interfaces belong to a CNI, so it
    # leaves them unconfigured. Without them nodeadm brings the interfaces up with DHCP addresses of
    # its own, and ipvlan then shares an interface whose addressing is managed by something else.
    mkdir -p "/etc/eks/nodeadm/udev-net-manager/$INSTANCE_ID"
    %{if var.disable_predictable_interface_names~}

    # Turns off the kernel's predictable naming, so the extra ENIs come up as eth1, eth2 rather than
    # ens6, ens7. It only takes effect after the reboot, which is why the markers written below use
    # the eth names and any ens ones are removed.
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&net.ifnames=0 biosdevname=0 /' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    %{endif~}

    for OFFSET in $(seq 0 $((${var.multus_interface_count} - 1))); do
      echo "cni" > "/etc/eks/nodeadm/udev-net-manager/$INSTANCE_ID/${var.multus_interface_prefix}$((OFFSET + ${var.multus_interface_start_index}))"
    done

    # ipvlan l3 puts addresses on the interface that do not belong to its subnet from the kernel's
    # point of view, and reverse path filtering drops the replies.
    #
    # A drop-in file, truncated on each run, rather than appending to /etc/sysctl.conf and applying
    # it with "sysctl -p". Appending left a duplicate pair of lines behind on every run, and
    # "sysctl -p" reads the whole file and exits non-zero if any key in it cannot be set - which
    # under set -e aborted this script before the markers and the reboot, which is the failure the
    # trap above exists for. Nothing needs these values before the reboot, so writing the file and
    # letting the boot apply it is enough.
    echo "net.ipv4.conf.default.rp_filter = 0" > /etc/sysctl.d/99-multus-rp-filter.conf
    echo "net.ipv4.conf.all.rp_filter = 0" >> /etc/sysctl.d/99-multus-rp-filter.conf

    # jq reads the CLI's JSON below. The EKS AL2023 AMI has carried it, but installing it is cheap
    # and a missing jq would otherwise fail this script in the middle of the loop.
    command -v jq >/dev/null 2>&1 || dnf install -y -q jq

    for INDEX in $(seq 1 ${var.multus_interface_count}); do
      # node.k8s.amazonaws.com/no_manage tells the VPC CNI this interface is not its to hand
      # addresses out of. Without the tag the CNI adopts the ENI and starts assigning pod addresses
      # on it, and those collide with the ones Multus assigns from the same subnet.
      #
      # The security group is the Multus one, not the cluster's. Everything on the primary network -
      # the control plane's managed interfaces, this node's own interface, every pod the VPC CNI
      # addresses - stays in the cluster group, so a rule written for the secondary network applies
      # to the secondary network only.
      ENI_ID=$(aws ec2 create-network-interface --region "$REGION" \
        --subnet-id "$SUBNET_ID" --groups "$SECURITY_GROUP_ID" --description "Multus" \
        --tag-specifications 'ResourceType=network-interface,Tags=[{Key=node.k8s.amazonaws.com/no_manage,Value=true}]' \
        | jq -r '.NetworkInterface.NetworkInterfaceId')
      ATTACHMENT_ID=$(aws ec2 attach-network-interface --region "$REGION" \
        --network-interface-id "$ENI_ID" --instance-id "$INSTANCE_ID" --device-index "$INDEX" \
        | jq -r '.AttachmentId')
      # An ipvlan l3 attachment sends pod traffic out of this ENI with addresses that are not the
      # ENI's own, which the VPC drops unless the source/destination check is off.
      aws ec2 modify-network-interface-attribute --region "$REGION" \
        --network-interface-id "$ENI_ID" --no-source-dest-check
      # Without this the ENIs survive the instance and are billed while attached to nothing - and
      # terraform destroy knows nothing about them, because nothing here created them.
      aws ec2 modify-network-interface-attribute --region "$REGION" \
        --network-interface-id "$ENI_ID" \
        --attachment "AttachmentId=$ATTACHMENT_ID,DeleteOnTermination=True"
    done
    %{if var.disable_predictable_interface_names~}

    # Cleared here, after the attachments, and not with the rest of the host configuration above.
    #
    # On this first boot predictable naming is still in effect, so the ENIs attached by the loop come
    # up as ens6, ens7 - names the markers written above deliberately do not cover, because they name
    # the post-reboot interfaces. nodeadm therefore sees those links as systemd-managed and records an
    # io.systemd.Network marker of its own for each. After the reboot those markers name interfaces
    # that no longer exist, and leaving them behind makes the next boot's hook fail with
    #
    #   failed to ensure primary ENI only configuration: context deadline exceeded
    #
    # which is the state README.md records. Moving this removal up with the other host configuration
    # deletes nothing at all, because the markers it exists to clear are created by the loop above it.
    rm -f "/etc/eks/nodeadm/udev-net-manager/$INSTANCE_ID"/ens*
    %{endif~}

    --==BOUNDARY==--
  EOT
}
# The nodes the extra interfaces live on. Their launch template user data is what creates and
# attaches the ENIs, which is the half of Multus that AWS cannot do for you: Multus assumes the
# interfaces are already there.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  labels          = var.node_group_labels
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  # One subnet only, as the _monolithic template had it. Every extra ENI is created in this same
  # subnet, so a node in another zone would need its own attachment naming its own subnet - which is
  # why AWS's guidance is one node group per zone for this.
  subnet_ids = [module.network.private_subnet_a_id]
  key_name   = module.key_pair.key_name
  # EKS accepts only MIME multipart user data on a launch template: a bare shell script here is
  # silently ignored, and so is a bare NodeConfig. With no custom AMI, EKS merges its own NodeConfig
  # boundary into this document.
  custom_user_data = local.node_user_data
  # The node role already carries AmazonEKS_CNI_Policy, which is what lets this script create,
  # attach, tag and modify network interfaces. Nothing extra is needed - and nothing broader should
  # be added, which is worth saying because the script reads like it wants administrator access
  # (rules.md A-5).

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  #
  # The VPC reservation is in here for a different reason, and it is the one edge that is easy to
  # leave out: this node's own bootstrap attaches the Multus ENIs, and the VPC picks their primary
  # addresses out of the Multus subnet. A reservation created afterwards does not take back an
  # address already assigned, so an ENI ends up holding one of the addresses host-local later hands
  # to a pod. Both resources only reference module.network, so nothing orders them against each
  # other without saying so (rules.md D-2).
  depends_on = [
    module.network,
    module.eks_vpc_cni_addon,
    module.eks_kube_proxy_addon,
    aws_ec2_subnet_cidr_reservation.multus_pod_range,
  ]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# Multus itself: the CRD, the RBAC, the daemon config and the DaemonSet, from AWS's pinned EKS build
# rather than upstream's default branch.
module "multus_cni" {
  source = "./modules/multus_cni"

  image = local.multus_image
  # The file the VPC CNI writes on an EKS node. Multus delegates the pod's primary interface to it,
  # so naming the wrong one takes the primary interface away from every pod on the node.
  master_cni_config_file = "10-aws.conflist"

  # The DaemonSet has to land on a node, and its init container has to copy the shim onto that node's
  # filesystem, before any pod asking for an attachment can start. Ordering the module after the node
  # group also means terraform destroy removes Multus while nodes still exist to run the deletion
  # (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The IPAM plugin Multus calls to pick the addresses. Cluster-wide, which is the difference that
# matters once there is more than one node: host-local keeps its allocation store in a directory on
# each node, so every node starts handing out the bottom of the range and two pods get the same
# address. whereabouts keeps the store in the cluster as IPPool objects instead.
module "whereabouts_ipam" {
  source = "./modules/whereabouts_ipam"

  # The sweep that reclaims addresses whose pod is gone. Far more often than the upstream default of
  # once a day, because the ranges here are a /26 each and this project creates and deletes the same
  # pods repeatedly.
  reconciler_cron_expression = var.whereabouts_reconciler_cron_expression

  # It installs its binary into the same directory Multus reads plugins from, so Multus has to have
  # set that up first, and it has to land on a node to do it. Ordering the module after the node
  # group also means terraform destroy removes it while a kubelet still exists to run the deletion
  # (rules.md D-4).
  depends_on = [module.network, module.eks_node_group, module.multus_cni]
}
# What a pod's annotation names: an ipvlan attachment on the node's second interface, handing out
# addresses from the upper half of the node's subnet.
module "multus_network_attachment" {
  source = "./modules/multus_network_attachment"

  # One instance per extra interface the nodes attach, so every ENI that is created is also named by
  # an attachment. The keys come from variables alone, so they are known during plan even though the
  # subnet the values are carved from is not (rules.md B-8).
  for_each = local.multus_attachments

  name      = each.value.name
  namespace = var.workload_namespace
  # The key is the interface, derived from the same prefix, index and count the node bootstrap loops
  # over, so the two cannot disagree (rules.md B-1).
  master_interface = each.key
  # Named by the module that installed the plugin, so the attachment cannot ask for an IPAM that is
  # not on the node (rules.md B-5).
  ipam_type = module.whereabouts_ipam.ipam_type
  # The Multus subnet the ENIs were created in, read from the network module rather than restated
  # (rules.md B-5). A subnet of its own, so the link route ipvlan installs on a pod's net1 covers
  # only this network and leaves the node's subnet to the VPC CNI.
  subnet_cidr = module.network.multus_subnet_a_cidr_block
  # This instance's slice of the block the network module carved and the reservation below covers.
  # The split happens in the locals above rather than here because every attachment has to agree on
  # how the block is divided, and because the reservation names the whole of it (rules.md B-5/D-2).
  pod_range_cidr = each.value.pod_range_cidr

  # The CRD comes from the multus_cni module, so this fails with "no matches for kind" if applied
  # first (rules.md D-2). whereabouts is in the list because an attachment naming an IPAM plugin
  # that is not installed yet is accepted by the API server and only fails when a pod asks for it.
  depends_on = [
  module.network, module.multus_cni, module.whereabouts_ipam]
}
# Stops the VPC from handing the addresses Multus gives out to an ENI as well.
#
# The two sides have to name the same block, and they do: the CIDR comes back out of the attachment
# module that derived it, rather than being written twice (rules.md B-5). Without the reservation
# both the VPC and host-local allocate from the same range and the collision appears as a pod that
# can be reached from some places and not others.
#
# The _monolithic template made these reservations with two "aws ec2 create-subnet-cidr-reservation"
# calls from the bastion - so they were not in state, were not removed by destroy, and blocked the
# subnet's deletion on the way out.
resource "aws_ec2_subnet_cidr_reservation" "multus_pod_range" {
  subnet_id  = module.network.multus_subnet_a_id
  cidr_block = module.network.multus_pod_range_cidr
  # explicit rather than prefix. Both types stop AWS assigning the block to network interfaces,
  # which is the whole requirement here, but they say different things about who uses it afterwards:
  # prefix hands the block to AWS for prefix delegation - which the VPC CNI would allocate from if
  # ENABLE_PREFIX_DELEGATION were ever turned on in this project - and explicit says the addresses
  # are assigned by hand. host-local on the node hands these out, so explicit is the accurate one.
  reservation_type = "explicit"
  description      = "Addresses reserved for Multus pod interfaces on ${local.multus_master_interface}"

  # Only the network module, deliberately. This has to exist before the node group, because it is
  # the node's own bootstrap that attaches the Multus ENIs in this subnet and the VPC picks their
  # primary addresses - and a reservation created afterwards does not take back an address already
  # assigned. Depending on the attachment module, as an earlier version did, put this after
  # multus_cni and therefore after the nodes, which is how an ENI came to hold an address inside
  # this block (rules.md D-3).
  depends_on = [module.network]
}
module "multus_workload" {
  source = "./modules/multus_workload"

  name      = var.workload_name
  namespace = var.workload_namespace
  # One Deployment per interface, one pod each, each naming only its own attachment - so every pod
  # holds exactly one secondary ENI and no two pods share one. replicas_per_attachment is left at
  # its default of one for that reason; a second replica would be a second pod on the same ENI.
  #
  # Keyed by interface so the Deployments are named multi-homed-eth1, multi-homed-eth2 and the
  # mapping from pod to ENI is legible without reading an annotation. The names are taken from the
  # attachment modules rather than restated: a pod naming an attachment that does not exist stays in
  # ContainerCreating, and the reason is only in its events (rules.md B-5).
  network_attachments = { for interface in local.multus_interfaces : interface => module.multus_network_attachment[interface].name }
  # Changes whenever any attachment's CNI configuration does, which replaces these pods. Multus
  # plumbs a pod once, at creation, so without this an edited attachment leaves the running pods on
  # the old configuration - addresses from a subnet the attachment no longer names, and a link route
  # on net1 that still covers it (rules.md B-5).
  network_attachment_revision = substr(sha1(join(",", [for interface in local.multus_interfaces : module.multus_network_attachment[interface].config_revision])), 0, 12)
  # Pinned to the node group that actually has the extra interfaces. Nothing else in this cluster
  # does, and a pod scheduled elsewhere would never start (rules.md B-5).
  node_selector = module.eks_node_group.labels
  # What the sidecar needs to register each pod's secondary address with the VPC, which is
  # what makes the Multus network work between nodes rather than only within one.
  #
  # The OIDC values come from the cluster module rather than being restated: a trust policy naming a
  # different provider is accepted by IAM and fails only when a pod tries to assume the role
  # (rules.md B-5). The region, account and partition scope the policy to this account's interfaces.
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  region            = data.aws_region.current.region
  account_id        = data.aws_caller_identity.current.account_id
  partition         = data.aws_partition.current.partition

  # The attachment has to exist, Multus has to be running on the node, and the VPC reservation has to
  # be in place before the first pod takes an address out of that range. Ordering the module after
  # all three also makes terraform destroy remove the pods before Multus and before the reservation
  # (rules.md D-2/D-4).
  depends_on = [
    module.network,
    module.multus_cni,
    module.multus_network_attachment,
    aws_ec2_subnet_cidr_reservation.multus_pod_range,
  ]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server. The module is
  # handed an ID list and never learns it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that cluster and
  # carries all five tools (rules.md H-1). None of them creates anything: Multus, the attachment, the
  # demo Deployment and the two subnet CIDR reservations the _monolithic template made from here are
  # Terraform resources now (rules.md E-1).
  #
  # Bugs from that template that are not carried over. It ran "exec bash" partway through, which
  # replaces the shell and silently discarded every remaining line - eksctl, helm, the AWS Load
  # Balancer Controller install, the Multus apply, both CIDR reservations, the attachment and the
  # demo Deployment were all after it, so on a real boot none of them ran and the project
  # demonstrated nothing. It pulled eksctl from weaveworks rather than eksctl-io. And it wrote the
  # "complete" line for the k alias into .bashrc before the line that defines __start_kubectl, so
  # every login printed a "function not found" error (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not have
    # it without a restart.
    systemctl restart code-server

    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before
    # complete names it, or every login prints "function not found" (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know nothing about each
# other, so it belongs in the root (rules.md C-1).
resource "aws_eks_access_entry" "vscode_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "vscode_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode_access_entry]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the kubectl provider could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    multus_install = {
      order       = 4
      title       = "Multus install"
      description = "The image and the CNI configuration Multus delegates the primary interface to. Pinned to AWS's EKS build and pulled from this region, where the _monolithic template applied upstream's master branch and pulled from us-west-2"
      value       = "${module.multus_cni.image}, master CNI ${module.multus_cni.master_cni_config_file}"
    }
    interface_plan = {
      order       = 5
      title       = "How the interfaces are named and addressed"
      description = "The four things that have to agree: what the nodes create, what each attachment names, which pod asks for it, and what the VPC has been told to keep clear. All of them are derived from the same variables, so they cannot drift apart"
      value       = "${var.multus_interface_count} extra ENIs per node, one dedicated to one pod each: ${join(", ", [for interface in local.multus_interfaces : "${var.workload_name}-${interface} gets ${module.multus_network_attachment[interface].name} on ${interface}, addresses ${module.multus_network_attachment[interface].range_start}-${module.multus_network_attachment[interface].range_end}"])}. All out of ${module.network.multus_pod_range_cidr}, reserved in the VPC"
    }
    node_interface_check_command = {
      order       = 6
      title       = "1. Confirm the node got its extra interfaces"
      description = "The ENIs the node created for itself on boot, found by the tag that tells the VPC CNI to leave them alone. Fewer than expected means the node's bootstrap failed part way - its log is in /var/log/cloud-init-output.log on the instance"
      value       = "aws ec2 describe-network-interfaces --filters Name=tag:node.k8s.amazonaws.com/no_manage,Values=true --query 'NetworkInterfaces[].[NetworkInterfaceId,Attachment.DeviceIndex,PrivateIpAddress,MacAddress,Status]' --output table"
    }
    multus_daemon_check_command = {
      order       = 7
      title       = "2. Confirm Multus is running on that node"
      description = "DESIRED greater than READY means some node's init container has not finished copying the shim, and pods scheduled there will never get an extra interface"
      value       = module.multus_cni.daemon_set_check_command
    }
    cni_config_check_command = {
      order       = 8
      title       = "3. Confirm Multus generated its configuration"
      description = "Multus writes a 00-multus.conf into the node's CNI directory that delegates to 10-aws.conflist. If it is missing, the daemon is up but the node is still on the VPC CNI alone - and pods come up normally, with one interface"
      value       = module.multus_cni.cni_config_check_command
    }
    rollout_status_command = {
      order       = 9
      title       = "4. Wait for the demo pods"
      description = "A timeout here is the useful failure: unlike the EKS multi-NIC feature, a pod whose attachment cannot be satisfied stays in ContainerCreating rather than starting with one interface"
      value       = module.multus_workload.rollout_status_command
    }
    interface_list_command = {
      order       = 10
      title       = "5. Look inside a pod"
      description = "Three entries - loopback, eth0 from the VPC CNI, net1 from Multus - is the working state. Multus always names the interfaces it adds net1, net2 and so on, whatever the host interface behind them is called"
      value       = module.multus_workload.interface_list_command
    }
    network_status_command = {
      order       = 11
      title       = "6. Read what Multus recorded on the pods"
      description = "Multus writes back an annotation listing every interface it attached, with its address and the attachment that produced it. This is the authoritative answer and it is not in any manifest"
      value       = module.multus_workload.network_status_command
    }
    dedicated_eni_check_command = {
      order       = 12
      title       = "7. Confirm each pod got an ENI of its own"
      description = "The payoff, and the one check that tells this arrangement apart from the other one. One line per MAC, each with a count of 1, means every pod sits on a different secondary ENI. A count above one means two pods share an ENI, and a MAC matching the node's primary interface means Multus attached nothing - compare them against the table from step 1"
      value       = module.multus_workload.dedicated_eni_check_command
    }
    multus_security_group_eni_check_command = {
      order       = 13
      title       = "8. Confirm the ENIs carry the dedicated security group"
      description = "Every interface attached with the Multus group, which should be exactly the secondary ones - one row per interface per node. If the node's primary interface or one the VPC CNI created shows up here, the bootstrap passed the wrong group and a rule written for the secondary network also applies to the primary one"
      value       = module.multus_security_group.eni_check_command
    }
    whereabouts_allocations_command = {
      order       = 14
      title       = "9. Read the address allocations, cluster-wide"
      description = "One IPPool per range, holding the addresses handed out of it. This object is the difference from host-local, which kept the same information in a directory on each node - so two nodes both started at the bottom of the range and handed out the same address. The pool is named after the range, not after the attachment"
      value       = module.whereabouts_ipam.allocations_command
    }
    secondary_address_check_command = {
      order       = 15
      title       = "10. Confirm the VPC knows the pod addresses"
      description = "The check that tells a working secondary network from one that only works within a node. Each Multus ENI should list its own primary address plus the address of the pod riding it, registered by that pod's sidecar. Without the second one the VPC has no route to the pod and traffic between nodes is dropped with every security group and route table correct. An address here with no pod holding it is a leftover - the sidecar releases its own on shutdown, but not one whose node disappeared underneath it"
      value       = "aws ec2 describe-network-interfaces --filters Name=tag:node.k8s.amazonaws.com/no_manage,Values=true --query 'NetworkInterfaces[].{ENI:NetworkInterfaceId,Node:Attachment.InstanceId,Addresses:PrivateIpAddresses[].PrivateIpAddress}' --output json"
    }
    connectivity_check_command = {
      order       = 16
      title       = "11. Send traffic over the secondary network"
      description = "The only step that puts a packet on it. Steps 1-10 all read something - an ENI, a configuration file, an annotation, an allocation - and every one of them was green while net2 reached nothing, back when both attachments handed out the whole subnet and the kernel routed one range down the other interface. Pings between two pods of one Deployment, which is the only pair that can talk: each attachment has its own block, that block is the pod's only route out of the secondary interface, and another attachment's address therefore leaves through eth0 and is dropped by the group from step 8. Scales the Deployment to two pods to have a peer at all and scales it back afterwards, so run step 10 before and after to watch the second address appear and be released. Both pods on one node means ipvlan answered locally in microseconds and the VPC was never involved; on different nodes the round trip is milliseconds and the registration from step 10 is what carried it"
      value       = module.multus_workload.connectivity_check_command
    }
    pod_events_command = {
      order       = 17
      title       = "12. If a pod will not start"
      description = "Where a failed attachment is actually reported. The Deployment, the attachment and the DaemonSet all look healthy in that case. The sidecar's failures are here too: it starts before the application container and holds it until its startup probe passes, so a pod stuck in Init means the address could not be registered with the VPC"
      value       = module.multus_workload.pod_events_command
    }
    update_kubeconfig_command = {
      order       = 18
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() - which returns a map's values ordered by key - makes the README read top to
  # bottom while the order stays decided by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not available, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after
    # the bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into,
    # so it is defined once (rules.md B-5).
    #
    # SSM runs as root, hence the chown.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}
