terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# No kubernetes or kubectl provider here, unlike the other EKS projects in this
# repository. Everything this project configures inside the cluster - the
# CloudWatch agent, Fluent Bit and its eight log pipelines - is delivered by the
# amazon-cloudwatch-observability addon through its configuration_values, so the
# AWS provider is the only one needed (rules.md E-5).
