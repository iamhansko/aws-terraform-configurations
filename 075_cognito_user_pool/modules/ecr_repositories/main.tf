data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
# The repositories the workbench pushes the two service images into. for_each over literal keys, so each
# repository's address is known at plan (rules.md B-8).
resource "aws_ecr_repository" "repository" {
  for_each = var.repositories
  name     = each.value
  # As the _monolithic template had it: terraform destroy deletes the images with the repository. They are
  # built from a public git ref and can be rebuilt.
  force_delete = true
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}
