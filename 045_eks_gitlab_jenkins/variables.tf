variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Null falls through to the provider chain (AWS_REGION / AWS_DEFAULT_REGION)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2), or null."
  }
}

variable "project_name" {
  type        = string
  default     = "eks-gitlab-jenkins"
  description = "Prefix for resource names that have to be unique inside the account, and the title of the README written onto the workbench"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}

# --- Network ---

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

# --- EKS cluster ---

variable "cluster_name" {
  type        = string
  default     = "eks-cluster"
  description = "Name of the EKS cluster. Also the value of the elbv2.k8s.aws/cluster tag both pre-created load balancers carry, which is one of the three tags adoption depends on (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "EKS cluster Kubernetes version. Keep kubectl_download_version within one minor of this"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions this project is verified against."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server has a public endpoint. True here, and pinned true, because the StorageClass objects and all three Helm releases are applied by providers running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares kubectl and helm providers, and those
    # run wherever terraform runs. With a private-only endpoint they cannot
    # connect, plan still passes, and the failure appears mid-apply as a dial
    # timeout that looks exactly like the destroy-ordering problem rules.md D-4
    # describes (rules.md E-9, B-1).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its StorageClasses and Helm releases are applied by providers running on the machine executing terraform. To run with a private endpoint, drop the kubectl and helm providers and apply everything from the workbench through SSM Associations instead, as 041_eks_private_cluster does."
  }
}

variable "endpoint_private_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server also answers on a VPC-internal address. True, as the _monolithic template had it"
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoint. Narrow this for anything longer lived than a demo"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "Control plane log types shipped to CloudWatch Logs"

  validation {
    condition = alltrue([for t in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "enabled_cluster_log_types entries must be among: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas"

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

# --- Node group ---

variable "node_group_name" {
  type        = string
  default     = "core-nodegroup"
  description = "Name of the managed node group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.node_group_name))
    error_message = "node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.xlarge"]
  description = <<-DESC
    Instance types for the managed node group. A deliberate departure from the _monolithic template's
    t3.medium, which cannot run this project's workload - and does not say so.

    The pinned GitLab chart keeps its PostgreSQL, Redis and MinIO in the release, so the nodes host the
    datastores as well as the application, and two of the chart's pods request more memory than a
    t3.medium has to give: webservice asks for 2480Mi per replica and sidekiq for 1907Mi, against about
    3292Mi allocatable on a t3.medium. The sum fits across four of them, which is why this looks
    survivable; what does not fit is a single 2480Mi pod next to anything else, so one webservice
    replica has nowhere to go while the cluster still reports spare memory overall.

    The failure appears in neither plan nor apply. The release installs, Helm reports it deployed, and
    the pod sits Pending with "Insufficient memory" - there is no cluster autoscaler here to grow the
    group out from under it (rules.md E-10).
  DESC

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must contain at least one instance type."
  }
}

variable "node_desired_size" {
  type        = number
  default     = 4
  description = "Desired node count. Four, as the _monolithic template had it: GitLab alone schedules around thirty pods, and the chart's Gitaly and PostgreSQL workloads each want a volume and a whole CPU"

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  type        = number
  default     = 4
  description = "Minimum node count"

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_max_size" {
  type        = number
  default     = 6
  description = "Maximum node count"

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}

# --- AWS Load Balancer Controller ---

variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The _monolithic template ran `helm install` with no --version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a three-part semantic version."
  }
}

variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the controller uses one shared backend security group as the source of the node-side rules it writes"

  validation {
    # Both Services here name their own frontend security groups and neither sets
    # manage-backend-security-group-rules, so the controller writes no node-side
    # rules at all and this project declares them itself
    # (aws_vpc_security_group_ingress_rule.load_balancer_to_pods). That is the
    # second row of the table in rules.md G-2, and it is the row that requires
    # false (rules.md B-1).
    condition     = var.enable_backend_security_group == false
    error_message = "enable_backend_security_group must be false in this variant. Its Services name their own frontend security groups and do not set manage-backend-security-group-rules, so the node-side rules are declared in Terraform (load_balancer_to_pods). To let the controller manage them instead, add that annotation to both Services and set this to true (rules.md G-2)."
  }
}

