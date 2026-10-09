variable "aws_region" {
  type        = string
  default     = null
  description = "Region to create everything in. Null falls through to the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is what the _monolithic conversion did"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like a region code (e.g. ap-northeast-2), or be null to use the provider chain."
  }
}
variable "random_string" {
  type        = string
  description = <<-DESC
    Four lowercase letters appended to the bucket name, which is the CloudFormation parameter this template
    asked for ("Random 4 Characters (a-z)").

    Deliberately left without a default, unlike every other variable here (rules.md B-3). An S3 bucket name
    is globally unique across all accounts, so a default would be a name that works once and then fails for
    everyone else with BucketAlreadyExists - an apply-time error naming a bucket the reader never chose.
  DESC

  validation {
    condition     = can(regex("^[a-z]{4}$", var.random_string))
    error_message = "random_string must be exactly four lowercase letters (a-z), as the original CloudFormation parameter required. Digits and hyphens would still produce a legal bucket name, but the four-letter form is what the stack documented."
  }
}
variable "bucket_name_prefix" {
  type        = string
  default     = "sensitive-"
  description = "Prefix the random suffix is appended to, giving the sensitive-<random> name the _monolithic template built inline. Carried as a variable so the full name is composed in exactly one place and both the bucket and the notification read it from there (rules.md B-3)"

  validation {
    # 63 minus the four characters random_string adds, so a prefix that passes here cannot produce a name
    # that S3 rejects for length.
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*$", var.bucket_name_prefix)) && length(var.bucket_name_prefix) <= 59
    error_message = "bucket_name_prefix must start with a lowercase letter or digit, contain only lowercase letters, digits, dots and hyphens, and be at most 59 characters so the full name stays within S3's 63 character limit."
  }
}
variable "bucket_versioning_status" {
  type        = string
  default     = "Enabled"
  description = "Versioning state of the bucket, as the _monolithic template set it. Enabled matters here beyond the usual reasons: the function writes its masked copy back into the same bucket, so a second run over the same input leaves both results retrievable rather than overwriting the first"

  validation {
    condition     = contains(["Enabled", "Suspended"], var.bucket_versioning_status)
    error_message = "bucket_versioning_status must be Enabled or Suspended. Disabled is not a value S3 accepts - versioning can be suspended but never returned to its never-enabled state."
  }
}
variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket first. True, which the _monolithic template had no equivalent of: the demo's whole point is to put objects in this bucket and have the function write more, so without this every destroy fails with BucketNotEmpty. Versioning makes it worse, because emptying also means deleting every version and delete marker"
}
variable "lambda_function_name" {
  type        = string
  default     = "masking-start"
  description = "Name of the function, as the _monolithic template named it. Also the second half of the log group path the verification commands read"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.lambda_function_name))
    error_message = "lambda_function_name must be 1-64 characters of letters, digits, hyphens and underscores - Lambda's own limit."
  }
}
variable "lambda_source_directory" {
  type        = string
  default     = "lambda_src/lambda_function"
  description = "Directory holding the handler, relative to this root. Kept at the root rather than inside the module so the Python stays where a reader looks for it, and passed in as a path (rules.md B-6)"

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
    error_message = "lambda_runtime must be a supported python3.1x runtime, e.g. python3.13. The handler imports only boto3, re, os and json, all of which the runtime provides, so there is nothing here that pins an older one."
  }
}
variable "lambda_handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point, which has to agree with the file name and function name in lambda_source_directory. A mismatch is not a plan error: the function is created and every invocation fails with Runtime.ImportModuleError, visible only in its log group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./-]+\\.[a-zA-Z0-9_]+$", var.lambda_handler))
    error_message = "lambda_handler must be in <module>.<function> form, e.g. index.lambda_handler."
  }
}
variable "lambda_timeout" {
  type        = number
  default     = 300
  description = "How long the function may run, as the _monolithic template set it. Five minutes is generous for masking one text object, and it is also the ceiling on how long a single oversized upload can bill"

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 1 and 900 seconds - Lambda's own range."
  }
}
variable "lambda_memory_size" {
  type        = number
  default     = 128
  description = "Memory, and with it the share of CPU. 128MB is Lambda's own default, which is what the _monolithic template left in place by not setting it. It is stated here because the handler reads whole objects into memory, so this is the real limit on input size"

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "lambda_memory_size must be between 128 and 10240 MB."
  }
}
variable "lambda_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
  ]
  description = <<-DESC
    Managed policies attached to the function's role, both of which the _monolithic template attached.

    AmazonS3FullAccess is broader than this function needs - it reads and writes objects in one bucket - and
    it is kept rather than narrowed because narrowing it would be changing what the original did rather than
    converting it (rules.md A-5). A reader who wants least privilege overrides this list with just
    AWSLambdaBasicExecutionRole and passes the s3:GetObject/s3:PutObject statement through
    lambda_additional_policy_statements, which is scoped to this bucket.
  DESC

  validation {
    condition     = length(var.lambda_iam_policy_arns) > 0 && alltrue([for arn in var.lambda_iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "lambda_iam_policy_arns must be a non-empty list of IAM policy ARNs. It cannot be empty: a function whose role cannot write logs runs and leaves nothing behind to explain what it did."
  }
}
variable "lambda_additional_policy_statements" {
  type        = list(any)
  default     = []
  description = <<-DESC
    Statements added to the function's role as an inline policy, beyond the managed policies above. Empty by
    default, because the _monolithic template granted everything through AmazonS3FullAccess.

    This exists so lambda_iam_policy_arns can be narrowed without editing the module: only the caller knows
    what the function calls, and only the root knows the bucket's ARN (rules.md B-6). The least-privilege
    pairing is lambda_iam_policy_arns = [".../AWSLambdaBasicExecutionRole"] plus a statement here allowing
    s3:GetObject and s3:PutObject on arn:aws:s3:::<bucket>/*.
  DESC

  validation {
    condition     = alltrue([for statement in var.lambda_additional_policy_statements : can(statement.Effect) && can(statement.Action)])
    error_message = "lambda_additional_policy_statements entries must each have at least an Effect and an Action. IAM rejects a statement without them with MalformedPolicyDocument during apply, naming the policy rather than the statement."
  }
}
variable "notification_events" {
  type        = list(string)
  default     = ["s3:ObjectCreated:*"]
  description = "Events that invoke the function, as the _monolithic template configured them. ObjectCreated:* covers Put, Post, Copy and the completion of a multipart upload, so a large file uploaded by the CLI in parts triggers once at the end rather than per part"

  validation {
    condition     = length(var.notification_events) > 0 && alltrue([for event in var.notification_events : startswith(event, "s3:")])
    error_message = "notification_events must be a non-empty list of S3 event types (e.g. s3:ObjectCreated:*)."
  }
}
variable "notification_filter_prefix" {
  type        = string
  default     = "incoming/"
  description = <<-DESC
    Key prefix that narrows which uploads invoke the function.

    This restores something the conversion dropped. The CloudFormation template carried a Filter with an
    S3Key prefix rule of "incoming", and cfn2tf left it behind as a commented-out TODO, so the converted
    notification fired on every object in the bucket. The handler is written for that: it returns
    {"status": "Skipped"} for any key that does not start with "incoming/". Without the filter the function
    is therefore invoked by its own output as well - it writes masked/<name>, that is an ObjectCreated event,
    and the second invocation exists only to be skipped. That guard inside the handler is the one thing
    standing between this configuration and a recursive loop, which is why the filter belongs in the
    configuration rather than being left to the code.

    Set to null to reproduce the converted behaviour of notifying on every key.

    The trailing slash is a deliberate difference from the template's "incoming". S3 prefix matching is
    literal, so "incoming" also matches a top-level file called incomingreport.csv, which the handler then
    skips - an invocation and a CloudWatch log line for an object nobody meant to submit.
  DESC

  validation {
    condition     = var.notification_filter_prefix == null || can(regex("^[^/].*/$", var.notification_filter_prefix))
    error_message = "notification_filter_prefix must not begin with a slash and must end with one (e.g. incoming/), or be null to notify on every key. S3 keys have no leading slash, so a prefix that starts with one matches nothing and the function is simply never invoked."
  }
}
variable "masked_object_prefix" {
  type        = string
  default     = "masked/"
  description = "Where the handler writes its output, used to build the verification command that lists results. The handler owns this value - it is the replacement target of object_key.replace('incoming/', 'masked/') in index.py - so changing it here only changes what the command looks at"

  validation {
    condition     = can(regex("^[^/].*/$", var.masked_object_prefix))
    error_message = "masked_object_prefix must not begin with a slash and must end with one (e.g. masked/)."
  }
}
variable "log_tail_minutes" {
  type        = number
  default     = 30
  description = "How far back the log verification command reads. The function's log group only exists after its first invocation, so this command answering with a ResourceNotFoundException is the signal that the notification never fired, not that logging is broken"

  validation {
    condition     = var.log_tail_minutes >= 1
    error_message = "log_tail_minutes must be at least 1."
  }
}
