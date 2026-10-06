# The EFS demo, declared as Kubernetes objects instead of a pile of YAML files
# the workbench writes with `echo` and applies with kubectl (rules.md E-1). The
# _monolithic template rendered five manifests into /home/ec2-user/manifests and
# applied four of them from userdata, so nothing here was tracked in state and
# the volume handle reached the cluster through shell string substitution.
#
# Every object is a kubectl_manifest rather than a hashicorp/kubernetes typed
# resource, because the cluster these go into is created by the same
# `terraform apply` (rules.md E-2).
#
# Fargate needs no EFS CSI driver addon: the node agent is built into the
# Fargate stack. What it does not support is dynamic provisioning, so both
# volumes below are statically provisioned against a file system that already
# exists - which is the entire point this project demonstrates.

# Not applied by default, and the _monolithic template did not apply it either:
# it wrote csi_driver.yaml next to the others and left it out of the kubectl
# apply list. Fargate already registers the efs.csi.aws.com CSIDriver object,
# and CSIDriver.spec.attachRequired is immutable, so applying a second copy is
# at best a no-op and at worst a rejected update. Kept as an opt-in so the
# object the README's support table talks about is available as a real resource
# rather than a stray file (rules.md B-4).
resource "kubectl_manifest" "csi_driver" {
  count = var.register_csi_driver ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "CSIDriver"
    metadata = {
      name = var.csi_driver_name
    }
    spec = {
      attachRequired = false
    }
  })
}

# Referenced by name from the write PVC below, never by attribute, so the
# StorageClass has to be ordered ahead of it explicitly (rules.md E-2).
#
# There is no parameters block: the class exists only to pair a PV and a PVC by
# name. A provisioner that cannot dynamically provision has nothing to read from
# it, and asking it to provision is exactly what fails on Fargate.
resource "kubectl_manifest" "storage_class" {
  yaml_body = yamlencode({
    apiVersion  = "storage.k8s.io/v1"
    kind        = "StorageClass"
    metadata    = { name = var.storage_class_name }
    provisioner = var.csi_driver_name
  })
}

# Binding style 1: PV and PVC both name the StorageClass, and the control plane
# matches them on class plus capacity plus access mode.
resource "kubectl_manifest" "write_persistent_volume" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata   = { name = var.write_volume_name }
    spec = {
      capacity                      = { storage = var.storage_capacity }
      volumeMode                    = "Filesystem"
      accessModes                   = ["ReadWriteMany"]
      persistentVolumeReclaimPolicy = var.reclaim_policy
      storageClassName              = var.storage_class_name
      csi = {
        driver = var.csi_driver_name
        # The one value that makes this static provisioning: the file system
        # already exists and is named here. The _monolithic template got it
        # here by interpolating an AWS resource attribute into a shell heredoc;
        # this is the same value arriving as a module input instead.
        volumeHandle = var.file_system_id
      }
    }
  })

  depends_on = [kubectl_manifest.storage_class]
}

resource "kubectl_manifest" "write_persistent_volume_claim" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = var.write_claim_name
      namespace = var.namespace
    }
    spec = {
      accessModes      = ["ReadWriteMany"]
      storageClassName = var.storage_class_name
      resources        = { requests = { storage = var.storage_capacity } }
    }
  })

  # depends_on below orders the API calls; it does not order the phases. A PVC is
  # created Pending and reaches Bound only once the control plane's volume
  # controller has matched it to a PV, while kubectl_manifest returns as soon as
  # the API server accepts the object. Without this wait the pod below is created
  # in the same second as this claim, and the fargate-scheduler rejects a pod
  # whose claim is still Pending - once, with no retry (rules.md D-8).
  #
  # This side happened to win the race on the apply that uncovered the problem.
  # That is luck, not ordering, so the gate belongs on both claims.
  wait_for {
    field {
      key   = "status.phase"
      value = "Bound"
    }
  }

  depends_on = [kubectl_manifest.write_persistent_volume]
}

# Binding style 2: no StorageClass at all. storageClassName is the empty string
# so the default class is not substituted in, and volumeName points straight at
# the PV. This is the form to reach for when a class would only be a label -
# and the _monolithic template showed both side by side for that reason.
resource "kubectl_manifest" "read_persistent_volume" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata   = { name = var.read_volume_name }
    spec = {
      capacity                      = { storage = var.storage_capacity }
      volumeMode                    = "Filesystem"
      accessModes                   = ["ReadWriteMany"]
      persistentVolumeReclaimPolicy = var.reclaim_policy
      csi = {
        driver = var.csi_driver_name
        # Deliberately the same file system as the write volume: two pods
        # reaching one EFS file system through two independent PVs is what makes
        # the shared-storage demo work.
        volumeHandle = var.file_system_id
      }
    }
  })
}

resource "kubectl_manifest" "read_persistent_volume_claim" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = var.read_claim_name
      namespace = var.namespace
    }
    spec = {
      accessModes = ["ReadWriteMany"]
      resources   = { requests = { storage = var.storage_capacity } }
      # Empty string, not null: null lets the default StorageClass be filled in
      # by the admission controller, which would put this claim in a class the
      # read PV is not in and leave it Pending forever.
      storageClassName = ""
      volumeName       = var.read_volume_name
    }
  })

  # Same gate as the write claim, and this is the side that actually failed
  # (rules.md D-8). The volumeName path is systematically slower to bind than the
  # StorageClass path above: the volume controller resolves spec.volumeName
  # through its own PV cache, and when the PV was created moments earlier it is
  # not in that cache yet, so the first sync gives up and the claim waits for the
  # next one. The StorageClass path has no such lookup to miss. That is why the
  # reader is the pod that ends up Pending while the writer runs.
  wait_for {
    field {
      key   = "status.phase"
      value = "Bound"
    }
  }

  depends_on = [kubectl_manifest.read_persistent_volume]
}

# The two pods, as bare Pods rather than Deployments, matching the
# _monolithic template. A bare Pod is the honest shape here: the demo is about
# one writer and one reader on the same file system, and a controller
# rescheduling them would only add noise.
resource "kubectl_manifest" "write_pod" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = var.write_pod_name
      namespace = var.namespace
    }
    spec = {
      containers = [{
        name    = var.write_pod_name
        image   = var.image
        command = ["/bin/sh"]
        args = ["-c", join(" ", [
          "while true; do echo $(date -u) >> ${var.mount_path}/${var.output_file_name};",
          "sleep ${var.write_interval_seconds}; done",
        ])]
        volumeMounts = [{
          name      = var.volume_mount_name
          mountPath = var.mount_path
        }]
      }]
      volumes = [{
        name                  = var.volume_mount_name
        persistentVolumeClaim = { claimName = var.write_claim_name }
      }]
    }
  })

  depends_on = [kubectl_manifest.write_persistent_volume_claim]
}

resource "kubectl_manifest" "read_pod" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = var.read_pod_name
      namespace = var.namespace
    }
    spec = {
      containers = [{
        name    = var.read_pod_name
        image   = var.image
        command = ["/bin/sh"]
        args    = ["-c", "while true; do sleep 3600; done"]
        volumeMounts = [{
          name      = var.volume_mount_name
          mountPath = var.mount_path
        }]
      }]
      volumes = [{
        name                  = var.volume_mount_name
        persistentVolumeClaim = { claimName = var.read_claim_name }
      }]
    }
  })

  depends_on = [kubectl_manifest.read_persistent_volume_claim]
}
