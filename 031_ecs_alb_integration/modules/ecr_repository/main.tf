# The region the docker login and describe-images commands in outputs.tf name, and the one data source this
# module has.
#
# The caller declares this module with depends_on, which defers it to apply (rules.md D-6). Harmless here:
# it only ever reaches a command string, and the repository URL those commands are built around is an
# apply-time value anyway.
data "aws_region" "current" {}
# The registry that joins the two halves of this project: the workbench builds the Flask image and pushes it
# here, and the Fargate task definition pulls it from here.
resource "aws_ecr_repository" "repository" {
  name = var.name
  # MUTABLE, and that is load-bearing rather than a default taken on trust. Both halves of this project name
  # one moving tag (latest), so a second apply or a rebuild by hand pushes over it. IMMUTABLE would reject
  # that push with ImageTagAlreadyExistsException, and the workbench bootstrap does not stop on error - so
  # the push would fail, the marker would still be written, and the service would keep running the image
  # from the first apply with nothing saying so.
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}
