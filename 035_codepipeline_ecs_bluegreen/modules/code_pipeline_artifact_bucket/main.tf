# The pipeline's artifact store, which is a different bucket from the source bucket and not an
# alternative to it: the source action reads the archive out of one and writes its output artefact into
# the other, and the build action reads that artefact back and writes the appspec into it again.
#
# A module of its own rather than a resource inside the pipeline module, and the reason is a cycle. The
# CodeBuild role's S3 statement has to be scoped to this bucket, and the pipeline has to be ordered
# after the CodeBuild project because its policy names the project's ARN. If the pipeline module owned
# this bucket, CodeBuild would depend on the pipeline and the pipeline on CodeBuild. Lifting the bucket
# upstream of both breaks that, and a bucket is the natural thing to lift because it depends on nothing.
resource "aws_s3_bucket" "artifact_bucket" {
  # A generated name. The _monolithic template declared this bucket with no arguments at all, so the
  # provider generated one anyway - a prefix at least says what it is in a bucket listing.
  bucket_prefix = var.bucket_prefix
  # force_destroy, which the _monolithic template did not set, decided rather than defaulted
  # (rules.md I-4).
  #
  # Every pipeline execution writes two artefacts here under a generated key, and nothing removes them.
  # S3 refuses to delete a bucket that holds objects, so without this a destroy stops with
  # BucketNotEmpty - and it stops here rather than at the pipeline, so the pipeline is already gone and
  # the bucket that is blocking the destroy no longer has anything obviously pointing at it.
  #
  # What it discards is every past execution's artefacts, which is the record of what was deployed when.
  # For a demo that is the right trade and the root's outputs say so; for anything kept, a lifecycle
  # rule expiring old artefacts and force_destroy false is the other answer.
  force_destroy = var.force_destroy
  tags = {
    Name = var.bucket_prefix
  }
}
# No versioning here, deliberately, where the source bucket requires it. CodePipeline writes every
# artefact under its own generated key rather than overwriting one, so versions would only duplicate
# what the keys already distinguish - and every version would then also have to be deleted on destroy.
