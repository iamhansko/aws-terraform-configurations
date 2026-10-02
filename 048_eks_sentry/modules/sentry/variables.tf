variable "admin_email" {
  type        = string
  description = "Email for the Sentry admin user the chart creates on first install. The chart's own default is admin@sentry.local, which is why this has no default here - a shared demo with a predictable login is worse than one that refuses to start"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.admin_email))
    error_message = "admin_email must look like an email address. Sentry uses it as the login name, and a value it rejects leaves the release installed with no usable account."
  }
}
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Password for the Sentry admin user. sensitive so plan and apply do not print it, and no default on purpose: the chart defaults it to \"aaaa\" and this project publishes the dashboard through an internet-facing load balancer. Pass it with TF_VAR_sentry_admin_password"

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "admin_password must be at least 12 characters. The chart accepts anything, including its own \"aaaa\" default, and the dashboard this protects is reachable from the internet."
  }
}
variable "release_name" {
  type        = string
  default     = "sentry"
  description = "Helm release name. The chart derives its Ingress and Service names from it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "monitoring"
  description = "Namespace Sentry and its dependencies install into, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether this release creates its namespace. True because Sentry owns this namespace here; set false when another release in the same root already creates it, since only one of them can"
}
variable "chart_version" {
  type        = string
  default     = "27.1.0"
  description = "Pinned Sentry chart version, as the _monolithic template pinned it. Worth keeping pinned: this chart brings PostgreSQL, Redis, Kafka, ZooKeeper and ClickHouse as subcharts, and a floating version changes all of them at once"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 27.1.0."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://sentry-kubernetes.github.io/charts"
  description = "Helm repository hosting the Sentry chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "ingress_class_name" {
  type        = string
  default     = "nginx"
  description = "IngressClass Sentry's Ingress asks for. The chart leaves this unset by default, and an Ingress naming no class - or a class no controller owns - is created successfully and then never gets an address, so nothing reaches the dashboard (rules.md G-1)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_class_name))
    error_message = "ingress_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_annotations" {
  type = map(string)
  default = {
    # The chart's own values file asks for these when the controller is nginx, pointing at
    # getsentry/self-hosted#1927. Sentry sends large response headers; with nginx's default
    # proxy buffers the UI fails on some pages with an upstream header error rather than
    # anything that looks like a buffer problem. use-regex goes with the chart's
    # regexPathStyle: nginx default, which writes regex paths into the Ingress.
    "nginx.ingress.kubernetes.io/use-regex"            = "true"
    "nginx.ingress.kubernetes.io/proxy-buffers-number" = "16"
    "nginx.ingress.kubernetes.io/proxy-buffer-size"    = "32k"
    # The fourth one, and leaving it out took the whole dashboard down.
    #
    # nginx requires proxy_busy_buffers_size to be at least as large as proxy_buffer_size and at
    # least one buffer. Raising proxy-buffer-size to 32k while the controller's global
    # proxy-busy-buffers-size stayed at its 8k default makes the generated configuration invalid, and
    # a configuration that fails nginx's own test is never loaded:
    #
    #   [emerg] "proxy_busy_buffers_size" must be equal to or greater than the maximum of the value
    #           of "proxy_buffer_size" and one of the "proxy_buffers"
    #   Warning RELOAD  Error reloading NGINX: Error: exit status 1
    #
    # The controller keeps serving its last good configuration, which predates this Ingress, so every
    # request gets the default backend's 404 - including the dashboard URL. Nothing in that 404
    # mentions buffers, and "nginx -t" inside the controller passes, because the file it checks is the
    # last configuration that loaded rather than the one being rejected.
    #
    # Set per-Ingress rather than in the controller's ConfigMap on purpose. Globally, 32k would break
    # every other Ingress that keeps the defaults: nginx also caps busy_buffers_size at the total
    # buffer space minus one buffer, which for the default 4 buffers of 4k is 12k. Scoped to this
    # Ingress, where 16 buffers of 32k are allocated, the cap is 480k and 32k sits well inside it.
    "nginx.ingress.kubernetes.io/proxy-busy-buffers-size" = "32k"
  }
  description = "Annotations added to Sentry's Ingress. Defaults to the ones the chart's values file recommends for an nginx controller, plus the matching proxy-busy-buffers-size - the _monolithic template set none of them, which leaves parts of the UI failing on upstream header size"

  validation {
    condition     = alltrue([for key in keys(var.ingress_annotations) : length(key) > 0])
    error_message = "ingress_annotations must not contain empty keys."
  }
  validation {
    # The omission that caused the outage, caught at plan time instead of as a 404 (rules.md B-1).
    condition = (
      lookup(var.ingress_annotations, "nginx.ingress.kubernetes.io/proxy-buffer-size", null) == null
      || lookup(var.ingress_annotations, "nginx.ingress.kubernetes.io/proxy-busy-buffers-size", null) != null
    )
    error_message = "ingress_annotations sets proxy-buffer-size without proxy-busy-buffers-size. nginx rejects a configuration whose proxy_busy_buffers_size is smaller than proxy_buffer_size, the controller then keeps its previous configuration, and every request to this Ingress returns the default backend's 404 with nothing in the response about buffers. Add nginx.ingress.kubernetes.io/proxy-busy-buffers-size at the same size or larger."
  }
  validation {
    # And the sizes have to be in the right order, which only matters once both are present.
    condition = (
      lookup(var.ingress_annotations, "nginx.ingress.kubernetes.io/proxy-buffer-size", null) == null
      || lookup(var.ingress_annotations, "nginx.ingress.kubernetes.io/proxy-busy-buffers-size", null) == null
      || (
        can(regex("^[0-9]+k$", var.ingress_annotations["nginx.ingress.kubernetes.io/proxy-buffer-size"]))
        && can(regex("^[0-9]+k$", var.ingress_annotations["nginx.ingress.kubernetes.io/proxy-busy-buffers-size"]))
        && tonumber(replace(var.ingress_annotations["nginx.ingress.kubernetes.io/proxy-busy-buffers-size"], "k", ""))
        >= tonumber(replace(var.ingress_annotations["nginx.ingress.kubernetes.io/proxy-buffer-size"], "k", ""))
      )
    )
    error_message = "proxy-busy-buffers-size must be at least proxy-buffer-size, and both must be written as a whole number of kilobytes such as \"32k\" so they can be compared here. nginx refuses to load a configuration that breaks this, and the controller reports it only in its own log."
  }
}
variable "ingress_enabled" {
  type        = bool
  default     = true
  description = "Whether the chart creates an Ingress. The chart's own default is false, and leaving it there means ingress_class_name and ingress_annotations are applied to nothing - the release succeeds and the dashboard has no address, with no error anywhere (rules.md G-1)"
}
variable "wait_for_release" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the apply waits for the *main manifest's* workloads to become Ready.

    False, and pinned false, because true cannot ever be satisfied on a first install. Helm installs in
    this order:

      1. pre-install hooks
      2. apply the main manifest
      3. with --wait, block until the main manifest's workloads are Ready
      4. run the post-install hooks, in weight order, waiting for each group

    The main manifest contains 12 workloads, and two of them have readiness probes that depend on a
    database schema: sentry-web probes /_health/ and sentry-snuba-api probes /health. The schema is
    created by sentry-snuba-migrate (hook weight 5) and sentry-db-init (weight 6) - post-install hooks,
    which only run in step 4.

    So step 3 waits for something only step 4 can make true. That is a deadlock, not a slow install, and
    no timeout value fixes it: 3000 seconds failed, 5400 failed, and any larger number would fail after
    taking longer about it. Each attempt also leaves the release in `failed` state, so the apply after
    it reports "cannot re-use a name that is still in use" instead (rules.md E-7).

    Turning this off does not make the apply return early. Helm waits for hook resources regardless of
    --wait, and 41 of this chart's workloads are post-install hooks - so the apply still blocks through
    all twelve weight groups, ending with relay at weight 25. What it stops doing is demanding that
    web and snuba-api be healthy before the migrations that make them healthy have run.
  DESC

  validation {
    # A constant condition rather than a cross-variable one: the constraint is a property of this chart,
    # not of any combination of inputs here (rules.md B-1).
    condition     = var.wait_for_release == false
    error_message = "wait_for_release must stay false. helm --wait blocks on the main manifest before post-install hooks run, and sentry-web and sentry-snuba-api cannot pass their readiness probes until the hook-driven database migrations have completed - so waiting deadlocks and the release is left in `failed` state. The hooks are still waited on either way; timeout_seconds governs them (rules.md E-7)."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 5400
  description = <<-DESC
    How long to wait for the release.

    Still needed with wait_for_release false, because helm waits for hook resources regardless of
    --wait - and 45 of this chart's resources are hooks: 5 Jobs and 40 Deployments across 12 distinct
    hook weights, run strictly in weight order with a wait after each group. The ClickHouse migrations
    (snuba-migrate) take minutes on their own, and every wave of Deployments pulls the getsentry/sentry
    image onto nodes that have never cached it.

    Raised from the 3000 the _monolithic template used, which did not cover that chain on a cold
    cluster. When it expires helm reports one line, "context deadline exceeded", and nothing about
    where it had got to - see the install_progress_command output for that.
  DESC

  validation {
    condition     = var.timeout_seconds >= 1800
    error_message = "timeout_seconds must be at least 1800. This chart installs through 12 serialized hook weights, one of which runs the ClickHouse migrations, so a shorter timeout fails an install that would have succeeded - and a timed-out install leaves the release in `failed` state, after which every apply reports only \"cannot re-use a name that is still in use\" (rules.md E-7)."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra chart values. type is auto when omitted and may only be auto or string, so a caller can force a value the chart must receive as a string (rules.md E-7)"

  validation {
    condition     = alltrue([for v in var.additional_set_values : v.type == null || contains(["auto", "string"], v.type)])
    error_message = "additional_set_values type must be omitted, \"auto\" or \"string\" - the only values helm_release accepts."
  }
}
variable "bitnami_image_namespace" {
  type        = string
  default     = "bitnamilegacy"
  description = "Docker Hub namespace the Bitnami-based subchart images are pulled from, prefixed to each image name. bitnamilegacy rather than bitnami, because Bitnami moved its versioned tags there and the tags this chart pins no longer exist under bitnami - the pull fails as NotFound, PostgreSQL never starts, and the install dies in the db-check hook with DeadlineExceeded rather than anything mentioning images. Point it at a mirror to stop depending on an archive that receives no updates; a mirror on another registry also needs image.registry, which additional_set_values can supply"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*[a-z0-9]$", var.bitnami_image_namespace))
    error_message = "bitnami_image_namespace must be a lowercase Docker repository namespace such as \"bitnamilegacy\", with no leading or trailing slash and no tag."
  }
}
