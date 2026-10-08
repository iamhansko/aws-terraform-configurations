data "aws_region" "current" {}
# The registry that joins the two halves of this project: the image builder instance pushes an arm64
# image here, and the ECS task definition pulls it from here.
#
# The _monolithic template declared this as force_delete and a name, nothing else. The lifecycle policy
# and the scan setting below are additions - both follow from the repository being written to on every
# apply over one moving tag rather than once by hand.
resource "aws_ecr_repository" "repository" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
  encryption_configuration {
    encryption_type = var.encryption_type
  }
}
resource "aws_ecr_lifecycle_policy" "expire_untagged" {
  count      = var.untagged_image_expiry_days == null ? 0 : 1
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
