# Velero: its IAM role, its Pod Identity association and its Helm release.
#
# Replaces the _monolithic bootstrap, which downloaded the velero CLI onto the bastion, wrote a
# velero.sh containing a "velero install" invocation, and ran it once per cluster (rules.md E-1).
# Nothing that produced was in Terraform state: not the Deployment, not the node agent DaemonSet,
# and not the BackupStorageLocation and VolumeSnapshotLocation custom resources that decide where
# every backup goes. A terraform destroy left all of it running.
#
# The role, the association and the release stay in one module because the association names the
# service account the chart creates, and neither half works alone (rules.md C-2).
#
# Worth noting what "velero install" and this Helm release differ on, because the CLI is what the
# upstream sample uses. The CLI applies the CRDs and then creates the Deployment; the chart does the
# same and additionally owns the BackupStorageLocation and VolumeSnapshotLocation objects, which is
# the part that matters here. Those two objects are the entire configuration of where backups and
# snapshots live, and having them in state means a change to the bucket or the region shows up as a
# plan diff rather than as a backup silently going to the old place.
resource "aws_iam_role" "velero" {
  name        = var.role_name
  name_prefix = var.role_name == null ? var.role_name_prefix : null

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
resource "aws_iam_role_policy" "velero" {
  name = "velero"
  role = aws_iam_role.velero.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Snapshot work. These do not support resource-level permissions for the describe calls, and
        # Velero has to be able to snapshot volumes it did not create, so the resource stays "*" -
        # that part matches the _monolithic template. What is added is the condition-free split
        # between reads and writes, so the destructive action is at least visible on its own line.
        Sid    = "ReadVolumesAndSnapshots"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
        ]
        Resource = "*"
      },
      {
        Sid    = "CreateAndDeleteSnapshots"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
        ]
        Resource = "*"
      },
      {
        # Scoped to the one bucket, where the _monolithic template granted these on "*" - which is
        # read, write and delete access to every object in every bucket in the account, from a pod.
        # That is the single widest permission in the original template.
        Sid    = "ReadAndWriteBackupObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
        ]
        Resource = "${var.bucket_arn}/*"
      },
      {
        Sid      = "ListBackupBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.bucket_arn
      },
    ]
  })
}
resource "aws_eks_pod_identity_association" "velero" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.velero.arn
}
resource "helm_release" "velero" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "velero"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Blocks the apply until the Deployment is Available, which is what --wait on the CLI did.
  wait    = true
  timeout = var.timeout_seconds

  # values rather than a list of set entries. The chart's configuration is nested lists of objects
  # (backupStorageLocation and volumeSnapshotLocation are both slices), and expressing those through
  # --set means index syntax and one string per leaf - where a boolean or a number reaching the
  # chart as a string is the failure rules.md E-7 describes. A single yamlencode keeps every value
  # the type it is written as.
  values = [yamlencode({
    # The plugin is not optional: the chart's own comment says at least one plugin provider image is
    # required, and without it Velero starts with no AWS object store or volume snapshotter and
    # reports the BackupStorageLocation as Unavailable.
    initContainers = [{
      name            = "velero-plugin-for-aws"
      image           = "${var.plugin_image_repository}:${var.plugin_image_tag}"
      imagePullPolicy = "IfNotPresent"
      volumeMounts = [{
        mountPath = "/target"
        name      = "plugins"
      }]
    }]

    serviceAccount = {
      server = {
        create = true
        name   = var.service_account_name
        # No eks.amazonaws.com/role-arn annotation. With IRSA the chart needs it; with Pod Identity
        # the association above is the whole binding, and an annotation here would be inert while
        # reading as if IRSA were in use.
      }
    }

    credentials = {
      # The point of Pod Identity. With this true the chart creates a Secret and mounts it as a
      # credentials file, which is what the CLI's --no-secret was turning off in the _monolithic
      # bootstrap - here there is no secret and no static key to rotate.
      useSecret = false
    }

    configuration = {
      backupStorageLocation = [{
        name     = var.backup_storage_location_name
        provider = "aws"
        default  = true
        bucket   = var.bucket_name
        config = {
          # The bucket's own region, taken from the bucket module rather than assumed
          # (rules.md B-5). A mismatch here fails every backup with a redirect error that names no
          # bucket, which is a long way from the cause.
          region = var.bucket_region
        }
      }]
      volumeSnapshotLocation = [{
        name     = var.volume_snapshot_location_name
        provider = "aws"
        config = {
          # The cluster's region, not the bucket's. Snapshots are EBS snapshots and they are taken
          # where the volumes are; only the backup metadata and the moved data go to the bucket.
          # These two being the same value in the _monolithic template was a consequence of both
          # clusters and the bucket sharing one region, not a rule.
          region = var.snapshot_region
        }
      }]
      # EnableCSI is what makes Velero back up a volume through its VolumeSnapshot object rather
      # than skipping it. It is the reason the snapshot-controller addon has to exist.
      features = join(",", var.features)
    }

    # The node agent is what moves snapshot data into the bucket - "--snapshot-move-data" on a
    # backup does nothing without it, and the backup completes having captured only the snapshot's
    # existence in the source region. That is the failure this whole project is built to avoid, so
    # it defaults on, as the _monolithic template's --use-node-agent had it.
    deployNodeAgent = var.deploy_node_agent

    # The chart's own upgrade job for the CRDs, on by default. Left on: the CRDs are Velero's own
    # API and a chart version bump that changes them without upgrading them leaves backups that the
    # new server cannot read.
    upgradeCRDs = true
  })]

  # The policy has to be attached and the association has to exist before Velero's first AWS call,
  # and referencing neither from the release means nothing else orders them (rules.md D-1). A Velero
  # that starts without credentials marks its BackupStorageLocation Unavailable and keeps retrying,
  # so the failure is recoverable but wait = true will time out first.
  depends_on = [
    aws_iam_role_policy.velero,
    aws_eks_pod_identity_association.velero,
  ]
}
