variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name" {
  type        = string
  default     = "operator-sdk-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "Kubernetes version for the EKS cluster"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.33."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True for convenience - kubectl from your own machine - and deliberately not pinned with a validation, unlike the other EKS projects here. Every Kubernetes object in this project is applied by 'make deploy' from the bastion, inside the VPC, so this configuration already has the shape rules.md E-9 describes and works with a private endpoint (rules.md B-1/E-9)"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoint. Set this to your own address in CIDR form: bootstrap_cluster_creator_admin_permissions means anyone who can reach this endpoint with a valid AWS credential for the creating principal has cluster-admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "operator-sdk-key"
  description = "Name of the EC2 key pair created for the demo instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group. These run the operator and the workload it manages; the image build happens on the bastion, not here"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales the node group here, so this is only headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "ecr_repository_name" {
  type        = string
  default     = "memcached-operator"
  description = "Name of the ECR repository the operator image is pushed to"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.ecr_repository_name))
    error_message = "ecr_repository_name must use the character set ECR accepts for a repository name: lowercase letters, digits, dots, underscores, hyphens and slashes."
  }
}
variable "ecr_image_tag" {
  type        = string
  default     = "latest"
  description = "Tag the operator image is built, pushed and deployed under. One value reaches the docker push and the deployment that pulls it (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.ecr_image_tag))
    error_message = "ecr_image_tag must be 1-128 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "go_version" {
  type        = string
  default     = "1.27.1"
  description = "Go toolchain installed on the bastion from the official tarball, rather than the distribution's golang package as the _monolithic template used. The version matters: operator-sdk's Makefile builds controller-gen and kustomize with 'go install', and the Amazon Linux package trails what a current operator-sdk's generated go.mod asks for - which surfaces as 'go.mod requires go >= x.y' partway through 'make manifests', several minutes into the build"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.go_version))
    error_message = "go_version must look like 1.27.1 or 1.27."
  }
}
variable "operator_sdk_version" {
  type        = string
  default     = "v1.41.1"
  description = "operator-sdk release installed on the bastion, as the _monolithic template had it. The version decides which Go version the scaffolded Dockerfile and go.mod ask for, so it and go_version move together"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.operator_sdk_version))
    error_message = "operator_sdk_version must look like v1.41.1."
  }
}
variable "operator_sdk_gpg_key_id" {
  type        = string
  default     = "052996E2A20B5C7E"
  description = "Key the operator-sdk release checksums are signed with. Verifying it is the only real check here: the binary and its checksum file come from the same place, so a checksum alone proves the download was not corrupted rather than that it is genuine"

  validation {
    condition     = can(regex("^[0-9A-F]{16,40}$", var.operator_sdk_gpg_key_id))
    error_message = "operator_sdk_gpg_key_id must be a 16 or 40 character uppercase hexadecimal key ID."
  }
}
variable "operator_sdk_gpg_keyserver" {
  type        = string
  default     = "keyserver.ubuntu.com"
  description = "Keyserver the signing key is fetched from, as the _monolithic template had it. Exposed as a variable because this is the step most likely to fail for reasons unrelated to the project - a keyserver being unreachable fails the install step, which is the correct outcome but reads as a broken configuration"

  validation {
    condition     = length(var.operator_sdk_gpg_keyserver) > 0
    error_message = "operator_sdk_gpg_keyserver must not be empty."
  }
}
variable "operator_project_name" {
  type        = string
  default     = "memcached-operator"
  description = "Directory the operator is scaffolded into, under ~/projects. operator-sdk derives more from this than is obvious: the Kubernetes namespace it deploys into is <name>-system and the controller Deployment is <name>-controller-manager, so the checks in the outputs are built from this one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.operator_project_name))
    error_message = "operator_project_name must be a valid lowercase RFC 1123 DNS label; it becomes part of a namespace and a Deployment name."
  }
}
variable "operator_domain" {
  type        = string
  default     = "example.com"
  description = "API group suffix for the generated CRD, so the full group becomes <api_group>.<domain>"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.operator_domain))
    error_message = "operator_domain must be a lowercase DNS name such as example.com."
  }
}
variable "operator_go_module" {
  type        = string
  default     = "github.com/example/memcached-operator"
  description = "Go module path written into the generated go.mod. Never fetched - nothing imports this project - but it has to be a syntactically valid module path or 'go mod' rejects it"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9./_-]*$", var.operator_go_module))
    error_message = "operator_go_module must be a valid lowercase Go module path such as github.com/example/memcached-operator."
  }
}
variable "operator_api_group" {
  type        = string
  default     = "cache"
  description = "First segment of the generated CRD's API group. Also part of the sample manifest's filename, which the last build step applies, so it is read in two places from here (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*$", var.operator_api_group))
    error_message = "operator_api_group must be lowercase letters and digits, starting with a letter."
  }
}
variable "operator_api_version" {
  type        = string
  default     = "v1alpha1"
  description = "Version of the generated CRD, and part of the sample manifest's filename"

  validation {
    condition     = can(regex("^v[0-9]+((alpha|beta)[0-9]+)?$", var.operator_api_version))
    error_message = "operator_api_version must be a Kubernetes API version such as v1alpha1, v1beta1 or v1."
  }
}
variable "operator_kind" {
  type        = string
  default     = "Memcached"
  description = "Kind of the generated custom resource. Capitalised, as Kubernetes kinds are; the sample manifest's filename uses the lowercase form, which is derived rather than stated twice (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Z][A-Za-z0-9]*$", var.operator_kind))
    error_message = "operator_kind must be UpperCamelCase, e.g. Memcached."
  }
}
variable "operator_managed_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/memcached:1.6.45-alpine"
  description = "Image the generated operator deploys for each custom resource it sees. Pulled from ECR Public rather than Docker Hub, where the _monolithic template had it: Docker Hub rate-limits anonymous pulls per source address, and every node here shares one NAT gateway address per zone - so a Docker Hub image is the kind that works once and fails on the next scale-up"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.operator_managed_image))
    error_message = "operator_managed_image must carry an explicit tag; a floating latest makes a rebuild deploy something different with nothing to show it."
  }
}
variable "operator_container_command" {
  type = string
  # "-m,64" and not "-m=64", and "-o,modern" and not a bare "modern".
  #
  # The _monolithic template passed "memcached,-m=64,modern,-v" against memcached 1.4.36-alpine and
  # it worked, so the string was carried across unchanged. This project pulls 1.6.45-alpine instead -
  # see operator_managed_image, which moved to ECR Public to avoid Docker Hub's anonymous pull
  # limits - and on that version the same string is fatal:
  #
  #   Cannot set item size limit higher than 1/2 of memory max.   (exit 64)
  #
  # Nothing in that message names the argument that caused it. "-m" takes its value as the next
  # argument, so "-m=64" hands memcached the literal "=64", which parses as 0 MB; the default 1 MB
  # item size limit is then larger than half of zero and 1.6.x treats that as an error where 1.4.x
  # did not. The missing "-o" is a second, independent defect - it made "modern" a stray positional
  # argument - but fixing only that changes nothing, because "-m=64" is what fails.
  #
  # Measured against 1.6.45-alpine rather than reasoned about:
  #
  #   memcached -m=64 modern -v       exit 64    the string this replaced
  #   memcached -m=64 -o modern -v    exit 64    the operator-sdk tutorial's own form
  #   memcached -m=64 -v              exit 64
  #   memcached -m 64 -v              Running
  #   memcached -m 64 -o modern -v    Running    this value
  #
  # and the original pairing, to confirm what actually changed:
  #
  #   1.4.36-alpine, memcached -m=64 modern -v   Running
  default     = "memcached,-m,64,-o,modern,-v"
  description = "Comma-separated command the generated operator gives the managed container, in the form operator-sdk's deploy-image plugin expects. Passed through to the scaffolding, which turns it into the container's command list. Note that a short option and its value are separate elements: \"-m=64\" is one element that memcached reads as the value \"=64\""

  validation {
    condition     = length(var.operator_container_command) > 0
    error_message = "operator_container_command must not be empty."
  }
  validation {
    # The trap that caused this, caught at plan time. A short option written as -x=value is a single
    # argument whose value is "=value", and the program it reaches reports whatever that mis-parse
    # breaks rather than the argument form - here, a message about item size limits (rules.md B-1).
    condition     = !anytrue([for arg in split(",", var.operator_container_command) : can(regex("^-[a-zA-Z]=", arg))])
    error_message = "operator_container_command contains a short option written as -x=value. Short options take their value as the next element, so split it into two: \"-m,64\" rather than \"-m=64\". Long options are fine with an equals sign (\"--memory-limit=64\")."
  }
}
variable "operator_run_as_user" {
  type        = number
  default     = 1001
  description = "UID the managed container runs as. Non-root, which is what lets the generated pod satisfy a restricted Pod Security Standard - the scaffolding sets runAsNonRoot together with this"

  validation {
    condition     = var.operator_run_as_user > 0
    error_message = "operator_run_as_user must be greater than zero; running as root would defeat the runAsNonRoot the scaffolding sets alongside it."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0 on the code-server port. True as the _monolithic template had it, because code-server is reached from a browser - but it runs with authentication disabled, so narrow this to your own address where possible"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance. This one does real work: it compiles the operator and builds a container image, which is why the root volume below is larger than the repository default"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "vscode_root_volume_size" {
  type        = number
  default     = 50
  description = "Root volume size in GiB for the VS Code instance. Larger than usual because a Go toolchain, a Go module cache, a Docker image cache and the operator image all live on it. The _monolithic template set 20, which is enough to reach the image build and run out during it - and a build that fails on disk space part-way leaves a half-pushed repository"

  validation {
    condition     = var.vscode_root_volume_size >= 30
    error_message = "vscode_root_volume_size must be at least 30 GiB; a Go toolchain plus a Docker build cache does not fit in less."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the VS Code instance where each step drops its completion marker. The steps wait on each other's markers rather than trusting depends_on (rules.md D-5/H-2)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "operator_sdk_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the operator-sdk install step may take. It waits for the instance bootstrap first, which includes downloading a Go toolchain, kubectl, eksctl and helm"

  validation {
    condition     = var.operator_sdk_timeout_seconds > 0
    error_message = "operator_sdk_timeout_seconds must be positive."
  }
}
variable "operator_build_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the scaffold, build, push and deploy step may take. Thirty minutes, where the _monolithic template allowed ten for the same work: compiling controller-gen, compiling the operator inside a container, pushing the image and waiting for a rollout does not reliably fit in ten, and an SSM association that gives up first reports 'unexpected state Failed' with no indication that it simply ran out of time (rules.md A-4)"

  validation {
    condition     = var.operator_build_timeout_seconds > 0
    error_message = "operator_build_timeout_seconds must be positive."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README step may take. It waits for the build step's marker, so its own work is a single file write"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
