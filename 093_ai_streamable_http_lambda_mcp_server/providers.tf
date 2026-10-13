terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# random is still here, for a different reason than in the _monolithic template. There it generated a uuid to
# stand in for AWS::StackId so names could be sliced out of it; names come from project_name and name_prefix
# now. It generates the MCP auth token, which the template took as a variable defaulting to "Peccy".
