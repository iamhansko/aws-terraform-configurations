# The StorageClass Karmada's etcd claims its volume from.
#
# The guidance installer created the same object by writing JSON to /tmp and running kubectl apply, so it
# existed in the cluster and nowhere else (rules.md E-1). Name, provisioner, binding mode and the encrypted
# parameter are all as that script had them - ebs-sc, ebs.csi.aws.com, WaitForFirstConsumer, gp3, encrypted -
# because the class name is then passed to the chart as etcd.internal.pvc.storageClass and a claim naming a
# class that does not exist simply stays Pending.
#
# Declared through alekc/kubectl rather than hashicorp/kubernetes because the cluster it goes into is created
# in this same apply, and hashicorp/kubernetes is configured during plan, when the cluster endpoint is still
# unknown (rules.md E-2).
resource "kubectl_manifest" "storage_class" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = var.name
      annotations = {
        # A string, not a boolean. Annotation values are always strings, and yamlencode would render a bare
        # true unquoted - which the API server rejects with a message about unmarshalling bool into string
        # (the same class of failure rules.md E-7 describes for Helm values).
        "storageclass.kubernetes.io/is-default-class" = tostring(var.is_default_class)
      }
    }
    provisioner = "ebs.csi.aws.com"
    parameters = {
      type      = var.volume_type
      encrypted = tostring(var.encrypted)
    }
    reclaimPolicy = var.reclaim_policy
    # WaitForFirstConsumer, as the installer's class had it, and it is load-bearing rather than incidental:
    # the volume is created in the zone the pod was scheduled into. With Immediate the volume is created
    # first in an arbitrary zone, and an etcd pod that cannot be scheduled there stays Pending forever with
    # no message saying why - which then looks like the whole control plane failing to start, because every
    # other Karmada component waits on etcd.
    volumeBindingMode    = var.volume_binding_mode
    allowVolumeExpansion = var.allow_volume_expansion
  })
}
