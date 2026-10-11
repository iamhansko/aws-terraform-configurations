locals {
  tolerations = [{
    key      = var.gpu_toleration_key
    operator = "Equal"
    value    = "true"
    effect   = "NoSchedule"
  }]
  gpu_resources = {
    requests = { "nvidia.com/gpu" = var.gpu_request }
    limits   = { "nvidia.com/gpu" = var.gpu_request }
  }
}
# The one-line proof that a GPU reached a container.
#
# A bare Amazon Linux image with no NVIDIA tooling in it, running nvidia-smi. It works because the
# container runtime injects the host's driver and devices into any container that requested
# nvidia.com/gpu - so if this prints a GPU table, the node, the device plugin and the runtime are all
# doing their part. A Pending pod here is the device plugin; a pod that starts and cannot find
# nvidia-smi is the runtime.
#
# A bare Pod rather than a Deployment, as the _monolithic template had it: it is a diagnostic that
# should run once and stay, not a workload to keep alive. restartPolicy OnFailure keeps a crash visible
# instead of quietly restarting it forever.
#
# The _monolithic template echoed this into a file on the bastion and applied it with kubectl, after an
# "exec bash" line that discards everything following it - so on a real boot neither pod here ever
# reached the cluster (rules.md E-1/E-2).
resource "kubectl_manifest" "nvidia_smi_pod" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = var.smi_pod_name
      namespace = var.namespace
      labels    = { app = var.smi_pod_name }
    }
    spec = {
      restartPolicy = "OnFailure"
      tolerations   = local.tolerations
      containers = [{
        name    = "nvidia-smi"
        image   = var.smi_image
        command = ["/bin/sh", "-c"]
        # Stays alive after printing, so the output can be read with kubectl logs at any time rather
        # than only while the pod is still terminating.
        args      = ["nvidia-smi && tail -f /dev/null"]
        resources = local.gpu_resources
      }]
    }
  })
}
# The application. It asks for a GPU the same way the diagnostic pod does, which is the point: nothing
# about it knows whether the GPU it got is a whole card or a time slice of one.
#
# A Deployment rather than the _monolithic template's bare Pod. A Pod cannot be scaled, and scaling is
# how the time-slicing cluster is told from the other one: with slicing off, a second replica stays
# Pending because there is one nvidia.com/gpu per card; with it on, several replicas start on the same
# card. Expressing that needs a replica count.
resource "kubectl_manifest" "app" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.app_pod_name
      namespace = var.namespace
      labels    = { app = var.app_pod_name }
    }
    spec = {
      replicas = var.app_replicas
      selector = {
        matchLabels = { app = var.app_pod_name }
      }
      template = {
        metadata = {
          labels = { app = var.app_pod_name }
        }
        spec = {
          tolerations = local.tolerations
          containers = [{
            name  = var.app_pod_name
            image = var.app_image
            args  = var.app_args
            ports = [{
              name          = "http"
              containerPort = var.app_port
            }]
            resources = local.gpu_resources
            volumeMounts = [{
              name      = "model-cache"
              mountPath = var.app_data_path
            }]
          }]
          volumes = [{
            name = "model-cache"
            # On the node rather than on a PersistentVolume, as the original had it. The consequence is
            # worth being explicit about: the cache belongs to whichever node the pod landed on, so a
            # rescheduled pod downloads the models again, and two replicas on two nodes each keep their
            # own copy.
            hostPath = {
              path = var.app_host_path
              type = "DirectoryOrCreate"
            }
          }]
        }
      }
    }
  })
}
