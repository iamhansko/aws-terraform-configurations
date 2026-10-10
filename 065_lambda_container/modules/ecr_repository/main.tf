# The region the docker login and describe-images commands in outputs.tf name, and the one data source this
# module has. The caller declares this module with depends_on, which defers it to apply (rules.md D-6) -
# harmless here, because it only ever reaches a command string.
data "aws_region" "current" {}
# The registry that joins the two halves of this project: the workbench builds the function's image and pushes
# it here, and Lambda pulls it from here when the function is created.
resource "aws_ecr_repository" "repository" {
  name = var.name
  # MUTABLE, and that is load-bearing. The workbench pushes one moving tag (latest), and the rebuild command in
  # the README pushes over it. IMMUTABLE would reject the second push with ImageTagAlreadyExistsException.
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}
