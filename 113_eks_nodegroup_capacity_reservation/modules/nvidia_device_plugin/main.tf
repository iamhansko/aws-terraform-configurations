# The NVIDIA device plugin, which is what makes the GPU on a node schedulable.
#
# The EKS-optimized AL2023 NVIDIA AMI this project launches carries the driver, the CUDA user mode
# driver and the container toolkit, so nvidia-smi works on the host. It does not carry this plugin:
# "The EKS-optimized AL2023 NVIDIA AMIs do not include the NVIDIA Kubernetes device plugin or the
# NVIDIA DRA driver, and these must be installed separately"
# (https://docs.aws.amazon.com/eks/latest/userguide/ml-eks-optimized-ami.html). The Bottlerocket
# NVIDIA variant does include it, which is where the belief that the AMI handles this comes from.
#
# Until it is installed the node reports no nvidia.com/gpu in status.allocatable, so a pod with a
# resources.limits entry for one stays Pending forever - on a node whose GPU is idle and working.
# Nothing reports that as an error: the node is Ready, the AMI is correct, and the scheduler is
# right to refuse, because as far as the cluster is concerned the resource does not exist.
#
# A Helm release rather than the plugin's static DaemonSet manifest applied from a GitHub raw URL,
# so the version is pinned, recorded in state and upgradeable (rules.md E-1). No kubectl provider is
# needed for it, which is why this root still declares none.
#
# The caller has one obligation, and installing this release does not discharge it. The chart gives
# the DaemonSet a required node affinity with three alternative terms, and a node matching none of
# them gets no pod:
#
#   feature.node.kubernetes.io/pci-10de.present = true    set by node-feature-discovery
#   feature.node.kubernetes.io/cpu-model.vendor_id = NVIDIA   set by node-feature-discovery
#   nvidia.com/gpu.present = true                         the chart's own documented override
#
# The EKS AMI sets none of these, so either the caller labels its GPU nodes with the third one or it
# sets enable_gpu_feature_discovery, which installs node-feature-discovery and gets the first. With
# neither, the DaemonSet is created with DESIRED = 0 and no GPU is ever advertised - and because a
# DaemonSet wanting zero pods counts as ready, wait = true below reports success. That is the one
# failure mode of this module that looks exactly like a working install.
resource "helm_release" "nvidia_device_plugin" {
  name       = var.release_name
  repository = var.chart_repository
  chart      = "nvidia-device-plugin"
  version    = var.chart_version
  namespace  = var.namespace
  # kube-system already exists, and creating a namespace the cluster owns would make destroy try to
  # remove it.
  create_namespace = false
  # Holds the apply until the DaemonSet reports ready, so the GPU count in the caller's outputs is
  # meaningful when apply finishes rather than some minutes later. See the DESIRED = 0 caveat above
  # for what this does not catch.
  wait    = true
  timeout = var.timeout_seconds

  set = concat(
    [
      # GPU Feature Discovery, off by default. It labels nodes with the GPU model, driver version
      # and memory, and it pulls in node-feature-discovery as a subchart to do it - which is the
      # other way to satisfy the node affinity described above.
      #
      # Rendered as a bare boolean. The chart guards nothing with kindIs here, but helm --set
      # already infers a boolean from "false" and the chart's own default is a boolean, so this
      # entry must not carry type = "string" (rules.md E-7).
      {
        name  = "gfd.enabled"
        value = tostring(var.enable_gpu_feature_discovery)
      },
    ],
    var.additional_set_values,
  )
}
