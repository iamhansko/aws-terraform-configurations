variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name" {
  type        = string
  default     = "kubecost-cluster"
  description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns, so the pre-created load balancer carries the same value (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "Kubernetes version for the EKS cluster"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.33."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the kubectl and helm providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2); the _monolithic template had this true as well, driving the same charts from an SSM Association on the bastion. Narrow public_access_cidrs rather than leaving the default open"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoint. Set this to your own address in CIDR form: bootstrap_cluster_creator_admin_permissions means anyone who can reach this endpoint with a valid AWS credential for the creating principal has cluster-admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "kubecost-key"
  description = "Name of the EC2 key pair created for the demo instances"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "public_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/elb" = "1"
  }
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets' (rules.md G-1)"

  validation {
    condition = alltrue([
      for key, value in var.public_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "public_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer. A misspelled key is not rejected by AWS, so the failure surfaces much later as a controller that cannot auto-discover subnets (rules.md G-1)."
  }
}
variable "private_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  description = "Tags merged into every private subnet, used the same way for internal load balancers (rules.md G-1)"

  validation {
    condition = alltrue([
      for key, value in var.private_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "private_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer. A misspelled key is not rejected by AWS, so the failure surfaces much later as a controller that cannot auto-discover subnets (rules.md G-1)."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count. Two, because Kubecost brings its own Prometheus alongside the cost analyzer and the ingress controller"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
}
variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the StorageClass created for the EBS CSI driver and marked cluster-default. Kubecost's bundled Prometheus claims a volume without naming a class, so the default is what it gets"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "kubecost_namespace" {
  type        = string
  default     = "kubecost"
  description = "Namespace holding Kubecost and its ingress controller. Also the first half of the load balancer's stack tag, which is why it has to match what the pre-created load balancer carries (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.kubecost_namespace))
    error_message = "kubecost_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_release_name" {
  type        = string
  default     = "ingress-nginx"
  description = "Helm release name for the ingress controller. The chart derives its Service name from this as <release>-ingress-nginx-controller, and that Service name is half of the stack tag the pre-created load balancer must carry to be adopted (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_release_name))
    error_message = "ingress_release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_nginx_chart_version" {
  type        = string
  default     = "4.13.0"
  description = "Pinned ingress-nginx chart version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.ingress_nginx_chart_version))
    error_message = "ingress_nginx_chart_version must be a semantic version."
  }
}
variable "kubecost_chart_version" {
  type        = string
  default     = "2.8.3"
  description = "Pinned Kubecost version. Also builds the URL of the upstream values-eks-cost-monitoring.yaml the chart is layered with, so the two cannot end up at different versions"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubecost_chart_version))
    error_message = "kubecost_chart_version must be a semantic version, e.g. 2.8.3."
  }
}
variable "kubecost_basic_auth_user" {
  type        = string
  default     = "kubecost"
  description = "Username for the dashboard's HTTP basic auth"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.kubecost_basic_auth_user))
    error_message = "kubecost_basic_auth_user must be letters, digits, dots, underscores or hyphens - it goes into a colon-separated htpasswd line."
  }
}
variable "kubecost_basic_auth_password" {
  type        = string
  sensitive   = true
  description = "Password for the dashboard's HTTP basic auth. No default on purpose: the _monolithic template defaulted both the user and the password to 'kubecost', which is a working credential for an internet-facing dashboard committed to the repository. Pass it with TF_VAR_kubecost_basic_auth_password"

  validation {
    condition     = length(var.kubecost_basic_auth_password) >= 8
    error_message = "kubecost_basic_auth_password must be at least 8 characters."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because nothing here relies on it: the only Service of that type is the one the ingress-nginx chart creates, and it names the controller itself through the aws-load-balancer-type: external annotation (rules.md G-1). Nothing races the controller as the modules are ordered today - kubecost sits behind module.ingress_nginx, which sits behind the controller - but the chart gives this webhook failurePolicy: Fail and no namespaceSelector, so leaving it on makes that chain load-bearing for a reason unrelated to why it exists, and keeps gating every Service created later in the cluster's life, including during a controller rollout or after a node replacement, when the answer is \"no endpoints available for service aws-load-balancer-webhook-service\""

  validation {
    # The constraint is real rather than stylistic, so it belongs here and not in the
    # description (rules.md B-1). The failure it prevents names the webhook rather than
    # the release that tripped over it, which is a long way from the cause.
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. The one Service of type LoadBalancer here sets aws-load-balancer-type: external, so the controller claims it without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster and fails any release installing Services while the controller has no Ready pod. To run with it true, order every module that creates a Service after module.aws_load_balancer_controller, and note that only covers the apply, not a later controller rollout (rules.md G-4)."
  }
}
variable "load_balancer_port" {
  type        = number
  default     = 80
  description = "Port the ingress controller and its load balancer listen on"

  validation {
    condition     = var.load_balancer_port > 0 && var.load_balancer_port <= 65535
    error_message = "load_balancer_port must be between 1 and 65535."
  }
}
variable "load_balancer_security_group_name" {
  type        = string
  default     = "kubecost-nlb-sg"
  description = "Name of the frontend security group attached to the pre-created NLB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.load_balancer_security_group_name)) && !startswith(var.load_balancer_security_group_name, "sg-")
    error_message = "load_balancer_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group and the load balancer security group accept traffic from 0.0.0.0/0. False by default: the dashboard exposes the cluster's cost and workload inventory, and basic auth is the only thing in front of it"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the VS Code instance where the bootstrap drops its completion marker. The README association waits for that marker instead of trusting depends_on (rules.md D-5/H-2)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README SSM association may take. It first waits for the instance bootstrap to finish, which includes downloading kubectl, eksctl and helm"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
