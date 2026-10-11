# Prometheus and Grafana for the Kafka cluster, with Prometheus remote-writing to Amazon Managed
# Service for Prometheus.
#
# The blueprint installed this through aws-ia/eks-blueprints-addons (enable_kube_prometheus_stack) with
# helm-values/kube-prometheus-amp-enable.yaml, created the workspace and its ingest role in amp.tf, and
# generated the Grafana admin password into Secrets Manager in addons.tf. All of it is here because the
# pieces reference each other: the release annotates its service account with the role, the role trusts
# that service account by name, and the values point remote write at the workspace (rules.md C-2).
#
# No data sources: the account, partition and region come in as variables. The root orders this module
# after the node group with depends_on, which would defer any data source here to apply (rules.md D-6).
locals {
  amp_enabled = var.enable_amazon_prometheus
  # prometheus_endpoint ends in a slash; the remote write path is appended to it and Grafana's data
  # source takes it without one, which is how the blueprint spelled both URLs by hand.
  amp_endpoint = one(aws_prometheus_workspace.amp[*].prometheus_endpoint)

  prometheus_spec = merge(
    {
      # Every PodMonitor and ServiceMonitor in the cluster, not only the ones this release labels -
      # the Strimzi PodMonitors in modules/kafka_monitoring carry no Helm labels at all.
      podMonitorSelectorNilUsesHelmValues     = false
      serviceMonitorSelectorNilUsesHelmValues = false
      serviceMonitorSelector                  = {}
      serviceMonitorNamespaceSelector         = {}
      retention                               = var.prometheus_retention
      scrapeInterval                          = var.scrape_interval
      evaluationInterval                      = var.evaluation_interval
      scrapeTimeout                           = var.scrape_timeout
      storageSpec = {
        volumeClaimTemplate = {
          metadata = { name = "data" }
          spec = {
            storageClassName = var.storage_class_name
            accessModes      = ["ReadWriteOnce"]
            resources        = { requests = { storage = var.prometheus_storage_size } }
          }
        }
      }
    },
    local.amp_enabled ? {
      remoteWrite = [{
        url   = "${local.amp_endpoint}api/v1/remote_write"
        sigv4 = { region = var.aws_region }
        queueConfig = {
          maxSamplesPerSend = 1000
          maxShards         = 200
          capacity          = 2500
        }
      }]
    } : null,
  )

  values = {
    prometheus = merge(
      { prometheusSpec = local.prometheus_spec },
      local.amp_enabled ? {
        serviceAccount = {
          create      = true
          name        = var.amp_service_account_name
          annotations = { "eks.amazonaws.com/role-arn" = one(aws_iam_role.amp_ingest[*].arn) }
        }
      } : null,
    )
    alertmanager = { enabled = false }
    grafana = merge(
      {
        enabled                  = true
        defaultDashboardsEnabled = false
      },
      local.amp_enabled ? {
        # Grafana borrows Prometheus's service account, as the blueprint had it, so the AMP data source
        # below can sign its queries with the same role that writes the samples.
        serviceAccount = {
          create = false
          name   = var.amp_service_account_name
        }
        "grafana.ini" = { auth = { sigv4_auth_enabled = true } }
        additionalDataSources = [{
          name      = "AMP"
          editable  = true
          type      = "prometheus"
          isDefault = false
          url       = trimsuffix(local.amp_endpoint, "/")
          jsonData = {
            sigV4Auth   = true
            sigV4Region = var.aws_region
          }
        }]
      } : null,
    )
  }
}

