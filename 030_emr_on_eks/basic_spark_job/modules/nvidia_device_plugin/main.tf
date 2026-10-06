# The NVIDIA device plugin, which is what makes a GPU schedulable at all: without it a g4dn node
# advertises no nvidia.com/gpu resource and every pod requesting one stays Pending, on a cluster whose
# nodes each have a working GPU.
#
# Optionally with time slicing, which is the whole comparison this project is built around. The plugin
# reads a configuration out of a config map and can be told to advertise one physical GPU as several -
# so two pods each asking for a GPU both get scheduled onto one card and take turns on it.
#
# The _monolithic template installed this with helm from a shell on the bastion, twice, once per
# cluster - and on the time-slicing cluster it applied the config map the plugin was told to read
# *after* installing the chart. The plugin therefore started with a config map that did not exist:
# depending on the version it either crash-loops until one appears or comes up with no sharing at all,
# which is the failure that makes a time-slicing demo look identical to the cluster it is being compared
# against. Here the config map is created first and the release depends on it (rules.md E-1/D-1).
locals {
  time_slicing_enabled = var.time_slicing_replicas != null
  # The plugin's own configuration format. Its shape belongs to the plugin version, which is why the
  # chart version is pinned rather than floating.
  time_slicing_config = {
    version = "v1"
    flags = {
      migStrategy = "none"
    }
    sharing = {
      timeSlicing = {
        resources = [{
          name     = "nvidia.com/gpu"
          replicas = var.time_slicing_replicas
        }]
      }
    }
  }
}
resource "kubectl_manifest" "time_slicing_config" {
  count = local.time_slicing_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = var.config_map_name
      namespace = var.namespace
    }
    data = {
      # The chart mounts this key by name. yamlencode rather than a heredoc, so the replica count is a
      # number the plugin will accept rather than whatever indentation survived being echoed through a
      # shell.
      "time-slicing.conf" = yamlencode(local.time_slicing_config)
    }
  })
}
resource "helm_release" "nvidia_device_plugin" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "nvidia-device-plugin"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false
  # Holds the apply until the DaemonSet is ready. That matters for what comes next: a pod requesting
  # nvidia.com/gpu before the plugin has advertised any stays Pending, and a Pending pod on a cluster
  # with idle GPU nodes reads like a scheduling problem rather than a timing one.
  wait    = true
  timeout = var.timeout_seconds

  set = concat(
    [
      {
        name  = "gfd.enabled"
        value = tostring(var.enable_gpu_feature_discovery)
      },
    ],
    # Only when there is a config map to point at. Naming one that does not exist is what the original
    # did, and the plugin does not treat it as an error (rules.md B-4).
    local.time_slicing_enabled ? [{
      name  = "config.name"
      value = var.config_map_name
    }] : [],
    var.additional_set_values,
  )

  # config.name is a literal string rather than a reference, so nothing else tells Terraform the config
  # map has to exist first (rules.md D-1). This is the ordering the _monolithic template had backwards.
  depends_on = [kubectl_manifest.time_slicing_config]
}
