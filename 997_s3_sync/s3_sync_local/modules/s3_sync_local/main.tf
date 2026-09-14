locals {
  # ** is required: a single * only matches entries at the top level of
  # source_dir, so a tree like src/1/1-1.txt would produce an empty set. This
  # fileset is used only to build the change-detection hash below - the
  # actual upload/skip/delete decision for each file is made by
  # 'aws s3 sync' itself at apply time, not by Terraform.
  matched  = fileset(var.source_dir, var.file_pattern)
  excluded = toset(flatten([for pattern in var.exclude_patterns : tolist(fileset(var.source_dir, pattern))]))
  selected = setsubtract(local.matched, local.excluded)

  # Re-invocation trigger: hashing the selected files' contents directly
  # catches a file whose bytes changed but whose name/count didn't, which a
  # count of files or a directory mtime would miss.
  content_hash = sha256(join("", [for relative_path in sort(tolist(local.selected)) : filemd5("${var.source_dir}/${relative_path}")]))

  delete_arg   = var.delete_removed ? "--delete" : ""
  exclude_args = join(" ", [for pattern in var.exclude_patterns : "--exclude ${pattern}"])
  region_arg   = var.aws_region != null ? "--region ${var.aws_region}" : ""

  # No quotes around the path/URI arguments. local-exec runs through
  # /bin/sh on Linux/macOS but cmd.exe on Windows by default, and cmd.exe's
  # own quote-stripping when it builds the child process command line
  # re-escapes any double quotes already in the string, so aws.exe receives
  # literal backslash-quote characters glued onto the s3:// argument
  # instead of a clean value (reproduced directly: quoting this command
  # makes the AWS CLI fail with "Error: Invalid argument type" on Windows,
  # while the unquoted form parses correctly on both Windows and Linux/
  # macOS). Since S3 bucket names and key prefixes cannot contain spaces,
  # quoting was never required for those two arguments; source_dir is the
  # one value here that could contain a space, so paths with spaces are not
  # supported (see the source_dir variable description).
  sync_command = trimspace("aws s3 sync ${var.source_dir} s3://${var.bucket}/${var.key_prefix} ${local.delete_arg} ${local.exclude_args} ${local.region_arg}")

  # The destroy-time command is resolved to its final form here rather than
  # branching at shell runtime (e.g. a bash `if`), because that branching
  # syntax isn't portable between /bin/sh and cmd.exe either. `echo` with no
  # further arguments is a harmless no-op on both.
  cleanup_command = trimspace("aws s3 rm s3://${var.bucket}/${var.key_prefix} --recursive ${local.region_arg}")
  destroy_command = var.delete_on_destroy ? local.cleanup_command : "echo skipping cleanup, delete_on_destroy is false"
}

# Runs the sync via the AWS CLI on the machine executing `terraform apply`,
# instead of packaging a Lambda function (modules/lambda_s3_sync in the
# sibling s3_sync_lambda project) to do the same work inside AWS. This
# requires the AWS CLI to be installed and credentialed on whichever machine
# runs Terraform - the Lambda variant has no such local dependency, since the
# function carries its own IAM role.
resource "null_resource" "s3_sync" {
  # Every value the provisioners need is copied into triggers rather than
  # read from var.*/local.* directly in the destroy-time provisioner below,
  # because destroy-time provisioners can only reliably reference the
  # resource's own attributes (via self) - the module's input variables may
  # belong to other resources being destroyed in the same operation.
  triggers = {
    sync_command    = local.sync_command
    destroy_command = local.destroy_command
    content_hash    = local.content_hash
  }

  provisioner "local-exec" {
    command = self.triggers.sync_command
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers.destroy_command
  }
}
