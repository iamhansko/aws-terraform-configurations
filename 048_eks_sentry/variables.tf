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
  default     = "sentry-cluster"
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
variable "sentry_admin_email" {
  type        = string
  default     = "admin@example.com"
  description = "Login name for the Sentry admin user. The chart's own default is admin@sentry.local; this is only the username half, so it is not treated as a secret"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.sentry_admin_email))
    error_message = "sentry_admin_email must look like an email address, because Sentry uses it as the login name."
  }
}
variable "sentry_admin_password" {
  type        = string
  sensitive   = true
  description = "Password for the Sentry admin user. No default on purpose: the chart defaults it to \"aaaa\" and this project publishes the dashboard through an internet-facing load balancer, so a default here would be a working administrator login on a public address. Pass it with TF_VAR_sentry_admin_password"

  validation {
    condition     = length(var.sentry_admin_password) >= 12
    error_message = "sentry_admin_password must be at least 12 characters. The dashboard it protects is reachable from the internet whenever allow_inbound_from_anywhere is true."
  }
}
variable "sentry_namespace" {
  type        = string
  default     = "monitoring"
  description = "Namespace Sentry and its subcharts install into, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.sentry_namespace))
    error_message = "sentry_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "sentry_chart_version" {
  type        = string
  default     = "27.1.0"
  description = "Pinned Sentry chart version, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.sentry_chart_version))
    error_message = "sentry_chart_version must be a semantic version."
  }
}
variable "sentry_cli_version" {
  type        = string
  default     = "2.42.2"
  description = "Pinned sentry-cli version installed on the VS Code instance. The _monolithic template piped the installer with no version, so every rebuild picked up whatever was current - and the CLI's major versions are not interchangeable with older self-hosted servers. It goes into the user's own bin, so the install needs no sudo (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.sentry_cli_version))
    error_message = "sentry_cli_version must be a semantic version, e.g. 2.42.2."
  }
}
variable "sentry_timeout_seconds" {
  type        = number
  default     = 5400
  description = <<-DESC
    How long to wait for the Sentry release.

    Raised from the 3000 the _monolithic template used. The chart installs through 12 serialized helm
    hook weights - 5 Jobs and 40 Deployments carry a helm.sh/hook annotation - and helm waits for each
    weight group before starting the next. One of those groups runs the ClickHouse migrations, and each
    wave of Deployments pulls the getsentry/sentry image onto nodes with no cached layers.

    When it is too short helm reports one line, "context deadline exceeded", and the release is left in
    `failed` state - so the next apply reports a name collision instead and the original cause is gone
    (rules.md E-7).
  DESC

  validation {
    condition     = var.sentry_timeout_seconds >= 1800
    error_message = "sentry_timeout_seconds must be at least 1800; this chart's serialized hook chain does not finish faster than that on a cold cluster."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the helm provider runs on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2). Narrow public_access_cidrs rather than leaving the default open"

  validation {
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its charts are installed by the helm provider from the machine running terraform. To run with a private endpoint, install them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "sentry-key"
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
    error_message = "public_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer."
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
  default     = ["t3.xlarge"]
  description = <<-DESC
    Instance types for the managed node group.

    Sized by pod count, not by CPU or memory. `helm template` of this chart renders 46 Deployments and
    7 StatefulSets - 55 pods once replicas are counted - and only four of them declare a resource
    request at all, 2.1 vCPU and 2.1 GiB between them. So what decides whether the release can come up
    is how many pods a node will accept, and under the VPC CNI that is
    (ENIs x (IPs per ENI - 1)) + 2:

      t3.medium   3 x (6 - 1)  + 2 =  17
      t3.large    3 x (12 - 1) + 2 =  35
      t3.xlarge   4 x (15 - 1) + 2 =  58

    t3.medium was the earlier default, and three of them give 51 slots before the DaemonSets take
    theirs - about 39 usable against 55 needed. The chart's pods stayed Pending on "Too many pods",
    helm waited out its whole 3000 second timeout, and the release was left in `failed` state. Every
    apply after that reported only "cannot re-use a name that is still in use", which describes the
    second attempt and says nothing about the first (rules.md E-7).
  DESC

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }

  validation {
    # The maxPods table is inline rather than a local, because a variable validation can only see
    # other variables. Restricted to the types whose pod capacity has actually been worked out -
    # anything else would be checked against a number nobody verified.
    condition = alltrue([
      for t in var.node_group_instance_types :
      contains(["t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge", "m5.large", "m5.xlarge", "m5.2xlarge"], t)
    ])
    error_message = "node_group_instance_types must be drawn from t3.medium, t3.large, t3.xlarge, t3.2xlarge, m5.large, m5.xlarge or m5.2xlarge. This variant checks that the node group offers enough pod slots for the chart, and it can only do that for types whose maxPods value is recorded in node_group_desired_size's validation."
  }
}
variable "sentry_required_pod_slots" {
  type        = number
  default     = 55
  description = <<-DESC
    How many pods the Sentry chart schedules, used to check the node group is large enough before
    anything is created.

    Measured rather than estimated, and re-measurable without a cluster:

      helm template sentry sentry/sentry --version <chart_version> \
        --set user.email=a@b.c --set user.password=x \
        | grep -cE '^kind: (Deployment|StatefulSet)'

    That counts objects; 55 is the figure with replicas counted. Raise it when the chart version moves,
    because a chart that outgrows the node group fails as a 50-minute helm timeout rather than as
    anything that names the cause.
  DESC

  validation {
    condition     = var.sentry_required_pod_slots > 0
    error_message = "sentry_required_pod_slots must be positive."
  }
}
variable "node_overhead_pods_per_node" {
  type        = number
  default     = 3
  description = "Pods each node gives up to DaemonSets before any workload is scheduled: aws-node, kube-proxy and the EBS CSI node driver. Subtracted from the node group's raw pod capacity in the check below, so that check compares usable slots rather than advertised ones"

  validation {
    condition     = var.node_overhead_pods_per_node >= 0
    error_message = "node_overhead_pods_per_node must not be negative."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 3
  description = "Desired node count. Three, and what makes three enough is the instance type rather than the count - see node_group_instance_types for the arithmetic"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }

  validation {
    # The constraint is about the combination - instance type, node count, and how many pods the chart
    # brings - so it cannot be stated on any one of them alone (rules.md B-1). Cross-variable
    # conditions are available since Terraform 1.9, which this repository requires.
    #
    # Worth blocking in plan because the failure mode is so poor: the pods that do not fit stay
    # Pending, helm waits out its timeout, and the release is left `failed` so every later apply
    # reports a name collision instead (rules.md E-7).
    condition = (
      var.node_group_desired_size * (
        lookup({
          "t3.medium" = 17, "t3.large" = 35, "t3.xlarge" = 58, "t3.2xlarge" = 58,
          "m5.large"  = 29, "m5.xlarge" = 58, "m5.2xlarge" = 58,
        }, var.node_group_instance_types[0], 0) - var.node_overhead_pods_per_node
      ) - 3 # CoreDNS replicas plus the ingress controller
    ) >= var.sentry_required_pod_slots
    error_message = "node_group_desired_size x the instance type's maxPods, less the DaemonSet overhead, must leave at least sentry_required_pod_slots free. The Sentry chart schedules 55 pods and only four of them request any CPU or memory, so the binding limit is how many pods a node accepts - (ENIs x (IPs per ENI - 1)) + 2 under the VPC CNI, which is 17 for a t3.medium and 58 for a t3.xlarge. Raise the instance type or the node count: pods that do not fit stay Pending, helm waits out its whole timeout, and the release is then stuck in `failed` state (rules.md B-1/E-7)."
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
  description = "Maximum node count. Nothing scales the node group here, so this is only headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "bitnami_image_namespace" {
  type        = string
  default     = "bitnamilegacy"
  description = "Docker Hub namespace the Sentry chart's Bitnami-based subchart images are pulled from. bitnamilegacy rather than bitnami: Bitnami moved its versioned tags into that namespace, so the tags this chart pins return NotFound under bitnami - which stops PostgreSQL and surfaces as the db-check hook failing with DeadlineExceeded. The legacy namespace receives no updates, so a mirror is the better long-term answer"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*[a-z0-9]$", var.bitnami_image_namespace))
    error_message = "bitnami_image_namespace must be a lowercase Docker repository namespace such as \"bitnamilegacy\", with no leading or trailing slash and no tag."
  }
}
variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the default gp3 StorageClass backed by the EBS CSI driver, as the _monolithic template named it. Cosmetic rather than referenced: none of the chart's eight claims names a storageClassName, so they reach this class through its default annotation - which is also why a cluster without a default class leaves all eight Pending"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The controller is what turns the ingress controller's Service into the NLB; the _monolithic template installed it from a helm command in userdata (rules.md E-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because the one such Service here - the ingress controller's - sets aws-load-balancer-type: external and is claimed without it (rules.md G-1). The chart gives that webhook failurePolicy: Fail and no namespaceSelector, so leaving it on gates every Service creation in the cluster behind a controller pod being Ready - and the Sentry chart creates a dozen Services (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. The ingress controller's Service sets aws-load-balancer-type: external, so the controller claims it without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster - including all of Sentry's subchart Services (rules.md G-4)."
  }
}
variable "ingress_namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the ingress controller is installed into. kube-system as the _monolithic template had it, which is also why the load balancer's stack tag reads kube-system/ingress-nginx-controller (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_namespace))
    error_message = "ingress_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_release_name" {
  type        = string
  default     = "ingress-nginx"
  description = "Helm release name for the ingress controller. The chart names its controller Service <release>-controller once fullnameOverride pins the fullname, and that Service name is half of the stack tag the pre-created load balancer must carry to be adopted (rules.md G-3)"

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
variable "load_balancer_ports" {
  type = map(number)
  default = {
    http  = 80
    https = 443
  }
  description = "Ports the ingress controller's Service publishes and its load balancer listens on, keyed by the names the ingress-nginx chart uses under controller.service.ports. One map drives the Service, the frontend security group and the rule from the load balancer to the pods, so the three cannot disagree (rules.md B-5/G-1). The _monolithic template opened only 80 on the security group while the chart published 80 and 443, leaving the https listener reachable by nothing"

  validation {
    condition     = length(var.load_balancer_ports) > 0
    error_message = "load_balancer_ports must contain at least one port."
  }
  validation {
    condition     = alltrue([for name in keys(var.load_balancer_ports) : contains(["http", "https"], name)])
    error_message = "load_balancer_ports keys must be http or https - the only two port names the ingress-nginx chart defines under controller.service.ports."
  }
  validation {
    condition     = alltrue([for port in values(var.load_balancer_ports) : port > 0 && port <= 65535])
    error_message = "load_balancer_ports values must be between 1 and 65535."
  }
}
variable "load_balancer_security_group_name" {
  type        = string
  default     = "sentry-nlb-sg"
  description = "Name of the frontend security group attached to the pre-created NLB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.load_balancer_security_group_name)) && !startswith(var.load_balancer_security_group_name, "sg-")
    error_message = "load_balancer_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "synced_load_balancer_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created NLB. Null generates a unique one, which is what lets this project be deployed twice in one account - adoption is decided entirely by tags, so the name plays no part in it (rules.md G-3)"

  validation {
    condition     = var.synced_load_balancer_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.synced_load_balancer_name))
    error_message = "synced_load_balancer_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the NLB's frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it, because the Sentry dashboard and code-server are both reached from a browser - but code-server has no authentication in front of it and Sentry's admin login is only as strong as sentry_admin_password, so narrow this where possible"
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
  description = "How long the README SSM association may take. It first waits for the instance bootstrap to finish, which includes downloading kubectl, eksctl, helm and the Sentry CLI"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
