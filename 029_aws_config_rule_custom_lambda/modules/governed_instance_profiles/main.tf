# The demo's fixtures: instance profiles for the Config rule to pass judgement on.
#
# Nothing in this module is infrastructure. The Config service role, the function's execution role and
# the workbench's role all do a job; these two roles exist only to be found non-compliant, which is
# why they are a separate module from everything else and why they are data rather than code.
#
# Neither profile is attached to an instance here, and that is the shape of the demo rather than a
# missing resource. The rule is change-triggered on AWS::EC2::Instance, so what it evaluates is an
# instance that carries one of these profiles - the caller's launch_test_instance_command output is
# the step that produces one.
locals {
  # One attachment per (fixture, policy) pair, flattened into a map so each gets its own resource
  # address.
  #
  # Both halves of every key are literals in configuration - the caller's map keys and the managed
  # policy ARNs - so they are known at plan time and are legal for_each keys. The map-with-static-keys
  # requirement in rules.md B-8 is about values that arrive as another module's output, which these
  # are not; it is the same distinction that lets rules.md B-7 use toset on a policy ARN list.
  #
  # flatten rather than merge([...]...) because a fixture with no policies contributes an empty list
  # and an empty profiles map contributes nothing at all: merge with a splatted empty list fails with
  # "not enough function arguments", and no_permissions is exactly the empty case.
  policy_attachments = {
    for pair in flatten([
      for key, profile in var.profiles : [
        for policy_arn in profile.policy_arns : {
          # basename of an IAM policy ARN is the policy name, so the address reads
          # ["broad_permissions.AdministratorAccess"] rather than carrying a full ARN.
          key         = "${key}.${basename(policy_arn)}"
          profile_key = key
          policy_arn  = policy_arn
        }
      ]
    ]) : pair.key => pair
  }
}
resource "aws_iam_role" "governed_role" {
  for_each = var.profiles

  name = each.value.role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = var.assume_role_services }
      Action    = "sts:AssumeRole"
    }]
  })
  # The rule's whole subject is which policies are attached to this role, and the handler detaches
  # and reattaches them at runtime. Tagging what it started as is the only way to tell a fixture that
  # was remediated from one that was always like that - attached policies are not in this resource's
  # state, so terraform state show says nothing about them either.
  tags = {
    Name                    = each.value.role_name
    GovernanceFixture       = each.key
    InitialAttachedPolicies = length(each.value.policy_arns) == 0 ? "none" : join(",", [for arn in each.value.policy_arns : basename(arn)])
  }
}
resource "aws_iam_instance_profile" "governed_instance_profile" {
  for_each = var.profiles

  name = each.value.instance_profile_name
  # An instance profile holds at most one role, so this attribute is a single role name string - not
  # the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes. jsonencode([...]) here
  # would send the literal string ["governance-instance-profile-1"] as roleName, which IAM rejects
  # during apply while terraform validate and plan both pass, because the attribute is a string
  # either way (rules.md A-3).
  #
  # This project has three instance profiles - these two and the workbench's - which is the densest
  # concentration of that trap in the repository, and the handler reads the result: it calls
  # get_instance_profile and requires len(roles) == 1, so a profile built wrong would come back as
  # "Instance profile must have exactly one role" rather than as an IAM error.
  role = aws_iam_role.governed_role[each.key].name
}
resource "aws_iam_role_policy_attachment" "governed_role" {
  for_each = local.policy_attachments

  role       = aws_iam_role.governed_role[each.value.profile_key].name
  policy_arn = each.value.policy_arn
}
