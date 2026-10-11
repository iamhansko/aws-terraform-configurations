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
  default     = "teleport-cluster"
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
variable "teleport_domain_name" {
  type        = string
  description = "DNS zone the Teleport host lives in, e.g. example.com. Required: this project cannot be applied without a real hosted zone, because Teleport's proxy will not become ready until cert-manager has proved control of a name inside it. There is no self-signed fallback - the certificate has to be one a browser and a tsh client both accept"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.teleport_domain_name)) && length(split(".", var.teleport_domain_name)) >= 2
    error_message = "teleport_domain_name must be a lowercase DNS name with at least two labels, such as example.com."
  }
}
variable "teleport_route53_hosted_zone_id" {
  type        = string
  description = "Hosted zone ID for teleport_domain_name. Taken as an ID rather than discovered with a data source on purpose: a data source would make plan fail with 'no matching Route 53 Hosted Zone found' in an account that has none, before showing anything else that might be wrong"

  validation {
    condition     = can(regex("^[A-Z0-9]{8,32}$", var.teleport_route53_hosted_zone_id))
    error_message = "teleport_route53_hosted_zone_id must be a bare hosted zone ID such as Z1234567890ABC - not the /hostedzone/... path the Route 53 API sometimes returns, which is what 'aws route53 list-hosted-zones' prints."
  }
}
variable "teleport_subdomain" {
  type        = string
  default     = "teleport"
  description = "Label prepended to teleport_domain_name to form the cluster's host name. Separate from the domain so one value produces the chart's clusterName, the certificate's subject, and both DNS records - the _monolithic template set clusterName to the bare domain while pointing the records at teleport.<domain>, so the certificate covered a name nothing resolved to (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.teleport_subdomain))
    error_message = "teleport_subdomain must be a valid lowercase DNS label."
  }
}
variable "teleport_issuer_email" {
  type        = string
  description = "Address Let's Encrypt registers the ACME account with and sends expiry notices to"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.teleport_issuer_email))
    error_message = "teleport_issuer_email must be a single email address."
  }
}
variable "acme_server" {
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  description = "ACME directory the issuer registers with. Production, as the _monolithic template had it, which means production rate limits: five duplicate certificates per week for the same set of names. Repeated applies of this project against one domain will hit that, and the failure appears as a Challenge that never completes. Point this at the staging directory while iterating"

  validation {
    condition     = can(regex("^https://", var.acme_server))
    error_message = "acme_server must be an https URL."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the helm and kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2). Note this is the EKS endpoint, not the way users reach the cluster - the point of Teleport is that they do not need it"

  validation {
    # Pinned in the direction this variant actually depends on. The two forms fail
    # differently and the SSM alternative is E-9's, so the choice is recorded rather than
    # left implicit (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because cert-manager, Teleport and the load balancer controller are installed by the helm provider from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "teleport-key"
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
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets'. The _monolithic template tagged no subnets at all (rules.md G-1)"

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
  description = "Instance types for the managed node group. Teleport's state lives in DynamoDB and S3 rather than on these nodes, which is what makes the auth pods interchangeable"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it - enough to place two auth and two proxy replicas with the chart's anti-affinity"

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
variable "teleport_replica_count" {
  type        = number
  default     = 2
  description = "Auth and proxy replicas, two as the _monolithic template had it"

  validation {
    condition     = var.teleport_replica_count >= 1
    error_message = "teleport_replica_count must be at least 1."
  }
}
variable "teleport_chart_version" {
  type        = string
  default     = "18.11.2"
  description = "Pinned teleport-cluster chart version, where the _monolithic template pinned nothing. The chart's major version is Teleport's own, and its state format in DynamoDB migrates forward on start"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.teleport_chart_version))
    error_message = "teleport_chart_version must be a semantic version (e.g. 18.11.2)."
  }
}
variable "teleport_kubernetes_cluster_role" {
  type        = string
  default     = "cluster-admin"
  description = "ClusterRole a user reaching the cluster through Teleport holds. Teleport impersonates a Kubernetes group bound to it, and the add-user command gives the user that group - without the group Teleport refuses every kubectl request with \"Your user's Teleport role does not allow Kubernetes access\". cluster-admin matches what the bastion's access entry has, since Teleport is the path that replaces it"

  validation {
    condition     = contains(["cluster-admin", "admin", "edit", "view"], var.teleport_kubernetes_cluster_role)
    error_message = "teleport_kubernetes_cluster_role must be one of the built-in user-facing ClusterRoles: cluster-admin, admin, edit or view. A binding to a ClusterRole that does not exist is accepted and grants nothing, so kubectl through Teleport would answer Forbidden while the apply succeeds."
  }
}
variable "teleport_backend_table" {
  type        = string
  default     = "teleport-helm-backend"
  description = "DynamoDB table Teleport creates for cluster state. Not a Terraform resource: its schema and indexes belong to Teleport and change between versions, which is why the IAM policy grants dynamodb:CreateTable instead"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{3,255}$", var.teleport_backend_table))
    error_message = "teleport_backend_table must be 3-255 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "teleport_audit_log_table" {
  type        = string
  default     = "teleport-helm-events"
  description = "DynamoDB table Teleport creates for the audit log, separate from the state table"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{3,255}$", var.teleport_audit_log_table))
    error_message = "teleport_audit_log_table must be 3-255 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "session_bucket_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the session recording bucket. Null generates one, which matters more than for most resources: S3 bucket names are unique across every AWS account, so a fixed name can collide with a stranger's"

  validation {
    condition     = var.session_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.session_bucket_name))
    error_message = "session_bucket_name must be a valid S3 bucket name, or null."
  }
}
variable "session_recording_retention_days" {
  type        = number
  default     = 30
  description = "How long superseded versions of session recordings are kept. Versioning is mandatory on this bucket, so without an expiry rule it grows without limit - including versions of recordings that were deleted. Set to 0 to keep everything, which is the right answer where the recordings are the audit trail"

  validation {
    condition     = var.session_recording_retention_days >= 0
    error_message = "session_recording_retention_days must be zero or greater; zero disables the expiry rule."
  }
}
variable "cert_manager_chart_version" {
  type        = string
  default     = "v1.21.2"
  description = "Pinned cert-manager version. Its CRDs are what the Teleport chart's Certificate object is an instance of, so an unpinned upgrade can replace them underneath a live certificate"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.cert_manager_chart_version))
    error_message = "cert_manager_chart_version must be a semantic version, optionally prefixed with v."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The controller is what adopts the pre-created NLB from Teleport's proxy Service. The _monolithic template created an IRSA role and a policy for it and never installed it - the helm command sat after an 'exec bash' line that replaced the shell (rules.md E-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because the one such Service here - Teleport's proxy - is given aws-load-balancer-type: external by this configuration and is claimed without it (rules.md G-1). The chart gives that webhook failurePolicy: Fail and no namespaceSelector, so leaving it on makes every Service creation in the cluster wait on a controller pod being Ready, and cert-manager and Teleport both create Services right after it is installed (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. Teleport's proxy Service is annotated with aws-load-balancer-type: external, so the controller claims it without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster (rules.md G-4)."
  }
}
variable "teleport_load_balancer_port" {
  type        = number
  default     = 443
  description = "Port the proxy Service publishes, and therefore the NLB's only listener and the port the frontend security group opens. One port because proxy listener mode is multiplex - Teleport separates SSH, Kubernetes and web traffic itself behind a single TLS port (rules.md B-5/G-1)"

  validation {
    condition     = var.teleport_load_balancer_port > 0 && var.teleport_load_balancer_port <= 65535
    error_message = "teleport_load_balancer_port must be a valid TCP port."
  }
}
variable "teleport_proxy_target_port" {
  type        = number
  default     = 3080
  description = "Port the proxy pod listens on. With a target type of ip the load balancer reaches the pod directly here, so this - not the Service port - is what the pod-side security group rule opens. Opening the wrong one leaves every target unhealthy with no error anywhere (rules.md G-1/G-2)"

  validation {
    condition     = var.teleport_proxy_target_port > 0 && var.teleport_proxy_target_port <= 65535
    error_message = "teleport_proxy_target_port must be a valid TCP port."
  }
}
variable "nlb_security_group_name" {
  type        = string
  default     = "teleport-nlb-sg"
  description = "Name of the frontend security group attached to the pre-created NLB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.nlb_security_group_name)) && !startswith(var.nlb_security_group_name, "sg-")
    error_message = "nlb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "synced_nlb_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created NLB. Null generates a unique one, which is what lets this project be deployed twice in one account - adoption is decided entirely by tags, so the name plays no part in it (rules.md G-3)"

  validation {
    condition     = var.synced_nlb_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.synced_nlb_name))
    error_message = "synced_nlb_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the NLB's frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. True for the NLB by necessity - Teleport is the front door and its users are not in this VPC - but code-server has no authentication in front of it, so narrow this to your own address with ingress_cidr_blocks where possible"
}
variable "create_dns_records" {
  type        = bool
  default     = true
  description = "Whether to create the two alias records pointing at the pre-created load balancer. True, and they are Terraform resources rather than a shell script's route53 change-batch - which is only possible because Terraform created the load balancer and therefore knows its DNS name and hosted zone ID (rules.md G-3). Set false when the zone is managed elsewhere, in which case the certificate will still be issued but nothing will resolve to the proxy"
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
  description = "How long the README SSM association may take. It first waits for the instance bootstrap to finish, which includes downloading kubectl, eksctl, helm and the tsh client"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
