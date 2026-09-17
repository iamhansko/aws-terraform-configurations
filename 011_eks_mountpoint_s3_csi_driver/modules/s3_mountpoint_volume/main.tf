# Replaces the _monolithic design, which echoed manifests/pod.yaml onto the
# bastion's disk and left it to the operator to run "kubectl apply". Declaring
# them as resources wires the bucket name and region in automatically, makes
# terraform plan show drift, and lets terraform destroy clean them up
# (rules.md E-1).
#
# Uses alekc/kubectl's kubectl_manifest rather than hashicorp/kubernetes: this
# module is applied in the same terraform apply as the EKS cluster whose outputs
# configure the provider, and hashicorp/kubernetes needs a reachable API server
# at plan time (rules.md E-2).
locals {
  # allow-delete has to agree with the driver's IAM policy, so both are driven
  # by the same variable rather than set in two places (rules.md B-5). region is
  # mandatory: the driver does not infer the bucket's region.
  mount_options = concat(
    var.allow_delete ? ["allow-delete"] : [],
    ["region ${var.region}"],
    var.prefix == null ? [] : ["prefix ${var.prefix}"],
    var.extra_mount_options,
  )
}
# Mountpoint has no dynamic provisioning: there is nothing for a StorageClass to
# create, because the bucket already exists. So unlike the EBS and EFS projects
# this is a statically provisioned PersistentVolume, and storageClassName is set
# to the empty string on both the volume and the claim to stop the default
# StorageClass from trying to provision something else for the claim.
resource "kubectl_manifest" "s3_persistent_volume" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata = {
      name = var.persistent_volume_name
    }
    spec = {
      capacity = {
        storage = var.volume_capacity
      }
      accessModes      = ["ReadWriteMany"]
      storageClassName = ""
      # Pre-binds the volume to one specific claim, so no other claim in the
      # cluster can be bound to this bucket by accident.
      claimRef = {
        namespace = var.namespace
        name      = var.claim_name
      }
      mountOptions = local.mount_options
      csi = {
        driver       = var.driver
        volumeHandle = var.volume_handle
        volumeAttributes = {
          bucketName = var.bucket_name
        }
      }
    }
  })
}
resource "kubectl_manifest" "s3_persistent_volume_claim" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = var.claim_name
      namespace = var.namespace
    }
    spec = {
      accessModes      = ["ReadWriteMany"]
      storageClassName = ""
      resources = {
        requests = {
          storage = var.volume_capacity
        }
      }
      # Names the volume explicitly, the other half of the claimRef above.
      volumeName = var.persistent_volume_name
    }
  })
  # volumeName is a plain string, not an attribute reference, so nothing else
  # tells Terraform the PersistentVolume must exist first (rules.md E-2).
  depends_on = [kubectl_manifest.s3_persistent_volume]
}
resource "kubectl_manifest" "demo_pod" {
  count = var.create_demo_pod ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = var.demo_pod_name
      namespace = var.namespace
    }
    spec = {
      containers = [{
        name    = "app"
        image   = var.demo_image
        command = ["/bin/sh"]
        # Writes one timestamped object and then stays up, so the file can be
        # found both in the bucket and through the mount.
        args = ["-c", "echo \"Hello from $(hostname)\" >> ${var.demo_mount_path}/$(date -u +%Y-%m-%dT%H-%M-%SZ).txt; tail -f /dev/null"]
        volumeMounts = [{
          name      = "persistent-storage"
          mountPath = var.demo_mount_path
        }]
      }]
      volumes = [{
        name = "persistent-storage"
        persistentVolumeClaim = {
          claimName = var.claim_name
        }
      }]
    }
  })
  depends_on = [kubectl_manifest.s3_persistent_volume_claim]
}
