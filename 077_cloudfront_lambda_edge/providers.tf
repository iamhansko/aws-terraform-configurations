terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
# The default provider has no alias, so nothing can silently land in a region it did not ask for
# (rules.md I-3). Everything but the Lambda@Edge functions uses it.
provider "aws" {
  region = var.aws_region
}
# us-east-1, for the Lambda@Edge functions only. CloudFront replicates Lambda@Edge from us-east-1 and accepts
# no function created anywhere else. The alias names the region, and the module that uses it says so in its
# own comment, because which provider a resource was created through does not appear in plan output.
#
# The _monolithic template had one provider. In any region but us-east-1 its functions were created where the
# rest of the stack was, and the distribution then failed to associate them at apply.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
# No random provider: it stood in for AWS::StackId to make the key pair name unique, which key_name_prefix
# does. The function names here are derived from project_name, as the _monolithic template derived them from
# its stack name.