# --- Frontend security group shared by both load balancers ---

variable "load_balancer_security_group_name" {
  type        = string
  default     = "nlb-sg"
  description = "Name of the frontend security group both network load balancers carry, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.load_balancer_security_group_name)) && !startswith(var.load_balancer_security_group_name, "sg-")
    error_message = "load_balancer_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}

variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the controlled inbound rules use 0.0.0.0/0. When false (the default), they use only the public IPv4 /32 dynamically returned by my_ip_lookup_url"
}

# --- GitLab ---

variable "gitlab_domain" {
  type = string
  # No default, unlike the _monolithic template's example.com. With a default,
  # Terraform never asks for this value, so a domain that did not arrive under
  # exactly this name on the apply itself was dropped without an error - a tfvars
  # entry the root does not declare only warns, an undeclared TF_VAR_ is ignored
  # outright, and a -var given to plan does not carry over to a later apply.
  # GitLab was then installed for example.com: global.hosts.domain, every Ingress
  # host, the certificates and the gitlab_url output all derive from this one
  # value. Required, an apply without it stops and asks instead.
  description = "Domain GitLab is served under, e.g. example.com. Every GitLab hostname is derived from it - gitlab.<domain> (the gitlab_url output), registry.<domain>, minio.<domain> and kas.<domain> - so a wildcard record for it has to resolve to the GitLab load balancer, which is what create_dns_record does when the zone is in this account"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.gitlab_domain))
    error_message = "gitlab_domain must be a valid lowercase DNS name with at least two labels (e.g. example.com)."
  }
}

variable "admin_email" {
  type = string
  # No default, for the same reason as gitlab_domain and with a harder edge: the
  # _monolithic template's me@example.com is an address Let's Encrypt refuses, so
  # that default could only ever produce a GitLab issuer that never registers.
  description = "Email address GitLab's cert-manager issuer registers its Let's Encrypt account with, also shown as the Jenkins administrator contact, as the _monolithic template used it for both. Must not be at example.com, example.net or example.org"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.admin_email))
    error_message = "admin_email must look like an email address."
  }

  validation {
    # Let's Encrypt refuses an account whose contact is at one of the three RFC 2606
    # example domains (boulder's forbiddenMailDomains). Nothing Terraform looks at
    # shows it: the release reports deployed, the Issuer stays at
    # ErrRegisterACMEAccount, and every GitLab hostname keeps cert-manager's
    # temporary self-signed certificate while its Certificate even reads Ready
    # (rules.md B-1).
    condition     = !can(regex("@example\\.(com|net|org)$", lower(var.admin_email)))
    error_message = "admin_email must not be at example.com, example.net or example.org. Let's Encrypt refuses an account whose contact is at one of those domains (\"contact email has forbidden domain\"), so GitLab's issuer never registers and every GitLab hostname keeps a self-signed certificate - with no error in plan or apply. Use a real address, such as one at your own domain."
  }
}

variable "gitlab_chart_version" {
  type        = string
  default     = "9.11.13"
  description = "Pinned GitLab chart version, in the 9.x series. Chart 10.0.0 removed the bundled PostgreSQL, Redis and MinIO subcharts and made all three external preconditions, so a 10.x version turns this project into one that also has to build an RDS instance, an ElastiCache cluster and S3 buckets. 9.11.13 is the newest version that still bundles them, which is the all-in-one install the _monolithic script performed"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.gitlab_chart_version))
    error_message = "gitlab_chart_version must be a three-part semantic version."
  }

  validation {
    # Single-digit major, not a numeric comparison: the regex validation above
    # does not gate this one, so tonumber on a non-numeric major would raise a
    # hard error rather than report this message (rules.md B-1).
    condition     = can(regex("^[0-9]\\.", var.gitlab_chart_version))
    error_message = "gitlab_chart_version must be below 10.0.0. Chart 10.0.0 removed the bundled PostgreSQL, Redis and MinIO, and the chart refuses to render without external replacements - a failure that shows up partway through apply as a CONFIGURATION CHECKS block, not at plan. 9.11.13 is the newest version that still bundles them. To run 10.x, provision external PostgreSQL, Redis and S3 object storage and pass them to module.gitlab through its additional_set_values."
  }
}

