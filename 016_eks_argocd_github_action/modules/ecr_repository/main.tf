# The registry the GitHub Actions workflow pushes to and Argo CD's manifests pull
# from. Its own module because nothing else in the pipeline needs to know how it is
# configured - the runner is handed a URL and the manifest a tag.
resource "aws_ecr_repository" "ecr" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability
  # Not in the _monolithic template, which left the repository at defaults. A demo
  # that pushes a handful of tags does not need this, but the alternative is a
  # terraform destroy that fails on a non-empty repository and has to be finished by
  # hand.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = {
    Name = var.name
  }
}
# Keeps the demo from accumulating images indefinitely. The workflow pushes a new tag
# on every commit to index.html, so without this the repository grows for as long as
# the stack is up.
resource "aws_ecr_lifecycle_policy" "ecr" {
  count      = var.max_image_count == null ? 0 : 1
  repository = aws_ecr_repository.ecr.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the most recent ${var.max_image_count} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.max_image_count
      }
      action = { type = "expire" }
    }]
  })
}
