variable "name" {
  type        = string
  description = "Name of the function, and the basis for its role and log group names. The _monolithic template named one function literally \"Backend\" and let CloudFormation generate the other; a literal Lambda name is unique per account and region, so the first of those fails a second apply in one account with ResourceConflictException. The caller derives both from the project name instead"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, hyphens and underscores - Lambda's own limit."
  }
}
variable "filename" {
  type        = string
  description = "Path to the zip holding the function's code, built by a data \"archive_file\" in the root. Passed in rather than built here so a module-level depends_on does not defer the packaging to apply (rules.md D-6)"

  validation {
    condition     = can(regex("\\.zip$", var.filename))
    error_message = "filename must be the path to a .zip archive."
  }
}
variable "source_code_hash" {
  type        = string
  description = "Base64 SHA-256 of the zip, from the same archive_file. Without it Lambda keeps serving the code it already has after a source change, and the only symptom is a function whose behaviour does not match the file on disk"

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]+={0,2}$", var.source_code_hash))
    error_message = "source_code_hash must be a base64 digest, which is what archive_file's output_base64sha256 produces."
  }
}
variable "handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point, as the _monolithic template had it for both functions. It has to match a module-level function in the zipped source: a mismatch is not a plan or apply error, it is a runtime \"Handler 'lambda_handler' missing on module 'index'\" on the first invocation"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./-]+\\.[a-zA-Z0-9_]+$", var.handler))
    error_message = "handler must be in <module>.<function> form, e.g. index.lambda_handler."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime, as the _monolithic template had it for both functions"

  validation {
    condition     = can(regex("^python3\\.(1[0-9]|[2-9][0-9])$", var.runtime))
    error_message = "runtime must be a supported python3.1x runtime, e.g. python3.13. Runtimes before 3.10 have reached end of support, and a function on one keeps working until AWS stops it - which is the worst way to find out."
  }
}
variable "timeout" {
  type        = number
  default     = 60
  description = "How long the function may run, as the _monolithic template had it. Sixty seconds is generous for both of these - one formats a JSON body and the other makes a single EC2 call - but the terminator is invoked synchronously by Terraform, so a timeout there fails the apply rather than a request"

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds - Lambda's own range."
  }
}
variable "memory_size" {
  type        = number
  default     = 128
  description = "Memory, and therefore the share of CPU. 128MB is Lambda's minimum and what the _monolithic template got by not setting it"

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}
variable "environment_variables" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Environment variables for the function. The backend takes one; the terminator takes none, which is why
    the environment block is dynamic - an empty block is not the same as no block, and Lambda reports a
    configuration difference for one on every plan.

    This is how the game password reaches the backend. The _monolithic template put it in the source
    instead, as a CloudFormation Fn::Sub placeholder - and that substitution was lost when the template was
    converted, so the function would have served the literal string $${GamePassword} to the browser. A value
    here is visible to anyone who can call lambda:GetFunctionConfiguration, which is the normal caveat for
    Lambda environment variables; it does not matter in this project, because the function hands the same
    value to unauthenticated callers by design.

    The $${...} above is escaped because a bare dollar-brace opens an interpolation in a Terraform
    heredoc, and the plan would fail with "Invalid reference" naming a variable that does not exist.
  DESC

  validation {
    condition     = alltrue([for name in keys(var.environment_variables) : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", name))])
    error_message = "environment_variables keys must start with a letter and contain only letters, digits and underscores - Lambda rejects anything else, and the message it returns names the whole request rather than the key."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "How long the function's logs are kept. The _monolithic template declared no log group at all, so Lambda created one on first invocation with retention set to never expire - logs kept forever for a demo, billed forever, and left behind by terraform destroy"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "inline_policy_name" {
  type        = string
  default     = "function"
  description = "Name of the inline policy carrying the log permissions and anything the caller added. The _monolithic template called the terminator's inline policy CustomLambdaPolicy; the name is local to the role, so it only has to be readable"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.inline_policy_name))
    error_message = "inline_policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
variable "managed_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies attached on top of the inline policy. Empty by default: the _monolithic template attached AWSLambdaBasicExecutionRole to both roles, and the inline policy above replaces it with writes to this function's own log group only. Pass the managed ARN here to get the original behaviour back"

  validation {
    condition     = alltrue([for arn in var.managed_policy_arns : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/", arn))])
    error_message = "managed_policy_arns must contain IAM policy ARNs, e.g. arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole."
  }
}
variable "additional_policy_statements" {
  type        = list(any)
  default     = []
  description = "Statements added to the function's role beyond writing its own logs. Supplied by the caller because only the caller knows what the function calls - the terminator needs ec2:TerminateInstances on one instance, the backend needs nothing (rules.md B-6)"

  validation {
    condition     = alltrue([for statement in var.additional_policy_statements : can(statement.Effect) && can(statement.Action) && can(statement.Resource)])
    error_message = "additional_policy_statements entries must each have Effect, Action and Resource. A statement missing one of them is accepted by jsonencode and rejected by IAM during apply with MalformedPolicyDocument."
  }
}
variable "create_function_url" {
  type        = bool
  default     = false
  description = "Whether to give the function a public HTTP endpoint. True for the backend, which the browser fetches the password from; false for the terminator, which only Terraform and the CLI invoke"
}
variable "function_url_authorization_type" {
  type        = string
  default     = "AWS_IAM"
  description = "Whether callers of the function URL have to sign their requests. The caller sets NONE for the backend because a browser has nothing to sign with - that makes the endpoint unauthenticated, and in this project it returns the game password to anybody. The default here is the safe one, so a new caller has to ask for the open behaviour rather than inherit it"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_authorization_type)
    error_message = "function_url_authorization_type must be NONE or AWS_IAM."
  }
}
variable "function_url_invoke_mode" {
  type        = string
  default     = "BUFFERED"
  description = "Whether the response is returned whole or streamed, as the _monolithic template had it. BUFFERED is what a handler returning a statusCode/body dict needs; RESPONSE_STREAM expects a handler written against the streaming interface and returns an empty body for one that is not"

  validation {
    condition     = contains(["BUFFERED", "RESPONSE_STREAM"], var.function_url_invoke_mode)
    error_message = "function_url_invoke_mode must be BUFFERED or RESPONSE_STREAM."
  }
}
variable "function_url_allow_origins" {
  type        = list(string)
  default     = []
  description = "Origins allowed to call the function URL from a browser, as the CORS allow_origins list. The _monolithic template used [\"*\"], which it has to: the page is served from an S3 website hostname and the function answers on a lambda-url hostname, so every fetch is cross-origin. Empty omits the CORS block entirely, which makes the browser refuse the response even though the function returned 200"

  validation {
    condition     = alltrue([for origin in var.function_url_allow_origins : length(origin) > 0])
    error_message = "function_url_allow_origins entries must not be empty strings."
  }
  validation {
    # A combination constraint rather than one about either value on its own (rules.md B-1): the CORS block
    # only exists inside the function URL resource, so origins passed without the URL are silently
    # discarded and the caller is left believing CORS is configured.
    condition     = length(var.function_url_allow_origins) == 0 || var.create_function_url
    error_message = "function_url_allow_origins is only used when create_function_url is true. Set create_function_url, or drop the origins."
  }
}
