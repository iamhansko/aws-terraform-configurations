variable "instance_id" {
  type        = string
  description = "Instance the build steps run on. It needs docker installed and an instance role that can reach ECR; the module never looks either up and never installs anything (rules.md B-6)"
  validation {
    condition     = can(regex("^i-[0-9a-f]+$", var.instance_id))
    error_message = "instance_id must be a valid EC2 instance ID (e.g. i-0123456789abcdef0)."
  }
}
variable "marker_file_path" {
  type        = string
  description = "Absolute directory holding the marker files that order the chain. The same directory the instance's bootstrap writes its own completion marker into - the caller passes one value to both (rules.md B-5)"
  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "initial_marker_name" {
  type        = string
  default     = "userdata"
  description = "Marker the first build step waits for, which is the one the instance bootstrap writes when it has finished installing docker. The name has to match what that bootstrap touches: a step waiting for a marker nobody writes fails on its own timeout, and the message points at the bootstrap rather than at this"
  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.initial_marker_name))
    error_message = "initial_marker_name must be a plain file name of letters, digits, dots, underscores and hyphens."
  }
}
variable "build_root" {
  type        = string
  default     = "/home/ec2-user"
  description = "Directory the per-application build contexts are created under, one subdirectory each. /home/ec2-user as the template's cfn-init files did, which also means they are visible in the code-server file tree. A dedicated directory per application keeps each docker build context to three files rather than handing the whole home directory to the daemon"
  validation {
    condition     = can(regex("^/", var.build_root)) && !can(regex("/$", var.build_root))
    error_message = "build_root must be an absolute path starting with '/' and must not end with a slash, because the application name is appended to it."
  }
}
variable "applications" {
  type = map(object({
    order           = number
    repository_name = string
    image_uri       = string
    image_tag       = string
    files           = map(string)
  }))
  description = <<-DESC
    The applications to build, keyed by name.

    The keys are literal strings in the caller's configuration, which is what makes this usable as a
    for_each - most of the values are not. image_uri and repository_name come from the repository modules
    and are unknown until apply, and a set built from them could not provide resource addresses
    (rules.md B-8).

    image_tag is the exception, and has to be known at plan: it is part of each build association's
    for_each key, which is what makes a new tag a create that waits rather than an update that does not
    (see main.tf). A tag read from a file digest or a literal works; one derived from an apply-time value
    fails plan with "Invalid for_each argument".

    files maps a path inside the build context to its contents. The caller reads them off disk with file(),
    so the path a file is written to here is independent of what it is called in src/ - which is how
    src/user/Dockerfile.user becomes Dockerfile in the build context without renaming anything.

    order sets the build sequence. The builds are deliberately serial; see main.tf.
  DESC
  validation {
    condition     = length(var.applications) > 0
    error_message = "applications must contain at least one entry."
  }
  validation {
    condition     = alltrue([for name in keys(var.applications) : can(regex("^[a-z0-9][a-z0-9_-]*$", name))])
    error_message = "applications keys must be lowercase names of letters, digits, underscores and hyphens, because each becomes a directory name on the instance and part of an association name."
  }
  validation {
    condition     = length(distinct([for app in var.applications : app.order])) == length(var.applications)
    error_message = "applications entries must each have a distinct order. Two sharing one order collapse into a single step in the derived build chain, which leaves one image never built and nothing reporting it."
  }
  validation {
    condition     = alltrue([for app in var.applications : length(app.files) > 0])
    error_message = "every applications entry must supply at least one file. A build context with no Dockerfile fails inside the association rather than at plan."
  }
  validation {
    condition     = alltrue([for app in var.applications : contains(keys(app.files), "Dockerfile")])
    error_message = "every applications entry's files must include a \"Dockerfile\" key. docker build reads that name from the context root, so a file written as Dockerfile.user would not be found - the caller maps the source file name to this one."
  }
  validation {
    condition     = alltrue([for app in var.applications : !anytrue([for content in values(app.files) : can(regex("(?m)^TFSOURCEFILE$", content))])])
    error_message = "no file contents may contain a line that is exactly TFSOURCEFILE: that is the heredoc delimiter each file is written with, and a line matching it would truncate the file and leave the rest of the script being parsed as shell."
  }
}
variable "association_name_prefix" {
  type        = string
  description = "Prefix for the association names, completed as <prefix>-build-<application>. No default: derived from the project name by the caller, so two copies of this project in one account produce distinguishable associations"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{1,100}$", var.association_name_prefix))
    error_message = "association_name_prefix must be 1-100 characters of letters, digits, underscores, dots and hyphens."
  }
}
variable "build_timeout_seconds" {
  type        = number
  default     = 2400
  description = <<-DESC
    How long Terraform waits for each association to report success.

    Generous on purpose, and the reason is the chain: the last step spends most of its wait on the two
    before it, so its budget has to cover the whole sequence rather than one build. A first run is the
    instance bootstrap (a few minutes for Development Tools, Python and code-server) plus three builds that
    each pull a golang:alpine layer and run go mod tidy against the module proxy.

    Too low and apply fails on a build that would have finished, leaving the images half-built and the
    services pointing at tags that do not exist yet.
  DESC
  validation {
    condition     = var.build_timeout_seconds >= 300 && var.build_timeout_seconds <= 7200
    error_message = "build_timeout_seconds must be between 300 and 7200. Below five minutes no build in this project completes; above two hours a genuinely stuck association holds the apply rather than failing it."
  }
}
variable "execution_timeout_seconds" {
  type        = number
  default     = 3600
  description = "AWS-RunShellScript's own command timeout, passed as a document parameter. Separate from build_timeout_seconds, which is the Terraform-side wait: if this one is the smaller of the two, SSM kills the command and reports a timeout while Terraform is still waiting, and the message describes a hung command rather than a budget"
  validation {
    condition     = var.execution_timeout_seconds >= 30 && var.execution_timeout_seconds <= 172800
    error_message = "execution_timeout_seconds must be between 30 and 172800, which is the range AWS-RunShellScript accepts."
  }
  validation {
    condition     = var.execution_timeout_seconds >= var.build_timeout_seconds
    error_message = "execution_timeout_seconds must be at least build_timeout_seconds. Otherwise SSM gives up on the command before Terraform gives up waiting, and the association's own message is about the document timeout rather than about the build."
  }
}
variable "wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds between checks of the predecessor's marker file"
  validation {
    condition     = var.wait_interval_seconds >= 1 && var.wait_interval_seconds <= 60
    error_message = "wait_interval_seconds must be between 1 and 60."
  }
}
variable "wait_attempts" {
  type        = number
  default     = 180
  description = "How many times a step checks for its predecessor's marker before giving up. The product of this and wait_interval_seconds is the in-script wait, and it has to be shorter than the two timeouts above - otherwise the command is killed from outside while still in its wait loop, and the useful message about which marker is missing is never printed"
  validation {
    condition     = var.wait_attempts >= 1
    error_message = "wait_attempts must be at least 1."
  }
  validation {
    condition     = var.wait_attempts * var.wait_interval_seconds < var.execution_timeout_seconds
    error_message = "wait_attempts times wait_interval_seconds must be less than execution_timeout_seconds, so a step that is still waiting reports which marker file it is waiting for rather than being killed by the document timeout."
  }
}
