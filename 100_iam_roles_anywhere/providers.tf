terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# The archive provider builds the terminator Lambda's deployment package from the Python under
# lambda_src/. It is declared here and nowhere else: the data source lives in the root rather than
# in the module that consumes it, for two reasons that both point the same way - archive_file
# resolves its source against path.module, and a module carrying depends_on would have the read
# deferred to apply (rules.md D-6). See the comment on the data source in main.tf.
#
# No kubernetes or helm provider, and no provider aliased to another region: everything here is
# AWS API calls in one region. The one thing in this project that cannot be done through a
# provider - decrypting the exported private key - is done by the instance in
# modules/certificate_export_ec2, because openssl is not an AWS API.
