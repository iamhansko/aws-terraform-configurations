output "role_arn" {
  value       = aws_iam_role.fleet_role.arn
  description = "ARN of the role, written into the server's config.ini as ROLE_ARN and set as the fleet's instance role"
}
output "role_name" {
  value       = aws_iam_role.fleet_role.name
  description = "Name of the role"
}
