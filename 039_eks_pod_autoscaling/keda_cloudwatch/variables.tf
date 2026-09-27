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
  default     = "keda-cloudwatch"
  description = "Name of the EKS cluster"
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
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the helm and kubectl providers in providers.tf install KEDA, the load balancer controller and the workload from wherever terraform runs, and all of them have to reach the API server from there. Set it false only together with moving that work onto the bastion, which is what 041_eks_private_cluster does"
  validation {
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the keda, aws_load_balancer_controller, nginx_workload and keda_scaled_object modules are applied from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does."
  }
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
  default     = "keda-cloudwatch-key"
  description = "Name of the EC2 key pair created for the demo instances"
  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "keda_chart_version" {
  type        = string
  default     = "2.17.2"
  description = "KEDA chart version, as the _monolithic template pinned it in KEDA_CHART_VERSION"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.keda_chart_version))
    error_message = "keda_chart_version must be a semver version, e.g. 2.17.2."
  }
}
variable "keda_namespace" {
  type        = string
  default     = "keda"
  description = "Namespace KEDA runs in. It is half of the service account subject in the operator role's trust policy, so changing it changes which pod may assume that role"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.keda_namespace))
    error_message = "keda_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "keda_operator_role_name" {
  type        = string
  default     = "keda-operator-role"
  description = "Name of the IAM role the KEDA operator assumes through IRSA to read CloudWatch"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.keda_operator_role_name))
    error_message = "keda_operator_role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "scaled_object_name" {
  type        = string
  default     = "cloudwatch-scaled-object"
  description = "Name of the ScaledObject. KEDA derives the HorizontalPodAutoscaler's name from it as keda-hpa-<this>"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.scaled_object_name))
    error_message = "scaled_object_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "scaler_target_metric_value" {
  type        = number
  default     = 100
  description = "Requests per period each replica is expected to absorb, 100 as the _monolithic template set it. KEDA divides the observed request count by this to get a replica count, so it is read together with scaler_metric_stat_period: at 60 seconds, 100 means 100 requests per minute per replica"
  validation {
    condition     = var.scaler_target_metric_value > 0
    error_message = "scaler_target_metric_value must be positive."
  }
}
variable "scaler_metric_stat_period" {
  type        = number
  default     = 60
  description = "Seconds each CloudWatch aggregation covers. 60 is the finest granularity ALB metrics are published at, so a shorter period returns gaps rather than fresher numbers"
  validation {
    condition     = contains([1, 5, 10, 30], var.scaler_metric_stat_period) || var.scaler_metric_stat_period % 60 == 0
    error_message = "scaler_metric_stat_period must be 1, 5, 10, 30 or a multiple of 60, as CloudWatch requires."
  }
}
variable "scaler_polling_interval" {
  type        = number
  default     = 30
  description = "Seconds between metric queries, 30 as the _monolithic template set it. Every poll is a billed CloudWatch GetMetricData call"
  validation {
    condition     = var.scaler_polling_interval > 0
    error_message = "scaler_polling_interval must be positive."
  }
}
variable "scaler_cooldown_period" {
  type        = number
  default     = 300
  description = "Seconds of no activity before scaling back to the floor, 300 as the _monolithic template set it"
  validation {
    condition     = var.scaler_cooldown_period > 0
    error_message = "scaler_cooldown_period must be positive."
  }
}
variable "scaler_min_replica_count" {
  type        = number
  default     = 1
  description = "Floor for the ScaledObject. One rather than zero: the metric is the load balancer's request count, and with no pod behind it there is no successful request to count, so the metric would sit at zero and nothing would ever scale back up. Scaling to zero needs a metric that exists while the workload does not - a queue depth, for instance"
  validation {
    condition     = var.scaler_min_replica_count >= 0
    error_message = "scaler_min_replica_count must not be negative."
  }
}
variable "scaler_max_replica_count" {
  type        = number
  default     = 10
  description = "Ceiling for the ScaledObject, 10 as the _monolithic template set it"
  validation {
    condition     = var.scaler_max_replica_count >= 1
    error_message = "scaler_max_replica_count must be at least 1."
  }
  validation {
    condition     = var.scaler_max_replica_count >= var.scaler_min_replica_count
    error_message = "scaler_max_replica_count must be greater than or equal to scaler_min_replica_count."
  }
}
variable "workload_name" {
  type        = string
  default     = "nginx"
  description = "Name of the Deployment, Service and Ingress. It is also the second half of the ALB's adoption stack tag, so this value reaches AWS as a tag (rules.md G-3)"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the workload, the ScaledObject and the TriggerAuthentication are created in. One namespace for all three, because a ScaledObject can only target a workload in its own namespace and a TriggerAuthentication is namespaced too"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_image" {
  type        = string
  default     = "nginxdemos/hello"
  description = "Container image for the demo workload. Its page prints the serving pod's name, so refreshing the load balancer URL shows requests spreading across replicas as KEDA adds them"
  validation {
    condition     = length(var.workload_image) > 0
    error_message = "workload_image must not be empty."
  }
}
variable "workload_container_port" {
  type        = number
  default     = 80
  description = "Port the container and the Service listen on"
  validation {
    condition     = var.workload_container_port > 0 && var.workload_container_port <= 65535
    error_message = "workload_container_port must be between 1 and 65535."
  }
}
variable "alb_target_type" {
  type        = string
  default     = "ip"
  description = "How the ALB registers targets. ip, so a new replica receives traffic as soon as its target is healthy rather than via a NodePort on every node. Constrained to ip here, because with manage_backend_security_group_rules false this project declares the pod-side rule itself, and that rule can only be written for a known port (rules.md G-2)"

  validation {
    condition     = contains(["ip", "instance"], var.alb_target_type)
    error_message = "alb_target_type must be ip or instance."
  }

  validation {
    # instance would send traffic to a NodePort, and Kubernetes assigns those from
    # 30000-32767 at random - so Terraform cannot know the port and the only rule it
    # could express would open the whole range. The controller is not writing these
    # rules here, so there is nothing to fall back on (rules.md G-2).
    condition     = var.manage_backend_security_group_rules ? true : var.alb_target_type == "ip"
    error_message = "alb_target_type must be ip while manage_backend_security_group_rules is false, because the pod-side rule is declared in Terraform and a NodePort is not known until Kubernetes assigns it. To use instance, hand the rules back to the controller by setting manage_backend_security_group_rules and enable_backend_security_group both true (rules.md G-2)."
  }
}
variable "manage_backend_security_group_rules" {
  type        = bool
  default     = false
  description = "Whether the controller writes the pod-side security group rules itself, via the Ingress annotation. False, so nothing asks it to - which is what allows enable_backend_security_group to be false and keeps the shared backend group from being created at all. The path from the load balancer to the pods is declared in Terraform instead, as aws_vpc_security_group_ingress_rule.load_balancer_to_pods, where it is visible in plan (rules.md G-2)"
}
variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the controller creates and uses its shared backend security group - the k8s-traffic-<cluster>-<hash> group it attaches to every load balancer and names as the traffic source in the rules it adds to node or ENI groups. False, so that group is never created. With manage_backend_security_group_rules also false the controller has no pod-side rules to write, so nothing is lost by turning it off; the trade is that the rule below belongs to Terraform, and a rule per load balancer accumulates on the pod-side group as load balancers are added"

  validation {
    # Cross-variable condition, available since Terraform 1.9: the constraint is about
    # the pair rather than either value alone. A workload that sets
    # manage-backend-security-group-rules while this is off is refused by the
    # controller, and only its own log says so - plan and apply both succeed and the
    # load balancer is simply never finished (rules.md B-1/G-2).
    condition     = var.manage_backend_security_group_rules ? var.enable_backend_security_group : true
    error_message = "enable_backend_security_group must be true when manage_backend_security_group_rules is true, because the controller rejects that combination when the Ingress also names its own frontend security group. Keep both false and let Terraform declare the pod-side rule, which is what this project does (rules.md G-2)."
  }
}
variable "alb_security_group_name" {
  type        = string
  default     = "alb-sg"
  description = "Name of the frontend security group attached to the pre-created ALB"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "alb_port" {
  type        = number
  default     = 80
  description = "Listener port on the ALB, and the port the load generator requests"
  validation {
    condition     = var.alb_port > 0 && var.alb_port <= 65535
    error_message = "alb_port must be between 1 and 65535."
  }
}
variable "synced_load_balancer_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created ALB. Null generates a unique one, which is what lets this project be deployed twice in one account - adoption is decided entirely by tags, so the name plays no part in it (rules.md G-3)"
  validation {
    condition     = var.synced_load_balancer_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.synced_load_balancer_name))
    error_message = "synced_load_balancer_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.0"
  description = "Pinned aws-load-balancer-controller chart version"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because nothing in this project is such a Service: the workload is reached through an Ingress and its Service is ClusterIP, and KEDA's three Services are ClusterIP too. Leaving it on is what broke this project's apply - the chart gives the webhook failurePolicy: Fail and no namespaceSelector, so every v1/services CREATE in the cluster goes through it, and the controller module and the KEDA module share no ordering and install in parallel. KEDA's Services landed in the window between the webhook being registered and the controller's Deployment becoming Available, and all three were rejected with \"no endpoints available for service aws-load-balancer-webhook-service\" (rules.md G-4)"

  validation {
    # The constraint is real rather than stylistic, so it belongs here and not in the
    # description (rules.md B-1). Turning this on reintroduces a cluster-wide gate on
    # Service creation that this project gains nothing from, and the resulting failure
    # names the webhook rather than the release that tripped over it - which is a long
    # way from the cause.
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. No Service here is of type LoadBalancer, so the webhook has nothing to mutate, while its failurePolicy: Fail applies to every Service created in the cluster and makes any parallel release fail whenever the controller has no Ready pod. To run with it true, order every module that creates a Service after module.aws_load_balancer_controller - and note that only covers the apply, not a later controller rollout (rules.md G-4)."
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
  description = "Desired node count"
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
  description = "Maximum node count, 4 as the _monolithic template had it. Nothing scales the node group here, so this is only headroom for a manual resize - the nginx replicas KEDA adds are small enough that ten of them fit comfortably"
  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the ALB's frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. False by default; code-server has no authentication in front of it. Note the demo needs the ALB reachable from wherever the load is generated - from inside the cluster, as the load generator command does, the cluster security group's own path is what matters"
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
