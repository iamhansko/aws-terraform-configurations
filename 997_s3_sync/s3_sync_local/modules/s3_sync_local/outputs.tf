output "object_keys" {
  value       = [for relative_path in sort(tolist(local.selected)) : "${var.key_prefix}${relative_path}"]
  description = "Object keys the sync is expected to produce, known at plan time from the local file tree (aws s3 sync decides the actual upload/skip/delete set at apply time; this is not read back from S3)"
}

output "object_count" {
  value       = length(local.selected)
  description = "Number of local files matched for syncing"
}

output "sync_id" {
  value       = null_resource.s3_sync.id
  description = "ID of the null_resource that ran the sync, useful only for referencing this resource elsewhere (e.g. depends_on); it is not an S3 identifier"
}

output "sync_command" {
  value       = local.sync_command
  description = "The exact 'aws s3 sync' command that was run, for troubleshooting"
}
