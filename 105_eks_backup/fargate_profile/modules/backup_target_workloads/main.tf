# The objects the backup is taken of: a StorageClass, claim and Deployment for each of the three volume
# kinds AWS Backup supports for EKS, a bare Pod, a Deployment pinned to the node group, and the RBAC
# objects a restore is documented to recreate.
#
# These are the point of the project, and in the _monolithic template not one of them was ever created.
# Every manifest was echoed into a file and applied by the workbench's user data - after a line reading
# `exec bash`, which replaces the shell and discards the rest of the script. So the cluster came up,
# the backup ran against it, and the recovery point contained an empty cluster. Nothing reported that:
# the instance booted normally and the backup job reported COMPLETED.
#
# As kubectl_manifest resources they are in Terraform state, so `plan` shows a change to them and
# `destroy` removes them while the CSI drivers that own their volumes are still installed
# (rules.md E-1/E-2/E-3/D-4).
locals {
  # Why these images rather than the ones the _monolithic template used. It pulled rockylinux:8, ubuntu
  # and nginx from Docker Hub, whose anonymous pull limit is shared by every node in the region - the
  # first symptom is a pod in ImagePullBackOff with a "toomanyrequests" message that has nothing to do
  # with this configuration. The ECR public mirrors have no such limit.
  volume_writer_command = ["/bin/sh"]
}

# --- EFS ---
#
# Static provisioning, and on a Fargate-only cluster that is not a preference. AWS supports no dynamic
# persistent volume provisioning with Fargate nodes - only static - which is also why this variant
# installs no aws-efs-csi-driver addon: the EFS node agent is built into the Fargate runtime, and the
# dynamic provisioner that would need the addon has nothing to run on anyway.
#
# The _monolithic template for this variant had exactly this shape: a StorageClass with no parameters, a
# PersistentVolume naming the file system, and a claim naming the class. The modularized copy was
# started from the node-group variants, where EFS is dynamically provisioned through an access point
# (provisioningMode efs-ap), and that shape cannot bind here. What it produced was:
#
#   PVC   efs-pvc   Pending   (ExternalProvisioning: "Waiting for a volume to be created either by the
#                              external provisioner 'efs.csi.aws.com' or manually ...")
#   Pod   efs-...   Pending   (FailedScheduling, fargate-scheduler: "Pod not supported on Fargate:
#                              volumes not supported: persistent-storage not supported because:
#                              PVC efs-pvc not bound")
#
# and the apply failed on the Deployment below rather than on either of those, because kubectl_manifest
# waits for a rollout that could not start and reported the exhausted deadline instead: "default/efs
# failed to fetch resource from kubernetes: client rate limiter Wait returned an error: context
# deadline exceeded". Nothing in that message names the claim.
#
# What the backup needs is unaffected. AWS Backup protects an EFS volume through its claim, and what
# disqualifies a claim is an in-tree or CSI-migrated provisioner - not a statically provisioned CSI
# volume. This claim is still backed by efs.csi.aws.com.
#
# No parameters block: with nothing to dynamically provision, the class exists only to pair the volume
# and the claim below by name. Asking this provisioner to provision is the thing that fails on Fargate.
resource "kubectl_manifest" "efs_storage_class" {
  count = var.create_efs_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion  = "storage.k8s.io/v1"
    kind        = "StorageClass"
    metadata    = { name = var.efs_storage_class_name }
    provisioner = "efs.csi.aws.com"
  })

  depends_on = [var.driver_dependency]
}

resource "kubectl_manifest" "efs_volume" {
  count = var.create_efs_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata   = { name = var.efs_volume_name }
    spec = {
      capacity   = { storage = var.efs_volume_size }
      volumeMode = "Filesystem"
      # ReadWriteMany, which is the reason to use EFS here: both replicas of the Deployment below write
      # to the same volume, so the restored volume has content from both.
      accessModes = ["ReadWriteMany"]
      # Retain, as the _monolithic template set it. The file system is an AWS resource this project owns
      # separately, so releasing the claim must not be a path to deleting its data.
      persistentVolumeReclaimPolicy = "Retain"
      storageClassName              = var.efs_storage_class_name
      csi = {
        driver = "efs.csi.aws.com"
        # The one value that makes this static: the file system already exists and is named here. A
        # bare file system id mounts its root, which is what both replicas share - a dynamically
        # provisioned volume would instead carry an fs-...::fsap-... handle for an access point that
        # only a running CSI controller could have created.
        volumeHandle = var.efs_file_system_id
      }
    }
  })

  depends_on = [kubectl_manifest.efs_storage_class]
}