variable "gitlab_wait" {
  type        = bool
  default     = false
  description = "Whether the apply blocks until every GitLab workload is ready. False, as the _monolithic script behaved: the chart installs around thirty workloads plus migration Jobs and a first install regularly runs past fifteen minutes"
}

variable "create_dns_record" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether to create the *.<gitlab_domain> alias record pointing at the GitLab load balancer, in this
    account's public hosted zone for gitlab_domain. True, as the _monolithic template had it.

    The record is not only how a browser reaches GitLab. Everything inside the release that talks to
    GitLab uses the public hostnames as well - CoreDNS forwards them to the VPC resolver, which asks
    public DNS - so without it the release still reports deployed while:
      - the bundled runner PANICs on every registration attempt with
        "lookup gitlab.<domain> on <cluster DNS>:53: no such host",
      - cert-manager's HTTP-01 self check fails the same way, so it never asks Let's Encrypt to
        validate, and every hostname keeps the temporary cert-manager.local certificate while its
        Certificate reads Ready,
      - and the gitlab_url output answers nothing.

    This used to default to false, so that a plan in an account without the zone would not stop at the
    zone lookup. That traded one loud failure at plan for the three silent ones above. Now an account
    without the zone stops at plan with "no matching Route 53 Hosted Zone found".

    Set it to false only when the zone lives somewhere else - another account or another DNS
    provider - and create the record there, pointing at the gitlab_load_balancer_url output. GitLab
    stays in the state above until that record resolves (rules.md B-1/B-4).
  DESC
}

variable "dns_record_name" {
  type        = string
  default     = null
  description = "Record name created in the hosted zone. Null uses *.<gitlab_domain>, which is what the _monolithic template created - one wildcard covering gitlab., registry., minio. and kas."

  validation {
    condition     = var.dns_record_name == null || length(var.dns_record_name) > 0
    error_message = "dns_record_name must be a non-empty record name, or null to derive *.<gitlab_domain>."
  }
}

# --- Jenkins ---

variable "jenkins_admin_username" {
  type        = string
  default     = "admin"
  description = "Jenkins administrator login name"

  validation {
    condition     = length(var.jenkins_admin_username) > 0
    error_message = "jenkins_admin_username must not be empty."
  }
}

variable "jenkins_admin_password" {
  type        = string
  sensitive   = true
  default     = "ChangeMe-Jenkins-1"
  description = "Jenkins administrator password. The _monolithic template defaulted to \"jenkins\" for an installation published through an internet-facing load balancer; this default is only longer, not secret, so override it"

  validation {
    condition     = length(var.jenkins_admin_password) >= 8
    error_message = "jenkins_admin_password must be at least 8 characters."
  }
}

variable "jenkins_chart_version" {
  type        = string
  default     = "5.9.64"
  description = "Pinned Jenkins chart version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.jenkins_chart_version))
    error_message = "jenkins_chart_version must be a three-part semantic version."
  }
}

variable "jenkins_ingress_nginx_chart_version" {
  type        = string
  default     = "4.13.0"
  description = "Pinned ingress-nginx chart version for the controller in front of Jenkins"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.jenkins_ingress_nginx_chart_version))
    error_message = "jenkins_ingress_nginx_chart_version must be a three-part semantic version."
  }
}

variable "jenkins_ingress_class_name" {
  type        = string
  default     = "jenkins-nginx"
  description = "IngressClass the Jenkins ingress controller creates and the Jenkins Ingress asks for. Not set as the cluster default, because GitLab brings its own controller and a shared default would let either claim the other's Ingress"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.jenkins_ingress_class_name))
    error_message = "jenkins_ingress_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}

# --- Pre-created load balancers ---

variable "gitlab_load_balancer_name" {
  type        = string
  default     = null
  description = "Name of the pre-created NLB in front of GitLab. Null generates a unique name, which is what lets this project be deployed twice in one account - adoption is decided by tags, never by the name (rules.md G-3)"

  validation {
    condition     = var.gitlab_load_balancer_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.gitlab_load_balancer_name))
    error_message = "gitlab_load_balancer_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}

