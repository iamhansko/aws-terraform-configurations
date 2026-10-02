output "secondary_cidr_block" {
  value       = aws_vpc_ipv4_cidr_block_association.secondary_cidr_block.cidr_block
  description = "The CIDR block associated with the VPC as a secondary range. Read from the association rather than the variable so the output reflects what AWS accepted"
}
output "subnet_ids" {
  value       = [for suffix in var.availability_zone_suffixes : aws_subnet.cni_subnet[suffix].id]
  description = "IDs of the tagged subnets, in availability_zone_suffixes order (rules.md C-3)"
}
output "subnet_ids_by_availability_zone" {
  value       = { for suffix, subnet in aws_subnet.cni_subnet : subnet.availability_zone => subnet.id }
  description = "Tagged subnet ID keyed by full Availability Zone name, for callers that need to place something in the same zone as a given node"
}
output "subnet_cidr_blocks" {
  value       = { for suffix, subnet in aws_subnet.cni_subnet : suffix => subnet.cidr_block }
  description = "CIDR block of each tagged subnet, keyed by AZ letter. This is the range pod addresses move into once the nodes' own subnets are full, so it is what tells you at a glance whether discovery is in play"
}
output "discovery_tag" {
  value       = "${var.discovery_tag_key}=${var.discovery_tag_value}"
  description = "The tag the subnets carry, re-exposed from the inputs so the string the CNI has to match is visible in terraform output rather than only inside a tags block (rules.md B-5). A subnet missing this tag is simply never considered, with no error anywhere"
}
output "subnet_check_command" {
  value       = "aws ec2 describe-subnets --filters Name=vpc-id,Values=${var.vpc_id} Name=tag-key,Values=${var.discovery_tag_key} --query 'Subnets[].{Subnet:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Free:AvailableIpAddressCount}' --output table"
  description = "Lists the subnets the CNI can discover, with the free address count it ranks them by. Run it against the same filter the CNI uses rather than trusting the console's subnet list, which shows every subnet regardless of tags"
}
output "interface_check_command" {
  value       = "aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${var.vpc_id} Name=interface-type,Values=interface --query 'NetworkInterfaces[].{ENI:NetworkInterfaceId,Subnet:SubnetId,AZ:AvailabilityZone,IP:PrivateIpAddress,Desc:Description}' --output table"
  description = "Every interface in the VPC with the subnet it lives in. Discovery working looks like this: interfaces described as \"aws-K8S-...\" appearing in the tagged subnets while the nodes themselves stay in the private ones"
}
