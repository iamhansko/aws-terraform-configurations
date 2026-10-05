variable "bundle_yaml" {
  type        = string
  description = <<-DESC
    The Gateway API CRD bundle, as YAML. Passed in rather than fetched here, and that is not a style
    choice - see this module's main.tf. A depends_on on a module block defers every data source inside
    that module until apply, and this module needs its documents at plan time to key a for_each by them
    (rules.md B-8/D-6).
  DESC

  validation {
    condition     = length(var.bundle_yaml) > 0
    error_message = "bundle_yaml must not be empty."
  }
  validation {
    condition = length([
      for document in split("\n---\n", "\n${var.bundle_yaml}") : document
      if try(yamldecode(document).kind, null) != null
    ]) > 0
    error_message = "bundle_yaml must contain at least one Kubernetes document. A 200 response that is not the bundle - a mirror's directory listing, for instance - looks like this, and without this check the module would quietly manage zero CRDs while the failure surfaced much later as a Gateway manifest rejected for an unknown kind."
  }
}
variable "bundle_url" {
  type        = string
  description = "Where the bundle came from. Carried only so it can be re-exposed as an output: it is built from a version and a channel, the combination is easy to get wrong, and a 404 shows up as a parse failure several steps away (rules.md B-5)"

  validation {
    condition     = can(regex("^https://", var.bundle_url))
    error_message = "bundle_url must be an https URL."
  }
}
variable "version_tag" {
  type        = string
  default     = "v1.2.0"
  description = "Gateway API release this bundle is, as the _monolithic template pinned it. This is the upstream Kubernetes SIG project's version rather than anything AWS publishes: the VPC Lattice controller implements these CRDs, so its own version has to be one that supports this release. Re-exposed as an output for that comparison"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.version_tag))
    error_message = "version_tag must look like v1.2.0."
  }
}
