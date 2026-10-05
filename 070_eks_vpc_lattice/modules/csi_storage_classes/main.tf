# The gp3 StorageClass, and optionally an EBS VolumeSnapshotClass.
#
# Small objects that decide whether this project's demo works at all, and the _monolithic template
# applied them with kubectl from a shell on the bastion, so neither was in state (rules.md E-1/E-2).
#
# What each is for:
#
#   StorageClass         gp3 is cheaper and faster than the gp2 class EKS ships, for the same size, so
#                        this declares a gp3 class and takes the default annotation. Nothing unmarks
#                        gp2: on current Kubernetes versions it carries no default annotation to
#                        begin with, and patching it is not possible anyway - see the note at the
#                        end of this file.
#   VolumeSnapshotClass  Only created when create_volume_snapshot_class is on, because the CRD behind
#                        it comes from the snapshot-controller addon. A cluster without that addon has
#                        no such kind, and the manifest then fails at apply rather than at plan
#                        (rules.md B-4).
#
# Declared through alekc/kubectl rather than hashicorp/kubernetes: the cluster is created in this same
# apply, so its endpoint is unknown at plan time, and VolumeSnapshotClass is a custom resource whose
# CRD hashicorp/kubernetes would need present at plan time to resolve its schema (rules.md E-2/E-3).
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
      type = var.volume_type
      # Encryption at rest on every volume this class provisions. The _monolithic template's class
      # set only the type, so the demo's volume - and therefore the snapshot and the backup taken
      # from it - was unencrypted.
      encrypted = tostring(var.encrypted)
    }
    reclaimPolicy = var.reclaim_policy
    # WaitForFirstConsumer, as the _monolithic template had it, and it is the right choice rather
    # than an incidental one: the volume is created in the zone the pod is scheduled into. With
    # Immediate the volume is created first, in an arbitrary zone, and a pod that cannot be
    # scheduled there stays Pending forever with no useful message.
    volumeBindingMode    = var.volume_binding_mode
    allowVolumeExpansion = var.allow_volume_expansion
  })
}
resource "kubectl_manifest" "volume_snapshot_class" {
  count = var.create_volume_snapshot_class ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "snapshot.storage.k8s.io/v1"
    kind       = "VolumeSnapshotClass"
    metadata = {
      name = var.volume_snapshot_class_name
      annotations = {
        "snapshot.storage.kubernetes.io/is-default-class" = tostring(var.is_default_snapshot_class)
      }
      # Velero only considers a snapshot class carrying this label when it picks one for a volume.
      # The _monolithic template's class had no labels, which works as long as the class is the
      # default - and stops working the moment a second class exists. The label is what makes the
      # choice explicit rather than incidental.
      labels = {
        "velero.io/csi-volumesnapshot-class" = "true"
      }
    }
    driver = "ebs.csi.aws.com"
    # Delete, as the _monolithic template had it: removing the VolumeSnapshot removes the EBS
    # snapshot behind it. Retain would leave snapshots behind after a destroy, billed and belonging
    # to nothing.
    deletionPolicy = var.snapshot_deletion_policy
  })

  # The CRD this instantiates comes from the snapshot-controller addon, which a different module
  # installs - nothing here can express that dependency (rules.md D-2/E-2).
}
# There is deliberately no resource here unmarking EKS's built-in gp2 class as default.
#
# An earlier version of this module patched gp2 to drop that annotation, on the reasoning that two
# default classes let a claim with no storageClassName bind to whichever one the API server picks.
# Two measurements retired it.
#
# It has nothing to do. gp2 on a current EKS cluster carries no default-class annotation at all -
# measured at Kubernetes 1.33 - so the gp3 class above is the only default either way:
#
#   NAME   PROV                    MODE                   DEFAULT
#   gp2    kubernetes.io/aws-ebs   WaitForFirstConsumer    <none>
#
# And attempting it fails. EKS creates gp2 with kubectl apply, so the object already carries a
# kubectl.kubernetes.io/last-applied-configuration recording its parameters and volumeBindingMode.
# kubectl_manifest applies through that same three-way merge, which reads the annotation, sees those
# fields missing from a partial manifest, and computes them as deletions:
#
#   Error: gp2 failed to run apply: error when applying patch:
#     {... "parameters":null,"volumeBindingMode":null}
#     StorageClass.storage.k8s.io "gp2" is invalid: [parameters: Forbidden: updates to parameters
#     are forbidden., volumeBindingMode: Invalid value: "Immediate": field is immutable]
#
# So "a partial manifest, and merge-patch semantics leave the rest of the object alone" holds only
# for objects with no last-applied-configuration. Against one that has it, a partial manifest is a
# request to delete every field it omits. Making it work would mean restating gp2's whole spec -
# exactly the ownership of an EKS-created object that rules.md E-4 says not to take on - in order to
# remove an annotation that is not there.
#
# Observed on 048_eks_sentry, whose apply this failed.
