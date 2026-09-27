variable "name" {
  type        = string
  default     = "cloudwatch-scaled-object"
  description = "Name of the ScaledObject"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "namespace" {
  type        = string
  description = "Namespace both objects are created in. Must be the namespace of the workload being scaled: a ScaledObject can only target a workload in its own namespace, and a TriggerAuthentication is namespaced too, so a cross-namespace reference would need the cluster-scoped ClusterTriggerAuthentication instead"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "trigger_authentication_name" {
  type        = string
  default     = "aws-trigger-auth"
  description = "Name of the TriggerAuthentication the ScaledObject references"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.trigger_authentication_name))
    error_message = "trigger_authentication_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "operator_role_arn" {
  type        = string
  description = "ARN of the IAM role the scaler authenticates as. Handed over as an ARN, so this module never learns which module created it (rules.md B-6)"
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/", var.operator_role_arn))
    error_message = "operator_role_arn must be an IAM role ARN."
  }
}
variable "identity_owner" {
  type        = string
  default     = "keda"
  description = "Whose identity the scaler uses. keda means the KEDA operator's own service account, which is the one wired for IRSA; workload would make KEDA use the scaled workload's service account instead, and that one has no AWS role attached here - a mismatch shows up as an authentication failure in the operator log rather than at apply time"
  validation {
    condition     = contains(["keda", "workload"], var.identity_owner)
    error_message = "identity_owner must be keda or workload."
  }
}
variable "scale_target_name" {
  type        = string
  description = "Name of the Deployment the ScaledObject resizes. It must be in the same namespace, and a target that does not exist is accepted and simply never scaled"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.scale_target_name))
    error_message = "scale_target_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "scale_target_kind" {
  type        = string
  default     = "Deployment"
  description = "Kind of the scale target"
  validation {
    condition     = contains(["Deployment", "StatefulSet", "ReplicaSet"], var.scale_target_kind)
    error_message = "scale_target_kind must be Deployment, StatefulSet or ReplicaSet."
  }
}
variable "aws_region" {
  type        = string
  description = "Region the CloudWatch metric is read from. It has to be the region the load balancer publishes into; a scaler pointed at the wrong region gets an empty result rather than an error, and an empty result is treated as zero load"
  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region, e.g. ap-northeast-2."
  }
}
variable "load_balancer_arn_suffix" {
  type        = string
  description = "The app/<name>/<id> tail of the load balancer ARN, which is how CloudWatch names it in the LoadBalancer dimension. Not the full ARN: a query built from the ARN matches no metric, and matching nothing looks exactly like no traffic"
  validation {
    condition     = can(regex("^(app|net)/[a-zA-Z0-9-]+/[a-z0-9]+$", var.load_balancer_arn_suffix))
    error_message = "load_balancer_arn_suffix must look like app/my-lb/0123456789abcdef, the arn_suffix of an aws_lb rather than its arn."
  }
}
variable "metric_namespace" {
  type        = string
  default     = "AWS/ApplicationELB"
  description = "CloudWatch namespace the metric lives in. AWS/ApplicationELB for an ALB; a network load balancer publishes to AWS/NetworkELB with different metric names"
  validation {
    condition     = length(var.metric_namespace) > 0
    error_message = "metric_namespace must not be empty."
  }
}
variable "metric_name" {
  type        = string
  default     = "RequestCount"
  description = "Metric the scaler reads. RequestCount is requests per period, which is why the target value below is read together with metric_stat_period"
  validation {
    condition     = length(var.metric_name) > 0
    error_message = "metric_name must not be empty."
  }
}
variable "metric_aggregation" {
  type        = string
  default     = "SUM"
  description = "Aggregate function the Metrics Insights query applies to the metric. SUM, which totals the requests in each period. The _monolithic template used COUNT, and that is not a smaller version of the same thing: COUNT returns how many observations matched, which for one load balancer at one-minute granularity is 1 per period - so the query returned 1 against a target of 100 and the workload could never scale, with no error anywhere to say so"
  validation {
    condition     = contains(["SUM", "AVG", "MAX", "MIN", "COUNT"], var.metric_aggregation)
    error_message = "metric_aggregation must be one of SUM, AVG, MAX, MIN or COUNT, the aggregate functions CloudWatch Metrics Insights accepts. COUNT counts observations rather than summing them, so it is almost never what a request-count trigger wants."
  }
}
variable "metric_stat_period" {
  type        = number
  default     = 60
  description = "Seconds each aggregation covers, which becomes the query's Period. 60 is the finest granularity ALB metrics are published at, so a shorter period returns gaps rather than fresher numbers. It also sets the scale of target_metric_value: with 60, that target is requests per minute"
  validation {
    condition     = contains([1, 5, 10, 30], var.metric_stat_period) || var.metric_stat_period % 60 == 0
    error_message = "metric_stat_period must be 1, 5, 10, 30 or a multiple of 60, as CloudWatch requires."
  }
}
variable "metric_collection_time" {
  type        = number
  default     = 300
  description = "How far back the scaler queries, in seconds. It must be larger than metric_stat_period - two or three times larger in practice - because CloudWatch is eventually consistent and the most recent period is often still empty; the scaler uses the newest datapoint it gets back"
  validation {
    condition     = var.metric_collection_time > 0
    error_message = "metric_collection_time must be positive."
  }
}
variable "ignore_null_values" {
  type        = bool
  default     = true
  description = "What to do when the query returns no datapoints. True substitutes min_metric_value, which reads as no load; false makes the scaler report an error and leave the replica count alone. True is the gentler default but it hides a broken query - a wrong region or a load balancer identifier that matches nothing looks exactly like an idle service"
}
variable "target_metric_value" {
  type        = number
  default     = 100
  description = "Requests per period each replica is expected to absorb. KEDA divides the observed value by this to get a replica count, so with the defaults 100 requests per minute asks for one replica and 500 asks for five"
  validation {
    condition     = var.target_metric_value > 0
    error_message = "target_metric_value must be positive."
  }
}
variable "min_metric_value" {
  type        = number
  default     = 0
  description = "Value substituted when CloudWatch returns no datapoint. Zero, which reads as no load - worth knowing, because a metric query that matches nothing at all is indistinguishable from genuine idleness"
  validation {
    condition     = var.min_metric_value >= 0
    error_message = "min_metric_value must not be negative."
  }
}
variable "polling_interval" {
  type        = number
  default     = 30
  description = "Seconds between metric queries. Every poll is a CloudWatch GetMetricData call, and those are billed, so a short interval on many ScaledObjects has a cost"
  validation {
    condition     = var.polling_interval > 0
    error_message = "polling_interval must be positive."
  }
}
variable "cooldown_period" {
  type        = number
  default     = 300
  description = "Seconds of no activity before scaling back to the floor. It only governs the return to minReplicaCount; intermediate scale-downs follow the HorizontalPodAutoscaler's own stabilisation window, which is why a scale-down can appear slower than this suggests"
  validation {
    condition     = var.cooldown_period > 0
    error_message = "cooldown_period must be positive."
  }
}
variable "min_replica_count" {
  type        = number
  default     = 1
  description = "Floor. One rather than zero: scaling to zero would leave no pod for the load balancer to send the request that would generate the metric, so the metric would stay at zero and nothing would ever scale back up"
  validation {
    condition     = var.min_replica_count >= 0
    error_message = "min_replica_count must not be negative."
  }
}
variable "max_replica_count" {
  type        = number
  default     = 10
  description = "Ceiling, 10 as the _monolithic template set it"
  validation {
    condition     = var.max_replica_count >= 1
    error_message = "max_replica_count must be at least 1."
  }
  validation {
    condition     = var.max_replica_count >= var.min_replica_count
    error_message = "max_replica_count must be greater than or equal to min_replica_count."
  }
}
