locals {
  # Fluent Bit's own config file format, not YAML - it goes into the ConfigMap as
  # opaque string data. Rendered from variables so the stream name and the region
  # appear in exactly one place (rules.md B-5).
  #
  # The _monolithic template's ConfigMap for this variant had no filters at all -
  # only output.conf - so records reach S3 as the raw container log line with no
  # pod name, namespace or labels attached. That is reproduced by default, because
  # it is what the delivered objects in the demo actually look like. Turning
  # include_kubernetes_filter on adds the metadata, at the cost of a Kubernetes API
  # lookup per pod.
  filters_conf = <<-EOT
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Keep_Log Off
        Buffer_Size 0
        Kube_Meta_Cache_TTL 300s
  EOT
  # Match * rather than kube.*: every record still carries its original kube.* tag,
  # so the two are equivalent today, and * keeps the block matching if a filter is
  # ever added that retags records.
  output_conf = <<-EOT
    [OUTPUT]
        Name  es
        Match ${var.match}
        Host  ${var.opensearch_endpoint}
        Port  443
        Index ${var.index_name}
        Suppress_Type_Name On
        AWS_Auth On
        AWS_Region ${var.aws_region}
        tls   On
  EOT
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
    # Only the keys this variant actually sets. flb_log_cw and filters.conf are
    # omitted entirely when off rather than written as empty strings: Fluent Bit
    # reads an empty filters.conf as a configuration error and refuses to start,
    # which looks exactly like the logging having silently failed.
    data = merge(
      { "output.conf" = local.output_conf },
      # Quoted deliberately: this is a ConfigMap value, so it has to be a string.
      # yamlencode of a bool would render flb_log_cw: false, which the API server
      # rejects for a ConfigMap ("cannot unmarshal bool into string").
      var.flb_log_cw == null ? {} : { flb_log_cw = tostring(var.flb_log_cw) },
      var.include_kubernetes_filter ? { "filters.conf" = local.filters_conf } : {},
    )
  })

  # metadata.namespace is a literal string, so nothing else tells Terraform the
  # Namespace must exist first (rules.md E-2).
  depends_on = [kubectl_manifest.aws_observability_namespace]
}
# Fluent Bit runs inside the Fargate infrastructure and signs its OpenSearch
# requests as the pod execution role - that is what AWS_Auth On in the OUTPUT block
# above means - so the permission has to be on that role rather than on anything
# the pod itself carries. The module is handed the role name and the domain ARN and
# never learns which Fargate profile or which domain module they came from
# (rules.md B-6).
data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "fargate_pod_execution_logging" {
  name = var.policy_name
  role = var.pod_execution_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Sid    = "FargateFluentBitOpenSearchHttp"
      Effect = "Allow"
      # es:ESHttp*, not kinesis:PutRecords. The two are different services: Fluent
      # Bit's es output plugin signs HTTP requests against the domain endpoint, and a
      # policy naming the Kinesis Data Streams action grants nothing here. The
      # mistake is invisible at apply time - every index request is rejected and the
      # domain simply stays empty.
      #
      # Narrower than the _monolithic template's es:*, which also covered domain
      # administration. Fluent Bit only ever issues HTTP requests.
      Action = ["es:ESHttpPost", "es:ESHttpPut", "es:ESHttpGet", "es:ESHttpHead"]
      # Scoped to this domain and the paths under it. The _monolithic template used
      # "*" with es:*, which let the role manage every domain in the account.
      Resource = ["${var.opensearch_arn}", "${var.opensearch_arn}/*"]
      }],
      # flb_log_cw sends Fluent Bit's own process log to CloudWatch, and it is the
      # log router itself - running as this role - that writes it. Turning the
      # ConfigMap key on without this permission produces the worst version of the
      # problem it exists to solve: the diagnostic channel fails silently too, so
      # the router looks like it never started.
      var.flb_log_cw == true ? [{
        Sid    = "FargateFluentBitProcessLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy",
        ]
        # Not narrowed past the account and region: the Fargate control plane picks
        # the group name for the process log, so there is no name here to scope to.
        # Widening beyond this - the "*" the AWS troubleshooting guide shows - would
        # additionally cover every other region.
        Resource = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
      }] : [],
    )
  })
}
