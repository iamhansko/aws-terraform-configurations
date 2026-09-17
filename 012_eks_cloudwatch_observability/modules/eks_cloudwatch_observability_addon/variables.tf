variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the amazon-cloudwatch-observability addon into"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Specific amazon-cloudwatch-observability addon version (e.g. v4.7.0-eksbuild.1). When null, EKS picks the default version for the cluster's Kubernetes version"
  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v4.7.0-eksbuild.1, or null."
  }
}
variable "service_account_name" {
  type        = string
  default     = "cloudwatch-agent"
  description = "Service account the CloudWatch agent runs as, and the one the Pod Identity association is created for. Fixed by the addon"
  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "namespace" {
  type        = string
  default     = "amazon-cloudwatch"
  description = "Namespace the addon installs into, which is where the Pod Identity association's service account lives"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
  description = "IAM managed policy ARNs attached to the CloudWatch agent's role. CloudWatchAgentServerPolicy covers both the Container Insights metrics the agent publishes and the log groups Fluent Bit creates"
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "container_log_components" {
  type = map(list(string))
  default = {
    "vpc-cni"                         = ["/var/log/containers/aws-node-*_kube-system_*.log"]
    "kube-proxy"                      = ["/var/log/containers/kube-proxy-*_kube-system_*.log"]
    "coredns"                         = ["/var/log/containers/coredns-*_kube-system_*.log"]
    "metrics-server"                  = ["/var/log/containers/metrics-server-*_kube-system_*.log"]
    "cluster-autoscaler"              = ["/var/log/containers/cluster-autoscaler-*_kube-system_*.log"]
    "aws-load-balancer-controller"    = ["/var/log/containers/aws-load-balancer-controller-*_kube-system_*.log"]
    "aws-efs-csi-driver"              = ["/var/log/containers/efs-csi-controller-*_kube-system_*.log", "/var/log/containers/efs-csi-node-*_kube-system_*.log"]
    "amazon-cloudwatch-observability" = ["/var/log/containers/amazon-cloudwatch-observability-controller-manager-*_amazon-cloudwatch_*.log", "/var/log/containers/cloudwatch-agent-*_amazon-cloudwatch_*.log", "/var/log/containers/fluent-bit-*_amazon-cloudwatch_*.log"]
  }
  description = "Per-component Fluent Bit log pipelines, keyed by component name with the container log paths to tail as the value. Each key produces one <name>.conf extra file with its own log group (/aws/eks/<cluster>/<name>), which is what separates a component's logs from everything else in CloudWatch Logs. A path glob matching no file costs nothing, so a key for a component that is not installed in this cluster is harmless - the pipeline simply stays idle"
  validation {
    condition     = alltrue([for name in keys(var.container_log_components) : can(regex("^[a-z0-9]([-.a-z0-9]*[a-z0-9])?$", name))])
    error_message = "container_log_components keys become Fluent Bit tags, log group names and state DB filenames, so each must be lowercase alphanumeric with dots or hyphens."
  }
  validation {
    condition     = alltrue([for paths in values(var.container_log_components) : length(paths) > 0])
    error_message = "container_log_components values must each list at least one log path."
  }
  validation {
    condition     = alltrue(flatten([for paths in values(var.container_log_components) : [for path in paths : can(regex("^/", path))]]))
    error_message = "container_log_components paths must be absolute (e.g. /var/log/containers/aws-node-*_kube-system_*.log)."
  }
}
variable "disable_default_container_logs" {
  type        = bool
  default     = true
  description = "Whether to blank out the addon's built-in application-log.conf and dataplane-log.conf pipelines. True by default because those two ship every container's stdout into two catch-all log groups, which duplicates everything the per-component pipelines above collect and buries it in the same stream. Set false to keep the addon's defaults alongside the custom pipelines"
}
variable "additional_extra_files" {
  type        = map(string)
  default     = {}
  description = "Additional Fluent Bit config files merged into the addon's extraFiles, keyed by filename (e.g. { \"my-app.conf\" = \"[INPUT]\\n...\" }). For pipelines that need more than the per-component template this module renders - a parser, say, or a non-container log source"
  validation {
    condition     = alltrue([for filename in keys(var.additional_extra_files) : can(regex("\\.conf$", filename))])
    error_message = "additional_extra_files keys must be Fluent Bit config filenames ending in .conf."
  }
}
variable "mem_buf_limit" {
  type        = string
  default     = "50MB"
  description = "Memory Fluent Bit may buffer per input before it pauses reading. Applies to every rendered pipeline"
  validation {
    condition     = can(regex("^[0-9]+(KB|MB|GB)$", var.mem_buf_limit))
    error_message = "mem_buf_limit must be a Fluent Bit size (e.g. 50MB)."
  }
}
variable "refresh_interval_seconds" {
  type        = number
  default     = 10
  description = "How often Fluent Bit rescans the log paths for newly created files"
  validation {
    condition     = var.refresh_interval_seconds > 0
    error_message = "refresh_interval_seconds must be greater than zero."
  }
}
variable "rotate_wait_seconds" {
  type        = number
  default     = 30
  description = "How long Fluent Bit keeps reading a rotated file before releasing it, so lines written during rotation are not lost"
  validation {
    condition     = var.rotate_wait_seconds > 0
    error_message = "rotate_wait_seconds must be greater than zero."
  }
}
variable "kubelet_port" {
  type        = number
  default     = 10250
  description = "Port the kubernetes filter queries for pod metadata. Reading from the local kubelet rather than the API server keeps the metadata lookups off the control plane"
  validation {
    condition     = var.kubelet_port > 0 && var.kubelet_port <= 65535
    error_message = "kubelet_port must be a valid TCP port."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when creating an addon that is migrating from a pre-existing self-managed installation"
  validation {
    condition     = contains(["NONE", "OVERWRITE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be one of: NONE, OVERWRITE."
  }
}
variable "resolve_conflicts_on_update" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when updating the addon"
  validation {
    condition     = contains(["NONE", "OVERWRITE", "PRESERVE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be one of: NONE, OVERWRITE, PRESERVE."
  }
}
