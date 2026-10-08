# An On-Demand Capacity Reservation for the GPU instance the node group launches.
#
# This is the subject of the project, so it is worth saying what it does and what it costs. A reservation
# holds capacity for one instance type in one availability zone, so that a launch cannot fail with
# InsufficientInstanceCapacity - which for GPU types is a real risk rather than a theoretical one. In exchange,
# the reserved capacity is billed from the moment it exists, whether or not anything is running in it.
#
# The consequence for this project: terraform destroy removes the reservation along with everything else, but
# scaling the node group to zero does not. A reservation left in place after a demo keeps charging for a
# g4dn.xlarge that is not running, and nothing in the console flags it as idle.
resource "aws_ec2_capacity_reservation" "reservation" {
  instance_type     = var.instance_type
  instance_platform = var.instance_platform
  availability_zone = var.availability_zone
  instance_count    = var.instance_count
  tenancy           = var.tenancy
  end_date          = var.end_date
  # "targeted" so only instances that name this reservation use it. EC2's default is "open", which the
  # _monolithic template inherited - and an open reservation can be consumed by any matching instance in the
  # zone, leaving the node group with nothing to launch into.
  instance_match_criteria = var.instance_match_criteria
  # limited when an end date is set, unlimited otherwise. Derived rather than configurable because EC2 rejects
  # the mismatched combinations, and the end date is the thing the caller actually decides.
  end_date_type = var.end_date == null ? "unlimited" : "limited"

  tags = var.tags
}
