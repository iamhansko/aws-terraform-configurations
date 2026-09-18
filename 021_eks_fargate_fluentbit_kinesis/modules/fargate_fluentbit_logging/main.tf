locals {
  # Fluent Bit's own config file format, not YAML - it goes into the ConfigMap as
  # opaque string data. Rendered from variables so the stream name and the region
  # appear in exactly one place (rules.md B-5).
  #
  # Only the kubernetes filter here, unlike the CloudWatch variant (020) which
  # also runs rewrite_tag. rewrite_tag exists to turn each pod's app label into a
  # tag so several OUTPUT blocks can match different applications; this variant
  # sends everything to one stream, so there is nothing to route and the filter
  # would only add work per record.
  filters_conf = <<-EOT
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Keep_Log Off
        Buffer_Size 0
        Kube_Meta_Cache_TTL 300s
  EOT
  # Match * rather than kube.*: with no rewrite_tag every record still carries its
  # original kube.* tag, so the two are equivalent today, and * keeps the block
  # matching if a filter is ever added that retags records.
  output_conf = <<-EOT
    [OUTPUT]
        Name  kinesis_streams
        Match ${var.match}
        region ${var.aws_region}
        stream ${var.stream_name}
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
# Fluent Bit runs inside the Fargate infrastructure and writes to Kinesis as the
# pod execution role, so the permission has to be on that role rather than on
# anything the pod itself carries. The module is handed the role name and the
# stream ARN and never learns which Fargate profile or which stream module they
# came from (rules.md B-6).
resource "aws_iam_role_policy" "fargate_pod_execution_logging" {
  name = var.policy_name
  role = var.pod_execution_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "FargateFluentBitKinesisPutRecords"
      Effect = "Allow"
      Action = ["kinesis:PutRecords"]
      # Scoped to the one stream, unlike the CloudWatch variant (020) which has to
      # use "*" because Fluent Bit creates the log groups itself and CreateLogGroup
      # cannot be scoped to a group that does not exist yet. Here the sink is a
      # Terraform resource, so its ARN is known and the grant is narrow.
      Resource = var.stream_arn
    }]
  })
}
