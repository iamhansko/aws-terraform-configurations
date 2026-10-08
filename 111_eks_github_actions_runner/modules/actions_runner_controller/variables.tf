variable "controller_namespace" {
  type        = string
  default     = "arc-systems"
  description = "Namespace the controller runs in, as the _monolithic template's helm command created it. Separate from the runners' namespace on purpose: the controller survives a runner scale set being removed"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.controller_namespace))
    error_message = "controller_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "runner_namespace" {
  type        = string
  default     = "arc-runners"
  description = "Namespace the runner pods are created in, as the _monolithic template had it. It is also where the GitHub credential Secret lives, and a runner scale set can only read a Secret in its own namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.runner_namespace))
    error_message = "runner_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_version" {
  type        = string
  default     = "0.14.2"
  description = "Version of both ARC charts. Pinned, where the _monolithic template's helm commands took whatever the registry served - and the two charts have to be the same version, because the runner scale set's CRDs are installed by the controller chart"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 0.14.2."
  }
}
variable "controller_release_name" {
  type        = string
  default     = "arc"
  description = "Helm release name for the controller, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.controller_release_name))
    error_message = "controller_release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "runner_set_name" {
  type        = string
  default     = "arc-runner-set"
  description = <<-DESC
    Helm release name for the runner scale set, as the _monolithic template named it.

    It is more than a release name: ARC uses it as the runner scale set's name, which is the string a workflow
    puts in "runs-on". So a workflow written against the default will not match a renamed set, and the failure
    is a job that queues forever with no error anywhere.
  DESC

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.runner_set_name))
    error_message = "runner_set_name must be a valid lowercase RFC 1123 DNS label - it becomes the runs-on label in a workflow."
  }
}
variable "github_config_url" {
  type        = string
  description = <<-DESC
    The repository, organisation or enterprise the runners register with.

    The _monolithic template built this as
    "https://github.com/$${"UNSUPPORTED_REF_GitHubRepository"}" - a literal left behind when the
    AWS::CodeStar::GitHubRepository resource it referenced failed to convert. So the runner set registered
    against a URL containing that placeholder, which is not a repository, and no runner ever came up.
  DESC

  validation {
    condition     = can(regex("^https://github\\.com/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?$", var.github_config_url))
    error_message = "github_config_url must be https://github.com/<owner> for an organisation or https://github.com/<owner>/<repo> for a repository."
  }
}
variable "github_token" {
  type        = string
  sensitive   = true
  description = <<-DESC
    Personal access token the runners authenticate with.

    Written into a Kubernetes Secret here, and the chart is pointed at that Secret by name. The _monolithic
    template passed it as "--set githubConfigSecret.github_token=..." on a helm command line inside EC2 user
    data, which put it in three places at once: the instance's user data, which any process on the instance can
    read from IMDS; /var/log/cloud-init-output.log, because the script ran under set -x; and the process list
    while helm ran. That template's own variable description recommended against exactly this.

    It still lands in Terraform state, which is unavoidable for a secret Terraform creates. A GitHub App
    private key held in Secrets Manager and mounted by the Secrets Store CSI driver is the production shape;
    this is the demo shape, named as such.
  DESC

  validation {
    condition     = length(var.github_token) > 0
    error_message = "github_token must not be empty."
  }
  validation {
    # Only the shape, not the value: a token with stray whitespace from pasting, or a username entered by
    # mistake, otherwise fails inside the controller as a 401 from GitHub with no hint that the credential is
    # malformed rather than wrong (rules.md B-1).
    #
    # Deliberately loose on the prefix. ghp_ is a classic token and github_pat_ a fine-grained one, but GitHub
    # has added prefixes before and a validation that enumerates them ages badly - so this checks that the
    # value is one unbroken run of token characters and long enough to be a credential.
    condition     = can(regex("^[A-Za-z0-9_]{36,}$", var.github_token))
    error_message = "github_token must be at least 36 characters of letters, digits and underscores with no whitespace. A classic token starts with ghp_ and a fine-grained one with github_pat_; this most often fails because the value was pasted with a trailing newline."
  }
}
variable "github_secret_name" {
  type        = string
  default     = "github-runner-credentials"
  description = "Name of the Secret holding the token. A named Secret rather than the chart's own generated one, so the token is created once and the release references it - which is what lets the release be re-run without the token appearing on a command line"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.github_secret_name))
    error_message = "github_secret_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "min_runners" {
  type        = number
  default     = 0
  description = "Runner pods kept running with no jobs queued, zero as the _monolithic template had it. Zero is the point of ARC: nothing runs, and therefore nothing is billed, until a workflow asks for a runner"

  validation {
    condition     = var.min_runners >= 0
    error_message = "min_runners must be zero or greater."
  }
}
variable "max_runners" {
  type        = number
  default     = 5
  description = "Most runner pods that can exist at once, five as the _monolithic template had it. The real ceiling is the node group: five runners need five pods' worth of capacity, and with nothing to scale the nodes they queue instead"

  validation {
    condition     = var.max_runners >= 1
    error_message = "max_runners must be at least 1."
  }
  validation {
    condition     = var.max_runners >= var.min_runners
    error_message = "max_runners must be greater than or equal to min_runners."
  }
}
variable "runner_group" {
  type        = string
  default     = null
  description = "GitHub runner group to register the scale set in. Null uses the default group. A group is how access to these runners is restricted to particular repositories, which matters as soon as the URL above is an organisation rather than one repository"

  validation {
    condition     = var.runner_group == null || length(var.runner_group) > 0
    error_message = "runner_group must be a non-empty string, or null to use the default group."
  }
}
variable "container_mode" {
  type        = string
  default     = "kubernetes"
  description = <<-DESC
    How a job that uses containers gets them. The _monolithic template set nothing, which leaves ARC's default
    of running the job directly in the runner pod - so a workflow with a "container:" key or a service
    container fails.

    "kubernetes" runs each job step as its own pod, which needs a ReadWriteMany volume for the work
    directory - so it also needs a storage class that provides one. "dind" runs Docker inside the runner pod
    and needs a privileged container. Empty string restores the original's behaviour.
  DESC

  validation {
    condition     = contains(["kubernetes", "dind", ""], var.container_mode)
    error_message = "container_mode must be kubernetes, dind, or an empty string to leave it unset."
  }
}
variable "helm_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long each release may take. The controller chart installs CRDs and waits for its deployment to be Available; the runner scale set release only waits for its AutoscalingRunnerSet custom resource to be accepted, because helm does not wait on custom resources - so a bad token does not show up here, and the root verifies registration separately"

  validation {
    condition     = var.helm_timeout_seconds >= 60
    error_message = "helm_timeout_seconds must be at least 60."
  }
}
