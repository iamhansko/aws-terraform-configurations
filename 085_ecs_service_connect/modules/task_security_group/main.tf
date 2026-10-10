# The security group on the task ENIs - the _monolithic template's ecs_service_security_group.
#
# With awsvpc networking every task has its own ENI and this group is the one on it, so this is where the
# traffic the tasks themselves make and receive is decided. The container instance group is not involved:
# image pulls and log delivery leave from the instance, everything else leaves from here.
resource "aws_security_group" "task_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.name
  }
}
# The rule the _monolithic template did not have, and the one ECS Exec cannot work without.
#
# The template declared this group with no egress, and Terraform - unlike CloudFormation - removes the
# allow-all egress rule AWS adds to a new group. An exec session is the SSM agent inside the task opening
# websocket channels to ssmmessages.<region>.amazonaws.com from the task ENI, so with no egress the task
# runs, its ExecuteCommandAgent reports RUNNING, and execute-command fails with TargetNotConnectedException.
# The same is true of the Service Connect proxy, which fetches its configuration from ECS over the task ENI,
# and of any AWS call the application makes with the task role.
#
# All outbound, as AWS would have left it. Narrowing it to 443 would hold for exec and for the proxy, but
# would also stop a task from calling another task's port, which is what the sibling projects exist to show.
resource "aws_vpc_security_group_egress_rule" "task_egress" {
  security_group_id = aws_security_group.task_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# Members of this group reaching each other's tasks on the listed ports.
#
# The _monolithic templates of 085 and 086 admitted all traffic from the group to itself; here it is the
# ports the tasks listen on, which is all that Service Connect (proxy to proxy, on the container port) and
# Cloud Map DNS (client to task address, on the container port) use. Empty creates no ingress rule, which is
# what the template of 084 had - an exec session is outbound from the task and needs no inbound rule.
#
# toset over numbers from configuration, known at plan (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "task_self_ingress" {
  for_each = toset([for port in var.self_ingress_ports : tostring(port)])

  security_group_id            = aws_security_group.task_security_group.id
  description                  = "TCP ${each.value} between tasks in this group"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.task_security_group.id
}
