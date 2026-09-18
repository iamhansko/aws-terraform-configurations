locals {
  # Fluent Bit's own config file format, not YAML - it goes into the ConfigMap as
  # opaque string data. Rendered from variables so the log group names and the
  # region appear in exactly one place (rules.md B-5).
  #
  # The rewrite_tag filter is what makes per-application log groups possible: it
  # turns each record's kubernetes.labels.app value into a tag prefixed with
  # "app-", and the OUTPUT blocks below match on those tags. A pod without an
  # "app" label keeps its kube.* tag and matches no output, so its logs are
  # dropped - that is the behaviour of the _monolithic configuration and it is
  # kept, because it is what makes the per-group routing visible in the demo.
  filters_conf = <<-EOT
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Keep_Log Off
        Buffer_Size 0
        Kube_Meta_Cache_TTL 300s
    [FILTER]
        Name rewrite_tag
        Match kube.*
        Rule $kubernetes['labels']['app'] ^(.*)$ app-$0 false
  EOT
  output_conf = join("\n", [for label, sink in var.log_sinks : <<-EOT
    [OUTPUT]
        Name cloudwatch_logs
        Match ${sink.match}
        region ${var.aws_region}
        log_group_name ${sink.log_group_name}
        log_stream_prefix ${var.log_stream_prefix}
        log_retention_days ${var.log_retention_days}
        auto_create_group ${var.auto_create_group}
  EOT
  ])
}
# The label is the whole point of this namespace: EKS only enables Fargate
# logging for a cluster that has a namespace named aws-observability carrying
# aws-observability: enabled. Without the label the ConfigMap below is ignored
# and pods produce no logs, with no error anywhere.
#
# Declared with alekc/kubectl rather than hashicorp/kubernetes because this
# module is applied in the same terraform apply as the cluster whose outputs
# configure the provider (rules.md E-2).
resource "kubectl_manifest" "aws_observability_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name   = var.namespace
      labels = { "aws-observability" = "enabled" }
    }
  })
}
# Read by the Fargate control plane when it schedules a pod, not by a controller
# inside the cluster. That is why it has to exist before the workload pods are
# created: a pod scheduled while this is missing gets no log router at all, and
# adding the ConfigMap afterwards does not retrofit it.
resource "kubectl_manifest" "aws_logging_configmap" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = var.configmap_name
      namespace = var.namespace
    }
    data = {
      # Quoted deliberately: this is a ConfigMap value, so it has to be a string.
      # yamlencode of a bool would render flb_log_cw: false, which the API server
      # rejects for a ConfigMap ("cannot unmarshal bool into string").
      flb_log_cw     = tostring(var.flb_log_cw)
      "filters.conf" = local.filters_conf
      "output.conf"  = local.output_conf
    }
  })

  # metadata.namespace is a literal string, so nothing else tells Terraform the
  # Namespace must exist first (rules.md E-2).
  depends_on = [kubectl_manifest.aws_observability_namespace]
}
# Fluent Bit runs inside the Fargate infrastructure and writes to CloudWatch as
# the pod execution role, so the permission has to be on that role rather than on
# anything the pod itself carries. The module is handed the role name and never
# learns which Fargate profile it belongs to (rules.md B-6).
resource "aws_iam_role_policy" "fargate_pod_execution_logging" {
  name = var.policy_name
  role = var.pod_execution_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "FargateFluentBitCloudWatchLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:CreateLogGroup",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:PutRetentionPolicy",
      ]
      # Not narrowed to the log group ARNs on purpose: auto_create_group is on, so
      # Fluent Bit creates the groups itself and CreateLogGroup is not scopable to
      # a group that does not exist yet. Narrowing this is the change to make if
      # the groups ever become Terraform resources.
      Resource = "*"
    }]
  })
}
