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
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. Needed because the helm and kubectl providers run from the machine executing terraform apply rather than from inside the VPC (rules.md E-1/E-2); the _monolithic design instead ran helm and kubectl from the bastion inside the VPC, which is why the underlying eks_cluster module still defaults this to false. Restrict access with public_access_cidrs rather than leaving it open to 0.0.0.0/0"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint when endpoint_public_access is true. Set this to your own address in CIDR form (e.g. [\"203.0.113.4/32\"]) instead of leaving the default: bootstrap_cluster_creator_admin_permissions grants anyone who can reach this endpoint with the creating AWS identity full cluster admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "stem-key"
  description = "Name of the EC2 key pair created for the VS Code instance and the worker nodes"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "node_group_name" {
  type        = string
  default     = "app-mng"
  description = "Name of the EKS managed node group"

  validation {
    condition     = length(var.node_group_name) > 0
    error_message = "node_group_name must not be empty."
  }
}
variable "node_group_labels" {
  type        = map(string)
  default     = { "mng/dedicated" = "app" }
  description = "Kubernetes labels applied to the managed node group's nodes"

  validation {
    condition     = alltrue([for key in keys(var.node_group_labels) : length(key) > 0])
    error_message = "node_group_labels must not contain empty Kubernetes label keys."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for the EKS managed node group"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired number of worker nodes"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum number of worker nodes"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum number of worker nodes"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}
variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Version of the aws-load-balancer-controller Helm chart"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a semantic version (e.g. 1.14.1)."
  }
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
  description = "Whether to allow inbound access to the code-server port (8000) on the VS Code EC2 instance from 0.0.0.0/0. Leave false and use SSM Session Manager port forwarding for anything but a short-lived demo"
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the VS Code EC2 instance, from the amazon-eks S3 bucket layout (<version>/<date>)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "nlb_security_group_name" {
  type        = string
  default     = "nlb-sg"
  description = "Name of the frontend security group handed to the controller through the Service's service.beta.kubernetes.io/aws-load-balancer-security-groups annotation"

  validation {
    condition     = length(var.nlb_security_group_name) > 0
    error_message = "nlb_security_group_name must not be empty."
  }
}
variable "nlb_target_type" {
  type        = string
  default     = "ip"
  description = "How the NLB reaches pods. Only 'ip' is accepted here: registering pod IPs directly means the traffic arrives on the pod's container port, a port Terraform knows and can therefore open on the cluster security group itself, and it also preserves the client source address without proxy protocol. 'instance' would route through a NodePort Kubernetes assigns at random from 30000-32767, and because this configuration stops the controller from managing the node-side rules (enable_backend_security_group = false, rules.md G-2) nothing would open that port - the only rule Terraform could express is the whole ephemeral range. To use instance targets, hand those rules back to the controller: set enable_backend_security_group = true and add the manage-backend-security-group-rules annotation to the Service"

  validation {
    condition     = var.nlb_target_type == "ip"
    error_message = "nlb_target_type must be ip in this configuration. The rule that lets the NLB reach the pods is declared in Terraform (load_balancer_to_pods in main.tf), because enable_backend_security_group is false and the Service sets no manage-backend-security-group-rules annotation - so the port has to be one Terraform can name, and an instance target's NodePort is assigned at random from 30000-32767. To use instance targets, set enable_backend_security_group = true and add the service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules annotation so the controller writes those rules itself (rules.md G-2)."
  }
}
variable "kube_ops_view_image_tag" {
  type        = string
  default     = "23.5.0"
  description = "Container image tag for the kube-ops-view dashboard. 23.5.0 is the last upstream release. Replaces the previous kube_ops_view_chart_version: the dashboard is declared as manifests now, because no dependable Helm chart exists for it and the maintained community chart silently drops Service annotations - which this variant depends on"

  validation {
    condition     = length(var.kube_ops_view_image_tag) > 0
    error_message = "kube_ops_view_image_tag must not be empty."
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
variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the AWS Load Balancer Controller uses a shared backend security group (the k8s-traffic-<cluster>-<hash> group it creates, attaches to every load balancer, and names as the traffic source in the rules it adds to node/ENI security groups). False in this variant, as in all of them: the workload supplies its own frontend security group but sets no manage-backend-security-group-rules annotation, so the controller writes no node-side rules and needs no shared group to name as their source. The load balancer carries only the frontend security group this configuration declares, and the path from it to the pods is the load_balancer_to_pods rule on the cluster security group in main.tf. Setting that annotation while this is false is the combination the controller rejects, and it then provisions nothing at all. The trade-off is a rule per load balancer on the cluster security group instead of one shared rule, which only matters once there are many (rules.md G-2)"
}
