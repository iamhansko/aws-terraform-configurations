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
  default     = "istio-cluster"
  description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns, so both pre-created load balancers carry the same value (rules.md G-3)"

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
    # differently and the SSM alternative is E-9's, so the choice is recorded rather
    # than left implicit (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its charts and manifests are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "istio-key"
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
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer, and this project needs it for both of them. The _monolithic template tagged no subnets at all, which leaves the controller failing with 'couldn't auto-discover subnets' for every Ingress and Service it is handed (rules.md G-1)"

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
  description = "Instance types for the managed node group. The control plane is the memory-hungry part: istiod alone requests 2 GiB, which has to fit on a single node"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it. Enough for istiod, the gateway proxy, the Kiali operator and server, two controller replicas, CoreDNS and the demo application with its sidecars"

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
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales the node group here, so this is only headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The controller is what reconciles the gateway Service into the NLB and the Kiali Ingress into the ALB. The _monolithic template installed it from a helm command in userdata that never ran (rules.md E-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because the one such Service here - the ingress gateway - sets aws-load-balancer-type: external and is claimed without it (rules.md G-1). The chart gives that webhook failurePolicy: Fail and no namespaceSelector, so leaving it on makes every Service creation in the cluster wait on a controller pod being Ready, and this project installs four more charts that create Services immediately afterwards (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. The ingress gateway Service sets aws-load-balancer-type: external, so the controller claims it without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster and would gate istiod, the gateway and Kiali behind a controller pod being Ready (rules.md G-4)."
  }
}
variable "istio_chart_version" {
  type        = string
  default     = "1.30.5"
  description = "Version of the istio base, istiod and gateway charts, all installed together. The _monolithic template pinned nothing, so the mesh version was whatever the repository served on the day (rules.md E-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.istio_chart_version))
    error_message = "istio_chart_version must be a semantic version (e.g. 1.30.5)."
  }
}
variable "istio_control_plane_namespace" {
  type        = string
  default     = "istio-system"
  description = "Namespace istiod and Kiali both live in. Defined at the root rather than left to the modules' defaults because the Kiali adoption stack tag is built from it, and the load balancer has to be tagged before the Kiali module runs - so both read this one variable (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.istio_control_plane_namespace))
    error_message = "istio_control_plane_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "istio_gateway_namespace" {
  type        = string
  default     = "istio-ingress"
  description = "Namespace the ingress gateway runs in, and the first half of the NLB's adoption stack tag. Same reason as istio_control_plane_namespace for living here (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.istio_gateway_namespace))
    error_message = "istio_gateway_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "istio_gateway_release_name" {
  type        = string
  default     = "istio-ingressgateway"
  description = "Helm release name for the gateway chart, which is also the Service name and therefore the second half of the NLB's adoption stack tag (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.istio_gateway_release_name))
    error_message = "istio_gateway_release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "istio_gateway_service_ports" {
  type = map(number)
  default = {
    http2 = 80
  }
  description = "Ports the gateway Service publishes, keyed by port name. One value feeds three places: the Service, the NLB frontend security group's inbound rules, and the pod-side rules that let the load balancer reach the proxy - so a listener cannot exist without a rule to match it (rules.md B-5/G-1). The chart's own defaults also include 443 and 15021, which this replaces: 443 is useless without a certificate, and 15021 is the readiness endpoint, reached directly on the pod by the health check rather than through a public listener"

  validation {
    condition     = length(var.istio_gateway_service_ports) > 0
    error_message = "istio_gateway_service_ports must contain at least one port."
  }
  validation {
    condition     = alltrue([for port in values(var.istio_gateway_service_ports) : port > 0 && port <= 65535])
    error_message = "istio_gateway_service_ports values must be valid TCP ports."
  }
}
variable "istio_gateway_health_check_port" {
  type        = number
  default     = 15021
  description = "Port the NLB health-checks on the gateway pod. Deliberately not one of istio_gateway_service_ports: the proxy only binds a traffic port once a Gateway resource declares a server on it, so a health check against port 80 fails on a mesh with no routes and leaves every target unhealthy. The pod-side security group rule has to open this as well as the traffic ports (rules.md G-2)"

  validation {
    condition     = var.istio_gateway_health_check_port > 0 && var.istio_gateway_health_check_port <= 65535
    error_message = "istio_gateway_health_check_port must be a valid TCP port."
  }
  validation {
    # Cross-variable, available since Terraform 1.9 (rules.md B-1). If the health check
    # port were also a published port it would become a public listener, which is the
    # opposite of why it was separated out.
    condition     = !contains(values(var.istio_gateway_service_ports), var.istio_gateway_health_check_port)
    error_message = "istio_gateway_health_check_port must not also appear in istio_gateway_service_ports; publishing it would turn the proxy's readiness endpoint into an internet-facing load balancer listener."
  }
}
variable "kiali_chart_version" {
  type        = string
  default     = "2.32.0"
  description = "Pinned kiali-operator chart version, which also decides the Kiali server version the operator installs"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kiali_chart_version))
    error_message = "kiali_chart_version must be a semantic version (e.g. 2.32.0)."
  }
}
variable "kiali_name" {
  type        = string
  default     = "kiali"
  description = "Name of the Kiali CR, and therefore of the Deployment, Service and Ingress the operator and this configuration build around it. Also the second half of the ALB's adoption stack tag (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.kiali_name))
    error_message = "kiali_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "kiali_auth_strategy" {
  type        = string
  default     = "anonymous"
  description = "How Kiali authenticates users. anonymous as the _monolithic template had it: no login screen, so anyone who reaches the load balancer has full read access to the mesh. Narrow allow_inbound_from_anywhere, or change this, for anything beyond a demo"

  validation {
    condition     = contains(["anonymous", "token", "openid", "header"], var.kiali_auth_strategy)
    error_message = "kiali_auth_strategy must be one of: anonymous, token, openid, header."
  }
}
variable "kiali_web_root" {
  type        = string
  default     = "/kiali"
  description = "Path prefix Kiali serves under. One value feeds the Kiali CR, the Ingress path, the ALB health check path and the URL in the outputs. The _monolithic template set the Ingress path and the health check but left the server at its default of /, so the ALB forwarded /kiali to a server that had no route for it - a healthy load balancer in front of a 404 (rules.md B-5)"

  validation {
    condition     = startswith(var.kiali_web_root, "/")
    error_message = "kiali_web_root must start with '/'."
  }
}
variable "kiali_server_port" {
  type        = number
  default     = 20001
  description = "Port the Kiali server listens on. With an ALB target type of ip the load balancer reaches the pod directly on this port, so this is what the pod-side security group rule opens (rules.md G-2)"

  validation {
    condition     = var.kiali_server_port > 0 && var.kiali_server_port <= 65535
    error_message = "kiali_server_port must be a valid TCP port."
  }
}
variable "kiali_load_balancer_port" {
  type        = number
  default     = 80
  description = "Listener port on the Kiali ALB, which the frontend security group opens. 80 is what the controller creates when an Ingress does not override listen-ports, so changing this alone would open a port with no listener behind it"

  validation {
    condition     = var.kiali_load_balancer_port > 0 && var.kiali_load_balancer_port <= 65535
    error_message = "kiali_load_balancer_port must be a valid TCP port."
  }
}
variable "demo_namespace" {
  type        = string
  default     = "mesh-demo"
  description = "Namespace for the demo application that gives the mesh something to carry"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_namespace))
    error_message = "demo_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "demo_name" {
  type        = string
  default     = "demo-app"
  description = "Name of the demo application's Deployment, Service, Gateway and VirtualService"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_name))
    error_message = "demo_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "demo_gateway_port" {
  type        = number
  default     = 80
  description = "Port the demo's Gateway declares a server on, which is what makes the proxy bind that port and the load balancer listener useful. Stated explicitly rather than derived from istio_gateway_service_ports, because that map may hold several ports and only one of them is the one this demo routes"

  validation {
    condition     = var.demo_gateway_port > 0 && var.demo_gateway_port <= 65535
    error_message = "demo_gateway_port must be a valid TCP port."
  }
  validation {
    # Cross-variable, available since Terraform 1.9 (rules.md B-1). A Gateway on a port
    # the Service does not publish is accepted by the API server and configures a
    # listener nothing can reach: the load balancer has no listener on that port at all,
    # so requests go nowhere while every object involved looks correct.
    condition     = contains(values(var.istio_gateway_service_ports), var.demo_gateway_port)
    error_message = "demo_gateway_port must be one of the ports in istio_gateway_service_ports. A Gateway declaring a server on a port the gateway Service does not publish produces no load balancer listener, and no resource reports anything wrong."
  }
}
variable "demo_route_traffic" {
  type        = bool
  default     = true
  description = "Whether the demo's Gateway and VirtualService are created. True, so an apply produces a load balancer URL that actually serves a page. Set false to reach the state the _monolithic template stopped at: Istio installed, the gateway pod Running, the NLB's targets healthy, and every request refused - because Envoy binds no traffic port until a Gateway declares a server on one. They are Terraform resources rather than files to kubectl apply, so this is a variable rather than a delete the next apply would undo (rules.md B-4/E-2)"
}
variable "nlb_security_group_name" {
  type        = string
  default     = "istio-nlb-sg"
  description = "Name of the frontend security group attached to the pre-created NLB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.nlb_security_group_name)) && !startswith(var.nlb_security_group_name, "sg-")
    error_message = "nlb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "alb_security_group_name" {
  type        = string
  default     = "kiali-alb-sg"
  description = "Name of the frontend security group attached to the pre-created ALB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "synced_nlb_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created NLB. Null generates a unique one, which is what lets this project be deployed twice in one account. The _monolithic template fixed it to \"istio\", which turns a tag mismatch into 'A load balancer with the same name exists, but with different settings' - a message that reads as a naming collision when the actual cause is that adoption failed (rules.md G-3)"

  validation {
    condition     = var.synced_nlb_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.synced_nlb_name))
    error_message = "synced_nlb_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "synced_alb_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created ALB. Null for the same reason as synced_nlb_name; the _monolithic template fixed it to \"kiali\" (rules.md G-3)"

  validation {
    condition     = var.synced_alb_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.synced_alb_name))
    error_message = "synced_alb_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the two load balancer frontend security groups and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it, because all three are reached from a browser - but code-server has no authentication and Kiali is set to anonymous, so narrow this to your own address with ingress_cidr_blocks where possible"
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
