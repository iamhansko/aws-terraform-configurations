# The pods that get a second interface from Multus - one Deployment per attachment, one pod each -
# and the IAM role that lets each of them register its own secondary address with the VPC.
#
# One annotation does the attaching: k8s.v1.cni.cncf.io/networks names a NetworkAttachmentDefinition,
# and Multus adds an interface for it on top of the primary one the VPC CNI gives every pod. Unlike
# the EKS multi-NIC feature next door, a pod asking for an attachment it cannot get does not come up
# with one interface - it stays in ContainerCreating. That is the better failure of the two, and it
# is still not reported anywhere except the pod's events.
#
# Why a Deployment per attachment rather than one Deployment naming them all. The goal here is one
# dedicated secondary ENI per pod, and a Deployment has exactly one pod template - so every replica
# of it necessarily carries the same annotation and therefore the same set of attachments. Listing
# both attachments on a single Deployment gives every pod both ENIs, which is the opposite
# arrangement: the ENIs are shared rather than dedicated. Splitting the Deployments is the only way
# to vary the annotation per pod.
#
# Why the IAM role is here rather than in a module of its own: the role exists only for the sidecar
# below, and the two have to name the same service account. Splitting them would mean the role's
# trust policy and the pod's service account were written in two places and had to agree
# (rules.md C-2).
#
# The _monolithic template echoed its manifest into a file on the bastion and applied it with
# kubectl, after an "exec bash" line that discards every following line - so on a real boot neither
# this nor the attachment it names ever reached the cluster (rules.md E-1/E-2).
locals {
  # Carried by every pod this module creates, on top of the per-Deployment app label. It exists so
  # that a diagnostic command can select all of them at once: the app label has to differ per
  # Deployment, because a Deployment whose selector also matched another one's pods would fight it
  # for ownership of them.
  group_label          = "multus.terraform.io/workload"
  service_account_name = var.name
  # Where the sidecar records what it registered, so the preStop hook can undo exactly that rather
  # than working it out again from an interface that may be on its way out.
  state_file = "/tmp/registered-address"
  # Named once because the connectivity check below has to exec into this container by name: ping
  # and ip live in this image, and not in the sidecar's, which carries the AWS CLI and nothing to
  # send a packet with (rules.md B-5).
  app_container_name = "network-multitool"
  # Why a pod has to do any of this.
  #
  # The VPC routes to an address only if that address is assigned to an ENI. The VPC CNI arranges
  # that for the primary interface - it assigns each pod's address as a secondary address on the
  # node's ENI. Nothing does it for a Multus interface: whereabouts picks the address out of its own
  # store, and the VPC never hears about it. The result is a network that works between pods on one
  # node, where the traffic never reaches the VPC, and silently fails between nodes - with security
  # groups and route tables all correct. AWS documents this behaviour and this remedy.
  #
  # The values are read from inside the pod's own network namespace, where the address and the MAC of
  # the interface carrying it are both unambiguous:
  #
  #   - the MAC comes from sysfs, which needs no tools at all;
  #   - the address comes from an ioctl, because the chosen image has python3 but no iproute2;
  #   - the ENI is found by that MAC rather than by asking the instance, so this does not depend on
  #     IMDS being reachable from a pod - which it often is not.
  #
  # ipvlan is what makes the MAC lookup work: an ipvlan interface shares its master's MAC, so the MAC
  # inside the pod is the MAC of the node ENI the traffic will leave by.
  read_address_command = "python3 -c 'import fcntl, socket, struct; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); print(socket.inet_ntoa(fcntl.ioctl(s.fileno(), 0x8915, struct.pack(\"256s\", b\"${var.secondary_interface_name}\"))[20:24]))'"
  # The sidecar's own command: register once, then keep watching.
  #
  # A sidecar rather than an initContainer, which is the other shape AWS documents. An initContainer
  # exits as soon as it has registered, and a container that has exited cannot run a preStop hook -
  # so the address stayed assigned to the ENI after the pod was gone. Those leftovers are bounded by
  # the ENI's secondary address limit rather than harmless, and they are invisible: whereabouts
  # correctly frees the address in its own store, so the two records disagree with nothing reporting
  # it. Staying alive also handles an address that changes while the pod runs, which is what a
  # workload moving a floating address between an active and a standby pod does.
  register_script = join("\n", [
    "set -euo pipefail",
    "IFACE=${var.secondary_interface_name}",
    "STATE=${local.state_file}",
    "",
    "register() {",
    "  MAC=$(cat /sys/class/net/$IFACE/address)",
    "  IP=$(${local.read_address_command})",
    "  ENI=$(aws ec2 describe-network-interfaces --filters Name=mac-address,Values=$MAC --query 'NetworkInterfaces[0].NetworkInterfaceId' --output text)",
    # describe returns the string None rather than failing when the filter matches nothing, so this
    # would otherwise go on to call assign with a network interface id of "None".
    "  if [ -z \"$ENI\" ] || [ \"$ENI\" = None ]; then echo \"no ENI carries MAC $MAC - is $IFACE really an ipvlan slave of a node ENI?\" >&2; return 1; fi",
    "  echo \"registering $IP on $ENI so the VPC routes it\"",
    # --allow-reassignment so that an address whose previous holder is gone, but which is still
    # recorded against some ENI, moves here instead of failing. Without it a pod that lands on a
    # different node after a restart cannot take its own address back.
    "  aws ec2 assign-private-ip-addresses --network-interface-id $ENI --private-ip-addresses $IP --allow-reassignment",
    # Written only after the call succeeded, which is what the startup probe waits for.
    "  printf '%s %s\\n' \"$ENI\" \"$IP\" > $STATE",
    "}",
    "",
    "register",
    "",
    # The watch. Cheap - one ioctl per interval, and an API call only when the address actually
    # changed. Without it this container would just be an initContainer that never exits.
    "while :; do",
    "  sleep ${var.ip_manager_watch_interval_seconds}",
    "  CURRENT=$(${local.read_address_command} || true)",
    "  RECORDED=$(cut -d' ' -f2 $STATE)",
    "  if [ -n \"$CURRENT\" ] && [ \"$CURRENT\" != \"$RECORDED\" ]; then",
    "    echo \"address on $IFACE changed from $RECORDED to $CURRENT\"",
    "    register",
    "  fi",
    "done",
  ])
  # Runs while the interface and the credentials are both still there, before the container is
  # killed and before the CNI tears the interface down. Reads what was registered rather than
  # recomputing it, because by now the address is the thing being taken away.
  unassign_script = join("\n", [
    "STATE=${local.state_file}",
    # Nothing to undo if registration never got as far as writing the file.
    "[ -f $STATE ] || exit 0",
    "read -r ENI IP < $STATE",
    "echo \"releasing $IP from $ENI\"",
    # Deliberately tolerant: a preStop hook that fails does not stop the pod from terminating, and
    # the address may already be gone - the node could have been removed, or another pod could have
    # taken the address with --allow-reassignment. Either way there is nothing left to release.
    "aws ec2 unassign-private-ip-addresses --network-interface-id $ENI --private-ip-addresses $IP || true",
  ])
  # The one check in this project that puts a packet on the secondary network. Everything else reads
  # configuration, annotations or EC2 state, and all of those can be right while the interface
  # reaches nothing - which is exactly what two attachments sharing one range looked like.
  #
  # Traffic goes between two pods of a single Deployment, not between two Deployments, because the
  # pairs are not interchangeable. Each attachment hands out its own block and the plugin writes that
  # block onto the interface as its prefix, so it is the pod's only route out of the secondary
  # interface. Another attachment's address does not match it, leaves through eth0 instead with the
  # pod's primary address as its source, and is dropped by the dedicated security group, which admits
  # only its own members. The interfaces are working; they are simply on different segments.
  connectivity_deployment = "${var.name}-${sort(keys(var.network_attachments))[0]}"
  connectivity_ping_commands = [
    "A=$(kubectl -n ${var.namespace} get pods -l app=${local.connectivity_deployment} -o jsonpath='{.items[0].metadata.name}')",
    "B=$(kubectl -n ${var.namespace} get pods -l app=${local.connectivity_deployment} -o jsonpath='{.items[1].metadata.name}')",
    "kubectl -n ${var.namespace} get pods -l app=${local.connectivity_deployment} -o wide",
    # Read off the interface rather than out of the annotation, so the address being pinged is the
    # one the pod actually holds and not the one Multus reported holding.
    "BIP=$(kubectl -n ${var.namespace} exec $B -c ${local.app_container_name} -- ip -4 -brief address show ${var.secondary_interface_name} | awk '{print $3}' | cut -d/ -f1)",
    # -I binds the source to the secondary interface. Without it the packet would take the pod's
    # default route out of eth0 and the test would pass while proving nothing about this network.
    "kubectl -n ${var.namespace} exec $A -c ${local.app_container_name} -- ping -c 4 -I ${var.secondary_interface_name} $BIP",
  ]
  # At one pod per attachment - the default, and what makes each ENI dedicated - there is nothing in
  # the pod's own range to talk to, so the check has to make a peer and then put the Deployment back
  # as it found it. The restore runs after a semicolon rather than && so that it still happens when
  # the ping fails, which is the case where leaving a stray pod behind would be least welcome.
  connectivity_check_command = var.replicas_per_attachment >= 2 ? join(" && ", local.connectivity_ping_commands) : join("", [
    join(" && ", concat([
      "kubectl -n ${var.namespace} scale deployment ${local.connectivity_deployment} --replicas=2",
      "kubectl -n ${var.namespace} rollout status deployment ${local.connectivity_deployment} --timeout=10m",
    ], local.connectivity_ping_commands)),
    "; kubectl -n ${var.namespace} scale deployment ${local.connectivity_deployment} --replicas=${var.replicas_per_attachment}",
  ])
}
# The role the sidecar assumes through IRSA. Scoped to the service account below, so only these pods
# can use it.
resource "aws_iam_role" "ip_manager_iam_role" {
  name_prefix = var.iam_role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Pinned to one service account in one namespace. Without the sub condition any pod in
          # the cluster with a projected token could assume this role.
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${local.service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "ip_manager_iam_role" {
  name_prefix = var.iam_role_name_prefix
  role        = aws_iam_role.ip_manager_iam_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Unscoped because it has to be: DescribeNetworkInterfaces takes no resource and no useful
        # condition key, so it is read access to the account's interfaces. It is how the pod finds
        # which ENI carries its MAC.
        Sid      = "AllowFindingTheEniByMac"
        Effect   = "Allow"
        Action   = "ec2:DescribeNetworkInterfaces"
        Resource = "*"
      },
      {
        # The writes, and the one statement worth reading closely. Narrowed to interfaces tagged as
        # the node's Multus ENIs, so a pod holding this role cannot move addresses around on the
        # node's primary interface or on the ones the VPC CNI manages - which is where every other
        # pod's address lives.
        Sid    = "AllowRegisteringOwnAddressOnMultusEnisOnly"
        Effect = "Allow"
        Action = [
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
        ]
        Resource = "arn:${var.partition}:ec2:${var.region}:${var.account_id}:network-interface/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/node.k8s.amazonaws.com/no_manage" = "true"
          }
        }
      },
    ]
  })
}
resource "kubectl_manifest" "service_account" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = local.service_account_name
      namespace = var.namespace
      annotations = {
        # What turns the projected token into AWS credentials. The role is referenced directly
        # rather than passed in, because it is created in this module (rules.md C-2).
        "eks.amazonaws.com/role-arn" = aws_iam_role.ip_manager_iam_role.arn
      }
    }
  })
}
resource "kubectl_manifest" "deployment" {
  # Keyed by the caller's label for each attachment - the host interface it rides, here - so the
  # keys come from variables and are known during plan even though the attachment names they map to
  # are another module's output and are not (rules.md B-8).
  for_each = var.network_attachments

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "${var.name}-${each.key}"
      namespace = var.namespace
      labels = {
        app                 = "${var.name}-${each.key}"
        (local.group_label) = var.name
      }
    }
    spec = {
      replicas = var.replicas_per_attachment
      selector = {
        # The per-Deployment label only. Selecting on the group label would make both Deployments
        # claim each other's pods.
        matchLabels = { app = "${var.name}-${each.key}" }
      }
      template = {
        metadata = {
          labels = {
            app                 = "${var.name}-${each.key}"
            (local.group_label) = var.name
          }
          annotations = merge(
            {
              # The whole mechanism. Multus reads this, finds the named attachment in the pod's
              # namespace, and runs the CNI plugin that attachment describes - adding one interface,
              # numbered net1. One name rather than a list, because this pod is meant to have one
              # secondary ENI and that ENI is meant to be its own.
              "k8s.v1.cni.cncf.io/networks" = each.value
            },
            # Not read by anything. It is here so that the pod template changes when the attachment's
            # configuration does, which is the only way these pods get re-plumbed: Multus reads the
            # attachment when it creates a pod and never again, so an edited attachment otherwise
            # leaves every running pod holding addresses from the old configuration while the object
            # describes the new one. Changing spec.template is what makes Kubernetes roll the
            # Deployment (rules.md B-4).
            #
            # Deliberately not wrapped in lifecycle.ignore_changes - unlike the one-shot rollout
            # trigger in rules.md E-4, this value has to be followed every time it changes.
            var.network_attachment_revision == null ? {} : {
              "multus.terraform.io/attachment-revision" = var.network_attachment_revision
            },
          )
        }
        spec = merge(
          # Omitted entirely when no selector was given, which is the case when every node in the
          # cluster carries the extra interfaces (rules.md B-4).
          length(var.node_selector) > 0 ? { nodeSelector = var.node_selector } : {},
          {
            serviceAccountName = local.service_account_name
            # Long enough for the preStop hook to make its API call before the container is killed.
            # The default of thirty seconds would usually do, but the hook and the application's own
            # shutdown share this budget.
            terminationGracePeriodSeconds = var.termination_grace_period_seconds
            # A native sidecar: an entry in initContainers carrying restartPolicy Always. That is
            # what keeps it running alongside the application instead of exiting, which is what
            # gives it a preStop hook to release the address with.
            initContainers = [{
              name          = "register-secondary-address"
              image         = var.ip_manager_image
              restartPolicy = "Always"
              command       = ["/bin/sh", "-c", local.register_script]
              env           = [{ name = "AWS_REGION", value = var.region }]
              lifecycle = {
                preStop = {
                  exec = { command = ["/bin/sh", "-c", local.unassign_script] }
                }
              }
              # The ordering guarantee a plain initContainer gave for free, and the thing most
              # easily lost in this conversion. Kubernetes starts the application container once a
              # sidecar has *started*, not once it has done anything - so without a probe the
              # application could run before the address was routable. The probe passes only after
              # the state file exists, which the script writes after the assign call returns.
              startupProbe = {
                exec             = { command = ["/bin/sh", "-c", "test -f ${local.state_file}"] }
                periodSeconds    = var.ip_manager_startup_probe_period_seconds
                failureThreshold = var.ip_manager_startup_probe_failure_threshold
              }
              securityContext = { allowPrivilegeEscalation = false }
              resources = {
                requests = {
                  cpu    = var.ip_manager_cpu_request
                  memory = var.ip_manager_memory_request
                }
              }
            }]
            containers = [{
              name  = local.app_container_name
              image = var.image
              # The image's own entrypoint starts nginx and sshd, which this demo does not need. A
              # sleep that forwards signals keeps the container alive and stops it from holding the
              # pod's shutdown open for the full grace period.
              command = ["/bin/bash", "-c", "trap : TERM INT; sleep infinity & wait"]
            }]
          },
        )
      }
    }
  })

  # The service account is named as a literal string in the pod spec, so nothing else orders it -
  # and a pod that starts before it exists gets no credentials and the sidecar fails
  # (rules.md D-1). The policy is in the list for the same reason as rules.md D-1 gives for cluster
  # roles: the role can be assumed before its permissions are attached.
  depends_on = [
    kubectl_manifest.service_account,
    aws_iam_role_policy.ip_manager_iam_role,
  ]
}
