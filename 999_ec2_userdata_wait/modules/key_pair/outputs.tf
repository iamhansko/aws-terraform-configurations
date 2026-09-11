output "key_name" {
  value       = aws_key_pair.key_pair.key_name
  description = "Name of the created EC2 key pair"
}

output "key_pair_id" {
  value       = aws_key_pair.key_pair.key_pair_id
  description = "ID of the created EC2 key pair"
}
