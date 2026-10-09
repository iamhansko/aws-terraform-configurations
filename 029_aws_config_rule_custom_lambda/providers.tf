terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# The archive provider builds the rule's Lambda deployment package from lambda_src/. It is declared
# here and nowhere else, because the data source that uses it has to live in this root rather than in
# modules/config_rule_lambda - archive_file resolves source_file against path.module, and that module
# carries depends_on, which would defer the read to apply (rules.md D-6). The data source in main.tf
# carries the full reasoning.
#
# The tls provider generates the EC2 key pair's private key, in modules/key_pair.
#
# No random provider, unlike the _monolithic template. That template declared random_uuid to stand in
# for AWS::StackId and used it for exactly one thing: slicing a segment out of the fake stack ARN to
# build a unique key pair name. Nothing here needs a unique name, and the reason is worth stating
# because it reads like a regression otherwise - AWS Config allows one customer managed configuration
# recorder per account per region, so this project cannot be deployed twice in one region whatever its
# resources are called. Fixed names are therefore free here, and they make the demo's fixtures
# findable by name from the workbench (see config_recorder_name in variables.tf).
#
# No kubernetes or helm provider: there is no EKS cluster in this root, which is also why the
# workbench installs code-server and nothing else (rules.md H-1 applies its five-tool rule only to a
# root that declares an EKS cluster).
