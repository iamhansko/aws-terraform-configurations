variable "name_prefix" {
  type        = string
  description = "Prefix for the generated bucket name. A prefix rather than a fixed name: S3 bucket names are globally unique, so a literal name collides with a second copy of this project and with everyone else in the world. The _monolithic template built a name out of a uuid standing in for AWS::StackId to get the same effect"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,40}$", var.name_prefix))
    error_message = "name_prefix must be 2-41 characters of lowercase letters, digits, dots and hyphens, leaving room for the generated suffix inside the 63 character bucket name limit."
  }
}
variable "index_document" {
  type        = string
  default     = "index.html"
  description = "Object the website endpoint serves for a request that names a directory, as the _monolithic template had it. This is the reason the project uses the website endpoint at all rather than the REST endpoint - see main.tf"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.index_document))
    error_message = "index_document must be a key without a leading slash, e.g. index.html."
  }
}
variable "error_document" {
  type        = string
  default     = null
  description = "Object the website endpoint serves for a 4xx. Null leaves it unset, as the _monolithic template did - which means a missing key returns the S3 website endpoint's own XML error page through CloudFront"

  validation {
    condition     = var.error_document == null || can(regex("^[^/][^\\s]*$", var.error_document))
    error_message = "error_document must be a key without a leading slash, or null."
  }
}
variable "objects" {
  type        = map(string)
  default     = {}
  description = "Objects written into the bucket, keyed by key with the body as the value. The _monolithic template created an empty bucket, so the distribution it built in front of it answered every request with a 404 - there was nothing to see. Content passed in here is what makes the demo answer something"

  validation {
    condition     = alltrue([for key in keys(var.objects) : can(regex("^[^/]", key))])
    error_message = "objects keys must not start with a slash."
  }
}
variable "content_types" {
  type = map(string)
  default = {
    html = "text/html"
    css  = "text/css"
    js   = "application/javascript"
    json = "application/json"
    svg  = "image/svg+xml"
    txt  = "text/plain"
  }
  description = "Content type per file extension. Needed because S3 defaults an object with no content type to application/octet-stream, which a browser downloads instead of rendering - so an index.html uploaded without this looks like a broken site rather than a missing header"

  validation {
    condition     = length(var.content_types) > 0
    error_message = "content_types must not be empty."
  }
}
variable "required_referer" {
  type        = string
  default     = null
  description = <<-DESC
    Secret value a request must carry in its Referer header to be allowed. Null makes the bucket readable
    by anyone, which is what the _monolithic template did.

    This exists because of a constraint of the website endpoint: it has no authentication of any kind, so
    serving through it means a public bucket policy, and a public bucket policy means the distribution can
    be bypassed by requesting the website endpoint directly. Origin Access Control - the usual answer -
    only works with the REST endpoint, which does not do index documents for subdirectories.

    Setting this to a secret that the distribution sends as a Referer header, and requiring it here, is
    AWS's documented mitigation for exactly this shape. It is not a strong boundary: anyone who learns the
    value can use it. It does stop a casual direct request.
  DESC

  validation {
    condition     = var.required_referer == null || length(var.required_referer) >= 16
    error_message = "required_referer must be at least 16 characters, or null to leave the bucket readable by anyone. A short value is guessable, and this is the only thing standing in front of the objects."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket before deleting it. True, because this project writes objects into it and a destroy would otherwise stop at BucketNotEmpty. Never true for a bucket holding anything worth keeping"
}
