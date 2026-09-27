# Replaces the _monolithic design, which wrote manifests/storageclass.yaml and
# manifests/deploy.yaml onto the bastion's disk and left it to the operator to
# run "kubectl apply" by hand. Declaring them as resources means terraform plan
# shows drift and terraform destroy cleans them up (rules.md E-1).
#
# Uses alekc/kubectl's kubectl_manifest rather than hashicorp/kubernetes: this
# module is applied in the same terraform apply as the EKS cluster whose
# outputs configure the provider, and hashicorp/kubernetes needs a reachable
# API server at plan time (rules.md E-2).
resource "kubectl_manifest" "ebs_storage_class" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name        = var.storage_class_name
      annotations = var.set_as_default_storage_class ? { "storageclass.kubernetes.io/is-default-class" = "true" } : {}
    }
    provisioner = var.provisioner
    # WaitForFirstConsumer delays volume creation until a pod is scheduled, so
    # the volume lands in the same AZ as the pod. Immediate binding would let
    # the scheduler pick an AZ the volume cannot be attached from.
    volumeBindingMode    = var.volume_binding_mode
    reclaimPolicy        = var.reclaim_policy
    allowVolumeExpansion = var.allow_volume_expansion
    parameters = merge({
      "csi.storage.k8s.io/fstype" = var.fs_type
      type                        = var.volume_type
      encrypted                   = tostring(var.encrypted)
      },
      # iopsPerGB only applies to the provisioned-IOPS families; io2/gp3 reject
      # it alongside their own iops parameter.
      contains(["io1", "io2"], var.volume_type) ? { iopsPerGB = tostring(var.iops_per_gb) } : {},
    )
    allowedTopologies = length(var.allowed_topology_zones) > 0 ? [{
      matchLabelExpressions = [{
        key    = "topology.kubernetes.io/zone"
        values = var.allowed_topology_zones
      }]
    }] : null
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
      accessModes = ["ReadWriteOnce"]
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
  depends_on = [kubectl_manifest.ebs_storage_class]
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
            name    = var.demo_deployment_name
            image   = var.demo_image
            command = ["/bin/sh"]
            args    = ["-c", "while true; do echo $(date -u) >> /data/out.txt; sleep 5; done"]
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