resource "kubectl_manifest" "efs_claim" {
  count = var.create_efs_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "efs-pvc"
      namespace = var.namespace
    }
    spec = {
      accessModes      = ["ReadWriteMany"]
      storageClassName = var.efs_storage_class_name
      # The same value the volume above declares as its capacity. A claim requesting more than the
      # volume offers does not bind, and the failure is a VolumeMismatch event on the claim rather than
      # anything on the volume (rules.md B-5).
      resources = { requests = { storage = var.efs_volume_size } }
    }
  })

  # depends_on orders the API calls; it does not order the phases. A claim is created Pending and
  # reaches Bound only once the control plane's volume controller has matched it to the volume, while
  # kubectl_manifest returns as soon as the API server accepts the object. Without this gate the
  # Deployment below is created in the same second, and fargate-scheduler rejects a pod whose claim is
  # still Pending - once, with no retry, so the pod stays Pending even after the claim binds
  # (rules.md D-8).
  #
  # The node-group variants of this project need no such gate: there kube-scheduler requeues the pod
  # and the same race resolves itself a few seconds later.
  wait_for {
    field {
      key   = "status.phase"
      value = "Bound"
    }
  }

  depends_on = [kubectl_manifest.efs_volume]
}

resource "kubectl_manifest" "efs_deployment" {
  count = var.create_efs_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "efs"
      namespace = var.namespace
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { app = "efs" } }
      template = {
        metadata = { labels = { app = "efs" } }
        spec = {
          containers = [{
            name    = "app"
            image   = var.volume_writer_image
            command = local.volume_writer_command
            # Appends a timestamp every five seconds, so the volume has content that makes it obvious
            # which recovery point a restore came from.
            args         = ["-c", "while true; do echo $(date -u) >> /data/out; sleep 5; done"]
            volumeMounts = [{ name = "persistent-storage", mountPath = "/data" }]
          }]
          volumes = [{
            name                  = "persistent-storage"
            persistentVolumeClaim = { claimName = "efs-pvc" }
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.efs_claim]
}

# --- EBS ---
#
# WaitForFirstConsumer, and it matters more than it looks: an EBS volume exists in one zone, so binding
# the claim before a pod is scheduled can place the volume where the pod cannot reach it. The topology
# restriction below is the same idea stated a second way.
resource "kubectl_manifest" "ebs_storage_class" {
  count = var.create_ebs_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion        = "storage.k8s.io/v1"
    kind              = "StorageClass"
    metadata          = { name = var.ebs_storage_class_name }
    provisioner       = "ebs.csi.aws.com"
    volumeBindingMode = "WaitForFirstConsumer"
    parameters = {
      "csi.storage.k8s.io/fstype" = var.ebs_fstype
      type                        = var.ebs_volume_type
      iopsPerGB                   = tostring(var.ebs_iops_per_gb)
      encrypted                   = "true"
    }
    allowedTopologies = [{
      matchLabelExpressions = [{
        key    = "topology.kubernetes.io/zone"
        values = var.ebs_allowed_zones
      }]
    }]
  })

  depends_on = [var.driver_dependency]
}

resource "kubectl_manifest" "ebs_claim" {
  count = var.create_ebs_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "ebs-pvc"
      namespace = var.namespace
    }
    spec = {
      # ReadWriteOnce: a block device belongs to one node, which is why the Deployment below can have
      # two replicas only if they land on the same node - and why a restore of this volume attaches it
      # to one pod.
      accessModes      = ["ReadWriteOnce"]
      storageClassName = var.ebs_storage_class_name
      resources        = { requests = { storage = var.ebs_volume_size } }
    }
  })

  depends_on = [kubectl_manifest.ebs_storage_class]
}

resource "kubectl_manifest" "ebs_deployment" {
  count = var.create_ebs_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "ebs"
      namespace = var.namespace
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { app = "ebs" } }
      template = {
        metadata = { labels = { app = "ebs" } }
        spec = {
          containers = [{
            name         = "app"
            image        = var.volume_writer_image
            command      = local.volume_writer_command
            args         = ["-c", "while true; do echo $(date -u) >> /data/out.txt; sleep 5; done"]
            volumeMounts = [{ name = "persistent-storage", mountPath = "/data" }]
          }]
          volumes = [{
            name                  = "persistent-storage"
            persistentVolumeClaim = { claimName = "ebs-pvc" }
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.ebs_claim]
}

# --- S3 through Mountpoint ---
#
# Static provisioning: the driver has no dynamic mode, so the volume names the bucket directly.
resource "kubectl_manifest" "s3_volume" {
  count = var.create_s3_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata   = { name = "s3-pv" }
    spec = {
      capacity    = { storage = var.s3_nominal_capacity }
      accessModes = ["ReadWriteMany"]
      # Empty, not unset. A statically provisioned volume has to opt out of every StorageClass,
      # including the cluster's default - leaving this out lets the default class provision an unrelated
      # EBS volume, which binds successfully and silently gives the pod the wrong storage.
      storageClassName = ""
      claimRef = {
        namespace = var.namespace
        name      = "s3-pvc"
      }
      # The _monolithic template also passed "prefix /", which AWS Backup cannot work with at all: its
      # own documentation says only whole buckets are supported as EKS backup targets, not prefixes.
      # Dropped rather than kept, because keeping it makes the bucket's child recovery point absent for
      # a reason nothing reports.
      mountOptions = concat(
        ["region ${var.aws_region}"],
        var.s3_allow_delete ? ["allow-delete"] : [],
      )
      csi = {
        driver = "s3.csi.aws.com"
        # Ignored by the driver, which takes the bucket from volumeAttributes. It only has to be unique
        # among this driver's volumes.
        volumeHandle     = "s3-csi-driver-volume"
        volumeAttributes = { bucketName = var.s3_bucket_name }
      }
    }
  })

  depends_on = [var.driver_dependency]
}

