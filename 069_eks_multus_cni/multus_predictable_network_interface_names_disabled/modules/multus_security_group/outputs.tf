output "security_group_id" {
  value       = aws_security_group.multus_security_group.id
  description = "ID of the security group. The node bootstrap passes this to create-network-interface, so it is what every Multus ENI is attached with"
}
output "name" {
  value       = aws_security_group.multus_security_group.name
  description = "Name of the security group, re-exposed so the caller's diagnostic output reads one value (rules.md B-5)"
}
output "eni_check_command" {
  value       = "aws ec2 describe-network-interfaces --filters Name=group-id,Values=${aws_security_group.multus_security_group.id} --query 'NetworkInterfaces[].[NetworkInterfaceId,PrivateIpAddress,Description,Attachment.InstanceId]' --output table"
  description = "Every interface attached with this group. Should list exactly the Multus ENIs - one row per interface per node, each described as Multus. The node's primary interface and the ones the VPC CNI creates must not appear: if they do, the bootstrap passed the wrong group and the separation this group exists for is not there"
}
