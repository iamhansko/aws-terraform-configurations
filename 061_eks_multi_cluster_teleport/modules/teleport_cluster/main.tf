# Teleport, running against AWS-managed state: DynamoDB for cluster state and the audit
# log, S3 for session recordings.
#
# The _monolithic template installed this from a shell script on the bastion and put the
# DynamoDB, S3 and Route 53 permissions on the node instance role. That gives them to
# every pod on every node through IMDS - and these are the permissions to read the audit
# log, delete session recordings, and rewrite the DNS record the cluster authenticates
# under. Here they are an IRSA role bound to Teleport's own service accounts, and the
# Route 53 half is gone entirely: the DNS records are Terraform resources in the root,
# because the load balancer they point at is one too (rules.md G-3).
data "aws_caller_identity" "current" {}
locals {
  # The chart names every service account after the release, so all four have to be
  # trusted. IAM treats a list of values on one condition key as OR (rules.md B-5).
  service_account_subjects = [
    for suffix in var.service_account_suffixes :
    "system:serviceaccount:${var.namespace}:${var.release_name}${suffix}"
  ]
  table_arn_prefix = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table"
}
resource "aws_iam_role" "teleport_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_host}:sub" = local.service_account_subjects
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "teleport_iam_role" {
  role = aws_iam_role.teleport_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ClusterStateStorage"
        Effect = "Allow"
        Action = [
          # CreateTable is the one the _monolithic template left out, and it is the first
          # call Teleport makes: with chartMode aws the table does not exist yet, so
          # Teleport creates it on start. Without this the auth pod fails its very first
          # backend write with AccessDeniedException and never becomes ready - and because
          # the table name looks right in the chart values, it reads as a DynamoDB problem
          # rather than a missing action.
          "dynamodb:CreateTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:UpdateTimeToLive",
          # Also missing from the template, and only needed because backups are on. It is
          # read during startup, so it fails in the same place as CreateTable.
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:UpdateContinuousBackups",
          "dynamodb:BatchWriteItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:ConditionCheckItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          # Teleport watches its own state through the table's stream, which is how a
          # second replica learns about a change the first one made.
          "dynamodb:DescribeStream",
          "dynamodb:GetShardIterator",
          "dynamodb:GetRecords",
        ]
        Resource = [
          "${local.table_arn_prefix}/${var.backend_table}",
          "${local.table_arn_prefix}/${var.backend_table}/stream/*",
        ]
      },
      {
        Sid    = "ClusterEventsStorage"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:UpdateTimeToLive",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:UpdateContinuousBackups",
          "dynamodb:BatchWriteItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
        ]
        Resource = [
          "${local.table_arn_prefix}/${var.audit_log_table}",
          # The audit log is queried by time range, which is a global secondary index
          # rather than the table's own key.
          "${local.table_arn_prefix}/${var.audit_log_table}/index/*",
        ]
      },
      {
        Sid    = "SessionRecordingBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketVersioning",
          "s3:GetEncryptionConfiguration",
        ]
        # Deliberately narrower than the _monolithic template's, which also granted
        # s3:CreateBucket, s3:PutBucketVersioning and s3:PutEncryptionConfiguration -
        # letting Teleport configure a bucket Terraform owns. The bucket module sets those
        # properties, so nothing here needs to write them.
        Resource = [var.session_recording_bucket_arn]
      },
      {
        Sid    = "SessionRecordingObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
        ]
        # No s3:DeleteObject. The template granted s3:*Object, which includes it - and a
        # session recording that the recorded party can delete is not an audit trail. The
        # bucket's lifecycle rule expires old versions instead.
        Resource = ["${var.session_recording_bucket_arn}/*"]
      },
    ]
  })
}
locals {
  # YAML rather than set entries. The chart takes nested maps of annotations whose keys
  # contain dots and slashes, which set would need escaped, and several booleans that must
  # stay booleans (rules.md E-7). yamlencode keeps both as written.
  values = {
    # chartMode aws is what switches the backend from a local volume to DynamoDB and S3.
    chartMode = "aws"
    # The cluster's own identity, and the name on the certificate it asks for.
    clusterName     = var.cluster_host
    kubeClusterName = var.kube_cluster_name
    # One TLS port for SSH, Kubernetes and web traffic, which is what lets the load
    # balancer have a single listener.
    proxyListenerMode = "multiplex"
    enterprise        = false
    aws = {
      region                 = var.aws_region
      backendTable           = var.backend_table
      auditLogTable          = var.audit_log_table
      auditLogMirrorOnStdout = var.audit_log_mirror_on_stdout
      sessionRecordingBucket = var.session_recording_bucket
      backups                = var.dynamo_backups
      dynamoAutoScaling      = var.dynamo_auto_scaling
    }
    highAvailability = {
      replicaCount = var.replica_count
      certManager = {
        enabled = true
        # Both halves matter. The name has to be an issuer that exists, and the kind has
        # to match how it was created - the chart defaults to Issuer, and this project's
        # issuer is cluster-scoped.
        issuerName = var.issuer_name
        issuerKind = var.issuer_kind
      }
    }
    annotations = {
      # Applied to all four service accounts, which is why the trust policy above names
      # all four.
      serviceAccount = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.teleport_iam_role.arn
      }
      # Merged with the chart's own three Service annotations rather than replacing them.
      # The one that matters is aws-load-balancer-type: the chart sets "nlb", which asks
      # the in-tree cloud provider for a network load balancer, and "external" is what
      # hands the Service to the AWS Load Balancer Controller instead. Only the controller
      # adopts a pre-created load balancer by tag, so without this override the pre-created
      # one is ignored and a second appears - with no error anywhere (rules.md G-1/G-3).
      service = merge(
        {
          "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"          = var.scheme
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = var.nlb_target_type
        },
        length(var.frontend_security_group_ids) > 0 ? {
          "service.beta.kubernetes.io/aws-load-balancer-security-groups" = join(",", var.frontend_security_group_ids)
        } : {},
      )
    }
  }
}
resource "helm_release" "teleport" {
  name       = var.release_name
  repository = var.chart_repository
  chart      = "teleport-cluster"
  version    = var.chart_version
  namespace  = var.namespace
  # kube-system already exists, but this stays true so the module does not depend on the
  # namespace being one of the built-in ones.
  create_namespace = true
  # Waits for the proxy to be ready, which means waiting for cert-manager to have issued
  # its certificate. That is the real gate on this project working: a DNS-01 challenge that
  # cannot be written, or a hosted zone that does not match the cluster host, surfaces here
  # rather than as a Teleport error.
  wait    = true
  timeout = var.timeout_seconds

  values = [yamlencode(local.values)]

  # Teleport cannot assume the role until the role carries its policy, and referencing the
  # ARN alone does not order this after the policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.teleport_iam_role]
}
# Kubernetes access through Teleport has two halves, and the chart provides neither.
#
# The Teleport half: Teleport refuses a Kubernetes request itself unless the user's roles
# resolve to at least one kubernetes_groups or kubernetes_users entry. The preset access role
# resolves both from the user's traits ({{internal.kubernetes_groups}}), so a user created with
# "tctl users add --roles=access,editor" and nothing more can tsh login and tsh kube ls, and
# then every kubectl call comes back with "Your user's Teleport role does not allow Kubernetes
# access". The add-user command in outputs.tf sets that trait to the group below.
#
# The Kubernetes half: the trait only names a group, and what a group may do is RBAC. The chart
# gives Teleport's own service account the right to impersonate and nothing else, so without
# this binding the same request would get past Teleport and come back Forbidden instead.
locals {
  # Named after the ClusterRole it is bound to, so the name cannot misdescribe what it grants.
  # Changing the ClusterRole therefore renames the group too, which revokes access from users
  # granted the old one instead of changing their permissions underneath them.
  kubernetes_group = "teleport:${var.kubernetes_cluster_role}"
}
resource "kubectl_manifest" "kubernetes_access_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      # The ClusterRole is part of the name because roleRef is immutable. A different ClusterRole
      # changes the name, which the provider treats as a replacement - an in-place update of
      # roleRef would be rejected by the API server.
      name = "${var.release_name}-users-${var.kubernetes_cluster_role}"
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = var.kubernetes_cluster_role
    }
    subjects = [{
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Group"
      name     = local.kubernetes_group
    }]
  })
}
