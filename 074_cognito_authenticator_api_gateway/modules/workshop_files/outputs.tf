output "s3_uri" {
  value       = "s3://${aws_s3_bucket.files.id}/${var.key_prefix}"
  description = "Where the tree is staged. Whatever reads this waits for every object, through the depends_on below (rules.md B-5)"
  # A reference to every object, so whatever reads this is ordered after the uploads, not only after the bucket.
  depends_on = [aws_s3_object.file]
}
output "bucket_name" {
  value       = aws_s3_bucket.files.id
  description = "Generated name of the staging bucket"
}
output "content_hash" {
  value       = sha1(join(",", [for path in sort(tolist(local.files)) : "${path}=${filemd5("${var.source_dir}/${path}")}"]))
  description = "One hash over every staged file's path and content. An SSM association that embeds it re-runs when any file changes"
}
output "file_count" {
  value       = length(local.files)
  description = "Number of files staged"
}
