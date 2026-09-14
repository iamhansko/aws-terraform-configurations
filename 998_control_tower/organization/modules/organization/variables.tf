variable "organization_root_id" {
  type        = string
  default     = null
  description = "Root ID of an AWS Organization that already exists. When null, this module creates the organization and uses its root. The _monolithic template used an empty string as the sentinel instead, which meant the caller had to pass \"\" explicitly to get a new organization; null is the idiomatic form for an optional switch (rules.md #4)"

  validation {
    condition     = var.organization_root_id == null || can(regex("^r-[0-9a-z]{4,32}$", var.organization_root_id))
    error_message = "organization_root_id must be a valid Organizations root ID (e.g. r-abc1), or null to create a new organization."
  }
}
variable "feature_set" {
  type        = string
  default     = "ALL"
  description = "Organization feature set, used only when this module creates the organization. Control Tower requires ALL: a CONSOLIDATED_BILLING organization cannot host a landing zone, because service control policies are unavailable"

  validation {
    condition     = contains(["ALL", "CONSOLIDATED_BILLING"], var.feature_set)
    error_message = "feature_set must be either ALL or CONSOLIDATED_BILLING."
  }
}
variable "organizational_unit_names" {
  type        = list(string)
  default     = ["Johan"]
  description = "Names of the organizational units created directly under the root, one per entry via for_each rather than a copied resource block per OU (rules.md #13). Control Tower creates its own Security OU during landing zone setup, so do not list it here"

  validation {
    condition     = length(var.organizational_unit_names) > 0
    error_message = "organizational_unit_names must contain at least one OU name."
  }

  validation {
    condition     = alltrue([for name in var.organizational_unit_names : can(regex("^[0-9A-Za-z][0-9A-Za-z_ -]{0,127}$", name))])
    error_message = "organizational_unit_names entries must be 1-128 characters of letters, digits, spaces, hyphens and underscores."
  }

  validation {
    condition     = length(distinct(var.organizational_unit_names)) == length(var.organizational_unit_names)
    error_message = "organizational_unit_names must not contain duplicates."
  }
}
variable "organizational_unit_tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every organizational unit this module creates"

  validation {
    condition     = alltrue([for key in keys(var.organizational_unit_tags) : length(key) > 0])
    error_message = "organizational_unit_tags must not contain empty tag keys."
  }
}
