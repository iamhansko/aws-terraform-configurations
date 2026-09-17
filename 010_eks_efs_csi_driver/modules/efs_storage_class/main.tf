# Replaces the _monolithic design, which echoed manifests/storageclass.yaml and
# manifests/deployment.yaml onto the bastion's disk - with FILE_SYSTEM_ID left
# for the operator to paste in - and left it to them to run "kubectl apply".
# Declaring them as resources means the file system ID is wired in
# automatically, terraform plan shows drift, and terraform destroy cleans them
# up (rules.md E-1).
#
# Uses alekc/kubectl's kubectl_manifest rather than hashicorp/kubernetes: this
# module is applied in the same terraform apply as the EKS cluster whose outputs
# configure the provider, and hashicorp/kubernetes needs a reachable API server
# at plan time (rules.md E-2).
resource "kubectl_manifest" "efs_storage_class" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name        = var.storage_class_name
      annotations = var.set_as_default_storage_class ? { "storageclass.kubernetes.io/is-default-class" = "true" } : {}
    }
    provisioner   = var.provisioner
    reclaimPolicy = var.reclaim_policy
    parameters = merge({
      provisioningMode = var.provisioning_mode
      fileSystemId     = var.file_system_id
      directoryPerms   = var.directory_perms
      },
      var.base_path == null ? {} : { basePath = var.base_path },
    )
    # Deliberately no volumeBindingMode or allowedTopologies, unlike the EBS
    # StorageClass in project 009. An EFS file system is reachable from every
    # availability zone that has a mount target, so there is no zone for the
    # scheduler to get wrong and nothing to gain from delaying provisioning
    # until a pod is placed.
  })
}
resource "kubectl_manifest" "demo_persistent_volume_claim" {
  count = var.create_demo_workload ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = var.demo_claim_name
      namespace = var.namespace
    }
    spec = {
      # ReadWriteMany is what separates this from the EBS driver: one volume,
      # mounted by every replica at once, across nodes and zones.
      accessModes = ["ReadWriteMany"]
      # References the StorageClass by the same variable the resource above is
      # named from, so the two can never drift apart.
      storageClassName = var.storage_class_name
      resources = {
        requests = {
          storage = var.demo_volume_size
        }
      }
    }
  })
  # storageClassName is a plain string, not an attribute reference, so nothing
  # else tells Terraform the StorageClass must exist first (rules.md E-2).
  depends_on = [kubectl_manifest.efs_storage_class]
}
resource "kubectl_manifest" "demo_deployment" {
  count = var.create_demo_workload ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.demo_deployment_name
      namespace = var.namespace
    }
    spec = {
      replicas = var.demo_replica_count
      selector = {
        matchLabels = { app = var.demo_deployment_name }
      }
      template = {
        metadata = {
          labels = { app = var.demo_deployment_name }
        }
        spec = {
          containers = [{
            name    = "app"
            image   = var.demo_image
            command = ["/bin/sh"]
            # Every replica appends to the same file, so "kubectl exec ... cat
            # /data/out" shows interleaved writes from all of them - the visible
            # proof that the volume really is shared.
            args = ["-c", "while true; do echo $(date -u) $(hostname) >> /data/out; sleep 5; done"]
            volumeMounts = [{
              name      = "persistent-storage"
              mountPath = "/data"
            }]
          }]
          volumes = [{
            name = "persistent-storage"
            persistentVolumeClaim = {
              claimName = var.demo_claim_name
            }
          }]
        }
      }
    }
  })
  depends_on = [kubectl_manifest.demo_persistent_volume_claim]
}
