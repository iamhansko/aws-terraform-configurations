data "aws_region" "current" {}
# One repository, instantiated once per application by the root.
#
# This is the join between the two halves of the project: the workbench builds an image and pushes it here,
# and an ECS task definition pulls it from here. In the _monolithic template nothing ever pushed, because
# the build lived in cfn-init metadata that was never executed - so these three repositories were created
# empty and the three services referenced images that did not exist.
#
# The lifecycle policy and the scan setting are additions on top of the template's bare name plus
# force_delete. Both follow from the repository now being written to on every apply over one moving tag.
resource "aws_ecr_repository" "repository" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
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
