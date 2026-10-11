variable "cluster_host" {
  type        = string
  description = "Public host name clients reach this Teleport cluster on. The chart uses it as the cluster's own identity and as the subject of the certificate it asks cert-manager for - the Certificate covers this name and *.<name>, so the DNS records pointing at the load balancer have to use the same value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.cluster_host)) && length(split(".", var.cluster_host)) >= 2
    error_message = "cluster_host must be a fully qualified lowercase DNS name such as teleport.example.com."
  }
}
variable "kube_cluster_name" {
  type        = string
  description = "Name this Kubernetes cluster is registered under inside Teleport. What a user sees in 'tsh kube ls', and what they pass to 'tsh kube login' - so it is worth being the EKS cluster's own name rather than the chart default"

  validation {
    condition     = length(var.kube_cluster_name) > 0
    error_message = "kube_cluster_name must not be empty."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace Teleport installs into, as the _monolithic template had it. Part of the IRSA trust policy's sub conditions, so it and the service account names below have to agree with where the chart actually puts them"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "release_name" {
  type        = string
  default     = "teleport"
  description = "Helm release name. The chart derives a great deal from it: the proxy Service, the auth and proxy Deployments, and all four service accounts are named after it - which is also why the adoption stack tag for the pre-created load balancer is <namespace>/<release name> (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://charts.releases.teleport.dev"
  description = "Helm repository hosting the teleport-cluster chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "18.11.2"
  description = "Pinned teleport-cluster chart version, where the _monolithic template pinned nothing. It matters more than usual here: the chart's major version is Teleport's own, and the state format in DynamoDB migrates forward on start - so an unpinned upgrade can move the backend to a version an older Teleport cannot read"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 18.11.2)."
  }
}
variable "aws_region" {
  type        = string
  description = "Region Teleport calls DynamoDB and S3 in"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name."
  }
}
variable "backend_table" {
  type        = string
  default     = "teleport-helm-backend"
  description = "DynamoDB table holding cluster state. Teleport creates it itself on first start, which is why the IAM policy here includes dynamodb:CreateTable - the table is deliberately not a Terraform resource, because its schema and its indexes are Teleport's to define and change between versions"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{3,255}$", var.backend_table))
    error_message = "backend_table must be 3-255 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "audit_log_table" {
  type        = string
  default     = "teleport-helm-events"
  description = "DynamoDB table holding the audit log. Created by Teleport for the same reason as backend_table, and separate from it so a retention policy can differ"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{3,255}$", var.audit_log_table))
    error_message = "audit_log_table must be 3-255 characters of letters, digits, dots, underscores and hyphens."
  }
  validation {
    # Cross-variable, available since Terraform 1.9 (rules.md B-1). Teleport would treat
    # one table as both, and the audit log's index layout is not the backend's.
    condition     = var.audit_log_table != var.backend_table
    error_message = "audit_log_table must differ from backend_table; cluster state and the audit log have different schemas and cannot share a table."
  }
}
variable "session_recording_bucket" {
  type        = string
  description = "S3 bucket session recordings are written to. Injected by name rather than looked up, so this module never learns how the bucket was configured (rules.md B-6)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.session_recording_bucket))
    error_message = "session_recording_bucket must be a valid S3 bucket name."
  }
}
variable "session_recording_bucket_arn" {
  type        = string
  description = "ARN of the same bucket, used as the resource in the writer's IAM policy. Passed alongside the name rather than rebuilt as arn:aws:s3:::<name>, so it stays correct in a partition where that prefix differs (rules.md B-5)"

  validation {
    condition     = can(regex("^arn:aws:s3:::", var.session_recording_bucket_arn))
    error_message = "session_recording_bucket_arn must be an S3 bucket ARN."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in the IRSA trust policy"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policy's sub/aud condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
variable "service_account_suffixes" {
  type        = list(string)
  default     = ["", "-proxy", "-hook", "-proxy-hook"]
  description = "Suffixes the chart appends to the release name when naming its service accounts. All four get the IRSA annotation, because the chart applies annotations.serviceAccount to every one of them, so all four have to appear in the trust policy - a service account annotated with a role it is not trusted to assume logs a rejected AssumeRoleWithWebIdentity on every start. Only the auth and hook accounts actually call AWS; the others are trusted so their logs stay clean"

  validation {
    condition     = length(var.service_account_suffixes) > 0
    error_message = "service_account_suffixes must contain at least one entry; an empty string means the release name on its own."
  }
}
variable "replica_count" {
  type        = number
  default     = 2
  description = "Auth and proxy replicas, two as the _monolithic template had it. Two is what makes the DynamoDB backend worth having: with one replica the state could live on a volume, and with two neither pod owns it"

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
}
variable "issuer_name" {
  type        = string
  description = "Name of the cert-manager issuer the chart asks for its certificate from. Passed in from the cert_manager module rather than restated, so the chart cannot reference an issuer that does not exist - which leaves the Certificate Pending and the proxy never ready, with nothing on the Certificate saying why (rules.md B-5)"

  validation {
    condition     = length(var.issuer_name) > 0
    error_message = "issuer_name must not be empty."
  }
}
variable "issuer_kind" {
  type        = string
  default     = "ClusterIssuer"
  description = "Kind of that issuer. ClusterIssuer, which differs from the chart's default of Issuer: the issuer this project creates is cluster-scoped, because a namespaced one cannot use cert-manager's IRSA identity without a flag that grants the same power to every Issuer in the cluster"

  validation {
    condition     = contains(["Issuer", "ClusterIssuer"], var.issuer_kind)
    error_message = "issuer_kind must be either Issuer or ClusterIssuer."
  }
}
variable "load_balancer_port" {
  type        = number
  default     = 443
  description = "Port the proxy Service publishes, and therefore the load balancer's only listener. One port because proxy listener mode is multiplex: Teleport distinguishes SSH, Kubernetes and web traffic itself on a single TLS port, instead of publishing one listener each. The frontend security group opens this same value (rules.md B-5/G-1)"

  validation {
    condition     = var.load_balancer_port > 0 && var.load_balancer_port <= 65535
    error_message = "load_balancer_port must be a valid TCP port."
  }
}
variable "proxy_target_port" {
  type        = number
  default     = 3080
  description = "Port the proxy pod listens on, which the chart maps the Service port to. With a load balancer target type of ip, traffic arrives here rather than on load_balancer_port - so this is what the pod-side security group rule has to open (rules.md G-1/G-2)"

  validation {
    condition     = var.proxy_target_port > 0 && var.proxy_target_port <= 65535
    error_message = "proxy_target_port must be a valid TCP port."
  }
}
variable "scheme" {
  type        = string
  default     = "internet-facing"
  description = "Load balancer scheme the Service asks for. Must agree with the internal flag on the pre-created load balancer, or the controller treats a mismatch as a different load balancer and builds a second one (rules.md G-3)"

  validation {
    condition     = contains(["internet-facing", "internal"], var.scheme)
    error_message = "scheme must be either internet-facing or internal."
  }
}
variable "nlb_target_type" {
  type        = string
  default     = "ip"
  description = "Whether the load balancer sends traffic to pod addresses (ip) or node ports (instance). ip keeps the pod-side rule to one known port and preserves the client address, which Teleport records in its audit log"

  validation {
    condition     = contains(["ip", "instance"], var.nlb_target_type)
    error_message = "nlb_target_type must be either ip or instance."
  }
}
variable "frontend_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups the controller should attach to the load balancer, named by ID in the Service annotation. The controller reconciles the load balancer's groups towards this list, so a group Terraform attached but absent here is removed. When empty the annotation is omitted (rules.md B-6)"

  validation {
    condition     = alltrue([for id in var.frontend_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "frontend_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "dynamo_backups" {
  type        = bool
  default     = true
  description = "Whether Teleport turns on DynamoDB continuous backups for its tables. True as the _monolithic template had it, which is why the IAM policy includes UpdateContinuousBackups and DescribeContinuousBackups - leaving those out makes Teleport fail to start rather than quietly skip the backups"
}
variable "dynamo_auto_scaling" {
  type        = bool
  default     = false
  description = "Whether Teleport configures DynamoDB auto scaling. False as the _monolithic template had it, which also means the tables are created on-demand rather than provisioned - and on-demand needs no auto scaling. Turning it on requires application-autoscaling permissions this policy does not grant"
}
variable "audit_log_mirror_on_stdout" {
  type        = bool
  default     = false
  description = "Whether audit events are also written to the pod's stdout. False as the _monolithic template had it. Worth turning on only where a log pipeline is the system of record - it duplicates every event, including ones naming users and commands, into container logs"
}
variable "timeout_seconds" {
  type        = number
  default     = 1200
  description = "How long the release may take to become ready. Long, because readiness waits on the whole certificate chain: cert-manager creates an ACME order, writes a DNS-01 challenge record, waits for it to propagate, and only then does the proxy get a certificate. Twenty minutes covers a slow propagation; a shorter timeout fails an apply that would have succeeded"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
variable "user_name" {
  type        = string
  default     = "teleport-admin"
  description = "Teleport user the add-user, reset, grant-Kubernetes-access and login commands are written for. A variable rather than a literal in each, because all four have to name the same account - the login command included, since tsh otherwise signs in as the local login (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._@-]{0,62}$", var.user_name))
    error_message = "user_name must start with a letter or digit and contain only letters, digits, dots, underscores, @ and hyphens, because it is interpolated into a shell command."
  }
}
variable "kubernetes_cluster_role" {
  type        = string
  default     = "cluster-admin"
  description = "ClusterRole a Teleport user holds in this cluster. Teleport's Kubernetes service reaches the API server by impersonating the Kubernetes groups the user's Teleport role resolves to, and the preset access role resolves them from the user's kubernetes_groups trait - a user created without that trait is refused by Teleport itself, with \"Your user's Teleport role does not allow Kubernetes access\", before Kubernetes RBAC is ever consulted. This module binds one group to this ClusterRole and writes that same group into the add-user command, so the two halves cannot disagree. cluster-admin by default, matching what the bastion's access entry has: Teleport is the access path that replaces that one"

  validation {
    # Only the built-in user-facing ClusterRoles. A binding that names a ClusterRole which does
    # not exist is accepted by the API server and grants nothing, so the mistake would surface
    # as Forbidden from kubectl rather than at plan (rules.md B-1/B-2).
    condition     = contains(["cluster-admin", "admin", "edit", "view"], var.kubernetes_cluster_role)
    error_message = "kubernetes_cluster_role must be one of the built-in user-facing ClusterRoles: cluster-admin, admin, edit or view. A binding to a ClusterRole that does not exist is accepted and grants nothing, so kubectl through Teleport would answer Forbidden while the apply succeeds."
  }
}
