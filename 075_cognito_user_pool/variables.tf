variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run. MemoryDB has to be offered there. Bedrock does not: the game calls it in fixed regions - the server and the item image embeddings in us-east-1, the item images in bedrock_image_region"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "spirit-of-kiro"
  description = "Prefix for every generated name - the cluster, services, repositories, user pool and buckets. Stands in for the _monolithic template's stack_name, and has its default"

  validation {
    # The tightest consumer is the bucket prefix, "<project_name>-client-" within 37 characters, and the
    # execution role name prefix the service module cuts at 26.
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.project_name))
    error_message = "project_name must be 2-20 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}
variable "environment" {
  type        = string
  default     = "dev"
  description = "Value of ENVIRONMENT in both services, as the _monolithic template's environment parameter. The item image service looks for <environment>.env in its image and falls back to its process environment, which is where every value it needs is set"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.environment))
    error_message = "environment must be 1-16 characters of lowercase letters, digits and hyphens, e.g. dev or prod."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether code-server accepts traffic from 0.0.0.0/0. True as the _monolithic template had it - a bool where that template used a string validated against [\"True\", \"False\"]. code-server has no authentication in front of it"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the VS Code workbench, as the _monolithic template had it. The client build and both docker builds run on it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.106.2"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.106.2)."
  }
}
variable "spirit_of_kiro_repository_url" {
  type        = string
  default     = "https://github.com/iamhansko/spirit-of-kiro.git"
  description = "Git repository the game is built from, as the _monolithic template cloned it"

  validation {
    condition     = can(regex("^https://[^\\s'\"]+\\.git$", var.spirit_of_kiro_repository_url))
    error_message = "spirit_of_kiro_repository_url must be an https URL ending in .git, with no spaces or quotes - it is placed into a shell command."
  }
}
variable "spirit_of_kiro_ref" {
  type        = string
  default     = "4f126ebdadaaead50e6a8354da6d5bb00bc9bebc"
  description = "Commit the game is built from, and the tag both images are pushed with. The _monolithic template cloned whatever the default branch held on the day of the apply and pushed it as latest, so two applies of the same configuration could run different games. Changing this re-runs the build and rolls both services onto the new images"

  validation {
    # A full commit ID rather than a branch or tag: it is what re-runs the build when it changes - a branch name
    # stays the same while what it points at moves, so the build would never re-run - and it has to be a valid
    # image tag, which a branch name with a slash is not.
    condition     = can(regex("^[0-9a-f]{40}$", var.spirit_of_kiro_ref))
    error_message = "spirit_of_kiro_ref must be a full 40-character commit ID. A branch or tag name does not re-run the build when it moves; to build the tip of a branch, pass its current commit (git ls-remote <url> <branch>)."
  }
}
variable "bedrock_image_model_id" {
  type        = string
  default     = "stability.stable-image-core-v1:1"
  description = "Bedrock model the item image service generates item images with, passed to it as BEDROCK_IMAGE_MODEL_ID. The game used amazon.nova-canvas-v1:0 hardcoded until that model reached end of life on 2026-09-30; from then every image request failed in Bedrock, the server stored items without an image, and the client showed only the alt text. Nothing in plan or apply sees a retired model - the failure is in the item image service's log"

  validation {
    # The service sends the Stability AI text-to-image body (prompt, negative_prompt, aspect_ratio,
    # output_format, seed), which these three share. Another model takes a different body and fails in
    # Bedrock at the first item, not here.
    condition = contains([
      "stability.stable-image-core-v1:1",
      "stability.stable-image-ultra-v1:1",
      "stability.sd3-5-large-v1:0",
    ], var.bedrock_image_model_id)
    error_message = "bedrock_image_model_id must be a Stability AI text-to-image model the item image service can call with its request body: stability.stable-image-core-v1:1, stability.stable-image-ultra-v1:1 or stability.sd3-5-large-v1:0. A model with another request format needs a change to item-images/lib/item-image.ts in the game first."
  }
}
variable "bedrock_image_region" {
  type        = string
  default     = "us-west-2"
  description = "Region the item image service invokes bedrock_image_model_id in, passed to it as BEDROCK_IMAGE_REGION. Not the deploy region: the three Stability text-to-image models are offered in us-west-2, and the tasks reach it through their NAT gateways. The task role allows bedrock:InvokeModel in every region"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.bedrock_image_region))
    error_message = "bedrock_image_region must be a region code such as us-west-2."
  }
}
variable "bun_version" {
  type        = string
  default     = "1.2.15"
  description = "Bun release that builds the game client on the workbench. The _monolithic template installed whatever was latest; this is the release both service images are built on (oven/bun:1.2.15 in their Dockerfiles at the pinned commit), so the client and the services build with one toolchain"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.bun_version))
    error_message = "bun_version must be a semantic version (e.g. 1.2.15)."
  }
}
variable "server_container_port" {
  type        = number
  default     = 8080
  description = "Port the game server listens on, as the _monolithic template's EcsServiceMapping had it. The service module passes it to the container as PORT, so the two cannot disagree"

  validation {
    condition     = var.server_container_port >= 1024 && var.server_container_port <= 65535 && floor(var.server_container_port) == var.server_container_port
    error_message = "server_container_port must be an integer between 1024 and 65535 - the images run as the unprivileged bun user, which cannot bind below 1024."
  }
}
variable "image_generation_container_port" {
  type        = number
  default     = 3001
  description = "Port the item image service listens on, as the _monolithic template's EcsServiceMapping had it. Passed to the container as PORT"

  validation {
    condition     = var.image_generation_container_port >= 1024 && var.image_generation_container_port <= 65535 && floor(var.image_generation_container_port) == var.image_generation_container_port
    error_message = "image_generation_container_port must be an integer between 1024 and 65535 - the images run as the unprivileged bun user, which cannot bind below 1024."
  }
}
variable "task_cpu" {
  type        = number
  default     = 1024
  description = "CPU units for each service's task, as the _monolithic template had both"

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "task_cpu must be a Fargate CPU size: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}
variable "task_memory" {
  type        = number
  default     = 2048
  description = "Memory in MiB for each service's task, as the _monolithic template had both. Has to be a size Fargate pairs with task_cpu"

  validation {
    condition     = var.task_memory >= 512 && var.task_memory % 512 == 0
    error_message = "task_memory must be a multiple of 512 MiB."
  }
  validation {
    # The range Fargate accepts for the chosen CPU size. An unsupported pair passes plan and is rejected by
    # RegisterTaskDefinition partway through apply. The step within the range is not checked here; the
    # multiple-of-512 rule above covers the smaller sizes.
    condition = (
      var.task_memory >= lookup({ "256" = 512, "512" = 1024, "1024" = 2048, "2048" = 4096, "4096" = 8192, "8192" = 16384, "16384" = 32768 }, tostring(var.task_cpu), 0) &&
      var.task_memory <= lookup({ "256" = 2048, "512" = 4096, "1024" = 8192, "2048" = 16384, "4096" = 30720, "8192" = 61440, "16384" = 122880 }, tostring(var.task_cpu), 0)
    )
    error_message = "task_memory must be within the range Fargate pairs with task_cpu: 256 takes 512-2048, 512 takes 1024-4096, 1024 takes 2048-8192, 2048 takes 4096-16384, 4096 takes 8192-30720, 8192 takes 16384-61440 and 16384 takes 32768-122880."
  }
}
variable "service_desired_count" {
  type        = number
  default     = 2
  description = "Tasks per service, as the _monolithic template had both. The server's target group keeps a player on one task with a load balancer cookie"

  validation {
    condition     = var.service_desired_count >= 1 && floor(var.service_desired_count) == var.service_desired_count
    error_message = "service_desired_count must be a positive integer."
  }
}
variable "memorydb_node_type" {
  type        = string
  default     = "db.r6g.large"
  description = "Node type of the item image service's MemoryDB cluster, as the _monolithic template had it. MemoryDB bills per node-hour whether or not the game is played; this is the largest line of this project's cost"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.memorydb_node_type))
    error_message = "memorydb_node_type must be a MemoryDB node type, e.g. db.r6g.large or db.t4g.small."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each step drops its completion marker. Every association waits for the previous step's marker rather than relying on depends_on (rules.md D-5/H-2)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "game_build_timeout_seconds" {
  type        = number
  default     = 3600
  description = "How long the build step may take, including its wait for the workbench bootstrap: a client build and two docker builds on the workbench. The _monolithic template gave its CreationPolicy 10 minutes for all of it and the bootstrap, which a first docker pull and bun install can exceed on their own. Measured on a t3.medium, the clone, the client build and both image builds took 42 seconds before the pushes. It is the build association's wait, and the timeout of the function that waits for the images, which is the wait that actually holds the apply. That function is capped at 900 seconds, the longest Lambda runs; a build slower than that fails the apply without failing the build, and the next terraform apply waits again"

  validation {
    condition     = var.game_build_timeout_seconds >= 600
    error_message = "game_build_timeout_seconds must be at least 600."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long the README association may take. It waits for the build step"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
