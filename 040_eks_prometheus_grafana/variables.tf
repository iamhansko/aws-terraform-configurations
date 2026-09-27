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
  default     = "prometheus-grafana-cluster"
  description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find its own load balancers, so a pre-created load balancer has to carry the same value (rules.md G-3)"

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
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl outside one minor version of the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the kubectl and helm providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2); the _monolithic template had this true as well, driving the same charts from an SSM Association on the bastion instead. Narrow public_access_cidrs rather than leaving the default open"
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
  default     = "prometheus-grafana-key"
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
  description = "Desired node count. Two because the monitoring stack alone schedules Prometheus, Alertmanager, Grafana and three ingress controllers"

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
  description = "Name of the StorageClass created for the EBS CSI driver and marked cluster-default. Prometheus and Alertmanager request volumes without naming a class, so the default is what they get"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "monitoring_namespace" {
  type        = string
  default     = "monitoring"
  description = "Namespace holding the monitoring stack and its three ingress controllers"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.monitoring_namespace))
    error_message = "monitoring_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_controllers" {
  type = map(object({
    release_name          = string
    ingress_class_name    = string
    ingress_class_value   = string
    load_balancer_sg_name = string
    readme_order          = number
  }))
  default = {
    grafana = {
      release_name          = "grafana-ingress-nginx"
      ingress_class_name    = "grafana-ingress"
      ingress_class_value   = "ingress.nginx/grafana"
      load_balancer_sg_name = "grafana-nlb-sg"
      readme_order          = 1
    }
    prometheus = {
      release_name          = "prometheus-ingress-nginx"
      ingress_class_name    = "prometheus-ingress"
      ingress_class_value   = "ingress.nginx/prometheus"
      load_balancer_sg_name = "prometheus-nlb-sg"
      readme_order          = 2
    }
    alertmanager = {
      release_name          = "alertmanager-ingress-nginx"
      ingress_class_name    = "alertmanager-ingress"
      ingress_class_value   = "ingress.nginx/alertmanager"
      load_balancer_sg_name = "alertmanager-nlb-sg"
      readme_order          = 3
    }
  }
  description = "The three ingress-nginx controllers, one per monitoring UI, keyed by a caller-chosen label. Each needs its own IngressClass name and controller value, because an Ingress picks its controller by class and two controllers sharing a controller value both reconcile both classes. Keys are static so they can drive for_each (rules.md B-8)"

  validation {
    condition     = length(var.ingress_controllers) > 0
    error_message = "ingress_controllers must contain at least one entry."
  }
  validation {
    condition     = length(distinct([for c in values(var.ingress_controllers) : c.ingress_class_value])) == length(var.ingress_controllers)
    error_message = "Each ingress_controllers entry needs a unique ingress_class_value. Two controllers sharing one value makes both of them reconcile both classes and fight over each Ingress's status."
  }
  validation {
    condition     = alltrue([for k in keys(var.ingress_controllers) : can(regex("^[a-z0-9-]+$", k))])
    error_message = "ingress_controllers keys are used in resource addresses and security group descriptions, so each must be lowercase alphanumeric with hyphens (rules.md F-1)."
  }
}
variable "ingress_nginx_chart_version" {
  type        = string
  default     = "4.13.0"
  description = "Pinned ingress-nginx chart version, shared by all three controllers"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.ingress_nginx_chart_version))
    error_message = "ingress_nginx_chart_version must be a semantic version."
  }
}
variable "prometheus_storage_size" {
  type        = string
  default     = "20Gi"
  description = "Size of the Prometheus persistent volume. Named at the root because it is not optional once a StorageClass is in play: the chart defaults it to nothing, and a claim template without a size is rejected only later, when the StatefulSet controller tries to create the pod (rules.md B-3)"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.prometheus_storage_size))
    error_message = "prometheus_storage_size must be a Kubernetes storage quantity such as 20Gi."
  }
}
variable "alertmanager_storage_size" {
  type        = string
  default     = "5Gi"
  description = "Size of the Alertmanager persistent volume"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.alertmanager_storage_size))
    error_message = "alertmanager_storage_size must be a Kubernetes storage quantity such as 5Gi."
  }
}
variable "kube_prometheus_stack_chart_version" {
  type        = string
  default     = "77.14.0"
  description = "Pinned kube-prometheus-stack chart version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kube_prometheus_stack_chart_version))
    error_message = "kube_prometheus_stack_chart_version must be a semantic version."
  }
}
variable "grafana_admin_user" {
  type        = string
  default     = "admin"
  description = "Grafana admin username"

  validation {
    condition     = length(var.grafana_admin_user) > 0
    error_message = "grafana_admin_user must not be empty."
  }
}
variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  description = "Grafana admin password. No default on purpose: the _monolithic template defaulted it to prom-operator and printed it in an output, which put a working credential for an internet-facing Grafana into the plan, the state file and the instance README. Pass it with TF_VAR_grafana_admin_password"

  validation {
    condition     = length(var.grafana_admin_password) >= 8
    error_message = "grafana_admin_password must be at least 8 characters."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because nothing here relies on it: the only Service of that type is the one the ingress-nginx chart creates, and it names the controller itself through the aws-load-balancer-type: external annotation (rules.md G-1). Nothing races the controller as the modules are ordered today - kube_prometheus_stack sits behind module.ingress_nginx, which sits behind the controller - but the chart gives this webhook failurePolicy: Fail and no namespaceSelector, so leaving it on makes that chain load-bearing for a reason unrelated to why it exists, and keeps gating every Service created later in the cluster's life, including during a controller rollout or after a node replacement, when the answer is \"no endpoints available for service aws-load-balancer-webhook-service\""

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
  description = "Port the ingress controllers and their load balancers listen on"

  validation {
    condition     = var.load_balancer_port > 0 && var.load_balancer_port <= 65535
    error_message = "load_balancer_port must be between 1 and 65535."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group and the load balancer security groups accept traffic from 0.0.0.0/0. False by default; the monitoring UIs have no authentication in front of them beyond Grafana's own login, so opening them to the internet exposes Prometheus and Alertmanager to anyone"
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
