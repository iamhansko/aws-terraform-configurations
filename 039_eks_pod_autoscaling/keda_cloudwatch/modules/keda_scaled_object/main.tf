locals {
  # The CloudWatch Metrics Insights query the scaler runs. SCHEMA(...) restricts the
  # match to metrics carrying exactly the LoadBalancer dimension, so the per-AZ and
  # per-target-group series are excluded and one time series comes back.
  #
  # The identifier in the WHERE clause is the load balancer's arn_suffix
  # (app/<name>/<id>), not its ARN - that is the string CloudWatch puts in the
  # LoadBalancer dimension. A query built from the full ARN is accepted and matches
  # nothing, and with ignore_null_values true, matching nothing is indistinguishable
  # from an idle service.
  metric_expression = "SELECT ${var.metric_aggregation}(${var.metric_name}) FROM SCHEMA(\"${var.metric_namespace}\", LoadBalancer) WHERE LoadBalancer = '${var.load_balancer_arn_suffix}'"
}
# How the scaler authenticates to CloudWatch. The _monolithic template wrote this into
# a YAML file on the bastion with echo and applied it with "kubectl apply -f manifests
# || true", so a rejected manifest left no trace at all. It is a resource here
# (rules.md E-1), declared as a raw manifest through alekc/kubectl because it is a
# custom resource whose CRD arrives with the KEDA release in the same apply
# (rules.md E-2/E-3).
resource "kubectl_manifest" "trigger_authentication" {
  yaml_body = yamlencode({
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"
    metadata = {
      name      = var.trigger_authentication_name
      namespace = var.namespace
    }
    spec = {
      podIdentity = {
        provider = "aws"
        # identityOwner only, with no roleArn beside it. KEDA documents the two as
        # mutually exclusive, and the _monolithic template set both - so the
        # combination it shipped is unsupported. identityOwner keda is the right half
        # to keep here: the operator's own service account is the one the chart
        # annotates for IRSA, so the role is already reachable without naming it
        # again. Naming a roleArn instead would mean the operator assuming a second
        # role, which needs its own trust relationship.
        identityOwner = var.identity_owner
      }
    }
  })
}
# The variant. Scaling is driven by a CloudWatch metric published by the load balancer
# in front of the workload, so the signal comes from outside the cluster entirely -
# which is what separates this from the hpa variant, where the signal is the pods' own
# measured CPU.
resource "kubectl_manifest" "scaled_object" {
  yaml_body = yamlencode({
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      scaleTargetRef = {
        apiVersion = "apps/v1"
        kind       = var.scale_target_kind
        name       = var.scale_target_name
      }
      pollingInterval = var.polling_interval
      cooldownPeriod  = var.cooldown_period
      minReplicaCount = var.min_replica_count
      maxReplicaCount = var.max_replica_count
      triggers = [{
        type = "aws-cloudwatch"
        # Every value here is a string. KEDA's trigger metadata is a map[string]string,
        # so the numbers have to be quoted - yamlencode would otherwise emit them
        # unquoted and the CRD's schema rejects the object.
        metadata = {
          expression = local.metric_expression
          # Period of the query above. With 60, target_metric_value is a per-minute
          # figure.
          metricStatPeriod = tostring(var.metric_stat_period)
          # How far back to look. Larger than the period on purpose: CloudWatch is
          # eventually consistent, so the newest period is often still empty.
          metricCollectionTime = tostring(var.metric_collection_time)
          # KEDA divides the observed value by this to get a replica count.
          targetMetricValue = tostring(var.target_metric_value)
          minMetricValue    = tostring(var.min_metric_value)
          ignoreNullValues  = tostring(var.ignore_null_values)
          awsRegion         = var.aws_region
        }
        authenticationRef = {
          name = var.trigger_authentication_name
        }
      }]
    }
  })
  # authenticationRef names the TriggerAuthentication as a string rather than
  # referencing an attribute of it, so nothing else tells Terraform it has to exist
  # first (rules.md D-1). A ScaledObject whose authenticationRef is missing is
  # accepted and then fails to authenticate on every poll.
  depends_on = [kubectl_manifest.trigger_authentication]
}
