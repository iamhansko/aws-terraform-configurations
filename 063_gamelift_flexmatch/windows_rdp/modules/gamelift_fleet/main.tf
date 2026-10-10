# The game server side: the build GameLift copies out of S3, the fleet that runs
# it, the alias that names the fleet, and the queue that places game sessions on
# the alias. FlexMatch sits in front of the queue (modules/gamelift_matchmaking).
#
# The caller has to hold the build until server.zip is in the bucket. The
# instance builds and uploads it during the same apply, and CreateBuild copies
# the object at the moment it is called: a missing key fails the build, and
# nothing in this module can see the upload happen. The root does it through
# build_bucket_name, which the build alone reads, so the build role's grant
# below is not held back with it.

# The role GameLift assumes to copy server.zip out of the bucket.
#
# Trusted by gamelift.amazonaws.com only. The _monolithic template trusted
# cloudformation.amazonaws.com as well, a leftover of the CloudFormation stack
# that created the build; there is no stack here.
resource "aws_iam_role" "build" {
  name_prefix = var.build_role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "gamelift.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# Read on the one object, in place of the template's s3:GetObject,
# s3:GetObjectVersion and s3:*Object* on everything in the bucket - the last of
# which also granted PutObject and DeleteObject. GameLift only reads the build.
resource "aws_iam_role_policy" "build" {
  name = "GameLiftBuildPolicy"
  role = aws_iam_role.build.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:GetObjectVersion"]
      Resource = "${var.build_bucket_arn}/${var.build_object_key}"
    }]
  })
}
resource "aws_gamelift_build" "build" {
  name             = var.build_name
  operating_system = var.operating_system
  storage_location {
    bucket   = var.build_bucket_name
    key      = var.build_object_key
    role_arn = aws_iam_role.build.arn
  }

  # GameLift assumes the role and reads the object inside CreateBuild, so the
  # read grant has to exist first; the role_arn reference orders this after the
  # role only (rules.md D-1).
  depends_on = [aws_iam_role_policy.build]
}
# ON_DEMAND, where the _monolithic template had SPOT. GameLift scores each Spot
# instance type and location for viability, and one it judges non-viable it
# stops placing game sessions on and drains of instances - even ones EC2 has
# not reclaimed. That is a cost saving with a queue that can fall back to
# another fleet; the queue below has this fleet as its only destination, so it
# leaves matches with nowhere to go.
#
# Not observed in this variant, which had not been applied: the template
# variant's SPOT c5.large fleet in us-east-1 met it on 2026-10-10. Seven
# INSTANCE_RECYCLED events ("due to high risk of EC2 Spot interruptions") in
# about 80 minutes, one 20 seconds after its instance launched; an ACTIVE
# instance for at most 15 of the 60 minutes after the fleet went ACTIVE; and a
# match that timed out in the queue (PlacementsTimedOut, then
# MatchmakingTimedOut) while the fleet itself stayed ACTIVE and nothing failed
# in Terraform. A Windows instance takes over ten minutes to reach
# ProcessReady, so recycling at that rate leaves the fleet empty most of the
# time. variables.tf holds the type to ON_DEMAND (rules.md B-1).
resource "aws_gamelift_fleet" "fleet" {
  name              = var.fleet_name
  build_id          = aws_gamelift_build.build.id
  ec2_instance_type = var.ec2_instance_type
  fleet_type        = var.fleet_type
  instance_role_arn = var.instance_role_arn

  dynamic "ec2_inbound_permission" {
    for_each = var.ec2_inbound_permissions
    content {
      from_port = ec2_inbound_permission.value.from_port
      to_port   = ec2_inbound_permission.value.to_port
      ip_range  = ec2_inbound_permission.value.ip_range
      protocol  = ec2_inbound_permission.value.protocol
    }
  }
  runtime_configuration {
    game_session_activation_timeout_seconds = var.game_session_activation_timeout_seconds
    max_concurrent_game_session_activations = var.max_concurrent_game_session_activations
    server_process {
      concurrent_executions = var.server_process_concurrent_executions
      launch_path           = var.server_launch_path
    }
  }
}
# description is required in practice, although the provider marks it
# optional. Create sends it only when set, so an alias without one is created
# fine; update always sends it, and UpdateAlias rejects "" with "Value at
# 'description' failed to satisfy constraint: Member must have length greater
# than or equal to 1". The first time that bites is the first fleet
# replacement - the one moment the alias has to move - and it stops the apply
# with the new fleet ACTIVE and the alias, so the queue, still pointing at the
# deleted one. The template variant met exactly that.
resource "aws_gamelift_alias" "alias" {
  name        = var.alias_name
  description = var.alias_description
  routing_strategy {
    type     = "SIMPLE"
    fleet_id = aws_gamelift_fleet.fleet.id
  }
}
resource "aws_gamelift_game_session_queue" "queue" {
  name               = var.queue_name
  timeout_in_seconds = var.queue_timeout_in_seconds
  destinations       = [aws_gamelift_alias.alias.arn]
}
