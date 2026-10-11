# The NVIDIA GPU Operator, which is what makes a GPU node's GPU schedulable: it runs the device plugin that
# advertises nvidia.com/gpu, GPU Feature Discovery that labels the node with the GPU model, and the MIG
# manager. Without it a g6 node joins, reports Ready, and advertises no GPU - so the ComfyUI pod, which asks
# for one, stays Pending on a cluster that physically has the hardware.
#
# Replaces the blueprint's GpuOperatorAddon, installed through CDK (rules.md E-1). The values are the ones
# the blueprint passed, minus two that this chart version no longer reads:
#
#   operator.defaultRuntime: containerd - not a value in v26.3.2's values.yaml; the operator detects the
#                                          runtime itself.
#   migManager.WITH_REBOOT: true        - never a top-level value. The chart takes MIG manager settings as
#                                          migManager.env entries, so this key was silently ignored and the
#                                          manager ran with its default. Carrying it over would reproduce a
#                                          setting that did nothing, so it is dropped rather than translated
#                                          into one that would change behaviour.
#
# helm does not reject unknown values, so both rendered without complaint - which is why they are worth
# naming here (rules.md E-7).
resource "helm_release" "gpu_operator" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "gpu-operator"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Holds the apply until the operator Deployment is ready, so a GPU node that joins afterwards has an
  # operator waiting to deploy the device plugin onto it.
  wait    = true
  timeout = var.timeout_seconds

  set = concat(
    [
      # Booleans rendered as bare booleans, never type = "string". The chart prints these into its
      # ClusterPolicy, and also branches on driver.enabled with {{ if .Values.driver.enabled }} to decide
      # whether to render an NVIDIADriver object - where the string "false" is truthy (rules.md E-7).
      {
        name  = "driver.enabled"
        value = tostring(var.driver_enabled)
      },
      {
        name  = "toolkit.enabled"
        value = tostring(var.toolkit_enabled)
      },
      {
        name  = "devicePlugin.enabled"
        value = "true"
      },
      {
        name  = "migManager.enabled"
        value = tostring(var.mig_manager_enabled)
      },
      {
        name  = "mig.strategy"
        value = var.mig_strategy
      },
    ],
    # Only when pinned. Null keeps the chart's own image versions (rules.md B-4).
    var.device_plugin_version == null ? [] : [{
      name  = "devicePlugin.version"
      value = var.device_plugin_version
      # A version string such as v0.17.0 is already a string to helm, but an all-numeric override would
      # not be.
      type = "string"
    }],
    var.gfd_version == null ? [] : [{
      name  = "gfd.version"
      value = var.gfd_version
      type  = "string"
    }],
    var.additional_set_values,
  )
}