# The namespace, created here rather than by the release's create_namespace, so that terraform destroy
# can wait for it. Prometheus keeps its data on a PersistentVolumeClaim from a StatefulSet's claim
# template, and helm uninstall leaves such claims behind - so without this the EBS volume outlives the
# cluster. Deleting the namespace deletes the claim, and wait = true holds the destroy until it is gone,
# while the EBS CSI driver that deletes the volume is still running (rules.md D-7).
resource "kubectl_manifest" "namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.namespace }
  })
  wait = true
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}
# The blueprint's admin password store, kept so the password never has to be printed or written to the
# workbench's disk. recovery_window_in_days = 0 as the blueprint had it, so terraform destroy deletes the
# secret immediately and a second apply can reuse the name.
resource "aws_secretsmanager_secret" "grafana" {
  name                    = var.grafana_admin_secret_name
  description             = "Grafana admin password for the ${var.release_name} release"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

resource "aws_prometheus_workspace" "amp" {
  count = local.amp_enabled ? 1 : 0

  alias = "amp-ws-${var.cluster_name}"
}
# The blueprint's policy (amp.tf, aws_iam_policy.grafana), statement for statement: read access to
# CloudWatch metrics and logs and to EC2 tags for Grafana's CloudWatch data source, and query and remote
# write on Amazon Managed Prometheus workspaces in this account and region. Scoped already, so it is
# carried over rather than widened (rules.md A-5).
resource "aws_iam_policy" "amp_ingest" {
  count = local.amp_enabled ? 1 : 0

  description = "Remote write and query on Amazon Managed Prometheus, and CloudWatch reads, for ${var.release_name} on ${var.cluster_name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowReadingMetricsFromCloudWatch"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
        ]
      },
      {
        Sid      = "AllowGetInsightsCloudWatch"
        Effect   = "Allow"
        Resource = "arn:${var.partition}:cloudwatch:${var.aws_region}:${var.account_id}:insight-rule/*"
        Action   = ["cloudwatch:GetInsightRuleReport"]
      },
      {
        Sid      = "AllowReadingAlarmHistoryFromCloudWatch"
        Effect   = "Allow"
        Resource = "arn:${var.partition}:cloudwatch:${var.aws_region}:${var.account_id}:alarm:*"
        Action   = ["cloudwatch:DescribeAlarmHistory", "cloudwatch:DescribeAlarms"]
      },
      {
        Sid      = "AllowReadingLogsFromCloudWatch"
        Effect   = "Allow"
        Resource = "arn:${var.partition}:logs:${var.aws_region}:${var.account_id}:log-group:*:log-stream:*"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents",
        ]
      },
      {
        Sid      = "AllowReadingTagsInstancesRegionsFromEC2"
        Effect   = "Allow"
        Resource = "*"
        Action   = ["ec2:DescribeTags", "ec2:DescribeInstances", "ec2:DescribeRegions"]
      },
      {
        Sid      = "AllowReadingResourcesForTags"
        Effect   = "Allow"
        Resource = "*"
        Action   = ["tag:GetResources"]
      },
      {
        Sid    = "AllowListApsWorkspaces"
        Effect = "Allow"
        Resource = [
          "arn:${var.partition}:aps:${var.aws_region}:${var.account_id}:/*",
          "arn:${var.partition}:aps:${var.aws_region}:${var.account_id}:workspace/*",
          "arn:${var.partition}:aps:${var.aws_region}:${var.account_id}:workspace/*/*",
        ]
        Action = [
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
          "aps:GetMetricMetadata",
          "aps:GetSeries",
          "aps:QueryMetrics",
          "aps:RemoteWrite",
          "aps:GetLabels",
        ]
      },
    ]
  })
}
resource "aws_iam_role" "amp_ingest" {
  count = local.amp_enabled ? 1 : 0

  description = "IRSA role for ${var.namespace}/${var.amp_service_account_name}, shared by Prometheus and Grafana"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.amp_service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "amp_ingest" {
  count = local.amp_enabled ? 1 : 0

  role       = aws_iam_role.amp_ingest[0].name
  policy_arn = aws_iam_policy.amp_ingest[0].arn
}

resource "helm_release" "kube_prometheus_stack" {
  name       = var.release_name
  repository = var.chart_repository
  chart      = "kube-prometheus-stack"
  version    = var.chart_version
  namespace  = kubectl_manifest.namespace.name
  # Blocks until the chart's own Deployments and DaemonSets are ready. Not Prometheus itself, which is a
  # StatefulSet the operator creates after the release - so a Prometheus pod stuck Pending on its volume
  # claim does not fail this apply; the README's commands are where that shows.
  wait          = true
  wait_for_jobs = true
  timeout       = var.timeout_seconds

  values = [yamlencode(local.values)]

  set_sensitive = [
    {
      name  = "grafana.adminPassword"
      value = random_password.grafana.result
    },
  ]

  # The role must carry its policy before Prometheus starts remote writing, or the first minutes of
  # samples are rejected with 403 and dropped (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.amp_ingest]
}
