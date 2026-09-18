variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "nma"
  description = "Prefix for the resources' Name tags and for every cluster name (\"nma\" produces nma-vpc, nma-fork-failed-out-of-pid, ...)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric, optionally with hyphens."
  }
}
variable "scenarios" {
  type = map(object({
    cluster_suffix = string
    node_name      = string
    condition      = string
    description    = string
  }))
  default = {
    fork_failed_out_of_pid = {
      cluster_suffix = "fork-failed-out-of-pid"
      node_name      = "ForkFailedOutOfPID-Node"
      condition      = "ForkFailedOutOfPID"
      description    = "The kernel refuses to fork because the PID cgroup is exhausted. Reproduce by starting more processes than pids.max allows on a node"
    }
    interface_not_up = {
      cluster_suffix = "interface-not-up"
      node_name      = "InterfaceNotUp-Node"
      condition      = "InterfaceNotUp"
      description    = "A network interface the CNI depends on is down. Reproduce with 'ip link set <iface> down' on a node"
    }
    ipamd_not_ready = {
      cluster_suffix = "ipamd-not-ready"
      node_name      = "IPAMDNotReady-Node"
      condition      = "IPAMDNotReady"
      description    = "The VPC CNI's IP address manager is not answering, so no pod can get an address. Reproduce by stopping the aws-node pod's ipamd"
    }
    missing_loopback_interface = {
      cluster_suffix = "missing-loopback-interface"
      node_name      = "MissingLoopbackInterface-Node"
      condition      = "MissingLoopbackInterface"
      description    = "A container namespace has no lo interface, which breaks anything talking to itself. Reproduce by deleting lo inside a pod namespace"
    }
    pod_stuck_terminating = {
      cluster_suffix = "pod-stuck-terminating"
      node_name      = "PodStuckTerminating-Node"
      condition      = "PodStuckTerminating"
      description    = "A pod stays in Terminating because the runtime cannot reap it. Reproduce with a container that ignores SIGTERM and a finalizer"
    }
    xfs_small_average_cluster_size = {
      cluster_suffix = "xfs-small-average-cluster-size"
      node_name      = "XfsSmallAverageClusterSize-Node"
      condition      = "XfsSmallAverageClusterSize"
      description    = "The XFS filesystem is fragmented enough that allocation slows down. Reproduce by filling and deleting many small files"
    }
  }
  description = "One EKS cluster per entry, each demonstrating a different condition the EKS Node Monitoring Agent reports. The _monolithic template wrote all six out by hand - six clusters, six node groups, six launch templates, thirty-six addons - and they differed only in these four strings. Keys are literals in the configuration, so they are known at plan time and safe as for_each keys (rules.md B-8)"

  validation {
    condition     = length(var.scenarios) > 0
    error_message = "scenarios must contain at least one entry."
  }
  validation {
    condition     = alltrue([for k in keys(var.scenarios) : can(regex("^[a-z0-9_]+$", k))])
    error_message = "scenarios keys become part of Terraform resource addresses, so each must be lowercase alphanumeric with underscores."
  }
  validation {
    condition     = alltrue([for s in values(var.scenarios) : can(regex("^[a-z0-9-]+$", s.cluster_suffix))])
    error_message = "scenarios[*].cluster_suffix becomes part of an EKS cluster name, so it must be lowercase alphanumeric with hyphens."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "Kubernetes version for every cluster. The _monolithic template pinned 1.32 on the clusters while its staged Karpenter script exported K8S_VERSION=1.33 - one variable removes that disagreement"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.31, 1.32, 1.33."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC shared by every cluster"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "key_name" {
  type        = string
  default     = "nma-key"
  description = "Name of the EC2 key pair created for the bastion and every node group"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for every scenario's managed node group"

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must contain at least one instance type."
  }
}
variable "node_desired_size" {
  type        = number
  default     = 3
  description = "Nodes per scenario. Three, as the _monolithic template had it: enough that a condition on one node is visibly different from the other two. Six scenarios at three nodes each is eighteen instances, which is the running cost of this project"

  validation {
    condition     = var.node_desired_size > 0
    error_message = "node_desired_size must be greater than zero."
  }
}
variable "enable_node_repair" {
  type        = bool
  default     = true
  description = "Whether the managed node groups replace a node the Node Monitoring Agent reports as unhealthy. True, as the _monolithic template had it - this is the behaviour the agent exists to drive, and with it off the demo shows a detected condition and no reaction"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the bastion"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) from 0.0.0.0/0, as the _monolithic template did. Leave false and use SSM Session Manager port forwarding for anything but a short-lived demo"
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the bastion"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module and the SSM association that writes the README once it appears (rules.md D-5/H-2)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM association waits for the README command to report success"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be greater than zero."
  }
}
variable "cloudwatch_observability_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess",
  ]
  description = "Managed policies on the role the CloudWatch agent assumes through Pod Identity. Attached with for_each rather than one resource per policy (rules.md B-7)"

  validation {
    condition     = alltrue([for arn in var.cloudwatch_observability_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "cloudwatch_observability_policy_arns must contain valid IAM policy ARNs."
  }
  validation {
    condition     = contains(var.cloudwatch_observability_policy_arns, "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy")
    error_message = "cloudwatch_observability_policy_arns must include CloudWatchAgentServerPolicy. Without it the agent starts and every PutLogEvents fails with AccessDenied, so the log group is never created and the demo looks like the agent detected nothing."
  }
}
