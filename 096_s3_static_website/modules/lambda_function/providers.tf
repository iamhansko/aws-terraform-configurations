terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}
# No archive provider here even though this module packages a function. The zip is built by a
# data "archive_file" in the root and passed in as filename plus source_code_hash, so that a module-level
# depends_on does not defer the read to apply (rules.md D-6) - see the note at the top of main.tf.
