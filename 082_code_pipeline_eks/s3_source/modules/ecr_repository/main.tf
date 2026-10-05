# The registry the pipeline's image build stage pushes into. Unlike the ECR-source variant, nothing here
# watches it: the source event is an upload to S3, and this repository is downstream of it.
#
# The _monolithic template declared this as a name and nothing else. Everything below it is an addition,
# and each one is there because the repository is written to repeatedly by a pipeline rather than once by
# hand.
resource "aws_ecr_repository" "repository" {
  name = var.name
  # MUTABLE on purpose. Every pipeline run pushes the same tag over the previous image, so the tag has to be
  # movable - IMMUTABLE makes the second run fail and the demo work exactly once.
  image_tag_mutability = var.image_tag_mutability
  # True so that destroy does not stop at RepositoryNotEmptyException with the cluster already gone.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
  encryption_configuration {
    encryption_type = var.encryption_type
  }
}
# Without this the repository grows by one image per pipeline run, forever: each push over the same tag
# leaves the previous image tagged with nothing, and nothing removes it.
resource "aws_ecr_lifecycle_policy" "expire_untagged" {
  count = var.untagged_image_expiry_days == null ? 0 : 1

  repository = aws_ecr_repository.repository.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Remove untagged images, which every push over a moving tag leaves behind"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = var.untagged_image_expiry_days
      }
      action = {
        type = "expire"
      }
    }]
  })
}
