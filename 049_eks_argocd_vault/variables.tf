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
  default     = "argocd-vault-cluster"
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
variable "argocd_cli_version" {
  type        = string
  default     = "v3.1.5"
  description = "Pinned Argo CD CLI version installed on the VS Code instance. The _monolithic template downloaded /releases/latest, so a rebuild picked up whatever was current - and a CLI ahead of the server refuses some commands. Pinned to match argocd_image_tag (rules.md H-1)"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_cli_version))
    error_message = "argocd_cli_version must look like v3.1.5."
  }
}
variable "github_user" {
  type        = string
  description = "GitHub username the token belongs to and the owner of the repository Argo CD is pointed at. No default: it identifies a real account"

  validation {
    # No lookahead: Terraform's regex is RE2, which has none, and can() would swallow the
    # resulting error and report every value as invalid. The "no trailing or doubled hyphen" rule
    # is expressed by requiring an alphanumeric after each hyphen instead.
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9]|-[A-Za-z0-9])*$", var.github_user)) && length(var.github_user) <= 39
    error_message = "github_user must be a valid GitHub username: 1-39 characters of letters, digits and single hyphens, not starting or ending with a hyphen."
  }
}
variable "github_repo" {
  type        = string
  default     = "argocd-vault-sample"
  description = "Repository name Argo CD syncs from, and the directory the seed manifests are written into on the instance"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.github_repo))
    error_message = "github_repo must be 100 characters or fewer of letters, digits, dots, underscores and hyphens."
  }
}
variable "github_repo_visibility" {
  type        = string
  default     = "private"
  description = "Visibility of the seed repository this configuration creates. Private by default: the manifests hold <path:...> placeholders rather than secrets, but the repository is created under a real account and a demo is a poor reason to publish anything"

  validation {
    condition     = contains(["public", "private"], var.github_repo_visibility)
    error_message = "github_repo_visibility must be either public or private."
  }
}
variable "github_manifest_path" {
  type        = string
  default     = "manifest"
  description = "Directory inside the repository the manifests are committed to, and the --path Argo CD is given. One variable because three places have to agree - the commit paths, the working copy on the instance and the application's path - and an application whose path holds no manifests syncs nothing while reporting no error (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$", var.github_manifest_path))
    error_message = "github_manifest_path must be a relative path with no leading or trailing slash, such as \"manifest\"."
  }
}
variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token for the CodeBuild source credential. sensitive so plan and apply do not print it, and no default on purpose. Pass it with TF_VAR_github_token"

  validation {
    condition     = can(regex("^(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})$", var.github_token))
    error_message = "github_token must look like a GitHub personal access token: ghp_/gho_/ghu_/ghs_/ghr_ followed by at least 36 characters, or github_pat_ followed by at least 22."
  }
}
variable "seed_workload_image" {
  type        = string
  default     = "nginx:1.29-alpine"
  description = "Image for the seed deployment Argo CD syncs. The _monolithic template used nginx:latest, which means the Application drifts every time the upstream tag moves - exactly the thing a GitOps demo should not do. Pinned instead"

  validation {
    condition     = can(regex(":", var.seed_workload_image))
    error_message = "seed_workload_image must include an explicit tag; a bare name resolves to :latest and changes under the deployment."
  }
}
variable "vault_namespace" {
  type        = string
  default     = "vault"
  description = "Namespace Vault runs in, and the first half of its Ingress adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.vault_namespace))
    error_message = "vault_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "vault_release_name" {
  type        = string
  default     = "vault"
  description = "Helm release name for Vault. The chart names its Ingress after it, which is the second half of the adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.vault_release_name))
    error_message = "vault_release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "vault_chart_version" {
  type        = string
  default     = "0.34.1"
  description = "Pinned hashicorp/vault chart version. The _monolithic template pinned nothing"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.vault_chart_version))
    error_message = "vault_chart_version must be a semantic version."
  }
}
variable "vault_secrets_engine_path" {
  type        = string
  default     = "kv"
  description = "Mount path for the kv-v2 secrets engine the bootstrap enables. The seed manifests reference <path:kv/data/admin#user>, so this and the seed have to agree - which is why both read this one variable (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]*$", var.vault_secrets_engine_path))
    error_message = "vault_secrets_engine_path must be a lowercase mount path such as kv."
  }
}
variable "vault_demo_secret_name" {
  type        = string
  default     = "admin"
  description = "Name of the demo secret written into the kv engine. The seed deployment reads kv/data/<this>#user and #password, so the two move together"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_/-]*$", var.vault_demo_secret_name))
    error_message = "vault_demo_secret_name must be a lowercase secret path such as admin."
  }
}
variable "vault_demo_secret_user" {
  type        = string
  default     = "demo-user"
  description = "Value written to the demo secret's user field. Not a credential to anything - it exists so the plugin has something to substitute into the seed deployment's ADMIN_USER"

  validation {
    condition     = length(var.vault_demo_secret_user) > 0
    error_message = "vault_demo_secret_user must not be empty."
  }
}
variable "vault_demo_secret_password" {
  type        = string
  sensitive   = true
  description = "Value written to the demo secret's password field. sensitive because it is a secret by construction, even in a demo - the _monolithic template had \"hyunsu1234\" inline in a commented-out command. No default, so nothing ships with a known value. Pass it with TF_VAR_vault_demo_secret_password"

  validation {
    condition     = length(var.vault_demo_secret_password) >= 8
    error_message = "vault_demo_secret_password must be at least 8 characters."
  }
}
variable "argocd_namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace Argo CD runs in, and the first half of its Service adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.argocd_namespace))
    error_message = "argocd_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "argocd_release_name" {
  type        = string
  default     = "argocd"
  description = "Helm release name for Argo CD. The chart names the server Service <release>-server, which is the second half of the adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.argocd_release_name))
    error_message = "argocd_release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "argocd_chart_version" {
  type        = string
  default     = "10.9.2"
  description = "Pinned argo-cd chart version. Replaces the _monolithic template's \"kubectl apply -f .../stable/manifests/install.yaml\", which installed a different Argo CD on every apply"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_chart_version))
    error_message = "argocd_chart_version must be a semantic version."
  }
}
variable "argocd_image_tag" {
  type        = string
  default     = "v3.1.5"
  description = "Argo CD application image tag, pinned alongside the chart. The CLI on the instance is pinned to the same value so the two cannot drift"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_image_tag))
    error_message = "argocd_image_tag must look like v3.1.5."
  }
}
variable "avp_version" {
  type        = string
  default     = "1.16.1"
  description = "Pinned argocd-vault-plugin version the repo-server's init container downloads"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.avp_version))
    error_message = "avp_version must be a semantic version."
  }
}
variable "argocd_server_insecure" {
  type        = bool
  default     = true
  description = "Whether argocd-server serves plain HTTP instead of terminating TLS and redirecting to HTTPS"

  validation {
    # A constant condition, because the constraint is about this variant rather than a combination
    # of values (rules.md B-1). Nothing detects the violation at plan or apply time: the release
    # installs, the Service gets its address, every target reports healthy, and only a browser finds
    # out. Measured against the deployed stack before this was pinned:
    #
    #   http://<nlb>   -> 307, Location: https://<nlb>/
    #   https://<nlb>  -> connection failed
    condition     = var.argocd_server_insecure
    error_message = "argocd_server_insecure must be true in this variant, because the Argo CD frontend security group opens only argocd_load_balancer_port and the project outputs an http:// URL. With TLS on, argocd-server answers that port with a 307 to https:// and the dashboard cannot be reached at all. To run with it false, add the HTTPS port to nlb_security_group's ports map and expect a self-signed certificate warning."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the helm and kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2). Narrow public_access_cidrs rather than leaving the default open"

  validation {
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
  default     = "argocd-vault-key"
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
  default     = ["t3.medium"]
  description = "Instance types for the managed node group"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 3
  description = "Desired node count. Three rather than two, because Argo CD brings seven deployments and Vault a StatefulSet on top of the cluster addons - pods left Pending on capacity look exactly like pods left Pending on volumes"

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
variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the gp3 StorageClass backed by the EBS CSI driver, as the _monolithic template named it. Vault's claim names this rather than relying on a default class, because a fresh EKS cluster has none - its built-in gp2 uses the in-tree provisioner removed in Kubernetes 1.23 and carries no default annotation, so a claim that names no class binds to nothing and vault-0 stays Pending"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The controller is what turns Vault's Ingress into the ALB and Argo CD's Service into the NLB"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because the one such Service here - Argo CD's server - sets aws-load-balancer-type: external and is claimed without it (rules.md G-1). The chart gives that webhook failurePolicy: Fail and no namespaceSelector, so leaving it on gates every Service creation in the cluster behind a controller pod being Ready, and this project creates well over a dozen (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. Argo CD's server Service sets aws-load-balancer-type: external, so the controller claims it without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster (rules.md G-4)."
  }
}
variable "vault_load_balancer_port" {
  type        = number
  default     = 80
  description = "Listener port on the ALB fronting Vault's UI, and the port its frontend security group opens. Vault's Ingress terminates nothing, so this is plain http"

  validation {
    condition     = var.vault_load_balancer_port > 0 && var.vault_load_balancer_port <= 65535
    error_message = "vault_load_balancer_port must be between 1 and 65535."
  }
}
variable "argocd_load_balancer_port" {
  type        = number
  default     = 80
  description = "Listener port on the NLB fronting the Argo CD UI, and the port its frontend security group opens. The chart's server Service publishes 80 and 443; this project reaches it over 80 as the _monolithic template did, so only that port is opened"

  validation {
    condition     = var.argocd_load_balancer_port > 0 && var.argocd_load_balancer_port <= 65535
    error_message = "argocd_load_balancer_port must be between 1 and 65535."
  }
}
variable "argocd_container_port" {
  type        = number
  default     = 8080
  description = "Container port the argocd-server pod listens on. Distinct from the Service port on purpose: with target-type ip the load balancer sends traffic straight to the pod, so this - not the Service port - is what the pod-side rule on the cluster security group has to open. Opening the Service port instead leaves every target unhealthy with no error anywhere (rules.md G-1/G-2)"

  validation {
    condition     = var.argocd_container_port > 0 && var.argocd_container_port <= 65535
    error_message = "argocd_container_port must be between 1 and 65535."
  }
}
variable "vault_container_port" {
  type        = number
  default     = 8200
  description = "Container port Vault listens on, and the target the ALB sends traffic to under target-type ip - so the port the pod-side rule opens (rules.md G-1/G-2)"

  validation {
    condition     = var.vault_container_port > 0 && var.vault_container_port <= 65535
    error_message = "vault_container_port must be between 1 and 65535."
  }
}
variable "alb_security_group_name" {
  type        = string
  default     = "argocd-vault-alb-sg"
  description = "Name of the frontend security group attached to the pre-created ALB in front of Vault"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "nlb_security_group_name" {
  type        = string
  default     = "argocd-vault-nlb-sg"
  description = "Name of the frontend security group attached to the pre-created NLB in front of Argo CD"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.nlb_security_group_name)) && !startswith(var.nlb_security_group_name, "sg-")
    error_message = "nlb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "vault_load_balancer_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created ALB. Null generates a unique one, which is what lets this project be deployed twice in one account - adoption is decided entirely by tags, so the name plays no part in it (rules.md G-3)"

  validation {
    condition     = var.vault_load_balancer_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.vault_load_balancer_name))
    error_message = "vault_load_balancer_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "argocd_load_balancer_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created NLB. Null generates a unique one (rules.md G-3)"

  validation {
    condition     = var.argocd_load_balancer_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.argocd_load_balancer_name))
    error_message = "argocd_load_balancer_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the two frontend security groups and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it, because all three UIs are reached from a browser - but code-server has no authentication and Vault's UI holds the demo secrets, so narrow this where possible"
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
  description = "Directory on the VS Code instance where each step drops its completion marker. The associations chain on these markers rather than trusting depends_on (rules.md D-5/H-2)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "vault_bootstrap_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the Vault bootstrap association may take. It waits for the instance bootstrap, then for vault-0 to be Running, then initialises and unseals Vault"

  validation {
    condition     = var.vault_bootstrap_timeout_seconds > 0
    error_message = "vault_bootstrap_timeout_seconds must be positive."
  }
}
variable "github_seed_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the seed-repository association may take. It writes three manifests, zips them and uploads the zip to S3"

  validation {
    condition     = var.github_seed_timeout_seconds > 0
    error_message = "github_seed_timeout_seconds must be positive."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README association may take. It is last in the marker chain, so it waits for both steps before it"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
