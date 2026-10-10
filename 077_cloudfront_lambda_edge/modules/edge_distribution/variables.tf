variable "bucket_prefix" {
  type        = string
  default     = "lambda-edge-origin-"
  description = "Prefix for the generated S3 origin bucket name. The _monolithic template let Terraform generate one"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, periods and hyphens, starting with a letter or digit."
  }
}
variable "comment" {
  type        = string
  default     = null
  description = "Comment shown with the distribution in the console"
}
variable "default_root_object" {
  type        = string
  default     = "index.html"
  description = "Object served for a request to /, as the _monolithic template had it, and the key the page is uploaded under"

  validation {
    condition     = length(var.default_root_object) > 0 && !startswith(var.default_root_object, "/")
    error_message = "default_root_object must not be empty and must not start with a slash."
  }
}
variable "index_html" {
  type        = string
  default     = "<h2>Hello World</h2>\n"
  description = "Content of the default root object, as the _monolithic template's userdata wrote it"
}
variable "price_class" {
  type        = string
  default     = "PriceClass_All"
  description = "Edge locations the distribution uses. All, which is what the _monolithic template got by not setting it"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}
variable "ec2_origin_domain_name" {
  type        = string
  description = "Public DNS name of the instance behind the EC2 origin. A DNS name rather than an IP, because CloudFront custom origins take names only"

  validation {
    condition     = length(var.ec2_origin_domain_name) > 0 && !can(regex("^[0-9.]+$", var.ec2_origin_domain_name))
    error_message = "ec2_origin_domain_name must be a DNS name, not an IP address - CloudFront rejects an IP as an origin."
  }
}
variable "ec2_origin_http_port" {
  type        = number
  description = "Port the instance answers HTTP on. Taken from the instance module, so the origin and the security group name the same port (rules.md B-5)"

  validation {
    # CloudFront accepts 80, 443 and 1024-65535 for a custom origin's HTTP port.
    condition     = var.ec2_origin_http_port == 80 || var.ec2_origin_http_port == 443 || (var.ec2_origin_http_port >= 1024 && var.ec2_origin_http_port <= 65535)
    error_message = "ec2_origin_http_port must be 80, 443 or between 1024 and 65535 - the ports CloudFront accepts for a custom origin."
  }
}
variable "ec2_path_prefix" {
  type        = string
  description = "Path routed to the EC2 origin, e.g. /code. Taken from the instance module, so the behaviours name the path nginx proxies (rules.md B-5)"

  validation {
    condition     = can(regex("^/[a-z0-9-]+$", var.ec2_path_prefix))
    error_message = "ec2_path_prefix must be a single path segment such as /code."
  }
}
variable "s3_origin_lambda_arn" {
  type        = string
  description = "Qualified ARN of the Lambda@Edge function version run on viewer requests for the S3 origin (the default behaviour)"

  validation {
    # The two mistakes CloudFront rejects only at apply, after the distribution has started to create: a
    # function outside us-east-1, and an unqualified ARN or $LATEST instead of a published version.
    condition     = can(regex("^arn:aws:lambda:us-east-1:[0-9]{12}:function:[a-zA-Z0-9_-]+:[0-9]+$", var.s3_origin_lambda_arn))
    error_message = "s3_origin_lambda_arn must be the qualified ARN of a published version of a function in us-east-1 (arn:aws:lambda:us-east-1:<account>:function:<name>:<version>)."
  }
}
variable "ec2_origin_lambda_arn" {
  type        = string
  description = "Qualified ARN of the Lambda@Edge function version run on viewer requests for the EC2 origin behaviours"

  validation {
    condition     = can(regex("^arn:aws:lambda:us-east-1:[0-9]{12}:function:[a-zA-Z0-9_-]+:[0-9]+$", var.ec2_origin_lambda_arn))
    error_message = "ec2_origin_lambda_arn must be the qualified ARN of a published version of a function in us-east-1 (arn:aws:lambda:us-east-1:<account>:function:<name>:<version>)."
  }
}
variable "cache_policy_id" {
  type        = string
  default     = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  description = "Cache policy on every behaviour. The AWS managed Managed-CachingDisabled, as the _monolithic template had it - the point is to watch the Lambda@Edge function run on every request, not to cache"

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.cache_policy_id))
    error_message = "cache_policy_id must be a cache policy ID (a UUID)."
  }
}
variable "origin_request_policy_id" {
  type        = string
  default     = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  description = "Origin request policy on the EC2 origin behaviours. The AWS managed Managed-AllViewer, as the _monolithic template had it - code-server's websocket handshake needs the viewer's headers, cookies and query strings"

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.origin_request_policy_id))
    error_message = "origin_request_policy_id must be an origin request policy ID (a UUID)."
  }
}
