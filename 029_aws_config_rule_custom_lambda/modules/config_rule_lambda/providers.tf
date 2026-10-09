terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}
# No archive provider here, although this module creates the function. The deployment package is
# built by the caller and arrives as filename plus source_code_hash: archive_file resolves its source
# against path.module and the Python lives at the project root, and this module carries depends_on,
# which would defer the read to apply and make source_code_hash unknown at plan (rules.md D-6). The
# caller's main.tf has the detail.
