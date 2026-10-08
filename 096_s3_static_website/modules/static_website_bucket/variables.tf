variable "name_prefix" {
  type        = string
  description = "Prefix for the generated bucket name. A prefix rather than a fixed name: bucket names are globally unique, so a literal name collides with a second copy of this project and with everyone else in the world. The _monolithic template declared the bucket with no name at all, which has the same effect and produces a name that says nothing about what is in it"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,40}$", var.name_prefix))
    error_message = "name_prefix must be 2-41 characters of lowercase letters, digits, dots and hyphens, leaving room for the generated suffix inside the 63 character bucket name limit."
  }
}
variable "index_document" {
  type        = string
  default     = "index.html"
  description = "Object the website endpoint serves for a request that names a directory, as the _monolithic template had it. This is the reason the project uses the website endpoint rather than the REST endpoint - see main.tf. The key has to exist inside the game zip the seeder unpacks, or the site answers 404 at its root with nothing in the configuration looking wrong"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.index_document))
    error_message = "index_document must be a key without a leading slash, e.g. index.html."
  }
}
variable "error_document" {
  type        = string
  default     = "error.html"
  description = "Object the website endpoint serves for a 4xx, as the _monolithic template had it. Null leaves it unset, which means a missing key returns the endpoint's own XML error page. The game zip does not currently contain an error.html, so a bad path returns the S3 404 page either way - the setting is reproduced because the template had it, not because it resolves"

  validation {
    condition     = var.error_document == null || can(regex("^[^/][^\\s]*$", var.error_document))
    error_message = "error_document must be a key without a leading slash, or null to leave it unset."
  }
}
variable "policy_id" {
  type        = string
  default     = "MyPolicy"
  description = "Id field of the bucket policy document, carried over verbatim from the _monolithic template. It is a label only - IAM does not use it for anything - and it is a variable rather than a literal so the inherited name can be replaced without editing the module"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,128}$", var.policy_id))
    error_message = "policy_id must be 1-128 characters of letters, digits, hyphens and underscores."
  }
}
variable "policy_statement_id" {
  type        = string
  default     = "PublicGet"
  description = "Sid of the public-read statement, as the _monolithic template had it. Shows up in CloudTrail and in the console's policy view, so it is worth saying what the statement does"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{1,128}$", var.policy_statement_id))
    error_message = "policy_statement_id must be 1-128 alphanumeric characters - IAM rejects anything else in a Sid."
  }
}
variable "sse_algorithm" {
  type        = string
  default     = "AES256"
  description = "Server-side encryption applied to new objects. AES256 is SSE-S3, which is what S3 applies by default and what the _monolithic template therefore got without saying so. aws:kms would need a key policy that allows the seeder's role to encrypt, which it does not have"

  validation {
    condition     = contains(["AES256", "aws:kms", "aws:kms:dsse"], var.sse_algorithm)
    error_message = "sse_algorithm must be AES256, aws:kms or aws:kms:dsse."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket before deleting it. True, because the seeder instance writes objects into it that Terraform never knew about, so a destroy would otherwise stop at BucketNotEmpty and leave the whole root half torn down. Never true for a bucket holding anything worth keeping"
}
