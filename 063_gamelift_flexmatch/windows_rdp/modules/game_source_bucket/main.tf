# The bucket the Windows instance fills and everything downstream reads from.
#
# Nothing Terraform creates puts an object here. The instance's userdata clones
# the sample repository and uploads three things: server.zip, which it builds
# with the SQS queue URL and the fleet role ARN baked into config.ini and which
# aws_gamelift_build reads; the whole clone, which is how Lambda/code.zip - the
# package all six game functions are created from - gets here at all; and
# client.zip, the two game clients for the participant to download. The root's
# artifact_waiter (modules/s3_object_waiter), a function that asks S3 for the
# first two until they exist, is what holds the consumers.
resource "aws_s3_bucket" "game_source" {
  bucket_prefix = var.bucket_prefix

  # Every object in this bucket was uploaded from the instance, so none of them
  # is in state and destroy would otherwise stop at BucketNotEmpty after the
  # instance that could have emptied it is already gone.
  force_destroy = var.force_destroy
}
