# Holds the three artifacts the workbench uploads during the same apply: the Lambda package and the GameLift
# server build (both read by Terraform-managed resources) and the client archive (read by the person playing).
# None of them is a Terraform object, which is why force_destroy is set and why the root holds the consumers on
# a function that asks S3 for the objects until they exist (modules/s3_object_waiter).
resource "aws_s3_bucket" "game_source_bucket" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy
}
