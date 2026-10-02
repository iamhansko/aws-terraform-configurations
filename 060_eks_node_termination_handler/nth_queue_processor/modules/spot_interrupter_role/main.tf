# The IAM role the amazon-ec2-spot-interrupter CLI runs its experiments as.
#
# This project has no aws_fis_experiment_template. The interruption is sent by the CLI, which
# builds a template on the fly from a list of instance IDs, runs it and deletes it again - so
# the template is not infrastructure and the only durable piece is this role.
#
# The name is not a choice. The tool looks for a role called exactly "aws-fis-itn", and its
# getOrCreateFISRole calls CreateRole unconditionally: on EntityAlreadyExists it returns the
# ARN it assumed the role would have and moves on, attaching no policy. Two consequences:
#
#   - Pre-creating the role here means the tool never needs iam:CreateRole, and the role is in
#     state and removed on destroy rather than left behind in the account.
#   - Because the tool skips the policy when the role already exists, the permissions have to
#     be complete here. AWSFaultInjectionSimulatorEC2Access carries
#     ec2:SendSpotInstanceInterruptions, which is what the action needs.
#
# The fixed name also means two deployments of this project cannot coexist in one account, and
# that an apply after a previous run of the tool created the role fails on EntityAlreadyExists.
# Neither is avoidable while the tool decides the name; import the existing role or delete it.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
resource "aws_iam_role" "spot_interrupter_role" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["fis.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
      Condition = {
        # Confused deputy protection, which the _monolithic template's trust policy omitted -
        # and which matters more for a fixed, well-known role name than for a generated one:
        # anyone who can guess the name can name it in their own experiment template.
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:fis:*:${data.aws_caller_identity.current.account_id}:experiment/*"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "spot_interrupter_role" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.spot_interrupter_role.name
  policy_arn = each.value
}
