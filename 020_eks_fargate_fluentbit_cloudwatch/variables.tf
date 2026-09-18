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
variable "log_sinks" {
  type = map(object({
    match          = string
    log_group_name = string
  }))
  default = {
    web = {
      match          = "app-web*"
      log_group_name = "/fargate/web"
    }
    stress = {
      match          = "app-stress*"
      log_group_name = "/fargate/stress"
    }
  }
  description = "CloudWatch destinations, one Fluent Bit OUTPUT block per entry. The key is the pod's app label: a pod labelled app=web matches the app-web* tag the rewrite_tag filter builds. Two entries by default so the demo shows logs from two workloads landing in two separate groups"

  validation {
    condition     = length(var.log_sinks) > 0
    error_message = "log_sinks must contain at least one entry."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 60
  description = "Retention Fluent Bit sets on the log groups it creates"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "flb_log_cw" {
  type        = bool
  default     = false
  description = "Whether Fluent Bit ships its own process log to CloudWatch. Turn on when the workload's logs never arrive and the question is whether Fluent Bit started at all"
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
