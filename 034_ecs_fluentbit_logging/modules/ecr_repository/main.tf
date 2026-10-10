data "aws_region" "current" {}
# One private repository. The root instantiates this module twice - once for the application image and
# once for the Fluent Bit image - because the two repositories differ only in their name and tag, and
# nothing about either is specific to what it holds.
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
      description  = "Remove untagged images, which every re-push over the same tag leaves behind"
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
