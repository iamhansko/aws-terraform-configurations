# The gp3 StorageClass that backs Vault's data volume.
#
# Why this exists as its own module rather than living inside eks_ebs_csi_driver_addon: installing
# the addon is necessary but not sufficient, and that gap is what broke this project. The addon
# registers the ebs.csi.aws.com CSIDriver and runs its controller, and it creates no StorageClass at
# all. The only class on a fresh EKS cluster is the built-in gp2, whose provisioner is the in-tree
# kubernetes.io/aws-ebs that Kubernetes removed in 1.23 - and on current versions it does not carry
# the default-class annotation either. Measured on this project's own cluster at Kubernetes 1.33:
#
#   NAME   PROV                    MODE                   DEFAULT
#   gp2    kubernetes.io/aws-ebs   WaitForFirstConsumer    <none>
#
# So the chart's PersistentVolumeClaim, which names no storageClassName, resolved to no class, was
# never provisioned, and vault-0 sat Pending for hours:
#
#   Warning  FailedScheduling  0/3 nodes are available: pod has unbound immediate
#                              PersistentVolumeClaims
#
# That is also why the bootstrap association failed rather than the association's script being
# wrong: "vault operator init" was waiting on a pod that could never start. The addon module's
# comment claimed the addon was what made volumes work; it is this class that does.
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
        # A string, not a boolean. Kubernetes annotation values are always strings, and yamlencode
        # would render a bare true unquoted - which the API server rejects with a message about
        # unmarshalling bool into string (the same failure rules.md E-7 describes for Helm values).
        "storageclass.kubernetes.io/is-default-class" = tostring(var.is_default_class)
      }
    }
    provisioner = "ebs.csi.aws.com"
    parameters = {
      type      = var.volume_type
      encrypted = tostring(var.encrypted)
    }
    reclaimPolicy = var.reclaim_policy
    # WaitForFirstConsumer, and it is the right choice rather than an incidental one: the volume is
    # created in the zone the pod is scheduled into. With Immediate the volume is created first, in
    # an arbitrary zone, and a pod that cannot be scheduled there stays Pending forever with no
    # useful message - the same dead end this module was written to fix, reached a different way.
    volumeBindingMode    = var.volume_binding_mode
    allowVolumeExpansion = var.allow_volume_expansion
  })
}
# There is deliberately no resource here unmarking EKS's built-in gp2 class as default.
#
# Other projects in this repo carry one, on the reasoning that a cluster with two default classes
# hands a claim naming no class to whichever the API server picks. Two measurements retired it.
#
# It has nothing to do. gp2 on a current EKS cluster carries no default annotation at all - measured
# at Kubernetes 1.33, see the table above - so there is no annotation to remove.
#
# And attempting it fails. EKS creates gp2 with kubectl apply, so the object already carries a
# kubectl.kubernetes.io/last-applied-configuration recording its parameters and volumeBindingMode.
# kubectl_manifest applies through the same three-way merge, which reads that annotation, sees the
# fields missing from a partial manifest, and computes them as deletions:
#
#   Error: gp2 failed to run apply: error when applying patch:
#     {... "parameters":null,"volumeBindingMode":null}
#     StorageClass.storage.k8s.io "gp2" is invalid: [parameters: Forbidden: updates to parameters
#     are forbidden., volumeBindingMode: Invalid value: "Immediate": field is immutable]
#
# So "a partial manifest and merge-patch semantics leave the rest of the object alone" holds only for
# objects with no last-applied-configuration. Against one that has it, a partial manifest is a
# request to delete every field it omits. Making this work would mean restating gp2's whole spec,
# which is exactly the ownership of an EKS-created object that rules.md E-4 says not to take on - to
# remove an annotation that is not there.
#
# Vault names its class explicitly anyway, so nothing here depends on which class is default.

