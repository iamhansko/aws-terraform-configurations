variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the SAM template was deployed. Bedrock offers each model in a subset of regions, so a variant that calls a model has to be deployed where that model is"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "kakao-bedrock-chat"
  description = "Prefix of every name this variant creates - the two functions, the layer, the API and the buckets. The SAM template fixed the function names (chatbot-lambda, callback-lambda), so two of these variants could not exist in one account at once"

  validation {
    # The callback function name, "<project_name>-callback", is the tightest: Lambda caps names at 64.
    condition     = can(regex("^[a-z][a-z0-9-]{1,39}$", var.project_name))
    error_message = "project_name must be 2-40 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}
variable "lambda_runtime" {
  type        = string
  default     = "python3.12"
  description = "Runtime of every function, and the one the layer is built on. python3.12, as the SAM template had it"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.lambda_runtime))
    error_message = "lambda_runtime must be a Python runtime, e.g. python3.12."
  }
}
variable "function_timeout" {
  type        = number
  default     = 480
  description = "Seconds an invocation may take, for every function - the SAM template's Globals.Function.Timeout, which the _monolithic conversion dropped and so left Lambda's default of 3 seconds"

  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 900 && floor(var.function_timeout) == var.function_timeout
    error_message = "function_timeout must be an integer between 1 and 900."
  }
}
variable "function_memory_size" {
  type        = number
  default     = 1024
  description = "Memory in MB for every function - the SAM template's Globals.Function.MemorySize, which the _monolithic conversion dropped and so left Lambda's default of 128"

  validation {
    condition     = var.function_memory_size >= 128 && var.function_memory_size <= 10240 && floor(var.function_memory_size) == var.function_memory_size
    error_message = "function_memory_size must be an integer between 128 and 10240."
  }
}
variable "layer_requirements" {
  type = list(string)
  default = [
    "requests==2.34.2",
  ]
  description = "pip requirements of the layer the callback function runs with, pinned. requests posts the answer to Kakao's callback URL; boto3 comes with the runtime. The SAM template shipped a prebuilt layer.zip instead, which is not in this repository"

  validation {
    condition     = length(var.layer_requirements) > 0 && alltrue([for requirement in var.layer_requirements : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*(\\[[A-Za-z0-9._,-]+\\])?==[0-9][A-Za-z0-9.+!-]*$", requirement))])
    error_message = "layer_requirements must be a non-empty list of exact pins, name==version."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Days every log group keeps events. The SAM template declared no log groups, so Lambda created them on first use, with no expiry, and deleting the stack left them behind"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653."
  }
}
variable "api_stage_name" {
  type        = string
  default     = "v1"
  description = "Stage the skill API is deployed to - the SAM template's StageName - and the first path segment of the skill URL"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,128}$", var.api_stage_name))
    error_message = "api_stage_name must be 1-128 characters of letters, digits and underscores."
  }
}
variable "skill_path" {
  type        = string
  default     = "kakao"
  description = "Path of the skill under the stage, as the SAM template's Skill event had it (/kakao). The skill URL entered in Kakao's chatbot admin center ends with it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.skill_path))
    error_message = "skill_path must be one path segment of letters, digits, dots, underscores and hyphens, without slashes."
  }
}
variable "bedrock_region" {
  type        = string
  default     = "us-east-1"
  description = "Bedrock Runtime source Region, independent of the Region where Lambda and API Gateway run. The account SCP denies Bedrock in ap-northeast-2 but permits it in us-east-1, so only inference traffic leaves the deployment Region"

  validation {
    condition     = var.bedrock_region == "us-east-1"
    error_message = "bedrock_region must be us-east-1 in this variant. The account SCP explicitly denies Bedrock calls in ap-northeast-2; moving only the Bedrock client avoids replacing the regional Lambda and API resources."
  }
}
variable "bedrock_model_id" {
  type        = string
  default     = "us.anthropic.claude-sonnet-4-6"
  description = "US system inference profile used by the callback function, passed as BEDROCK_MODEL_ID. The former Claude 3.5 Sonnet version has reached end of life; this profile is active in us-east-1 and accepts the same Anthropic Messages request body"

  validation {
    condition     = var.bedrock_model_id == "us.anthropic.claude-sonnet-4-6"
    error_message = "bedrock_model_id must be us.anthropic.claude-sonnet-4-6 in this variant. To use another model, verify it in bedrock_region and update the request format and least-privilege IAM resources together; otherwise Terraform can succeed while invocation fails."
  }
}
