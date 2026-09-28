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
  default     = "adot-amp-metric-cluster"
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
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the helm and kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2); the _monolithic template had this true as well, driving the same objects from an SSM Association on the bastion. Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant actually depends on. The two forms fail
    # differently and the SSM alternative is E-9's, so the choice is recorded rather than
    # left implicit (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because cert-manager and the add-on's RBAC are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "adot-amp-metric-key"
  description = "Name of the EC2 key pair created for the demo instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group. This variant runs the most of the three: the Prometheus collector, the Grafana operator, Grafana itself with a plugin installed at startup, and an ingress controller"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 3
  description = "Desired node count, three as the _monolithic template had it - one more than the other two variants, because this one also runs Grafana and an ingress controller"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 3
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 6
  description = "Maximum node count, six as the _monolithic template had it. Nothing scales the node group here, so this is only headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "cert_manager_chart_version" {
  type        = string
  default     = "v1.21.2"
  description = "Pinned cert-manager version. Not optional and not incidental: the ADOT add-on installs an operator whose admission webhook serves TLS from a certificate cert-manager issues, so without it the add-on installs and the operator never becomes ready. The _monolithic template installed it unpinned from a shell script (rules.md E-1)"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.cert_manager_chart_version))
    error_message = "cert_manager_chart_version must be a semantic version, optionally prefixed with v."
  }
}
variable "adot_addon_version" {
  type        = string
  default     = null
  description = "Specific adot add-on version, or null to let EKS pick its default - which is what the _monolithic template did. The add-on's configuration schema is versioned with it, so pinning this pins the shape of the configuration below as well"

  validation {
    condition     = var.adot_addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.adot_addon_version))
    error_message = "adot_addon_version must look like v0.156.0-eksbuild.1, or null."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0 on the code-server port. True as the _monolithic template had it, because code-server is reached from a browser - but it runs with authentication disabled, so narrow this to your own address where possible"
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
variable "amp_workspace_alias" {
  type        = string
  default     = null
  description = "Alias for the Amazon Managed Prometheus workspace. Null derives it from the cluster name. Not the workspace's identity - AMP assigns a ws-<uuid> that everything references - but it names the log groups, so two deployments in one account do not collide on them"

  validation {
    condition     = var.amp_workspace_alias == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_.]{0,99}$", var.amp_workspace_alias))
    error_message = "amp_workspace_alias must start with a letter or digit and contain only letters, digits, hyphens, underscores and dots, or null."
  }
}
variable "amp_log_retention_days" {
  type        = number
  default     = 7
  description = "How long AMP's rule evaluation and query logs are kept. The _monolithic template created both log groups with no retention, so they never expire and survive a terraform destroy"

  validation {
    condition = var.amp_log_retention_days == 0 || contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.amp_log_retention_days)
    error_message = "amp_log_retention_days must be 0 (never expire) or one of the retention periods CloudWatch Logs accepts."
  }
}
variable "amp_enable_query_logging" {
  type        = bool
  default     = true
  description = "Whether AMP logs the queries it serves. True, which restores something the _monolithic template lost: its CloudFormation source configured query logging, cfn2tf could not map that property, and it was left as a comment - so the log group existed and nothing wrote to it"
}
variable "enable_emf" {
  type        = bool
  default     = true
  description = "Whether the Prometheus collector also exports to CloudWatch as embedded metric format, as the _monolithic template had it. Independent of the AMP export: both pipelines read the same scrape, so this is a second destination rather than an alternative - and it is why the collector's role carries a CloudWatch policy alongside the Prometheus one"
}
variable "grafana_operator_chart_version" {
  type        = string
  default     = "v5.19.0"
  description = "Pinned grafana-operator chart version, as the _monolithic template had it - the one release in that template that was pinned. The operator's version decides which apiVersion its custom resources use, so an unpinned upgrade can leave the Grafana and GrafanaDatasource objects unrecognised"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.grafana_operator_chart_version))
    error_message = "grafana_operator_chart_version must be a semantic version, optionally prefixed with v."
  }
}
variable "grafana_namespace" {
  type        = string
  default     = "monitoring"
  description = "Namespace Grafana and its operator run in, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.grafana_namespace))
    error_message = "grafana_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "grafana_admin_user" {
  type        = string
  default     = "admin"
  description = "Grafana administrator login name, as the _monolithic template had it"

  validation {
    condition     = length(var.grafana_admin_user) > 0
    error_message = "grafana_admin_user must not be empty."
  }
}
variable "grafana_admin_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Administrator password. Null generates one, which is the default. The _monolithic template defaulted this to the literal string \"grafana\" and printed it in a Terraform output; here it reaches the container through a Kubernetes Secret and an environment variable, and the outputs carry the command to retrieve it rather than the value (rules.md H-2)"

  validation {
    condition     = var.grafana_admin_password == null || length(var.grafana_admin_password) >= 8
    error_message = "grafana_admin_password must be at least 8 characters, or null to generate one."
  }
}
variable "grafana_secrets_manager_name" {
  type        = string
  default     = null
  description = "Optional Secrets Manager secret the generated Grafana credential is also written to, so it can be read without Terraform state. Null keeps it in state and in the Kubernetes Secret only"

  validation {
    condition     = var.grafana_secrets_manager_name == null || can(regex("^[a-zA-Z0-9/_+=.@-]{1,512}$", var.grafana_secrets_manager_name))
    error_message = "grafana_secrets_manager_name must be 1-512 characters of letters, digits and /_+=.@- , or null."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The controller is what adopts the pre-created NLB from the ingress controller's Service (rules.md G-3)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because the one such Service here - the ingress controller's - is annotated with aws-load-balancer-type: external and is claimed without it (rules.md G-1). The chart gives that webhook failurePolicy: Fail and no namespaceSelector, so leaving it on makes every Service creation in the cluster wait on a controller pod being Ready, and three more charts create Services right after it (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. The ingress controller's Service sets aws-load-balancer-type: external, so the controller claims it without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster (rules.md G-4)."
  }
}
variable "ingress_nginx_chart_version" {
  type        = string
  default     = "4.13.0"
  description = "Pinned ingress-nginx chart version, where the _monolithic template pinned nothing"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.ingress_nginx_chart_version))
    error_message = "ingress_nginx_chart_version must be a semantic version."
  }
}
variable "ingress_nginx_namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the ingress controller runs in, as the _monolithic template had it. First half of the adoption stack tag for the pre-created load balancer, and the load balancer has to be tagged before this module runs - so both read this one variable (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_nginx_namespace))
    error_message = "ingress_nginx_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_nginx_release_name" {
  type        = string
  default     = "ingress-nginx"
  description = "Helm release name for the ingress controller. The chart's Service is <release>-controller once fullnameOverride pins it, which is the second half of the adoption stack tag - left unpinned the chart chooses between two spellings by testing whether the release name happens to contain the chart name, and a wrong guess makes the controller build a second load balancer rather than adopt the pre-created one (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_nginx_release_name))
    error_message = "ingress_nginx_release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_nginx_class_name" {
  type        = string
  default     = "nginx"
  description = "IngressClass the controller claims, and the class Grafana's Ingress names. One value for both, because a class no controller claims produces no error and no address (rules.md B-5/G-1)"

  validation {
    condition     = length(var.ingress_nginx_class_name) > 0
    error_message = "ingress_nginx_class_name must not be empty."
  }
}
variable "load_balancer_ports" {
  type = map(number)
  default = {
    http  = 80
    https = 443
  }
  description = "Ports the ingress controller's Service publishes, keyed by port name. One value feeds three places: the Service, the NLB frontend security group, and the pod-side rules that let the load balancer reach the controller - so a listener cannot exist without a rule to match it. The _monolithic template opened only 80 in its security group while the chart published both, leaving a 443 listener that accepted nothing (rules.md B-5/G-1)"

  validation {
    condition     = length(var.load_balancer_ports) > 0
    error_message = "load_balancer_ports must contain at least one port."
  }
  validation {
    condition     = alltrue([for port in values(var.load_balancer_ports) : port > 0 && port <= 65535])
    error_message = "load_balancer_ports values must be valid TCP ports."
  }
}
variable "nlb_security_group_name" {
  type        = string
  default     = "amp-grafana-nlb-sg"
  description = "Name of the frontend security group attached to the pre-created NLB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.nlb_security_group_name)) && !startswith(var.nlb_security_group_name, "sg-")
    error_message = "nlb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "synced_nlb_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created NLB. Null generates a unique one, which is what lets this project be deployed twice in one account - adoption is decided entirely by tags, so the name plays no part in it. The _monolithic template fixed it to \"grafana\" (rules.md G-3)"

  validation {
    condition     = var.synced_nlb_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.synced_nlb_name))
    error_message = "synced_nlb_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
