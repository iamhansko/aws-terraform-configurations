output "instance_id" {
  value       = aws_instance.node.id
  description = "EC2 instance ID of the node"
}

output "private_ip" {
  value       = aws_instance.node.private_ip
  description = "Private address of the node"
}

output "private_dns" {
  value       = aws_instance.node.private_dns
  description = "Private DNS name of the node, which is also the name it registers with in Kubernetes"
}

output "node_role_arn" {
  value       = aws_iam_role.node.arn
  description = "ARN of the node's IAM role, mapped into system:nodes by the EC2_LINUX access entry this module creates"
}

output "node_role_name" {
  value       = aws_iam_role.node.name
  description = "Name of the node's IAM role, for a caller that has to attach another policy to it"
}

output "max_pods" {
  value       = var.max_pods
  description = "Pod ceiling written into the node's kubelet configuration, re-exposed so a verification command does not restate it (rules.md B-5)"
}

output "node_status_command" {
  value       = "kubectl get node ${aws_instance.node.private_dns} -o wide"
  description = "Command that shows whether this instance joined. A node missing here with the instance running means the kubelet was refused - the access entry or the NodeConfig is wrong, and neither produces an error on the AWS side"
}

output "node_capacity_command" {
  value       = "kubectl get node ${aws_instance.node.private_dns} -o jsonpath='{.status.allocatable.pods}' ; echo"
  description = "Command that prints the pod ceiling the node reported. It should match max_pods; a lower number means nodeadm did not read the NodeConfig part of the user data"
}

output "bootstrap_log_command" {
  value       = "aws ssm start-session --target ${aws_instance.node.id} --document-name AWS-StartInteractiveCommand --parameters command='sudo journalctl -u nodeadm-config -u nodeadm-run --no-pager | tail -50'"
  description = "Command that reads nodeadm's own log through Session Manager, which is where a rejected NodeConfig is explained. There is no other place to look: a self-managed node reports nothing to EKS"
}
