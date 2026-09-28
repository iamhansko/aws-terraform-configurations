# The AWS Distro for OpenTelemetry add-on, and one IRSA role per collector it runs.
#
# Its own module, like every other EKS add-on in this repository (rules.md C-4). That
# matters more here than for most: this add-on installs an operator with a webhook, which
# is why it has to come after cert-manager, and its configuration schema is versioned with
# the add-on rather than with the provider.
#
# The add-on runs up to three collectors, and each gets its own Kubernetes service account
# with a name the add-on decides. So there is one IAM role per enabled collector rather than
# one shared role: a trust policy names exactly one service account, and the three
# collectors need different AWS permissions anyway - writing log events, remote-writing
# metrics, and putting trace segments.
locals {
  # Keys are literal strings from this configuration, so every for_each below is known
  # during plan even though the role ARNs are not (rules.md B-8).
  #
  # The service account names are the add-on's, not this module's. They cannot be chosen:
  # the add-on creates them, and a trust policy naming anything else produces a collector
  # whose AssumeRoleWithWebIdentity is rejected - which shows up as an exporter failing to
  # authenticate, several layers below anything Terraform reports.
  pipelines = merge(
    var.container_logs == null ? {} : {
      container_logs = {
        service_account = "adot-col-container-logs"
        policy_arns     = var.container_logs.iam_policy_arns
      }
    },
    var.prometheus_metrics == null ? {} : {
      prometheus_metrics = {
        service_account = "adot-col-prom-metrics"
        policy_arns     = var.prometheus_metrics.iam_policy_arns
      }
    },
    var.otlp_ingest == null ? {} : {
      otlp_ingest = {
        service_account = "adot-col-otlp-ingest"
        policy_arns     = var.otlp_ingest.iam_policy_arns
      }
    },
  )
  # One entry per (collector, policy) pair. Keyed by the collector and the policy's own
  # name, so the resource addresses stay stable when a policy is added or removed
  # (rules.md B-7).
  policy_attachments = {
    for pair in flatten([
      for key, pipeline in local.pipelines : [
        for arn in pipeline.policy_arns : { pipeline = key, arn = arn }
      ]
    ]) : "${pair.pipeline}|${basename(pair.arn)}" => pair
  }
}
resource "aws_iam_role" "adot_collector_iam_role" {
  for_each = local.pipelines

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
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.operator_namespace}:${each.value.service_account}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "adot_collector_iam_role" {
  for_each = local.policy_attachments

  role       = aws_iam_role.adot_collector_iam_role[each.value.pipeline].name
  policy_arn = each.value.arn
}
locals {
  # The add-on's configuration schema, assembled from whichever collectors are enabled.
  #
  # Every "enabled" below is a real boolean, not the string "true". The schema declares them
  # as type boolean, unlike the vpc-cni add-on's enableNetworkPolicy, which is declared as a
  # string and rejects a boolean. The two are not interchangeable and only apply reports the
  # mismatch, so the schema is the thing to check rather than the neighbouring project
  # (rules.md E-5):
  #
  #   aws eks describe-addon-configuration --addon-name adot --addon-version <v>
  collector = merge(
    var.container_logs == null ? {} : {
      containerLogs = {
        serviceAccount = {
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.adot_collector_iam_role["container_logs"].arn
          }
        }
        pipelines = {
          logs = {
            cloudwatchLogs = { enabled = true }
          }
        }
        exporters = {
          awscloudwatchlogs = {
            log_group_name  = var.container_logs.log_group_name
            log_stream_name = var.container_logs.log_stream_name
          }
        }
      }
    },
    var.prometheus_metrics == null ? {} : {
      prometheusMetrics = {
        serviceAccount = {
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.adot_collector_iam_role["prometheus_metrics"].arn
          }
        }
        pipelines = {
          metrics = {
            amp = { enabled = var.prometheus_metrics.enable_amp }
            emf = { enabled = var.prometheus_metrics.enable_emf }
          }
        }
        exporters = {
          prometheusremotewrite = {
            endpoint = var.prometheus_metrics.remote_write_endpoint
          }
        }
      }
    },
    var.otlp_ingest == null ? {} : {
      otlpIngest = {
        serviceAccount = {
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.adot_collector_iam_role["otlp_ingest"].arn
          }
        }
        pipelines = {
          traces = {
            xray = { enabled = var.otlp_ingest.enable_xray }
          }
        }
      }
    },
  )
}
resource "aws_eks_addon" "adot" {
  cluster_name                = var.cluster_name
  addon_name                  = "adot"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  # JSON, which is what the API accepts - the _monolithic template wrote the same structure
  # as a hand-indented YAML heredoc. Both are valid, and the heredoc is the one where a
  # misplaced indent produces a document the add-on accepts and reads differently than
  # intended (rules.md E-5).
  configuration_values = jsonencode({ collector = local.collector })

  # Nothing here references the RBAC objects or cert-manager, so the caller has to order
  # this module after both (rules.md D-2). Neither is optional: EKS installs this add-on as
  # the eks:addon-manager user, which has no permission to create the operator without that
  # RBAC, and the operator's webhook serves TLS from a certificate cert-manager issues.
}
