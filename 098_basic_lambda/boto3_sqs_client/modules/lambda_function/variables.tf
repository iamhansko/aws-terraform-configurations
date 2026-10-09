variable "function_name" {
  type        = string
  default     = "queue-lambda"
  description = "Name of the function, as the _monolithic template named it. The load generator looks the function up by this name through GetFunctionUrlConfig rather than being handed the URL, so changing it here means changing it in the generator script too"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores - Lambda's own limit."
  }
}
variable "role_name" {
  type        = string
  default     = "queue-lambda-role"
  description = <<-DESC
    Name of the execution role, as the _monolithic template named it.

    A fixed name, which is reproduced rather than replaced by name_prefix, because the original chose it and
    the cost is visible: a second copy of this project in the same account fails with EntityAlreadyExists.
    Set it to null to let IAM generate one.
  DESC

  validation {
    condition     = var.role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters from the set IAM accepts for a role name, or null to have one generated."
  }
}
variable "source_directory" {
  type        = string
  description = "Directory holding the handler source, resolved by the caller (rules.md B-6)"

  validation {
    condition     = length(var.source_directory) > 0
    error_message = "source_directory must not be empty."
  }
}
variable "handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point, in <module>.<function> form"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./-]+\\.[a-zA-Z0-9_]+$", var.handler))
    error_message = "handler must be in <module>.<function> form, e.g. index.lambda_handler."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime, as the _monolithic template set it"

  validation {
    condition     = can(regex("^python3\\.(1[0-9]|[2-9][0-9])$", var.runtime))
    error_message = "runtime must be a supported python3.1x runtime, e.g. python3.13."
  }
}
variable "timeout" {
  type        = number
  default     = 300
  description = <<-DESC
    How long the function may run, as the _monolithic template set it.

    Five minutes is far longer than this handler needs - it parses a JSON body and makes one SendMessage call,
    measured at about 26 ms - and the generous value is not harmless. A function URL invokes synchronously,
    so an in-flight request holds a concurrent execution for as long as the function runs, and the concurrency
    ceiling is what limits the burst this project is built to demonstrate. A handler that hangs for the full
    timeout holds its slot for 300 seconds and every request behind it gets a 429.
  DESC

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds - Lambda's own range."
  }
}
variable "memory_size" {
  type        = number
  default     = 128
  description = <<-DESC
    Memory, and with it the share of CPU. 128MB is Lambda's default, which is what the _monolithic template
    left in place by not setting it.

    Raising it does not raise the throughput of the burst, and that is worth knowing before anyone tries:
    the limit is the number of concurrent executions available to this function, not the duration of one.
    All of a batch's requests arrive within a few milliseconds of each other, so a shorter invocation changes
    how quickly the accepted ones finish, not how many are accepted.
  DESC

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}
variable "queue_url" {
  type        = string
  description = "URL of the queue the handler sends to, injected as the QUEUE_URL environment variable. Taken from the queue module's output rather than assembled from a name, so the function cannot be configured against a queue that does not exist (rules.md B-6)"

  validation {
    condition     = can(regex("^https://sqs\\.[a-z0-9-]+\\.amazonaws\\.com(\\.cn)?/[0-9]{12}/[a-zA-Z0-9_.-]+$", var.queue_url))
    error_message = "queue_url must be an SQS queue URL (e.g. https://sqs.ap-northeast-2.amazonaws.com/123456789012/queue)."
  }
}
variable "queue_arn" {
  type        = string
  description = "ARN of the same queue, which is what the inline sqs:SendMessage statement narrows itself to. Both are needed because an IAM Resource element takes an ARN while the SDK call takes a URL"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_.-]+$", var.queue_arn))
    error_message = "queue_arn must be an SQS queue ARN (e.g. arn:aws:sqs:ap-northeast-2:123456789012:queue)."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  description = "Managed policies attached to the execution role. Just the log-writing policy, as the _monolithic template attached - the queue access is an inline policy scoped to one queue rather than a managed policy, which is the one thing about the original's IAM that was already least privilege"

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs. Dropping AWSLambdaBasicExecutionRole leaves a function whose throttling and errors cannot be read anywhere."
  }
}
variable "function_url_authorization_type" {
  type        = string
  default     = "NONE"
  description = <<-DESC
    Whether the function URL requires a signed request. NONE, as the _monolithic template configured it, which
    means the URL is a public unauthenticated HTTP endpoint that writes into the SQS queue - anyone who learns
    it can fill the queue, and the account pays for the invocations and the messages.

    That is what the original did and it is kept, because the demo's load generator posts to it with plain
    aiohttp and no SigV4 signing. The alternative is AWS_IAM, which stops the public exposure and also stops
    the generator working as written: it would have to sign each request for the lambda service, and the
    generator's instance role would need lambda:InvokeFunctionUrl. Switching this to AWS_IAM here is
    deliberately allowed, and it also removes the public invoke permission below rather than leaving a
    principal "*" statement behind.

    Nothing about this URL is secret, and it is printed as an output and written into a README on an instance
    whose code-server has auth disabled. Treat an apply of this project as a public endpoint in that account.
  DESC

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_authorization_type)
    error_message = "function_url_authorization_type must be NONE or AWS_IAM - the only two values Lambda accepts for a function URL."
  }
}
variable "metrics_window_minutes" {
  type        = number
  default     = 30
  description = "How far back the metric verification commands this module exposes look"

  validation {
    condition     = var.metrics_window_minutes >= 1
    error_message = "metrics_window_minutes must be at least 1."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = <<-DESC
    How long the function's own logs are kept.

    The _monolithic template declared no log group for the function, so Lambda created one on first invocation
    with retention set to never expire. Under the load this project generates that is tens of thousands of log
    lines per run, kept and billed forever, and terraform destroy removes none of it.

    Declaring the group is what makes retention settable. The risk is the inverse one: the group name is fixed
    at /aws/lambda/<function_name>, so if anything invokes the function before this resource is created, Lambda
    creates the group first and the apply fails with ResourceAlreadyExistsException. Nothing here can invoke the
    function before the function exists, and the function depends on this group.
  DESC

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
