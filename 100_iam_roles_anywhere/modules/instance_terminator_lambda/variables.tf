variable "function_name" {
  type        = string
  description = "Name of the Lambda function. CloudFormation generated this automatically and Terraform requires it, so the caller derives it - see the root's variables"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point, as module.function. It has to match the Python: lambda_src/custom_resource_lambda_function/index.py defines lambda_handler and archive_file zips it as index.py. A mismatch is not a plan error - the function is created and every invocation answers Runtime.HandlerNotFound, which fails the apply at the invocation rather than at anything naming this variable"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+\\.[A-Za-z0-9_]+$", var.handler))
    error_message = "handler must be of the form module.function (e.g. index.lambda_handler)."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime, as the _monolithic template had it. Must stay a Python runtime: the deployment package is a single .py file and boto3 is only on the path because the Python runtimes bundle it"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.runtime))
    error_message = "runtime must be a python3.x runtime, because the function is a Python module and relies on the boto3 the Python runtimes provide."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = <<-DESC
    How long the function may run, which is how long the apply waits for the export. The function
    polls the bucket until every key in wait_object_keys has arrived and only then terminates, and
    the synchronous invocation holds the apply open for all of it - so this has to cover the whole
    instance bootstrap, not just the terminate call. The _monolithic template's 60 was enough for a
    function that terminated immediately, which is what emptied the bucket.

    The function keeps the last 30 seconds back to report what is still missing, so a value much
    below a minute leaves it no time to poll at all.
  DESC

  validation {
    condition     = var.timeout_seconds >= 60 && var.timeout_seconds <= 900
    error_message = "timeout_seconds must be between 60 and 900. 900 is the most Lambda accepts; below 60 the function has no time left to poll after the 30 seconds it reserves for reporting a timeout."
  }
}
variable "filename" {
  type        = string
  description = "Path to the deployment package, produced by the caller's archive_file. Passed in rather than built here because archive_file resolves its source against path.module and the Python lives at the project root (rules.md B-6, and D-6 for the other reason)"

  validation {
    condition     = can(regex("\\.zip$", var.filename))
    error_message = "filename must be the path to a .zip deployment package."
  }
}
variable "source_code_hash" {
  type        = string
  description = "Base64 SHA-256 of that package, from the same archive_file. Without it Lambda keeps running the code it already has after the source changes, and plan reports no difference"

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{43}=$", var.source_code_hash))
    error_message = "source_code_hash must be a base64-encoded SHA-256 digest, which is what archive_file's output_base64sha256 produces."
  }
}
variable "instance_ids" {
  type        = list(string)
  description = <<-DESC
    Instances the function terminates, sent as the invocation's input.

    A list used in a JSON body rather than as a for_each key, so it is allowed to be another
    module's output and unknown at plan time - the map-with-static-keys form only applies where the
    values become resource addresses (rules.md B-8).

    The function raises on an empty list rather than succeeding quietly, because an empty list
    terminates nothing and a silent success leaves the instance running with the exported private
    key still on it.

    Their launch time matters as well as their ids: an object only counts as arrived if it was
    written after the earliest of these instances launched, which is what keeps a previous
    apply's export from releasing the termination of this one.
  DESC

  validation {
    condition     = length(var.instance_ids) > 0
    error_message = "instance_ids must not be empty. The function rejects an empty list as well, but an apply that reaches it has already created the instance this was supposed to shut down."
  }
  validation {
    condition     = alltrue([for id in var.instance_ids : can(regex("^i-[0-9a-f]+$", id))])
    error_message = "instance_ids must contain EC2 instance IDs (e.g. i-0123456789abcdef0)."
  }
}
variable "policy_actions" {
  type        = list(string)
  default     = ["ec2:DescribeInstances", "ec2:TerminateInstances"]
  description = "EC2 actions granted to the function's role. The two EC2 calls the handler makes: DescribeInstances while it waits (for the launch time, and to stop waiting on an instance that is already gone) and TerminateInstances at the end. The S3 listing it also needs is granted separately, scoped to wait_bucket_arn. The _monolithic template granted ec2:* - main.tf records why that is narrowed (rules.md A-5)"

  validation {
    condition     = length(var.policy_actions) > 0 && alltrue([for action in var.policy_actions : can(regex("^ec2:[A-Za-z*]+$", action))])
    error_message = "policy_actions must be a non-empty list of ec2: actions."
  }
  validation {
    condition = alltrue([
      for required in ["ec2:DescribeInstances", "ec2:TerminateInstances"] :
      contains(var.policy_actions, required) || contains(var.policy_actions, "ec2:*")
    ])
    error_message = "policy_actions must include ec2:DescribeInstances and ec2:TerminateInstances, or ec2:* which subsumes both. Without DescribeInstances the wait retries AccessDenied until the function times out and the instance is never terminated; without TerminateInstances the final call raises UnauthorizedOperation."
  }
}
variable "wait_bucket_name" {
  type        = string
  description = "Bucket the function lists while it waits. It terminates the instances only once every key in wait_object_keys is there - that wait is what keeps the termination from landing in the middle of the export (rules.md B-6: injected, not discovered)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.wait_bucket_name))
    error_message = "wait_bucket_name must be a valid S3 bucket name of 3-63 characters."
  }
}
variable "wait_bucket_arn" {
  type        = string
  description = "ARN of that same bucket, for the s3:ListBucket statement. Taken alongside the name for the same reason the export module takes both: the policy needs the ARN, the API call needs the name, and deriving one from the other would mean assuming the partition"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.wait_bucket_arn))
    error_message = "wait_bucket_arn must be an S3 bucket ARN (e.g. arn:aws:s3:::my-bucket)."
  }
  validation {
    # The pair has to describe one bucket. Cross-variable, because neither value is wrong on its
    # own (rules.md B-1).
    condition     = endswith(var.wait_bucket_arn, ":${var.wait_bucket_name}")
    error_message = "wait_bucket_arn must be the ARN of wait_bucket_name. Two different buckets here means the function lists one while being authorized for the other, which retries AccessDenied until the timeout and leaves the instance running."
  }
}
variable "wait_object_keys" {
  type        = list(string)
  description = "Object keys that must all be in wait_bucket_name, written after the instances launched, before the function terminates them. The caller passes the export module's own key list rather than restating it, so the files the bootstrap writes and the files waited for cannot disagree (rules.md B-5)"

  validation {
    condition     = length(var.wait_object_keys) > 0 && alltrue([for key in var.wait_object_keys : length(key) > 0])
    error_message = "wait_object_keys must be a non-empty list of non-empty object keys. The function refuses an empty list rather than terminating without waiting."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  description = "Managed policies attached to the function's role, as the _monolithic template had them. AWSLambdaBasicExecutionRole is what lets the function create its log group and write to it; without it the function still runs and still terminates the instance, and leaves nothing behind to read when it does not"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must contain IAM policy ARNs."
  }
}