variable "jenkins_load_balancer_name" {
  type        = string
  default     = null
  description = "Name of the pre-created NLB in front of Jenkins. Null generates a unique name"

  validation {
    condition     = var.jenkins_load_balancer_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.jenkins_load_balancer_name))
    error_message = "jenkins_load_balancer_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}

# --- Storage ---

variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the gp3 StorageClass this project marks as the cluster default. Both GitLab and Jenkins claim volumes without naming a class, so the default is what they get"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}

# --- Workbench instance ---

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the code-server workbench, as the _monolithic template sized it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date>. Kept within one minor of kubernetes_version; the _monolithic template pinned a 1.33 build"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.1"
  description = "code-server release installed on the workbench. The _monolithic template pinned 4.102.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each bootstrap stage drops its completion marker (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}

variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association waits for success. It has to cover the whole instance bootstrap, since the command blocks on the userdata marker"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}

# --- Names the adoption tags are built from ---
#
# These exist as variables rather than literals because three places have to agree
# on each of them: the Helm release that creates the Service, the pre-created load
# balancer's service.k8s.aws/stack tag, and the verification command that reads the
# address back. A disagreement is not an error - the controller simply builds a
# second load balancer (rules.md G-3).

variable "gitlab_namespace" {
  type        = string
  default     = "gitlab"
  description = "Namespace the GitLab release is installed into, and the first half of its adoption tag"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gitlab_namespace))
    error_message = "gitlab_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "gitlab_release_name" {
  type        = string
  default     = "gitlab"
  description = "GitLab Helm release name. The chart's bundled ingress controller Service is named <release>-nginx-ingress-controller, which is the second half of the adoption tag"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gitlab_release_name))
    error_message = "gitlab_release_name must be a valid lowercase RFC 1123 label."
  }
}

variable "jenkins_namespace" {
  type        = string
  default     = "jenkins"
  description = "Namespace both the Jenkins release and its ingress-nginx controller are installed into, as the _monolithic script had them"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.jenkins_namespace))
    error_message = "jenkins_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "jenkins_ingress_release_name" {
  type        = string
  default     = "jenkins-nginx"
  description = "Helm release name of the ingress-nginx controller in front of Jenkins, as the _monolithic script named it. The module pins fullnameOverride to it, so its Service is <release>-controller rather than the chart's conditional <release>-ingress-nginx-controller"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.jenkins_ingress_release_name))
    error_message = "jenkins_ingress_release_name must be a valid lowercase RFC 1123 label."
  }
}

variable "jenkins_release_name" {
  type        = string
  default     = "jenkins"
  description = "Jenkins Helm release name. Also the name of the Ingress and Secret the chart creates"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.jenkins_release_name))
    error_message = "jenkins_release_name must be a valid lowercase RFC 1123 label."
  }
}

variable "load_balancer_ports" {
  type = map(number)
  default = {
    http  = 80
    https = 443
  }
  description = "Ports both ingress controller Services publish, the frontend security group opens, and the node-side rules allow. One map feeding all three, so a listener the security group never opened cannot appear (rules.md B-5). Both, as the _monolithic template's nlb-sg had them"

  validation {
    condition     = length(var.load_balancer_ports) > 0
    error_message = "load_balancer_ports must contain at least one port."
  }

  validation {
    condition     = alltrue([for name in keys(var.load_balancer_ports) : contains(["http", "https"], name)])
    error_message = "load_balancer_ports keys must be http or https - the only two ports the ingress-nginx chart defines under controller.service.ports. Any other key renders into a value the chart ignores, which is not an error and leaves the Service on its defaults."
  }

  validation {
    condition     = alltrue([for port in values(var.load_balancer_ports) : port > 0 && port <= 65535])
    error_message = "load_balancer_ports values must be valid TCP ports."
  }
}

variable "my_ip_lookup_url" {
  type        = string
  default     = "https://checkip.amazonaws.com/"
  description = "Trusted HTTPS endpoint that returns the public IPv4 address of the machine running Terraform. The address is converted to a /32 and used when an allow_inbound_from_anywhere switch is false"

  validation {
    condition     = startswith(var.my_ip_lookup_url, "https://")
    error_message = "my_ip_lookup_url must be an HTTPS URL because its response controls which source address the security groups admit."
  }
}
