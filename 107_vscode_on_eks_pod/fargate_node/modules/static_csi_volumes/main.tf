# Statically provisioned volumes: a PersistentVolume that names an AWS resource that already exists,
# plus the claim that binds to it.
#
# Both EFS and Mountpoint for S3 are here because static provisioning is one pattern with two sets of
# arguments - a PV carrying a csi block and a PVC pinned to it by volumeName - and neither driver
# supports dynamic provisioning in the shape this project needs. EBS is different: it provisions
# dynamically through a StorageClass, so it appears as a volumeClaimTemplate on the StatefulSet
# instead and nothing about it belongs here.
#
# The _monolithic template created the EFS file system, its mount targets, the S3 bucket and all three
# CSI driver addons, and then mounted none of them. Its pod manifest was byte-identical to the
# variant without any storage at all, so the entire difference between the two variants was
# infrastructure nothing referenced.
locals {
  # Required by the API and ignored by both drivers: EFS is elastic and a bucket has no size. Stated
  # once here rather than asked of the caller, who would only be inventing a number.
  nominal_capacity = "1200Gi"
}

resource "kubectl_manifest" "efs_persistent_volume" {
  for_each = var.efs_volumes

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata = {
      name = each.key
    }
    spec = {
      capacity   = { storage = local.nominal_capacity }
      volumeMode = "Filesystem"
      # ReadWriteMany, which is the reason to use EFS at all: every replica and every node can mount
      # the same volume at once.
      accessModes = ["ReadWriteMany"]
      # Retain, so deleting the claim does not delete the data. The file system itself is a Terraform
      # resource, so its lifecycle belongs to the caller rather than to a claim in the cluster.
      persistentVolumeReclaimPolicy = "Retain"
      # Empty, not unset. A statically provisioned volume has to opt out of every StorageClass,
      # including the cluster's default one - leaving this out lets the default class claim the PVC
      # and provision an unrelated EBS volume instead, which binds successfully and silently gives
      # the pod the wrong disk.
      storageClassName = ""
      csi = {
        driver = "efs.csi.aws.com"
        # The file system id, optionally with an access point after a double colon. An access point
        # is what gives the volume a fixed owner uid, which matters because the image runs as 1000.
        volumeHandle = each.value.access_point_id == null ? each.value.file_system_id : "${each.value.file_system_id}::${each.value.access_point_id}"
      }
    }
  })

  # The driver has to be installed before a PV naming it can be bound, and the mount targets have to
  # exist before a pod can reach the file system (rules.md D-4).
  depends_on = [var.driver_dependency]
}

resource "kubectl_manifest" "efs_persistent_volume_claim" {
  for_each = var.efs_volumes

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = each.key
      namespace = var.namespace
    }
    spec = {
      accessModes = ["ReadWriteMany"]
      # Both of these are what makes the binding static: the empty class opts out of provisioning,
      # and volumeName names the one PV this claim is allowed to bind to.
      storageClassName = ""
      volumeName       = each.key
      resources        = { requests = { storage = local.nominal_capacity } }
    }
  })

  depends_on = [kubectl_manifest.efs_persistent_volume]
}

resource "kubectl_manifest" "s3_persistent_volume" {
  for_each = var.s3_volumes

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata = {
      name = each.key
    }
    spec = {
      capacity                      = { storage = local.nominal_capacity }
      accessModes                   = ["ReadWriteMany"]
      persistentVolumeReclaimPolicy = "Retain"
      storageClassName              = ""
      # Mountpoint options, and the uid/gid/allow-other trio is the part that is easy to miss. The
      # driver mounts the bucket as root by default and FUSE refuses access to other users, so
      # without these the code-server container - uid 1000 - sees the mount point and gets permission
      # denied on everything inside it.
      mountOptions = concat(
        [
          "region ${each.value.region}",
          "uid=${var.mount_uid}",
          "gid=${var.mount_gid}",
          "allow-other",
        ],
        each.value.allow_delete ? ["allow-delete"] : [],
        each.value.extra_mount_options,
      )
      csi = {
        driver = "s3.csi.aws.com"
        # Not a real handle: the driver ignores it and takes the bucket from volumeAttributes. It only
        # has to be unique among the PVs this driver serves.
        volumeHandle = "s3-csi-${each.key}"
        volumeAttributes = {
          bucketName = each.value.bucket_name
        }
      }
    }
  })

  depends_on = [var.driver_dependency]
}

resource "kubectl_manifest" "s3_persistent_volume_claim" {
  for_each = var.s3_volumes

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = each.key
      namespace = var.namespace
    }
    spec = {
      accessModes      = ["ReadWriteMany"]
      storageClassName = ""
      volumeName       = each.key
      resources        = { requests = { storage = local.nominal_capacity } }
    }
  })

  depends_on = [kubectl_manifest.s3_persistent_volume]
}
