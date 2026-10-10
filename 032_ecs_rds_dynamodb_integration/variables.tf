variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Null falls through to the provider chain (AWS_REGION or the shared config), which is how the _monolithic template left it"
  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like an AWS region name (e.g. ap-northeast-2), or null to use the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "appdev"
  description = "Prefix for the names CloudFormation used to generate, which Terraform requires: the capacity provider, the log groups and the build association names. It replaces the _monolithic template's stack_name variable, which existed only so the cfn-init and cfn-signal calls could name a stack that does not exist"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be 2-31 characters, start with a lowercase letter and contain only lowercase letters, digits and hyphens, because it prefixes an ECS capacity provider name and a log group path."
  }
}
variable "applications" {
  type = map(object({
    order      = number
    dockerfile = string
  }))
  default = {
    user = {
      order = 1
      # Dockerfile.user rather than Dockerfile, which is what the file is called on disk. Every other
      # application's is just Dockerfile. The build context needs it written as "Dockerfile" either way, so
      # the name is mapped here rather than the file being renamed - src/ is the extracted form of the
      # template's cfn-init metadata and is left as it is found.
      dockerfile = "Dockerfile.user"
    }
    product = {
      order      = 2
      dockerfile = "Dockerfile"
    }
    stress = {
      order      = 3
      dockerfile = "Dockerfile"
    }
  }
  description = <<-DESC
    The three applications, keyed by name, as the _monolithic template's dockerBuildandPush config set wrote
    them. The key is the directory under src/, the ECR repository name, the service name stem and the build
    order's identity.

    order is the build sequence. The builds are serialised on one instance deliberately - see
    modules/container_image_builder.
  DESC
  validation {
    condition     = alltrue([for name in keys(var.applications) : can(regex("^[a-z0-9][a-z0-9_-]*$", name))])
    error_message = "applications keys must be lowercase names of letters, digits, underscores and hyphens: each becomes a directory under src/, an ECR repository name and part of an ECS service name."
  }
  validation {
    # A deliberate restriction rather than an oversight. main.tf wires each application's environment and
    # secrets by name - MYSQL_* for user, TABLE_NAME for product, nothing for stress - because those values
    # come from other modules and cannot live in this variable. Adding a fourth key here would build and
    # deploy a fourth image with no environment at all, and nothing would report that (rules.md B-1).
    condition     = toset(keys(var.applications)) == toset(["user", "product", "stress"])
    error_message = "applications must contain exactly the keys user, product and stress. Their environment, secrets and demonstration commands are wired by name in main.tf, because the values come from the database and table modules and cannot live in this variable - so a missing key leaves a dangling reference and an extra one would build and deploy an image with no environment at all. Changing the set means changing that wiring and adding a source tree under src/."
  }
  validation {
    condition     = length(distinct([for app in var.applications : app.order])) == length(var.applications)
    error_message = "applications entries must each have a distinct order, because the order determines the build chain's marker file sequence."
  }
  validation {
    condition     = alltrue([for app in var.applications : can(regex("^[A-Za-z0-9._-]+$", app.dockerfile))])
    error_message = "applications dockerfile values must be plain file names found under src/<key>/."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template's VpcMapping had it"
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two AZ letters the subnet pairs are placed in. Two, which is what the template's resources used and the smallest count this project runs on - the DB subnet group and multi_az both need a second zone, and a third would add a third NAT gateway for nothing (rules.md C-3). The template's AzMapping also defined \"c\" and nothing referenced it"
  validation {
    condition     = length(var.availability_zone_suffixes) == 2
    error_message = "availability_zone_suffixes must contain exactly two entries: the network module declares one public and one private subnet per zone by name rather than by for_each."
  }
}
variable "workbench_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the workbench AMI, as the template's BastionEc2AmiId parameter had it"
  validation {
    condition     = can(regex("^/", var.workbench_ami_ssm_parameter_name))
    error_message = "workbench_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "container_instance_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "SSM parameter path resolved to the container instance AMI, as the template's EcsAmiId parameter had it. An ECS-optimized AMI specifically: it carries the agent and the ecs-init package that registers the ecs.capability.task-eni attribute every awsvpc task definition here requires"
  validation {
    condition     = can(regex("^/", var.container_instance_ami_ssm_parameter_name))
    error_message = "container_instance_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the workbench's code-server port is open to 0.0.0.0/0, as the template had it. code-server runs with auth: none, so this exposes an unauthenticated shell on an instance holding AdministratorAccess - it is the demo's only way in and it is reproduced, but see modules/vscode_ec2 before leaving it running"
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench holding the marker files that order the SSM chain: the bootstrap's own completion, then one per image build, then the database schema, then the README. /run rather than /home, because it is a tmpfs - the markers describe this boot and should not survive a reboot into a state where nothing has actually run (rules.md D-5)"
  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "mysql_client_package" {
  type        = string
  default     = "mariadb105"
  description = "Package providing the mysql client on the workbench, which the schema step runs. mariadb105 is the Amazon Linux 2023 package name - there is no package called mysql, and a missing client shows up as \"mysql: command not found\" inside the schema association rather than anywhere in Terraform"
  validation {
    condition     = length(var.mysql_client_package) > 0
    error_message = "mysql_client_package must not be empty."
  }
}
variable "ecr_repository_name_prefix" {
  type        = string
  default     = ""
  description = "Prefix for the three ECR repository names, which the template left bare: user, product and stress. Empty reproduces that. Those names are short enough to collide with anything else in the account, so a prefix is the way to run a second copy of this project"
  validation {
    condition     = var.ecr_repository_name_prefix == "" || can(regex("^[a-z0-9][a-z0-9._/-]*$", var.ecr_repository_name_prefix))
    error_message = "ecr_repository_name_prefix must be empty or start with a lowercase letter or digit and contain only lowercase letters, digits, dots, underscores, hyphens and slashes."
  }
}
variable "rds_username" {
  type        = string
  default     = "admin"
  description = "Database master username, as the template's RdsUsername parameter had it. The same value reaches the user container as MYSQL_USER and the credential secret (rules.md B-5)"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,15}$", var.rds_username))
    error_message = "rds_username must be 1-16 characters, start with a letter and contain only letters, digits and underscores."
  }
}
variable "rds_password" {
  type        = string
  default     = null
  sensitive   = true
  description = <<-DESC
    Database master password. Null generates one and stores it in Secrets Manager, which is the default.

    The template had default = "dbpassword" here. That default is the change: a secret with a default is the
    secret the project runs with, and sensitive = true hid it from terraform output while the task
    definitions passed the same string to the containers as a plaintext environment variable.

    Nothing writes this value anywhere a person reads. The workbench README gets a retrieval command for the
    secret instead (rules.md H-2), and the user container receives it through the task definition's secrets
    list rather than its environment list.
  DESC
  validation {
    condition     = var.rds_password == null || can(regex("^[^/@\" ]{8,41}$", var.rds_password))
    error_message = "rds_password must be 8-41 characters and must not contain '/', '@', '\"' or a space, which RDS rejects for a MySQL master password - or null to generate one."
  }
}
variable "rds_database" {
  type        = string
  default     = "dev"
  description = "Initial database, as the template's RdsDatabase parameter had it. The user application connects to it and the schema step creates its table inside it"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,63}$", var.rds_database))
    error_message = "rds_database must be 1-64 characters, start with a letter and contain only letters, digits and underscores."
  }
}
variable "create_read_replica" {
  type        = bool
  default     = true
  description = "Whether to create the read replica. True, because the template declared one - see modules/rds_mysql for why what it declared was not actually a replica. Nothing in this project reads from it, so false is a legitimate way to halve the database cost of the demo"
}
variable "rds_schema_sql" {
  type        = string
  default     = <<-SQL
    CREATE TABLE IF NOT EXISTS user (
      id             VARCHAR(64)  NOT NULL,
      username       VARCHAR(255) NOT NULL,
      email          VARCHAR(255) NOT NULL,
      status_message TEXT,
      PRIMARY KEY (id),
      KEY idx_user_email (email)
    );
  SQL
  description = <<-DESC
    DDL the schema step applies to the initial database.

    An addition, not a reproduction: the _monolithic template created no schema anywhere. Nothing in it did,
    which means POST /v1/user would have answered 500 with "Error 1146: Table 'dev.user' doesn't exist" on a
    stack where everything else was correct - and that is the endpoint the user service exists to serve.

    The columns are read off src/user/main.go rather than chosen: the INSERT names id, username, email and
    status_message, and the SELECT filters on email, which is why there is an index on it.
  DESC
  validation {
    condition     = length(trimspace(var.rds_schema_sql)) > 0
    error_message = "rds_schema_sql must not be empty. To skip schema creation, replace it with a harmless statement such as \"SELECT 1;\" - the step is unconditional because the chain of marker files after it has to run, and because the user service does not work without a table."
  }
  validation {
    condition     = !can(regex("(?m)^TFSCHEMA$", var.rds_schema_sql))
    error_message = "rds_schema_sql must not contain a line that is exactly TFSCHEMA: that is the heredoc delimiter it is piped to the mysql client with, and such a line would end the statement early and leave the rest being parsed as shell."
  }
}
variable "restrict_task_ingress_to_vpc" {
  type        = bool
  default     = true
  description = "Whether the task security group admits all traffic from the whole VPC CIDR, as the template's first ingress block did. False leaves only the rule admitting the workbench on the application port, which is the narrower configuration and is enough for everything in this project"
}
variable "service_desired_count" {
  type        = number
  default     = 1
  description = "Tasks each of the three services keeps running, as the template had it"
  validation {
    condition     = var.service_desired_count >= 0
    error_message = "service_desired_count must be zero or more."
  }
  validation {
    # The ceiling is ENIs rather than CPU or memory: an awsvpc task consumes one on its instance and the
    # primary interface uses one, so a t3.medium runs two. Three instances is six slots.
    condition     = var.service_desired_count * length(var.applications) <= 6
    error_message = "service_desired_count times three services must not exceed six tasks, which is what three t3.medium container instances can hold: each awsvpc task takes one of the instance's three ENIs and the primary interface takes one. Beyond that the extra tasks stay pending and the service reports no instance meeting their requirements, which reads as a capacity problem rather than an ENI one."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = false
  description = "Whether apply blocks until each service reports a steady state. False, so a first apply is not held for the several minutes three deployments take. The trade is that apply succeeding does not mean the tasks are running - the service event commands in the outputs are how to tell"
}
variable "dynamo_table_index_name" {
  type        = string
  default     = "id"
  description = "Value passed to the product container as TABLE_INDEX_NAME, as the template passed it. The application reads the variable into a package-level string and never uses it, and \"id\" is the table's partition key rather than any index name - reproduced because it is inert. It was also the clue to what the key schema was meant to be: the table is keyed on id alone now, where the template had id + price (see modules/dynamodb_table)"
  validation {
    condition     = length(var.dynamo_table_index_name) > 0
    error_message = "dynamo_table_index_name must not be empty."
  }
}
variable "schema_timeout_seconds" {
  type        = number
  default     = 2400
  description = "How long Terraform waits for the schema association, and the executionTimeout SSM gives its command. It waits on the last image build's marker first, so its budget covers the tail of the build chain as well as its own work. 2400 rather than 1800 so it stays above marker_wait_attempts' thirty-minute wait with room left for the mysql run after it - at 1800 the two were equal, and the step would be killed at the moment it was about to report which marker was missing. The same 2400 the image build steps get in modules/container_image_builder"
  validation {
    condition     = var.schema_timeout_seconds >= 300 && var.schema_timeout_seconds <= 7200
    error_message = "schema_timeout_seconds must be between 300 and 7200."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 2400
  description = "How long Terraform waits for the README association, and the executionTimeout SSM gives its command. It is last in the chain and therefore waits on everything before it. 2400 rather than 1800 for the same reason as schema_timeout_seconds: it has to stay above marker_wait_attempts' thirty-minute wait, or the step is killed before it can say the schema marker never appeared"
  validation {
    condition     = var.readme_timeout_seconds >= 300 && var.readme_timeout_seconds <= 7200
    error_message = "readme_timeout_seconds must be between 300 and 7200."
  }
}
variable "marker_wait_attempts" {
  type        = number
  default     = 180
  description = "How many ten-second checks the schema and README steps make for the marker they are waiting on before giving up with a message naming it. Thirty minutes at the default, which has to stay below schema_timeout_seconds and readme_timeout_seconds (forty minutes each at their defaults) - otherwise the step is killed from outside while still waiting and never says which marker was missing"
  validation {
    condition     = var.marker_wait_attempts >= 1
    error_message = "marker_wait_attempts must be at least 1."
  }
  validation {
    condition     = var.marker_wait_attempts * 10 < var.schema_timeout_seconds && var.marker_wait_attempts * 10 < var.readme_timeout_seconds
    error_message = "marker_wait_attempts times ten seconds must be less than both schema_timeout_seconds and readme_timeout_seconds, so a step still waiting reports which marker file it is waiting for rather than being killed first."
  }
}
