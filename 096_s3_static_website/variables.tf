variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.), which is what the _monolithic file did. It decides where the bucket, the functions and the seeder instance live"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "project_name" {
  type        = string
  default     = "escape-room"
  description = "Base name for the bucket prefix, the two function names, the instance profile prefix and every Name tag. Stands in for the _monolithic file's stack_name variable, which existed because CloudFormation's AWS::StackName had no Terraform equivalent. One value rather than a name per resource, so a second copy of this project does not collide - and bucket names are globally unique, so this is the one that matters"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}$", var.project_name))
    error_message = "project_name must be 2-39 characters of lowercase letters, digits and hyphens, leaving room for the generated bucket suffix inside S3's 63 character limit and for the -terminate-seeder suffix inside Lambda's 64."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR of the VPC, as the _monolithic template had it. The public subnet is carved out of this as its first /24, which reproduces the template's literal 10.0.0.0/24"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block, e.g. 10.0.0.0/16."
  }
}
variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "Letter appended to the region name to pick the zone for the public subnet, reproducing the region-plus-a the _monolithic template interpolated inline"

  validation {
    condition     = can(regex("^[a-f]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single letter a-f."
  }
}
variable "website_index_document" {
  type        = string
  default     = "index.html"
  description = "Key the website endpoint serves for a request naming a directory, as the _monolithic template had it. The game zip has to contain this key - if it does not, the site answers 404 at its root and nothing in the configuration looks wrong"

  validation {
    condition     = can(regex("^[^/][^\\s]*\\.html?$", var.website_index_document))
    error_message = "website_index_document must be an .html or .htm key without a leading slash."
  }
}
variable "website_error_document" {
  type        = string
  default     = "error.html"
  description = "Key the website endpoint serves for a 4xx, as the _monolithic template had it. The current game zip does not contain an error.html, so S3 falls back to its own XML page either way - the setting is reproduced because the template had it. Null leaves it unset"

  validation {
    condition     = var.website_error_document == null || can(regex("^[^/][^\\s]*\\.html?$", var.website_error_document))
    error_message = "website_error_document must be an .html or .htm key without a leading slash, or null to leave it unset."
  }
}
variable "website_bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket first. True, because the seeder instance writes objects Terraform never recorded, so a destroy would otherwise stop at BucketNotEmpty with the rest of the root half torn down. The _monolithic template left it false and had the same problem"
}
variable "lambda_handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point for both functions, as the _monolithic template had it for both. Shared because both sources are an index.py defining lambda_handler"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./-]+\\.[a-zA-Z0-9_]+$", var.lambda_handler))
    error_message = "lambda_handler must be in <module>.<function> form, e.g. index.lambda_handler."
  }
}
variable "lambda_runtime" {
  type        = string
  default     = "python3.13"
  description = "Runtime for both functions, as the _monolithic template had it for both"

  validation {
    condition     = can(regex("^python3\\.(1[0-9]|[2-9][0-9])$", var.lambda_runtime))
    error_message = "lambda_runtime must be a supported python3.1x runtime, e.g. python3.13."
  }
}
variable "lambda_timeout" {
  type        = number
  default     = 60
  description = "Timeout for both functions, as the _monolithic template had it for both"

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 1 and 900 seconds - Lambda's own range."
  }
}
variable "lambda_memory_size" {
  type        = number
  default     = 128
  description = "Memory for both functions. 128MB is Lambda's minimum and what the _monolithic template got by not setting it"

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "lambda_memory_size must be between 128 and 10240 MB."
  }
}
variable "lambda_log_retention_days" {
  type        = number
  default     = 14
  description = "How long each function's logs are kept. The _monolithic template declared no log groups, so Lambda created them on first invocation with retention set to never expire - and terraform destroy left them behind"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.lambda_log_retention_days)
    error_message = "lambda_log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "backend_lambda_source_dir" {
  type        = string
  default     = "lambda_src/lambda_function"
  description = "Directory holding the backend function's source, relative to this root. The same path the _monolithic file pointed its archive_file at, kept so the sources stay where they are and stay readable"

  validation {
    condition     = can(regex("^[^/][^\\s]*[^/]$", var.backend_lambda_source_dir))
    error_message = "backend_lambda_source_dir must be a relative path without leading or trailing slashes, e.g. lambda_src/lambda_function."
  }
}
variable "terminate_seeder_lambda_source_dir" {
  type        = string
  default     = "lambda_src/custom_resource_lambda_function"
  description = "Directory holding the terminator function's source, relative to this root. The directory name still says custom_resource because that is what the CloudFormation template used it for; the function is no longer one, and renaming the directory would break the only link back to the original"

  validation {
    condition     = can(regex("^[^/][^\\s]*[^/]$", var.terminate_seeder_lambda_source_dir))
    error_message = "terminate_seeder_lambda_source_dir must be a relative path without leading or trailing slashes."
  }
}
variable "game_password" {
  type        = string
  default     = "988"
  sensitive   = true
  description = <<-DESC
    The escape-room answer, served by the backend function. Default as the _monolithic template had it.

    Marked sensitive, which keeps it out of plan output and the state's rendered diff - but it is not a
    secret in any real sense: the function hands it to unauthenticated callers over a public URL, and the
    hint files in the public bucket spell it out a digit at a time.

    Which is the thing to know before changing it. The hints are prose in game_hint_text_objects and they
    encode 9, then 8, then 8: the first digit from a flower colour, the second stated outright, the third
    as the number of vertices of a cube. Changing this value without rewriting those three files leaves a
    game whose hints lead to the wrong answer, and nothing anywhere reports it.
  DESC

  validation {
    condition     = length(var.game_password) > 0
    error_message = "game_password must not be empty - the backend returns it as the body of a JSON response and the page compares against it."
  }
}
variable "game_password_environment_variable" {
  type        = string
  default     = "GAME_PASSWORD"
  description = "Name of the environment variable the password reaches the backend through. The function source reads exactly this name, so the two are load-bearing together: rename one and the handler raises KeyError on every request, which the browser sees as a failed fetch (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.game_password_environment_variable))
    error_message = "game_password_environment_variable must start with a letter and contain only letters, digits and underscores."
  }
}
variable "backend_function_url_authorization_type" {
  type        = string
  default     = "NONE"
  description = "Whether callers of the backend's URL have to sign their requests. NONE, as the _monolithic template had it, and required here: the caller is a browser loading a page from an S3 website endpoint, with nothing to sign with. That makes this an unauthenticated public endpoint returning the game password"

  validation {
    # A constant condition rather than a cross-reference, because the constraint is about this variant
    # rather than about a combination: AWS_IAM here produces a site whose password check fails with 403 on
    # every request, with no error in the plan or the apply (rules.md B-1).
    condition     = var.backend_function_url_authorization_type == "NONE"
    error_message = "backend_function_url_authorization_type must be NONE in this project. The page fetches the URL from a browser with no credentials, so AWS_IAM makes every request 403 while apply still succeeds. To require signed requests, the password check has to move somewhere that can sign - a Lambda@Edge function or an API behind the site, neither of which this project has."
  }
}
variable "backend_function_url_invoke_mode" {
  type        = string
  default     = "BUFFERED"
  description = "Whether the backend's response is returned whole or streamed, as the _monolithic template had it. BUFFERED is what a handler returning a statusCode/body dict needs"

  validation {
    condition     = contains(["BUFFERED", "RESPONSE_STREAM"], var.backend_function_url_invoke_mode)
    error_message = "backend_function_url_invoke_mode must be BUFFERED or RESPONSE_STREAM. RESPONSE_STREAM expects a handler written against the streaming interface, which this one is not, and returns an empty body for one that is not."
  }
}
variable "backend_function_url_allow_origins" {
  type        = list(string)
  default     = ["*"]
  description = "Origins allowed to call the backend from a browser, as the _monolithic template had it. It has to be permissive: the page is served from an s3-website hostname and the function answers on a lambda-url hostname, so every fetch is cross-origin and the two hostnames are not known until apply. An empty list omits the CORS block, which makes the browser discard a response the function returned successfully"

  validation {
    condition     = length(var.backend_function_url_allow_origins) > 0
    error_message = "backend_function_url_allow_origins must not be empty, or the browser refuses every response from the backend even though the function returns 200."
  }
}
variable "backend_config_object_key" {
  type        = string
  default     = "data/lambda.json"
  description = "Key in the bucket holding the backend's URL, as the _monolithic template had it. The page fetches this object to learn the endpoint, so changing it here without changing the page leaves the game unable to check a password with every resource healthy"

  validation {
    condition     = can(regex("^[^/][^\\s]*\\.json$", var.backend_config_object_key))
    error_message = "backend_config_object_key must be a .json key without a leading slash, e.g. data/lambda.json."
  }
}
variable "game_source_url" {
  type        = string
  default     = "https://github.com/iamhansko/escape-room-workshop/releases/download/test/game.zip"
  description = "Zip the seeder downloads and unpacks onto the bucket, as the _monolithic template had it. This - not the src/ directory in this project - is what ends up on the site; src/ is the same content before it was released, and Terraform does not upload it"

  validation {
    condition     = can(regex("^https://.*\\.zip$", var.game_source_url))
    error_message = "game_source_url must be an https URL ending in .zip - the seeder opens the response body as a zip archive."
  }
}
variable "game_hint_text_objects" {
  type = map(string)
  default = {
    "hints/hint2.txt" = "교실에 꽃 한 송이가 숨겨져 있다.\n\n비밀번호의 1번째 자리는\n\n빨강꽃이라면 2\n파랑꽃이라면 9\n노랑꽃이라면 3\n분홍꽃이라면 4"
    "hints/hint3.txt" = "비밀번호는 총 3자리이다.\n2번째 자리는 8이다."
    "hints/hint4.txt" = "비밀번호의 마지막 자리는\n정육면체의 [꼭짓점 수]와 동일한 숫자이다."
  }
  description = "Text objects the seeder writes into the bucket, keyed by key. Carried over verbatim from the _monolithic template, where each was a separate put_object call in the generated Python. They are the clues to game_password and they encode 9, 8, 8 - see that variable before editing either side. Served as text/plain with charset=utf-8, without which a browser renders the Korean as mojibake"

  validation {
    condition     = alltrue([for key in keys(var.game_hint_text_objects) : can(regex("^[^/][^\\s]*$", key))])
    error_message = "game_hint_text_objects keys must be object keys without a leading slash or whitespace, e.g. hints/hint2.txt."
  }
}
variable "game_hint_image_objects" {
  type = map(string)
  default = {
    "hints/hint1.png" = "https://github.com/iamhansko/escape-room-workshop/raw/refs/heads/main/img/hint1.png"
  }
  description = "Objects the seeder fetches from a URL and copies into the bucket, keyed by destination key with the source URL as the value. One image, as the _monolithic template had it - pulled from a branch rather than a release, so the content can change under the site without anything here changing"

  validation {
    condition     = alltrue([for key in keys(var.game_hint_image_objects) : can(regex("^[^/][^\\s]*$", key))])
    error_message = "game_hint_image_objects keys must be object keys without a leading slash or whitespace, e.g. hints/hint1.png."
  }
  validation {
    condition     = alltrue([for url in values(var.game_hint_image_objects) : can(regex("^https://", url))])
    error_message = "game_hint_image_objects values must be https URLs the seeder can reach."
  }
}
variable "seeder_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Public SSM parameter holding the AMI id for the seeder, as the _monolithic file had it. The boot script calls dnf, so this has to resolve to an Amazon Linux 2023 image"

  validation {
    condition     = can(regex("^/aws/service/", var.seeder_ami_ssm_parameter_name))
    error_message = "seeder_ami_ssm_parameter_name must be one of the public /aws/service/ parameter paths AWS publishes AMI ids under."
  }
}
variable "seeder_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the seeder, as the _monolithic template had it. Inherited rather than chosen: the work is a zip download and a few dozen PUT calls"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.seeder_instance_type))
    error_message = "seeder_instance_type must be an EC2 instance type, e.g. t3.medium."
  }
}
variable "seeder_associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the seeder gets a public address, as the _monolithic template had it. It has to reach github.com and the S3 API through the internet gateway; false leaves the bucket empty and the apply still successful"
}
variable "seeder_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the seeder on SSH. Empty, which matches what the _monolithic template effectively had - it created no key pair, so there is nothing to authenticate with. Session Manager is the route in that works without opening a port, which is why AmazonSSMManagedInstanceCore is in seeder_iam_policy_arns"

  validation {
    condition     = alltrue([for cidr in var.seeder_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "seeder_ingress_cidr_blocks must contain valid IPv4 CIDR blocks, e.g. 203.0.113.4/32."
  }
}
variable "seeder_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  description = "Managed policies on the seeder's role, on top of the s3:PutObject statement its module writes. The _monolithic template attached AdministratorAccess instead; narrowing an automated role is allowed and has to be recorded, which the module's policy resource does (rules.md A-5). AmazonSSMManagedInstanceCore is added rather than inherited - it is what makes Session Manager work on a host with no key pair, which AdministratorAccess covered by accident"

  validation {
    condition     = alltrue([for arn in var.seeder_iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/", arn))])
    error_message = "seeder_iam_policy_arns must contain IAM policy ARNs, e.g. arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore."
  }
}
variable "seeder_python_package" {
  type        = string
  default     = "python3.13"
  description = "Python the seeder installs and symlinks to /usr/bin/python, as the _monolithic template had it. A package name Amazon Linux 2023 does not carry leaves every later line failing on a missing interpreter, visible only in the console log"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.seeder_python_package))
    error_message = "seeder_python_package must be a python3.x package name, e.g. python3.13."
  }
}
variable "seeder_python_requirements" {
  type        = list(string)
  default     = ["requests", "boto3"]
  description = "Packages pip installs on the seeder before the upload script runs, as the _monolithic template had it. Unpinned, as the original was: the script runs once on a fresh instance, so a pin would only document which versions it was last known to work with"

  validation {
    condition     = length(var.seeder_python_requirements) > 0
    error_message = "seeder_python_requirements must not be empty - the upload script imports boto3 and requests."
  }
}
variable "seeder_dnf_packages" {
  type        = list(string)
  default     = ["git"]
  description = "Packages the seeder installs before Python, as the _monolithic template had it. git is inherited and unused by the upload script; it is kept because the template installed it"

  validation {
    condition     = alltrue([for package in var.seeder_dnf_packages : can(regex("^[A-Za-z0-9._+-]+$", package))])
    error_message = "seeder_dnf_packages entries must be package names without spaces."
  }
}
variable "seeder_dnf_groups" {
  type        = list(string)
  default     = ["Development Tools"]
  description = "Package groups the seeder installs, as the _monolithic template had it. Nothing needs a compiler - requests and boto3 ship as wheels - so this is several minutes of boot time inherited from the original. The default keeps the original behaviour; [] drops it"

  validation {
    condition     = alltrue([for group in var.seeder_dnf_groups : length(group) > 0])
    error_message = "seeder_dnf_groups entries must not be empty."
  }
}
variable "seeder_content_types" {
  type = map(string)
  default = {
    html = "text/html"
    css  = "text/css"
    js   = "text/javascript"
    txt  = "text/plain"
    sh   = "text/x-sh"
    png  = "image/png"
    jpg  = "image/jpeg"
    webp = "image/webp"
    svg  = "image/svg+xml"
    gif  = "image/gif"
    json = "application/json"
  }
  description = "Content type per file extension for everything the seeder uploads, carried over from the _monolithic template's TYPE_MAP unchanged. S3 stores an object with no content type as application/octet-stream and a browser downloads that instead of rendering it, so this is what makes the site a site rather than a set of downloads"

  validation {
    condition     = length(var.seeder_content_types) > 0
    error_message = "seeder_content_types must not be empty, or every uploaded object falls back to seeder_default_content_type."
  }
}
variable "seeder_default_content_type" {
  type        = string
  default     = "application/octet-stream"
  description = "Content type for an uploaded file whose extension is not in the map. The _monolithic template had no fallback: it indexed TYPE_MAP directly, so one unexpected extension in the zip raised a KeyError which its blanket except swallowed, leaving a partly uploaded site and an exit code of 0. octet-stream rather than text/plain because an unknown extension in a game bundle is more likely a binary asset than text"

  validation {
    condition     = can(regex("^[a-z]+/[a-zA-Z0-9.+-]+$", var.seeder_default_content_type))
    error_message = "seeder_default_content_type must be a media type, e.g. application/octet-stream."
  }
}
variable "terminate_seeder_after_seeding" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether apply invokes the terminator function, which is what the _monolithic template's custom
    resource did.

    False, and this is the project's one deliberate behavioural divergence. Two reasons, set out in full
    above the aws_lambda_invocation resource in main.tf: the converted invocation could not have worked at
    all (it spoke the custom resource protocol to a resource that does a plain synchronous invoke), and
    terminating a managed aws_instance makes this root churn forever - the provider drops a terminated
    instance from state, so the next plan recreates it, which re-invokes this and terminates it again.

    There is a third, smaller reason to leave it off: Terraform can see that the instance exists but not
    that it has finished uploading, so the invoke lands minutes before the seed completes and leaves a
    half-filled bucket.

    Use the root's terminate_seeder_command instead once the bucket looks right.
  DESC
}
