# The registry that joins the three writers and one reader in this project.
#
# The bastion pushes one seed image under a fixed tag, which is the image the task definition this
# apply registers pulls. Every CodeBuild run afterwards pushes a fresh timestamped tag and registers a
# task definition revision naming it, which is what CodeDeploy then deploys. So the repository is
# written to by two different things and the tag it is read under changes on every pipeline run.
resource "aws_ecr_repository" "repository" {
  name = var.name
  # MUTABLE, which matters for the seed tag rather than the pipeline tags. A second apply re-runs the
  # bastion userdata and pushes the same fixed tag again; under IMMUTABLE that push is rejected and the
  # userdata, which deliberately does not stop on error, carries on to write its completion marker
  # anyway. The pipeline's tags are timestamps and never collide either way.
  image_tag_mutability = var.image_tag_mutability
  # force_delete, as the _monolithic template set. ECR refuses to delete a repository containing images
  # and this one is never empty by the time a destroy reaches it - the seed push happens during the
  # first apply. Without it, destroy stops here with RepositoryNotEmptyException.
  force_delete = var.force_delete
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
  encryption_configuration {
    encryption_type = var.encryption_type
  }
}
# No lifecycle policy, which is a decision rather than an omission.
#
# The usual rule to add here expires untagged images, and it would do nothing: every CodeBuild run
# pushes a new timestamp tag rather than moving an existing one, so no image in this repository ever
# becomes untagged. What does accumulate is tagged images, one per pipeline run, and expiring those by
# count would at some point expire the revision a running service is still pulling from. force_delete
# above is what keeps destroy working instead.
