# The default gp3 StorageClass, which the blueprint declared in addons.tf as
# kubernetes_storage_class.ebs_csi_encrypted_gp3_storage_class.
#
# Its own module rather than part of eks_ebs_csi_driver_addon, because installing the addon is
# necessary but not sufficient: the addon registers the ebs.csi.aws.com driver and runs its controller,
# and creates no StorageClass. The only class on a fresh EKS cluster is the built-in gp2, whose in-tree
# provisioner Kubernetes removed in 1.23.
#
# The default annotation is load-bearing. The Kafka node pools' persistent-claim volumes name no
# class, so they resolve through it - and without it they are created with no class, bind to nothing,
# and every broker and controller pod stays Pending while the Kafka resource reports nothing more
# specific than not being ready.
#
# Declared through alekc/kubectl rather than hashicorp/kubernetes, because the cluster is created in
# this same apply and its endpoint is unknown at plan time (rules.md E-2).
resource "kubectl_manifest" "storage_class" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = var.storage_class_name
      annotations = {
        # A string, not a boolean: annotation values are always strings, and yamlencode would render a
        # bare true, which the API server rejects (the failure rules.md E-7 describes for Helm values).
        "storageclass.kubernetes.io/is-default-class" = tostring(var.is_default_class)
      }
    }
    provisioner = "ebs.csi.aws.com"
    parameters = {
      type      = var.volume_type
      encrypted = tostring(var.encrypted)
      # The key the EBS CSI driver documents. The blueprint wrote fsType, the in-tree provisioner's
      # parameter name, which the CSI driver's parameter table no longer lists.
      "csi.storage.k8s.io/fstype" = var.fs_type
    }
    reclaimPolicy = var.reclaim_policy
    # WaitForFirstConsumer creates the volume in the zone the pod is scheduled into. That matters here:
    # Karpenter decides after the fact which zone it has capacity in, and a volume created up front in
    # another zone cannot be followed - the broker would stay Pending.
    volumeBindingMode    = var.volume_binding_mode
    allowVolumeExpansion = var.allow_volume_expansion
  })
}
# No resource unmarking EKS's built-in gp2 class, which the blueprint did with a kubernetes_annotations
# resource setting is-default-class to "false".
#
# It has nothing to do on this Kubernetes version: gp2 on current EKS clusters carries no default
# annotation at all. And kubectl_manifest cannot express it safely - EKS creates gp2 with kubectl apply,
# so a partial manifest here is read through the object's last-applied-configuration as a request to
# delete every field it omits, which the API server rejects because StorageClass parameters are
# immutable. 089_ai_kubeflow_on_eks measured both.
