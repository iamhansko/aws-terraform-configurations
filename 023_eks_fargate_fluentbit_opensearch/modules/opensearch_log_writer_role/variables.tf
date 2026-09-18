variable "role_name" {
  type        = string
  default     = "fargate-log-writer"
  description = "Name of the OpenSearch security role created for the log shipper. A purpose-built role rather than the built-in all_access, which the _monolithic template's src/client.py mapped to: all_access includes the security plugin itself, so a leaked signing identity could rewrite the domain's own role mappings"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters of letters, digits, underscores, dots or hyphens."
  }
}
variable "index_patterns" {
  type        = list(string)
  description = "Index name patterns the role may write to. Scoped to what Fluent Bit actually indexes, so the signing identity cannot touch the domain's system indices - notably .opendistro_security, which holds the role mappings"

  validation {
    condition     = length(var.index_patterns) > 0
    error_message = "index_patterns must name at least one pattern. An empty list produces a role that can reach the _bulk endpoint but write to nothing, which fails at request time rather than at apply."
  }
  validation {
    condition     = alltrue([for p in var.index_patterns : can(regex("^[a-z0-9][a-z0-9._*-]*$", p))])
    error_message = "index_patterns must be lowercase and start with a letter or digit, matching the names OpenSearch accepts for an index."
  }
}
variable "cluster_permissions" {
  type = list(string)
  default = [
    # The action group covering _bulk. Fluent Bit's es output sends every record
    # batch to the cluster-level _bulk endpoint, and the security plugin checks
    # this before it ever looks at the per-index permissions below - so without it
    # every flush is rejected while the index permissions look perfectly correct.
    "cluster_composite_ops",
    # GET / - the version probe some client versions issue before the first write.
    "cluster:monitor/main",
  ]
  description = "Cluster-level permissions granted to the role. Deliberately not the example's cluster_permissions = [\"*\"], which includes cluster settings changes and snapshot management"

  validation {
    condition     = length(var.cluster_permissions) > 0
    error_message = "cluster_permissions must not be empty. The _bulk endpoint is a cluster-level action, so a role with only index permissions cannot write at all."
  }
}
variable "allowed_index_actions" {
  type = list(string)
  default = [
    # Fluent Bit does not pre-create the index; the first batch has to create it,
    # and the mapping for the fields in that batch.
    "create_index",
    # indices:data/write* - the per-index half of the bulk request.
    "write",
  ]
  description = "Action groups the role may perform on the matched indices. write and create_index rather than crud, because a log shipper never reads back what it wrote"

  validation {
    condition     = length(var.allowed_index_actions) > 0
    error_message = "allowed_index_actions must not be empty."
  }
}
variable "backend_role_arns" {
  type        = list(string)
  description = "IAM role ARNs mapped onto the role above as backend roles. This is the step that has no AWS-side equivalent: an IAM policy allowing es:ESHttp* gets a request past the domain's access policy, and fine-grained access control then rejects it with 403 unless the signing role is also mapped here"

  validation {
    condition     = length(var.backend_role_arns) > 0
    error_message = "backend_role_arns must contain at least one ARN. A mapping with no backend roles grants nothing, which is indistinguishable from the mapping being absent."
  }
  validation {
    condition     = alltrue([for a in var.backend_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/", a))])
    error_message = "backend_role_arns must be IAM role ARNs. Fine-grained access control matches the full ARN including any path, unlike the aws-auth ConfigMap which rejects a path (rules.md E-6)."
  }
}
variable "mapped_users" {
  type        = list(string)
  default     = []
  description = "Internal-database users also mapped onto the role. Empty by default: the master user already has all_access, so adding it here grants nothing. The _monolithic template's client.py passed users=[\"admin\"] when it overwrote the all_access mapping, which was about not locking the master user out of a mapping it was replacing - not needed for a new role"
}
