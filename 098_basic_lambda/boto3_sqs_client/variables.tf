variable "aws_region" {
  type        = string
  default     = null
  description = "Region to create everything in. Null falls through to the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is what the _monolithic conversion did"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like a region code (e.g. ap-northeast-2), or be null to use the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "boto3-sqs-client"
  description = "Prefix for generated names - the key pair's, and the title of the README written onto the workbench. It is not a prefix for the resource names the _monolithic template fixed (queue, queue-lambda, queue-log-group); those are kept as they were, and their fixed-name consequences are described on the variables that hold them"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.project_name))
    error_message = "project_name must be 1-32 characters of lowercase letters, digits and hyphens."
  }
}
variable "al2023_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM public parameter holding the Amazon Linux 2023 AMI id, as the _monolithic template resolved it. A parameter rather than a literal ami- id, which is also why the lookup is in the root: both instance modules take a resolved id and do not need to know where it came from (rules.md B-6)"

  validation {
    condition     = startswith(var.al2023_ami_ssm_parameter_name, "/aws/service/ami-")
    error_message = "al2023_ami_ssm_parameter_name must be an AWS public AMI parameter path (starting /aws/service/ami-)."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.102.0.0/16"
  description = "CIDR of the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.102.0.0/16)."
  }
}
variable "queue_name" {
  type        = string
  default     = "queue"
  description = "Name of the SQS queue, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.queue_name))
    error_message = "queue_name must be 1-80 characters of letters, digits, hyphens and underscores."
  }
}
variable "queue_message_retention_seconds" {
  type        = number
  default     = 3600
  description = "How long an unconsumed message survives, as the _monolithic template set it. An hour, which is short enough that an abandoned load run stops being billed as stored messages on its own"

  validation {
    condition     = var.queue_message_retention_seconds >= 60 && var.queue_message_retention_seconds <= 1209600
    error_message = "queue_message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}
variable "queue_visibility_timeout_seconds" {
  type        = number
  default     = 30
  description = "How long a received message is hidden from other consumers. The same value the worker script passes on each receive_message call, which is why it is one variable - a queue default shorter than the worker's own timeout means a message that reappears and is processed twice"

  validation {
    condition     = var.queue_visibility_timeout_seconds >= 0 && var.queue_visibility_timeout_seconds <= 43200
    error_message = "queue_visibility_timeout_seconds must be between 0 and 43200 (12 hours)."
  }
}
variable "lambda_function_name" {
  type        = string
  default     = "queue-lambda"
  description = "Name of the function, as the _monolithic template named it. The load generator resolves the URL from this name through GetFunctionUrlConfig, and the name is written into the generator script as a literal - so changing it here means changing scripts/message_app.py.tftpl too"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.lambda_function_name))
    error_message = "lambda_function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "lambda_role_name" {
  type        = string
  default     = "queue-lambda-role"
  description = "Name of the function's execution role, as the _monolithic template named it. A fixed name, so a second copy of this project in the same account fails with EntityAlreadyExists; null has IAM generate one instead"

  validation {
    condition     = var.lambda_role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.lambda_role_name))
    error_message = "lambda_role_name must be 1-64 characters from the set IAM accepts for a role name, or null."
  }
}
variable "lambda_source_directory" {
  type        = string
  default     = "lambda_src/lambda_function"
  description = "Directory holding the handler, relative to this root"

  validation {
    condition     = length(var.lambda_source_directory) > 0 && !startswith(var.lambda_source_directory, "/")
    error_message = "lambda_source_directory must be a non-empty path relative to this root module."
  }
}
variable "lambda_runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime, as the _monolithic template set it"

  validation {
    condition     = can(regex("^python3\\.(1[0-9]|[2-9][0-9])$", var.lambda_runtime))
    error_message = "lambda_runtime must be a supported python3.1x runtime, e.g. python3.13."
  }
}
variable "lambda_timeout" {
  type        = number
  default     = 300
  description = "How long the function may run, as the _monolithic template set it. Far more than the handler needs, and not free: a function URL invoke is synchronous, so a request that hangs holds one of the few concurrent executions available for the whole timeout"

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 1 and 900 seconds."
  }
}
variable "lambda_function_url_authorization_type" {
  type        = string
  default     = "NONE"
  description = <<-DESC
    Whether the function URL requires a signed request. NONE, as the _monolithic template configured it,
    which makes it a public unauthenticated endpoint that anyone can use to put messages on the queue.

    That is what the original did and what the load generator expects - it posts with plain aiohttp and no
    SigV4 signing. AWS_IAM closes the endpoint and also stops the generator working as written, which is
    exactly the trade and is spelled out on the module's variable of the same name.
  DESC

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.lambda_function_url_authorization_type)
    error_message = "lambda_function_url_authorization_type must be NONE or AWS_IAM."
  }
}
variable "log_group_name" {
  type        = string
  default     = "queue-log-group"
  description = "Log group the worker's lines are shipped to, as the _monolithic template named it. One variable feeds both the group that is created and the CloudWatch agent configuration that writes to it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and the characters _ . / # -."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "Retention on both declared log groups - the worker's and the function's. The _monolithic template set none on either, which means never expire: a single load run is tens of thousands of lines on each side"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "metric_filter_pattern" {
  type        = string
  default     = "\"처리성공\""
  description = "What counts as a processed message. The quotes are part of the pattern - an unquoted term is matched as an alphanumeric token, which never matches Korean text, and the filter then counts nothing without ever reporting an error"

  validation {
    condition     = length(var.metric_filter_pattern) > 0
    error_message = "metric_filter_pattern must not be empty - an empty pattern matches every event, including the worker's error lines."
  }
}
variable "metric_namespace" {
  type        = string
  default     = "queue"
  description = "CloudWatch namespace the filter publishes into, as the _monolithic template had it"

  validation {
    condition     = length(var.metric_namespace) > 0 && !startswith(var.metric_namespace, "AWS/")
    error_message = "metric_namespace must not start with AWS/, which CloudWatch reserves."
  }
}
variable "metric_name" {
  type        = string
  default     = "queue-metric"
  description = "Name of the metric the filter publishes, as the _monolithic template had it"

  validation {
    condition     = length(var.metric_name) > 0
    error_message = "metric_name must not be empty."
  }
}
variable "metrics_window_minutes" {
  type        = number
  default     = 30
  description = "How far back every metric and log verification command in the outputs looks. One variable so the commands in the README all cover the same window"

  validation {
    condition     = var.metrics_window_minutes >= 1
    error_message = "metrics_window_minutes must be at least 1."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type of the code-server workbench, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "vscode_instance_name" {
  type        = string
  default     = "queue-bastion"
  description = "Name tag of the workbench, as the _monolithic template tagged it. The tag is kept for continuity with the original even though the module is called vscode_ec2 rather than bastion_ec2 - nothing connects through this host, and that module's main.tf sets out the evidence"

  validation {
    condition     = length(var.vscode_instance_name) > 0
    error_message = "vscode_instance_name must not be empty."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server listens on and the security group opens, as the _monolithic template had it"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be between 1 and 65535."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part version (e.g. 4.100.3)."
  }
}
variable "workbench_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-DESC
    Source CIDRs allowed to reach code-server and SSH on the workbench. 0.0.0.0/0, as the _monolithic
    template opened it.

    Worth reading twice before an apply: code-server there runs with auth: none and the instance role is
    AdministratorAccess, so this default means anyone who finds the address gets an editor and a shell with
    administrative credentials. Narrowing it to one address costs nothing and is the single most useful change
    to make to this project.
  DESC

  validation {
    condition     = alltrue([for cidr in var.workbench_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "workbench_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "worker_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the SQS worker, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.worker_instance_type))
    error_message = "worker_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "worker_instance_name" {
  type        = string
  default     = "queue-ec2"
  description = "Name tag of the worker instance, as the _monolithic template tagged it"

  validation {
    condition     = length(var.worker_instance_name) > 0
    error_message = "worker_instance_name must not be empty."
  }
}
variable "worker_log_file_path" {
  type        = string
  default     = "/var/log/Gwangju_queue.log"
  description = "File the worker logs to and the CloudWatch agent tails, as the _monolithic template named it. One variable because three places need the same string: the worker script, the agent configuration and the tail command in the outputs"

  validation {
    condition     = can(regex("^/[^ ]*$", var.worker_log_file_path))
    error_message = "worker_log_file_path must be an absolute path with no spaces."
  }
}
variable "worker_max_workers" {
  type        = number
  default     = 200
  description = <<-DESC
    Size of the worker's thread pool, as the _monolithic template called sqs_process with.

    It cannot be used: receive_message returns at most ten messages per call and the loop waits for that batch
    before fetching the next, so no more than ten of these threads are ever busy. The value is kept because it
    is what the original ran, and it is a variable so the arithmetic is visible rather than buried in a
    heredoc - draining faster means more receive calls in flight, not a bigger pool.
  DESC

  validation {
    condition     = var.worker_max_workers >= 1
    error_message = "worker_max_workers must be at least 1."
  }
}
variable "worker_wait_time_seconds" {
  type        = number
  default     = 5
  description = "Long-poll duration on each receive_message call, as the _monolithic template had it. Zero would be short polling, which returns immediately and empty most of the time and bills a request for each of those - the long poll is what makes an idle worker cheap"

  validation {
    condition     = var.worker_wait_time_seconds >= 0 && var.worker_wait_time_seconds <= 20
    error_message = "worker_wait_time_seconds must be between 0 and 20 - SQS's own maximum for WaitTimeSeconds."
  }
}
variable "worker_max_messages" {
  type        = number
  default     = 10
  description = "Messages requested per receive call, as the _monolithic template had it. Ten is also SQS's maximum, which is the ceiling that makes worker_max_workers unusable"

  validation {
    condition     = var.worker_max_messages >= 1 && var.worker_max_messages <= 10
    error_message = "worker_max_messages must be between 1 and 10 - SQS's own range for MaxNumberOfMessages."
  }
}
variable "start_worker" {
  type        = bool
  default     = false
  description = "Whether the worker starts at boot. False reproduces the _monolithic template, which left the run line commented out, so the queue visibly fills until someone starts the drain. The systemd unit is installed either way"
}
variable "load_test_concurrency" {
  type        = number
  default     = 100
  description = <<-DESC
    Simultaneous in-flight requests the generator keeps open. Must stay at or below the Lambda concurrency
    available to this function, because a function URL holds one concurrent execution per in-flight request
    and Lambda returns 429 for the excess.

    This is the number that made the original run report throttles for most of its requests. The account limit
    is 1000, but a workshop guardrail function reserves 890 of it, leaving 110 unreserved for every function
    without its own reservation - which is what this one uses. Offering 200 simultaneous requests against 110
    slots rejects the excess instantly.

    Raising lambda memory does not change that arithmetic: a batch's requests all arrive within a few
    milliseconds, so a shorter invocation changes how fast the accepted ones finish, not how many are accepted.
  DESC

  validation {
    condition     = var.load_test_concurrency >= 1 && var.load_test_concurrency <= 110
    error_message = "load_test_concurrency must be between 1 and 110. 110 is this account's UnreservedConcurrentExecutions - a guardrail function reserves 890 of the 1000 limit, and reserved_concurrent_executions cannot buy headroom here because AWS refuses any reservation that drops the unreserved pool below 100. To drive more than 110 concurrent requests, the burst has to reach SQS through something that is not a synchronous Lambda invocation, such as an API Gateway SQS integration."
  }
}
variable "load_test_total_requests" {
  type        = number
  default     = 20000
  description = "Total requests the generator sends. At the default concurrency this is 200 batches, and every successful request is one message on the queue - so this is also the backlog the worker has to drain"

  validation {
    condition     = var.load_test_total_requests >= 1
    error_message = "load_test_total_requests must be at least 1."
  }
}
variable "load_test_batch_delay_seconds" {
  type        = number
  default     = 0.1
  description = "Pause between batches. The original's one second was the real rate limiter: it held throughput to roughly the concurrency per second, while 110 slots retiring a 26 ms invocation can absorb far more"

  validation {
    condition     = var.load_test_batch_delay_seconds >= 0
    error_message = "load_test_batch_delay_seconds must not be negative."
  }
}
variable "load_test_max_retries" {
  type        = number
  default     = 5
  description = "Retries per request when Lambda answers 429. A 429 is backpressure rather than failure - the slot frees up in milliseconds - so the generator backs off and resends instead of dropping the message, which is what lets the success count reach load_test_total_requests"

  validation {
    condition     = var.load_test_max_retries >= 0
    error_message = "load_test_max_retries must not be negative."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module - which touches <path>/userdata as the last step of its user data - and the SSM associations that wait for it (rules.md D-5/H-2). Under /run so the markers vanish on reboot rather than leaving a stale file that makes an unfinished bootstrap look complete"

  validation {
    condition     = can(regex("^/[^ ]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path with no spaces."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README association waits to report success. It has to cover the whole instance bootstrap, because the command's first act is to wait for the user data marker - and that bootstrap includes a dnf update, the Development Tools group and three pip packages"

  validation {
    condition     = var.readme_timeout_seconds >= 15
    error_message = "readme_timeout_seconds must be at least 15, the minimum AWS accepts for wait_for_success_timeout_seconds."
  }
}
variable "message_app_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the generator-rewrite association waits to report success. It runs after the README association and waits for that one's marker, so its budget has to cover the bootstrap as well"

  validation {
    condition     = var.message_app_timeout_seconds >= 15
    error_message = "message_app_timeout_seconds must be at least 15, the minimum AWS accepts for wait_for_success_timeout_seconds."
  }
}
