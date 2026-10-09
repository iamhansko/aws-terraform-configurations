output "vpc_id" {
  value       = aws_vpc.egress_vpc.id
  description = "ID of the egress VPC. The firewall module needs it, and the root needs it for this VPC's transit gateway attachment"
}
output "vpc_cidr_block" {
  value       = aws_vpc.egress_vpc.cidr_block
  description = "CIDR of the egress VPC, handed back out so a caller writing a rule or a route against it does not restate the literal (rules.md B-5)"
}
output "availability_zone_a" {
  value       = var.availability_zone_a
  description = "First zone, returned exactly as it was passed in. The root pairs this VPC's zone a with the spoke VPC's zone a, and re-exposing the value is what lets it compare the two rather than trust that both were given the same input (rules.md B-5)"
}
output "availability_zone_b" {
  value       = var.availability_zone_b
  description = "Second zone, returned exactly as it was passed in (rules.md B-5)"
}
output "internet_gateway_id" {
  value       = aws_internet_gateway.egress_igw.id
  description = "ID of the internet gateway, the last hop before the internet"
}
output "public_subnet_a_id" {
  value       = aws_subnet.egress_public_subnet_a.id
  description = "ID of the zone a public subnet, which holds NAT gateway a"
}
output "public_subnet_b_id" {
  value       = aws_subnet.egress_public_subnet_b.id
  description = "ID of the zone b public subnet, which holds NAT gateway b"
}
output "public_subnet_ids" {
  value       = [aws_subnet.egress_public_subnet_a.id, aws_subnet.egress_public_subnet_b.id]
  description = "Both public subnets as a list, for a caller that wants all of them rather than one zone's (rules.md C-3)"
}
output "peering_subnet_a_id" {
  value       = aws_subnet.egress_peering_subnet_a.id
  description = "ID of the zone a transit gateway attachment subnet"
}
output "peering_subnet_b_id" {
  value       = aws_subnet.egress_peering_subnet_b.id
  description = "ID of the zone b transit gateway attachment subnet"
}
output "peering_subnet_ids" {
  value       = [aws_subnet.egress_peering_subnet_a.id, aws_subnet.egress_peering_subnet_b.id]
  description = "Both attachment subnets as a list, which is the form aws_ec2_transit_gateway_vpc_attachment's subnet_ids takes - one entry per zone the attachment should be available in (rules.md C-3)"
}
output "firewall_subnet_a_id" {
  value       = aws_subnet.egress_firewall_subnet_a.id
  description = "ID of the zone a firewall subnet. The firewall module maps a primary endpoint into it, and the root's zone a attachment route table points at that endpoint"
}
output "firewall_subnet_b_id" {
  value       = aws_subnet.egress_firewall_subnet_b.id
  description = "ID of the zone b firewall subnet"
}
output "firewall_subnet_ids" {
  value       = [aws_subnet.egress_firewall_subnet_a.id, aws_subnet.egress_firewall_subnet_b.id]
  description = "Both firewall subnets as a list (rules.md C-3)"
}
output "public_route_table_id" {
  value       = aws_route_table.egress_public_rt.id
  description = "ID of the public route table, exposed so the root can add the spoke return route - <spoke CIDR> -> transit gateway - without this module learning that a transit gateway exists (rules.md C-1)"
}
output "peering_route_table_a_id" {
  value       = aws_route_table.egress_peering_subnet_a_rt.id
  description = "ID of the zone a attachment route table. The root adds its 0.0.0.0/0 route pointing at the zone a firewall endpoint; pairing it with zone b's endpoint instead is not an error, just inspected traffic that crosses a zone boundary and leaves from the wrong NAT gateway"
}
output "peering_route_table_b_id" {
  value       = aws_route_table.egress_peering_subnet_b_rt.id
  description = "ID of the zone b attachment route table"
}
output "firewall_route_table_a_id" {
  value       = aws_route_table.egress_firewall_subnet_a_rt.id
  description = "ID of the zone a firewall subnet route table, which this module has already pointed at NAT gateway a. Exposed for inspection rather than for adding routes"
}
output "firewall_route_table_b_id" {
  value       = aws_route_table.egress_firewall_subnet_b_rt.id
  description = "ID of the zone b firewall subnet route table, pointed at NAT gateway b"
}
output "nat_gateway_a_id" {
  value       = aws_nat_gateway.egress_vpc_natgw_a.id
  description = "ID of the zone a NAT gateway"
}
output "nat_gateway_b_id" {
  value       = aws_nat_gateway.egress_vpc_natgw_b.id
  description = "ID of the zone b NAT gateway"
}
output "nat_gateway_a_public_ip" {
  value       = aws_eip.egress_vpc_natgw_a_elastic_ip.public_ip
  description = "Elastic IP of the zone a NAT gateway. Everything the spoke instance sends to the internet through zone a leaves as this address, so it is the expected answer to a curl against an address-reflecting service from that instance"
}
output "nat_gateway_b_public_ip" {
  value       = aws_eip.egress_vpc_natgw_b_elastic_ip.public_ip
  description = "Elastic IP of the zone b NAT gateway"
}
output "nat_gateway_public_ips" {
  value = {
    (var.availability_zone_a) = aws_eip.egress_vpc_natgw_a_elastic_ip.public_ip
    (var.availability_zone_b) = aws_eip.egress_vpc_natgw_b_elastic_ip.public_ip
  }
  description = "Both Elastic IPs keyed by zone. Keyed rather than listed because which one a flow leaves from identifies the zone the transit gateway chose, which is the only way to see from outside that zone affinity held"
}
