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
  default     = "ingress-nginx-cluster"
  description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns, so the pre-created load balancers carry the same value (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for the EKS cluster"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.34."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True, which is a deliberate change from the _monolithic template: that one kept the endpoint private and drove every Kubernetes object from an SSM Association on the bastion, which is the form rules.md E-9 describes. E-9 is for projects whose subject is the private endpoint, and this project's subject is two ingress controllers - paying E-9's price here would mean the two Helm releases, the StorageClass, the claim, the Deployment, the Service and the Ingress were all outside Terraform state. Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named
    # (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its Helm releases and manifests are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "ingress-nginx-key"
  description = "Name of the EC2 key pair created for the demo instance"

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
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets' (rules.md G-1). The _monolithic template tagged no subnets at all and got away with it only because it named the subnets on the load balancer by hand"

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
    error_message = "private_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer."
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
  description = "Desired node count, two as the _monolithic template had it. Two ingress controllers, the AWS Load Balancer Controller, CoreDNS, the EBS CSI driver and the demo pod all fit"

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
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales this node group, so it is headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. This controller is what turns each ingress-nginx Service into an NLB; the _monolithic template installed it with a helm command in the instance's user data, after an \"exec bash\" line that discarded every remaining line - so on a real boot it was never installed and nothing in the project worked (rules.md E-1/H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the AWS Load Balancer Controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False: both Services of that type here are the ingress controllers', and they set aws-load-balancer-type: external, so they are claimed without it (rules.md G-1). The chart gives that webhook failurePolicy: Fail and no namespaceSelector, so leaving it on makes every Service creation in the cluster wait on a controller pod being Ready - and this project creates its two ingress controller Services right after installing it (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. Both Services of type LoadBalancer here set aws-load-balancer-type: external, so the controller claims them without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster and would gate this project's own Services behind a controller pod being Ready (rules.md G-4)."
  }
}
variable "ingress_classes" {
  type        = set(string)
  default     = ["a", "b"]
  description = "The IngressClasses to stand up, one ingress-nginx release and one NLB each. Two, named a and b, as the _monolithic template had them - and the count is the subject: each class is owned by its own controller with its own controllerValue, so an Ingress naming a is served by one load balancer and the same Ingress naming b by the other, with nothing else changing. Keys of this set become resource addresses, so they are literal strings in configuration rather than anything computed (rules.md B-8)"

  validation {
    condition     = length(var.ingress_classes) >= 1
    error_message = "ingress_classes must contain at least one class."
  }
  validation {
    condition     = alltrue([for name in var.ingress_classes : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", name))])
    error_message = "ingress_classes entries must each be a valid lowercase RFC 1123 DNS label - each becomes an IngressClass name, part of a Helm release name and part of a Service name."
  }
}
variable "ingress_release_name_prefix" {
  type        = string
  default     = "ingress-nginx"
  description = "Prefix for each ingress-nginx release name, which becomes <prefix>-<class>. The chart's fullname is pinned to the release name, so the controller Service is <prefix>-<class>-controller - and that name is half of the stack tag its pre-created load balancer has to carry (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_release_name_prefix))
    error_message = "ingress_release_name_prefix must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace both ingress-nginx releases are installed into, kube-system as the _monolithic template had it. Also the first half of each load balancer's stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_namespace))
    error_message = "ingress_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_nginx_chart_version" {
  type        = string
  default     = "4.13.0"
  description = "Pinned ingress-nginx chart version, the same pin the rest of this repository uses. The _monolithic template pulled whatever helm repo update produced at boot time"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.ingress_nginx_chart_version))
    error_message = "ingress_nginx_chart_version must be a semantic version."
  }
}
variable "load_balancer_ports" {
  type = map(number)
  default = {
    http  = 80
    https = 443
  }
  description = "Ports each ingress controller Service publishes, keyed by the names the chart defines under controller.service.ports. One map feeds three places: the frontend security group's rules, the chart's Service, and the pod-side rules on the cluster security group (rules.md B-5). Both ports, because the chart publishes both whatever is set here - the _monolithic template's security group opened only 80, which left each NLB with a 443 listener nothing could reach while every resource reported success"

  validation {
    condition     = length(var.load_balancer_ports) > 0
    error_message = "load_balancer_ports must contain at least one port."
  }
  validation {
    condition     = alltrue([for name in keys(var.load_balancer_ports) : contains(["http", "https"], name)])
    error_message = "load_balancer_ports keys must be http or https - the only two port names the ingress-nginx chart defines under controller.service.ports. Another key renders into a chart value that is ignored rather than rejected, leaving the Service on its defaults."
  }
  validation {
    condition     = contains(keys(var.load_balancer_ports), "http")
    error_message = "load_balancer_ports must include http. The demo Ingress is served over plain http - nothing here issues a certificate - so dropping that port makes the app unreachable while terraform apply still succeeds."
  }
  validation {
    condition     = alltrue([for port in values(var.load_balancer_ports) : port > 0 && port <= 65535])
    error_message = "load_balancer_ports values must be between 1 and 65535."
  }
}
variable "load_balancer_security_group_name" {
  type        = string
  default     = "ingress-nginx-nlb-sg"
  description = "Name of the frontend security group shared by both pre-created NLBs, as the _monolithic template shared one group between them. An NLB can only be given security groups at creation, so this group and the load balancers are created together (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.load_balancer_security_group_name)) && !startswith(var.load_balancer_security_group_name, "sg-")
    error_message = "load_balancer_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the NLB frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it, because the app and code-server are both reached from a browser - but code-server has no authentication in front of it, so narrow this with ingress_cidr_blocks where possible"
}
variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the StorageClass created for the demo's MySQL volume, gp3 as the _monolithic template named it. The workload module is handed this value rather than restating it, because a claim naming a class that does not exist stays Pending and the pod never starts (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "workload_name" {
  type        = string
  default     = "todo"
  description = "Name of the demo Deployment and of the Ingress in front of it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo workload lives in, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_path_prefix" {
  type        = string
  default     = "/v1"
  description = "Prefix the demo app is served under. One value reaches uvicorn's --root-path, the Ingress rule's path regex and the rewrite annotation that strips it again; the _monolithic template wrote /v1 into all three by hand"

  validation {
    condition     = can(regex("^/[a-z0-9][a-z0-9-]*$", var.workload_path_prefix))
    error_message = "workload_path_prefix must be a single absolute path segment such as /v1."
  }
}
variable "workload_ingress_class" {
  type        = string
  default     = "a"
  description = "Which of the ingress_classes the demo Ingress asks for, a as the _monolithic template had it. Switching this to the other class is the demo: the same Ingress is then served by the other controller through the other load balancer, with nothing else changed"

  validation {
    # The one mistake this project makes easy, and the reason this is a cross-variable
    # condition rather than a format check: an Ingress naming a class no controller owns is
    # accepted by the API server, never gets an address, and reports no error anywhere
    # (rules.md B-1).
    condition     = contains(var.ingress_classes, var.workload_ingress_class)
    error_message = "workload_ingress_class must be one of the classes in ingress_classes. An Ingress naming a class no controller owns is created successfully, is reconciled by nobody, and never gets an address - with nothing in plan, apply or the Ingress's own events to say why."
  }
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
