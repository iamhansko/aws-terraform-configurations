# The default gp3 StorageClass that every one of Sentry's eight volume claims resolves through.
#
# Why this is its own module and not part of eks_ebs_csi_driver_addon: installing the addon is
# necessary but not sufficient, and that gap is what broke this project. The addon registers the
# ebs.csi.aws.com CSIDriver and runs its controller; it creates no StorageClass. The only class on a
# fresh EKS cluster is the built-in gp2, whose provisioner is the in-tree kubernetes.io/aws-ebs that
# Kubernetes removed in 1.23 - and on current versions it does not carry the default-class annotation
# either. Measured on a cluster from this repo at Kubernetes 1.33:
#
#   NAME   PROV                    MODE                   DEFAULT
#   gp2    kubernetes.io/aws-ebs   WaitForFirstConsumer    <none>
#
# The default annotation is load-bearing here rather than a nicety. None of the chart's eight claims
# names a storageClassName - rendered and counted, not assumed:
#
#   PVC sentry-data                      STS sentry-rabbitmq
#   STS sentry-clickhouse                STS sentry-sentry-redis-master
#   STS sentry-kafka-controller          STS sentry-sentry-redis-replicas
#   STS sentry-sentry-postgresql         STS sentry-zookeeper-clickhouse
#
# so each resolves to whichever class is annotated default, and with none annotated they resolve to
# nothing and stay Pending. The chart's own values document this: "If undefined (the default) or set
# to null, no storageClassName spec is set". That is why this module marks its class default instead
# of the release naming it - eight claims across five subcharts would mean eight different value
# paths to get right.
#
# What that failure looks like from Terraform is worth spelling out, because it does not mention
# volumes. sentry-sentry-postgresql never starts, so the chart's db-check hook at weight -1 waits on
# a database that will never answer, and helm waits for hook groups in order regardless of --wait. The
# release then runs to its timeout and reports:
#
#   Error: context deadline exceeded
#
# Raising the timeout does not help and neither does wait = false; the claim has to bind.
#
# The _monolithic template did create this class, with a kubectl apply from the bastion right after it
# rolled out the driver (rules.md E-1/E-2). Losing it was a conversion regression, not an upstream
# change. This class adds encryption at rest and volume expansion, which the original left off.
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
    # It matters more here than in most projects: eight claims spread over three availability zones.
    volumeBindingMode    = var.volume_binding_mode
    allowVolumeExpansion = var.allow_volume_expansion
  })
}
# There is deliberately no resource here unmarking EKS's built-in gp2 class as default.
#
# Other projects in this repo carry one, on the reasoning that two default classes would split
# Sentry's claims between gp3 and a gp2 whose in-tree provisioner no longer exists. Two measurements
# retired it.
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

