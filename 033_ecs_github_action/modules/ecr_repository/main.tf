data "aws_region" "current" {}
# The registry three things in this project meet at: the workbench pushes the first image here so the ECS
# service has something to pull, the GitHub Actions workflow pushes every later image here, and the task
# definition pulls from here.
#
# The _monolithic template declared a name and nothing else. The three settings below are additions, and
# force_delete is the one that matters: the workflow pushes a commit-sha tag on every run, so the
# repository is never empty by the time anyone runs terraform destroy, and ECR refuses to delete a
# repository that still holds images.
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
# Every push over the moving "latest" tag leaves the previous image untagged with nothing referencing it.
# The workflow pushes that tag on every run, so without this the repository grows for the life of the demo.
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
