variable "domain" {
  type        = string
  description = "Domain every GitLab hostname is derived from (gitlab.<domain>, registry.<domain>, minio.<domain>). The wildcard DNS record the caller creates has to point at the load balancer in front of this release"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain))
    error_message = "domain must be a valid lowercase DNS name with at least two labels (e.g. example.com)."
  }
}

variable "issuer_email" {
  type        = string
  description = "Address the bundled cert-manager issuer registers its Let's Encrypt account with. Let's Encrypt stopped mailing expiry notices in June 2025, but it still validates this at registration and refuses the RFC 2606 example domains"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.issuer_email))
    error_message = "issuer_email must look like an email address."
  }

  validation {
    # The constraint this description used to state without enforcing
    # (rules.md B-1). A refused contact fails nowhere Terraform looks: the release
    # reports deployed, the Issuer stays at ErrRegisterACMEAccount, and every
    # hostname keeps cert-manager's temporary self-signed certificate.
    condition     = !can(regex("@example\\.(com|net|org)$", lower(var.issuer_email)))
    error_message = "issuer_email must not be at example.com, example.net or example.org, because Let's Encrypt refuses an ACME account whose contact is at one of them. The release still installs, but the Issuer never registers and every GitLab hostname keeps a self-signed certificate."
  }
}

variable "release_name" {
  type        = string
  default     = "gitlab"
  description = "Helm release name. The chart derives its object names from it, including the ingress controller Service the caller has to name in ingress_service_name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 label."
  }
}

variable "namespace" {
  type        = string
  default     = "gitlab"
  description = "Namespace the release is installed into. Also the first half of the adoption tag"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether Helm creates the namespace. True, as the _monolithic script's --create-namespace had it"
}

variable "chart_repository" {
  type        = string
  default     = "https://charts.gitlab.io/"
  description = "Helm repository the GitLab chart comes from"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}

variable "chart_version" {
  type        = string
  default     = "9.11.13"
  description = <<-DESC
    Pinned GitLab chart version, and it has to stay in the 9.x series. The _monolithic script ran
    `helm install` with no --version at all, so what got installed depended on the day - and the day
    chart 10.0.0 shipped, that script stopped working.

    Chart 10.0.0 removed the bundled PostgreSQL, Redis and MinIO subcharts, so from that version on
    the three are preconditions rather than parts of the release. The chart enforces it with a `fail`
    in NOTES.txt, which aborts while templates are still rendering: nothing is created, no release
    record is written, and the only thing that comes back is a wall of CONFIGURATION CHECKS text
    naming global.psql.host, global.redis.host and the object storage `connection` properties.

    9.11.13 is the newest release of the last series that still bundles all three, which is what makes
    this an all-in-one install like the original. To run a 10.x chart instead, bring an RDS instance,
    an ElastiCache cluster and S3 buckets, and pass their hosts, credential Secrets and per-type
    connection Secrets through additional_set_values.
  DESC

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a three-part semantic version."
  }

  validation {
    # A single-digit major rather than tonumber(split(...)) on purpose: every
    # validation block is evaluated, so a non-numeric major here would make
    # tonumber raise a hard error instead of this message (rules.md B-1).
    condition     = can(regex("^[0-9]\\.", var.chart_version))
    error_message = "chart_version must be below 10.0.0, because this module installs GitLab with its bundled PostgreSQL, Redis and MinIO and chart 10.0.0 removed all three. A 10.x version does not fail at plan or at apply-time validation - it fails partway through apply, when the chart's own NOTES.txt check reports that global.psql.host, global.redis.host and the artifacts/lfs/uploads/packages connections are unset. 9.11.13 is the newest version that still bundles them. To run 10.x, provision external PostgreSQL, Redis and S3 object storage first and wire them in through additional_set_values."
  }
}

variable "ingress_service_name" {
  type        = string
  description = "Name of the Service the chart's bundled nginx-ingress controller creates - normally <release_name>-nginx-ingress-controller. Supplied by the caller rather than derived here, because the pre-created load balancer has to be tagged with it before this release runs, so the caller already has to know it (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.ingress_service_name))
    error_message = "ingress_service_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "stack_tag" {
  type        = string
  description = "The <namespace>/<service> value the AWS Load Balancer Controller writes into its service.k8s.aws/stack tag for this release's Service. Taken as an input and re-exposed as an output so the value exists in exactly one place, and a mismatch with the pre-created load balancer is visible in terraform output (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9][-a-z0-9.]*/[a-z0-9][-a-z0-9.]*$", var.stack_tag))
    error_message = "stack_tag must look like <namespace>/<service-name>."
  }
}

variable "scheme" {
  type        = string
  default     = "internet-facing"
  description = "Load balancer scheme the controller builds for the ingress Service. Has to agree with the subnets the pre-created load balancer sits in, or the controller builds a second one (rules.md G-3)"

  validation {
    condition     = contains(["internet-facing", "internal"], var.scheme)
    error_message = "scheme must be either internet-facing or internal."
  }
}

variable "nlb_target_type" {
  type        = string
  default     = "ip"
  description = "NLB target type. ip sends traffic to pod addresses directly, which is what lets the node-side rule name a container port instead of the whole NodePort range (rules.md G-2)"

  validation {
    condition     = contains(["ip", "instance"], var.nlb_target_type)
    error_message = "nlb_target_type must be either ip or instance."
  }
}

variable "frontend_security_group_ids" {
  type        = list(string)
  description = "Security groups the controller keeps on the load balancer. The pre-created NLB is built with this same list, because an NLB can only be given security groups at creation time"

  validation {
    condition     = length(var.frontend_security_group_ids) > 0 && alltrue([for id in var.frontend_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "frontend_security_group_ids must contain at least one valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}

variable "wait" {
  type        = bool
  default     = false
  description = "Whether the apply blocks until every workload in the release is ready. False by default: this chart installs around thirty workloads plus migration Jobs, and a first install regularly runs past fifteen minutes"
}

variable "timeout_seconds" {
  type        = number
  default     = 1800
  description = "Helm operation timeout. Only bites when wait is true, and then it has to cover the migration Jobs as well as the workloads"

  validation {
    condition     = var.timeout_seconds >= 600
    error_message = "timeout_seconds must be at least 600; a first GitLab install does not finish faster than that."
  }
}

variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra chart values, for narrowing the install down (gitlab-runner.install, prometheus.install) without editing the module"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "additional_set_values entries may only set type to \"auto\" or \"string\"; those are the two helm --set accepts (rules.md E-7)."
  }
}
