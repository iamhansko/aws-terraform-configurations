# The registry the operator image is built into.
#
# Terraform owns the repository; the image inside it is built and pushed by a step on the
# bastion, because building a container image needs a Docker daemon and the source it
# builds does not exist until operator-sdk has scaffolded it. That split is why
# force_delete matters (see the variable): nothing about the image is in state, so
# Terraform cannot clean it up before deleting the repository.
resource "aws_ecr_repository" "operator_ecr" {
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
