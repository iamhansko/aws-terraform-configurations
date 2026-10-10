output "role_arn" {
  value       = aws_iam_role.fleet.arn
  description = "ARN of the role, given to the fleet as instance_role_arn and written into the game server's config.ini as ROLE_ARN"
}
output "role_name" {
  value       = aws_iam_role.fleet.name
  description = "Generated name of the role"
}
