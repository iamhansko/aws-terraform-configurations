variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "cluster_name" {
  type        = string
  default     = "stem-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9\\-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "EKS cluster Kubernetes version (1.XX)"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.31, 1.32, 1.33."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. True here, unlike the _monolithic template: the kubectl provider that declares the logging ConfigMap runs from the machine executing terraform apply rather than from inside the VPC (rules.md E-2). Restrict access with public_access_cidrs rather than leaving it open"

  validation {
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this configuration. The aws-observability ConfigMap is declared with the kubectl provider, which connects from wherever terraform runs; with a private-only endpoint the apply fails on that resource. To run with a private endpoint, drop the fargate_fluentbit_logging module and apply its two manifests from the bastion instead - which is what the _monolithic template did (rules.md E-2)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint. Set this to your own address in CIDR form (e.g. [\"203.0.113.4/32\"]) instead of leaving the default: bootstrap_cluster_creator_admin_permissions grants anyone who can reach this endpoint with the creating AWS identity full cluster admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "stem-key"
  description = "Name of the EC2 key pair created for the VS Code instance"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "create_demo_workload" {
  type        = bool
  default     = true
  description = "Whether Terraform creates the web and stress pods. False leaves the cluster, the Fargate profile and the whole log pipeline in place with nothing producing records - which is how to stop the Fargate per-pod charge without destroying the project, and how to watch a pod get scheduled onto Fargate yourself: apply with this false, then set it true and watch. The pods are resources either way, so deleting them with kubectl only gets them recreated on the next apply"
}
variable "app_namespace" {
  type        = string
  default     = "app-fargate"
  description = "Namespace the demo workload runs in. The Fargate profile selects it, so every pod created there runs on Fargate and gets the Fluent Bit log router"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.app_namespace))
    error_message = "app_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "app_fargate_profile_name" {
  type        = string
  default     = "app-fargate"
  description = "Name of the Fargate profile selecting app_namespace"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.app_fargate_profile_name))
    error_message = "app_fargate_profile_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}
variable "kubesystem_fargate_profile_name" {
  type        = string
  default     = "kubesystem-fargate"
  description = "Name of the Fargate profile selecting kube-system. Not in the _monolithic template, which left the cluster with nowhere to run CoreDNS - so DNS never came up and the demo's stress pod had to reach nginx by IP"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.kubesystem_fargate_profile_name))
    error_message = "kubesystem_fargate_profile_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}
variable "firehose_delivery_stream_name" {
  type        = string
  default     = "firehose-deliverystream"
  description = "Name of the Firehose delivery stream Fluent Bit writes every pod log record into"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,64}$", var.firehose_delivery_stream_name))
    error_message = "firehose_delivery_stream_name must be 1-64 characters of letters, digits, underscores, dots or hyphens."
  }
}
variable "destination_bucket_prefix" {
  type        = string
  default     = "stem-fargate-logs-"
  description = "Prefix for the generated S3 bucket Firehose delivers to. The _monolithic template let CloudFormation generate the whole name; a prefix keeps that uniqueness while making the bucket recognisable"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,37}$", var.destination_bucket_prefix))
    error_message = "destination_bucket_prefix must be lowercase alphanumeric with dots or hyphens, 2-38 characters, starting with a letter or digit."
  }
}
variable "destination_bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the destination bucket while it still holds delivered log objects. True, because otherwise the destroy stops on a non-empty bucket and has to be finished by hand"
}
variable "firehose_buffering_interval_seconds" {
  type        = number
  default     = 60
  description = "How long Firehose waits before writing an object even when the 5 MB size threshold is not met. 60 rather than the 300-second default: at demo volumes nothing would land in the bucket for five minutes, which reads as a broken pipeline"

  validation {
    condition     = var.firehose_buffering_interval_seconds >= 0 && var.firehose_buffering_interval_seconds <= 900
    error_message = "firehose_buffering_interval_seconds must be between 0 and 900."
  }
}
variable "include_kubernetes_filter" {
  type        = bool
  default     = false
  description = "Whether Fluent Bit attaches pod metadata (name, namespace, labels) to each record. False reproduces the _monolithic template for this variant, whose ConfigMap had no filters at all - so delivered objects contain the raw container log line and nothing identifying the pod"
}
variable "log_match" {
  type        = string
  default     = "*"
  description = "Fluent Bit tag pattern the single OUTPUT block matches. '*' is what this variant demonstrates - every pod's records go to one stream, with no per-application routing. The CloudWatch variant (020) instead runs a rewrite_tag filter and matches on pod labels"

  validation {
    condition     = length(var.log_match) > 0
    error_message = "log_match must not be empty."
  }
}
variable "flb_log_cw" {
  type        = bool
  default     = true
  description = "Whether Fluent Bit ships its own process log to CloudWatch. True rather than the _monolithic template's omitted key, which is a deliberate departure: this is the only channel that reports a rejected PutRecordBatch, and with it off a permissions problem looks identical to the log router never having started - the bucket stays empty and the delivery stream reports zero IncomingRecords either way. Setting it true also adds the CloudWatch statement to the pod execution role's policy, since the router needs to be able to write it"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) on the VS Code EC2 instance from 0.0.0.0/0, as the _monolithic template did. Leave false and use SSM Session Manager port forwarding for anything but a short-lived demo"
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the VS Code EC2 instance, from the amazon-eks S3 bucket layout (<version>/<date>). Keep within one minor of kubernetes_version or the client falls outside the supported skew"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas"

  validation {
    condition     = var.coredns_replica_count > 0
    error_message = "coredns_replica_count must be greater than zero."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module (which touches <path>/userdata as the last step of its user data) and the SSM association that writes the README once it appears (rules.md D-5/H-2). Under /run so the markers vanish on reboot rather than making a stale file look like a completed bootstrap"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM association waits for the README command to report success. It has to cover the whole instance bootstrap, since the command's first act is to wait for the user data marker file"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be greater than zero."
  }
}
