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
  default     = "n8n-cluster"
  description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns (rules.md G-3)"

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
  description = "Whether the EKS API server endpoint is reachable from the internet. True as the _monolithic template had it, and needed because the helm and kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-2). Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named
    # (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its Helm release and every n8n manifest are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "n8n-key"
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
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets' (rules.md G-1)"

  validation {
    condition = alltrue([
      for key, value in var.public_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "public_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer (rules.md G-1)."
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
  default     = ["t3.large"]
  description = "Instance types for the managed node group, t3.large as the _monolithic template had it. n8n and a Postgres asking for a gibibyte each do not fit comfortably on anything smaller"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 1
  description = "Desired node count, one as the _monolithic template had it. Both pods hold ReadWriteOnce volumes, so nothing here benefits from a second node"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 1
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 3
  description = "Maximum node count, three as the _monolithic template had it. Nothing scales this node group, so it is headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the StorageClass both n8n claims ask for, gp3 as the _monolithic template named it. Named explicitly in the claims rather than relying on the cluster's default annotation (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. It is what turns n8n's Service into an NLB; the _monolithic template installed it with a helm command in user data, after an \"exec bash\" line that discarded every remaining line - so on a real boot it was never installed and nothing about n8n reached the cluster either (rules.md E-1/H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook. False, and now there is not even a Service of type LoadBalancer for it to act on - n8n is reached through an Ingress, and the webhook only injects spec.loadBalancerClass into Services. Its failurePolicy: Fail and missing namespaceSelector would still make every Service creation in the cluster wait on a controller pod being Ready (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. n8n is exposed through an Ingress, so there is no Service of type LoadBalancer for the webhook to mutate, while its failurePolicy: Fail applies to every Service created anywhere in the cluster (rules.md G-4)."
  }
}
variable "n8n_namespace" {
  type        = string
  default     = "n8n"
  description = "Namespace n8n and its Postgres live in, as the upstream manifests name it. Also the first half of the stack tag the pre-created NLB must carry to be adopted rather than duplicated (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.n8n_namespace))
    error_message = "n8n_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "n8n_name" {
  type        = string
  default     = "n8n"
  description = "Name of the n8n Deployment and Service, and the second half of the adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.n8n_name))
    error_message = "n8n_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "n8n_image" {
  type        = string
  default     = "n8nio/n8n:2.40.5"
  description = "n8n image, the version the upstream n8n-hosting manifests pin. The _monolithic template applied those manifests and then overrode the tag with \"kubectl set image ... n8nio/n8n:1.119.2\", so the version lived in a shell script rather than in any manifest (rules.md E-5)"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.n8n_image))
    error_message = "n8n_image must carry an explicit tag or a digest."
  }
}
variable "n8n_port" {
  type        = number
  default     = 5678
  description = "Port n8n listens on, which is also the Service port and the port the ALB forwards to. Not the listener port - that is ingress_listen_port, and conflating the two is what left the previous NLB shape listening on 5678 while publishing an address with no port. One value reaches the container, the Service, the Ingress backend and the pod-side rule (rules.md B-5)"

  validation {
    condition     = var.n8n_port > 0 && var.n8n_port <= 65535
    error_message = "n8n_port must be between 1 and 65535."
  }
}
variable "postgres_storage_size" {
  type        = string
  default     = "10Gi"
  description = "Size of the volume Postgres stores its data on. The upstream manifest asks for 300Gi, which is a real monthly gp3 bill for a demo that writes a handful of workflow rows"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.postgres_storage_size))
    error_message = "postgres_storage_size must be a Kubernetes storage quantity such as 10Gi."
  }
}
variable "n8n_service_type" {
  type        = string
  default     = "ClusterIP"
  description = "Type of the n8n Service. ClusterIP, because the ALB registers pod addresses directly with target-type ip and the Service is only the name the Ingress resolves (rules.md G-1)"

  validation {
    condition     = contains(["ClusterIP", "NodePort"], var.n8n_service_type)
    error_message = "n8n_service_type must be ClusterIP or NodePort - LoadBalancer would build a second load balancer beside the one the Ingress fronts (rules.md G-1)."
  }
}
variable "ingress_listen_port" {
  type        = number
  default     = 80
  description = "Port the ALB listens on, which is what the Ingress asks for with its listen-ports annotation and what the frontend security group opens. Distinct from n8n_port: the listener is plain http on 80 and the load balancer forwards to the pods on n8n's own port, which is what lets the published address carry no port at all"

  validation {
    condition     = var.ingress_listen_port > 0 && var.ingress_listen_port <= 65535
    error_message = "ingress_listen_port must be between 1 and 65535."
  }
  validation {
    # Not a hard requirement of anything, but the whole point of moving to an ALB here was that
    # http://<dns name> works with no port in it - and the module writes that same URL into n8n's
    # N8N_HOST and WEBHOOK_URL, where a non-default port would have to be added by hand or every
    # webhook n8n hands out would be wrong (rules.md B-1).
    condition     = var.ingress_listen_port == 80
    error_message = "ingress_listen_port must be 80 in this variant. The load balancer's URL is built as http://<dns name> with no port and handed to n8n as N8N_HOST and WEBHOOK_URL, so a different listener port would make every webhook address n8n generates unreachable. To use another port, extend the synced_load_balancer module's url output to include it."
  }
}
variable "ingress_healthcheck_path" {
  type        = string
  default     = "/healthz"
  description = "Path the ALB health-checks the n8n targets on. n8n answers 200 here as soon as it is serving http and without consulting Postgres, which is what is wanted: a database-gated check would deregister the only target whenever Postgres restarts. The default of / is worse than it looks - it returns the editor, and a redirect there would read as unhealthy against the ALB's default 200-only success codes"

  validation {
    condition     = startswith(var.ingress_healthcheck_path, "/")
    error_message = "ingress_healthcheck_path must start with '/'."
  }
}
variable "load_balancer_stickiness_attributes" {
  type        = string
  default     = "stickiness.enabled=true,stickiness.type=lb_cookie"
  description = "Target group attributes passed through to the controller. Stickiness keeps a browser on one pod, which is what makes the editor's long-lived connections behave with more than one replica; with a single replica it changes nothing and is kept because the _monolithic template had it. The type is lb_cookie rather than the source_ip the original set: source_ip is an NLB-only value, and elasticloadbalancing rejects it on an ALB target group - so on this shape the original value would fail the controller's reconciliation rather than do nothing"

  validation {
    condition     = can(regex("^[a-z0-9_.]+=[^,]+(,[a-z0-9_.]+=[^,]+)*$", var.load_balancer_stickiness_attributes))
    error_message = "load_balancer_stickiness_attributes must be a comma-separated list of key=value pairs."
  }
  validation {
    # The failure this prevents is a reconciliation error in the controller's log and an Ingress
    # that never gets a target group, which looks identical to a security group or subnet problem
    # from the outside (rules.md B-1/G-1).
    condition     = !can(regex("stickiness\\.type=source_ip", var.load_balancer_stickiness_attributes))
    error_message = "stickiness.type=source_ip is not valid on an ALB target group - it is the NLB value. Use lb_cookie or app_cookie here (rules.md G-1)."
  }
}
variable "load_balancer_security_group_name" {
  type        = string
  default     = "n8n-nlb-sg"
  description = "Name of the frontend security group attached to the pre-created ALB. It carries the listener port inbound, and the rule from it to the pods is declared separately in the root because no caller sets manage-backend-security-group-rules (rules.md G-2/G-3)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.load_balancer_security_group_name)) && !startswith(var.load_balancer_security_group_name, "sg-")
    error_message = "load_balancer_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the NLB frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it. Worth narrowing here more than in most of these projects: n8n's own sign-up page is open to whoever reaches it first, and code-server has no authentication at all"
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
