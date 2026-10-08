output "id" {
  value       = aws_ec2_capacity_reservation.reservation.id
  description = "ID of the reservation, which the node group's launch template names as its capacity_reservation_target (rules.md B-5)"
}
output "arn" {
  value       = aws_ec2_capacity_reservation.reservation.arn
  description = "ARN of the reservation"
}
output "instance_type" {
  value       = aws_ec2_capacity_reservation.reservation.instance_type
  description = "The reserved type, re-exposed so the launch template reads it from here rather than restating it - a launch template asking for a different type cannot use the reservation, and with capacity-reservations-only it cannot launch at all (rules.md B-5)"
}
output "availability_zone" {
  value       = aws_ec2_capacity_reservation.reservation.availability_zone
  description = "The reserved zone, re-exposed so the node group's subnet can be chosen to match it. A reservation is zonal, and a node group pointed at another zone's subnet leaves it unused"
}
output "instance_count" {
  value       = aws_ec2_capacity_reservation.reservation.instance_count
  description = "How many instances are reserved. This is the hard ceiling on the node group's size with capacity-reservations-only, re-exposed because a node group asking for more simply fails to launch the excess (rules.md B-5)"
}
output "is_open_ended" {
  value       = var.end_date == null
  description = "Whether the reservation runs until deleted. True is the billing risk: reserved capacity is charged whether or not an instance occupies it, so an open-ended reservation left after a demo keeps paying for a GPU that is not running"
}
output "usage_command" {
  value       = "aws ec2 describe-capacity-reservations --capacity-reservation-ids ${aws_ec2_capacity_reservation.reservation.id} --query 'CapacityReservations[].[State,InstanceType,AvailabilityZone,TotalInstanceCount,AvailableInstanceCount,InstanceMatchCriteria,EndDateType]' --output table"
  description = "The reservation and how much of it is used. AvailableInstanceCount equal to TotalInstanceCount means nothing is occupying it - which after the node group is up means the instances launched outside the reservation, and the target in the launch template is wrong"
}
output "billing_note" {
  value       = "Reserved capacity for ${aws_ec2_capacity_reservation.reservation.instance_count} x ${aws_ec2_capacity_reservation.reservation.instance_type} in ${aws_ec2_capacity_reservation.reservation.availability_zone} is billed from creation until the reservation is deleted, whether or not an instance is running in it. Scaling the node group to zero does not stop it"
  description = "What this costs while idle, stated because it is the one thing about this project that is easy to leave running by accident"
}
