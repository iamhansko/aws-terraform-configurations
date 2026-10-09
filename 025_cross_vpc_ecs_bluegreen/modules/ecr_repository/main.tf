# One ECR repository, instantiated once per application stack.
#
# A module of its own rather than a resource inside modules/app_stack, and the reason is an
# ordering cycle rather than cohesion. The repository has to exist before the workbench can build
# and push into it, and the task definition has to exist after that push - otherwise the service
# starts and its tasks stop with CannotPullContainerError against a tag that is not there yet. The
# push is an SSM association in the root, so the sequence is
#
#   ecr_repository -> image build association -> app_stack (task definition, service, pipeline)
#
# and the association sits between the two. With the repository inside app_stack, that association
# would have to both depend on app_stack and be depended on by it.
resource "aws_ecr_repository" "ecr_repository" {
  name = var.name
  # IMMUTABLE, as the _monolithic template had it, and it changes how the image build step has to
  # be written: pushing a tag that already exists is rejected with ImageTagAlreadyExistsException,
  # so that step checks for the tag first rather than pushing unconditionally. An SSM association
  # re-runs whenever its parameters change, so "unconditionally" would mean a failed association
  # on the second apply.
  image_tag_mutability = var.image_tag_mutability
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
  encryption_configuration {
    # AES256 or KMS. This is one of the few things the two stacks in this project genuinely differ
    # by: the _monolithic template left the green repository on AES256 and put the red one on the
    # project key. kms_key is only meaningful in the second case, and passing one with AES256 is
    # rejected at apply with InvalidParameterException.
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }
  # force_delete, which the _monolithic template did not set.
  #
  # The provider defaults it to false, and ECR refuses to delete a repository that still holds
  # images - so terraform destroy stops with RepositoryNotEmptyException on both repositories,
  # each holding the two tags the build step pushed. The destroy then has to be re-run after
  # emptying them by hand. Never true for a repository holding anything worth keeping.
  force_delete = var.force_delete
  tags = {
    Name = var.name
  }
}
