# --- Build ----------------------------------------------------------------------------------------------------
#
# The role GameLift assumes to copy the build out of S3. Scoped to reading that one object: the _monolithic
# template granted s3:*Object* on the whole bucket, which includes PutObject and DeleteObject, and trusted
# cloudformation.amazonaws.com as well - a leftover from the stack, and there is no stack here.
resource "aws_iam_role" "build_role" {
  name_prefix = var.build_role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["gamelift.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "build_role" {
  name = "GameLiftBuildPolicy"
  role = aws_iam_role.build_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadServerBuild"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:GetObjectVersion"]
      Resource = ["${var.source_bucket_arn}/${var.server_build_s3_key}"]
    }]
  })
}
resource "aws_gamelift_build" "build" {
  name             = var.build_name
  operating_system = var.build_operating_system
  storage_location {
    bucket   = var.source_bucket_name
    key      = var.server_build_s3_key
    role_arn = aws_iam_role.build_role.arn
  }
  # role_arn orders this after the role, not after its policy, and GameLift reads the object as soon as the
  # build is created (rules.md D-1).
  depends_on = [aws_iam_role_policy.build_role]
}
# --- Fleet, alias, queue --------------------------------------------------------------------------------------
#
# The provider waits for the fleet to reach ACTIVE, which on Windows takes tens of minutes - downloading,
# validating, activating. A server that never calls ProcessReady sends the fleet to ERROR instead, and the
# fleet's events (describe-fleet-events in the README) say why.
#
# ON_DEMAND, where the _monolithic template had SPOT. GameLift scores each Spot instance type and location for
# viability, and one it judges non-viable it stops placing game sessions on and drains of instances - even ones
# EC2 has not reclaimed. That is a cost saving with a queue that can fall back to another fleet; this queue has
# this fleet as its only destination, so it leaves matches with nowhere to go. The SPOT c5.large fleet in
# us-east-1, 2026-10-10 (KST), from its events, the queue's metrics and the FlexMatch events game-match-event
# logged:
#
#   04:42:33  CreateFleet               the first instance is recycled at 04:45:30, before the build is unpacked
#   05:07:07  FLEET_STATE_ACTIVE        apply succeeds; the instance it activated on is recycled at 05:08:40
#   05:22:27  INSTANCE_RECYCLED         "due to high risk of EC2 Spot interruptions", and again at 05:34:56,
#                                       05:51:51 and 06:04:43 - the last 20 seconds after that instance launched
#   05:29:01  PotentialMatchCreated     placement starts with no ACTIVE instance in the fleet
#   05:36:13  PotentialMatchCreated     a second match, placed behind the first
#   05:39:17  MatchmakingTimedOut       the first: PlacementsTimedOut, the queue's 600 seconds ran out
#   05:46:29  MatchmakingSucceeded      the second, only because an instance came up at 05:41 - the one game
#                                       the fleet hosted, played to the end and reported to SQS
#
# ActiveInstances was above zero for at most 15 of the 60 minutes after ACTIVE, while the fleet stayed ACTIVE
# and nothing failed in Terraform. A Windows instance takes over ten minutes from launch to ProcessReady, so
# recycling at that rate leaves the fleet empty most of the time. The build, the role, the ports and the server
# were all fine; capacity was the only thing missing. variables.tf holds the type to ON_DEMAND (rules.md B-1).
resource "aws_gamelift_fleet" "fleet" {
  name              = var.fleet_name
  build_id          = aws_gamelift_build.build.id
  ec2_instance_type = var.ec2_instance_type
  fleet_type        = var.fleet_type
  instance_role_arn = var.fleet_role_arn
  ec2_inbound_permission {
    from_port = var.inbound_from_port
    to_port   = var.inbound_to_port
    ip_range  = var.inbound_ip_range
    protocol  = var.inbound_protocol
  }
  runtime_configuration {
    game_session_activation_timeout_seconds = var.game_session_activation_timeout_seconds
    max_concurrent_game_session_activations = var.max_concurrent_game_session_activations
    server_process {
      concurrent_executions = var.concurrent_executions
      launch_path           = var.server_launch_path
    }
  }
}
# description is required in practice, although the provider marks it optional. Create sends it only when
# set, so an alias without one is created fine; update always sends it, and UpdateAlias rejects "" with
# "Value at 'description' failed to satisfy constraint: Member must have length greater than or equal to 1".
# The first time that bites is the first fleet replacement - the one moment the alias has to move - and it
# stops the apply with the new fleet ACTIVE and the alias, so the queue, still pointing at the deleted one.
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
  timeout_in_seconds = var.queue_timeout_seconds
  destinations       = [aws_gamelift_alias.alias.arn]
}