resource "kubectl_manifest" "s3_claim" {
  count = var.create_s3_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "s3-pvc"
      namespace = var.namespace
    }
    spec = {
      accessModes      = ["ReadWriteMany"]
      storageClassName = ""
      resources        = { requests = { storage = var.s3_nominal_capacity } }
      volumeName       = "s3-pv"
    }
  })

  depends_on = [kubectl_manifest.s3_volume]
}

resource "kubectl_manifest" "s3_deployment" {
  count = var.create_s3_workload ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "s3"
      namespace = var.namespace
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { app = "s3" } }
      template = {
        metadata = { labels = { app = "s3" } }
        spec = {
          containers = [{
            name    = "app"
            image   = var.volume_writer_image
            command = local.volume_writer_command
            # One object per pod start, then idle. Mountpoint has no random writes and no renames, so
            # appending in a loop the way the EFS and EBS pods do would fail here.
            args         = ["-c", "echo 'Hello from the container!' >> /data/$(date -u | tr ' :' '__').txt; tail -f /dev/null"]
            volumeMounts = [{ name = "persistent-storage", mountPath = "/data" }]
          }]
          volumes = [{
            name                  = "persistent-storage"
            persistentVolumeClaim = { claimName = "s3-pvc" }
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.s3_claim]
}

# --- Objects with no volume ---

# A bare Pod, which the project's own notes flag as the one object type whose restore is unreliable
# ("Pods ( Fargate randomly ? )"). Kept because that is worth being able to see.
resource "kubectl_manifest" "app_pod" {
  count = var.create_plain_workloads ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = "pod-app"
      namespace = var.namespace
    }
    spec = {
      containers = [{
        name  = "nginx"
        image = var.web_image
      }]
    }
  })

  depends_on = [var.driver_dependency]
}

resource "kubectl_manifest" "app_deployment" {
  count = var.create_plain_workloads ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "deployment-app"
      namespace = var.namespace
    }
    spec = {
      replicas = var.app_replicas
      selector = { matchLabels = { deployment = "app" } }
      template = {
        metadata = { labels = { deployment = "app" } }
        spec = merge(
          {
            containers = [{
              name  = "nginx"
              image = var.web_image
            }]
          },
          # Pinned to specific capacity when the caller asks for it. A restore into a cluster whose
          # nodes do not carry this label leaves the pods Pending - which is a useful thing to see, and
          # a reason the selector is a variable rather than a literal (rules.md B-4).
          length(var.app_node_selector) > 0 ? { nodeSelector = var.app_node_selector } : {},
        )
      }
    }
  })

  depends_on = [var.driver_dependency]
}

# --- RBAC ---
#
# The project's notes list ServiceAccounts, Roles, RoleBindings, ClusterRoles and ClusterRoleBindings as
# restorable - the cluster-scoped pair only when the restore role holds AmazonEKSClusterAdminPolicy.
# The _monolithic template created none of them, so that claim was untested.
resource "kubectl_manifest" "service_account" {
  count = var.create_rbac_objects ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = var.rbac_name
      namespace = var.namespace
    }
  })

  depends_on = [var.driver_dependency]
}

resource "kubectl_manifest" "role" {
  count = var.create_rbac_objects ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = var.rbac_name
      namespace = var.namespace
    }
    # camelCase, because this is the Kubernetes API's own field name - not the snake_case a typed
    # Terraform resource would use (rules.md E-2).
    rules = [{
      apiGroups = [""]
      resources = ["pods", "configmaps"]
      verbs     = ["get", "list", "watch"]
    }]
  })

  depends_on = [var.driver_dependency]
}

resource "kubectl_manifest" "role_binding" {
  count = var.create_rbac_objects ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name      = var.rbac_name
      namespace = var.namespace
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Role"
      name     = var.rbac_name
    }
    subjects = [{
      kind      = "ServiceAccount"
      name      = var.rbac_name
      namespace = var.namespace
    }]
  })

  # roleRef and subjects name their targets as literal strings, so nothing in the graph knows the Role
  # and the ServiceAccount have to exist first (rules.md D-1).
  depends_on = [kubectl_manifest.role, kubectl_manifest.service_account]
}

resource "kubectl_manifest" "cluster_role" {
  count = var.create_rbac_objects ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata   = { name = var.rbac_name }
    rules = [{
      apiGroups = [""]
      resources = ["nodes", "namespaces"]
      verbs     = ["get", "list", "watch"]
    }]
  })

  depends_on = [var.driver_dependency]
}

resource "kubectl_manifest" "cluster_role_binding" {
  count = var.create_rbac_objects ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata   = { name = var.rbac_name }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = var.rbac_name
    }
    subjects = [{
      kind      = "ServiceAccount"
      name      = var.rbac_name
      namespace = var.namespace
    }]
  })

  depends_on = [kubectl_manifest.cluster_role, kubectl_manifest.service_account]
}
