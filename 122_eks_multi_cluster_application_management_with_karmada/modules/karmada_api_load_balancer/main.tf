# The Network Load Balancer in front of the Karmada API server.
#
# The guidance installer got the same load balancer a different way: it applied a Service named
# karmada-service-loadbalancer into karmada-system, of type LoadBalancer, with selector app=karmada-apiserver
# and port 32443 forwarding to 5443, annotated service.beta.kubernetes.io/aws-load-balancer-type: nlb. An
# in-cluster controller then created the load balancer, and the script read its DNS name back out with
# kubectl and polled elbv2 describe-load-balancers until the state went active.
#
# That shape cannot work here, and the reason is not stylistic. Three things in this configuration need the
# API server's address as a value:
#
#   the karmada certificate needs it as a SAN (modules/karmada_certificates);
#   each member cluster's agent needs it in the kubeconfig in its Helm values (modules/karmada_member_agent);
#   the kubectl provider aimed at the Karmada API server needs it as its host, which is what makes the
#   PropagationPolicy and the demo Deployment Terraform resources at all.
#
# A load balancer created by a controller in response to a Service is not a Terraform resource, so its DNS
# name is not in state and cannot be any of those (rules.md G-1 says the same thing about the addresses the
# AWS Load Balancer Controller produces). Terraform therefore creates the load balancer and the chart
# publishes the API server on a NodePort behind it.
#
# This is not the adoption pattern of rules.md G-3 either. Nothing adopts this load balancer: there is no
# AWS Load Balancer Controller on the parent cluster, no Service of type LoadBalancer, and so none of the
# three tags G-3 is about. The whole object - listener, target group and target registration - belongs to
# Terraform, which is why its DNS name can be an output and why `terraform destroy` removes it.
locals {
  # The listener port and the Service's nodePort are deliberately the same number, so that the port in the
  # endpoint below is the port a reader will find on the nodes. They are independent settings - the listener
  # could forward 443 to 32443 - but keeping them equal removes a mapping nobody needs to hold in their head.
  #
  # 32443 is the port the guidance installer's Service published, kept so the endpoint reads the same.
  endpoint = "https://${aws_lb.karmada_api.dns_name}:${var.port}"
}
resource "aws_lb" "karmada_api" {
  name        = var.name
  name_prefix = var.name == null ? var.name_prefix : null
  # Network, not application. The Karmada API server speaks TLS with client certificates, and terminating
  # that at an ALB would break the only authentication it has - the apiserver has to see the client
  # certificate itself. A TCP listener passes the whole TLS session through untouched.
  load_balancer_type = "network"
  internal           = var.internal
  subnets            = var.subnet_ids
  # On, and it matters here. The targets are the parent cluster's worker nodes, which sit in the private
  # subnets, while the load balancer's own nodes sit in the public ones. With cross-zone off, a load balancer
  # node in a zone that happens to hold no worker node has nothing to forward to and is withdrawn from DNS -
  # so whether the endpoint resolves at all depends on how the node group's instances were spread. The cost
  # is cross-zone data transfer on the control plane's traffic, which is small.
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.enable_deletion_protection
  tags = {
    Name = var.tag_name
  }
}
resource "aws_lb_target_group" "karmada_api" {
  name        = var.name
  name_prefix = var.name == null ? var.name_prefix : null
  vpc_id      = var.vpc_id
  port        = var.port
  protocol    = "TCP"
  # instance, not ip. ip targets would be the Karmada apiserver pods, and nothing here knows their addresses
  # or notices when they change - that bookkeeping is what a controller is for. Registering the nodes
  # instead works because kube-proxy opens the Service's nodePort on every node in the cluster and routes
  # from there to whichever pod is ready, so the set of targets is stable even while the pods are not.
  target_type = "instance"
  # false, so the nodes see the load balancer's own private addresses as the source rather than the original
  # client's. Two reasons: the security group rule below can then be scoped to the VPC instead of to
  # 0.0.0.0/0, and client IP preservation is what makes an instance unable to reach a load balancer it is
  # itself registered with - a trap to avoid in a cluster whose own pods may end up calling this endpoint.
  #
  # A string, not a bool: this argument is typed as a string by the provider.
  preserve_client_ip = "false"
  health_check {
    # TCP rather than HTTPS. The apiserver's /readyz would be the better signal, but it requires a client
    # certificate - an unauthenticated HTTPS probe gets a TLS handshake failure, which the health check
    # reports as unhealthy on a perfectly healthy API server. A TCP open is what can actually be checked
    # from outside, and because kube-proxy only opens the nodePort once the Service exists, it is still a
    # real signal rather than always-true.
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = var.health_check_interval_seconds
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }
  tags = {
    Name = var.tag_name
  }
  # The load balancer has to exist before a target group can be renamed into place by name_prefix without
  # colliding, and more importantly the listener below references both - ordering them explicitly keeps the
  # create order stable when name_prefix is in use.
  depends_on = [aws_lb.karmada_api]
}
resource "aws_lb_listener" "karmada_api" {
  load_balancer_arn = aws_lb.karmada_api.arn
  port              = var.port
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.karmada_api.arn
  }
}
# Registration through the Auto Scaling group rather than per instance, so nodes replaced by the node group
# re-register themselves. A list of instance IDs could not be used here in any case: they are not known
# until apply, and for_each keys have to be (rules.md B-8).
resource "aws_autoscaling_attachment" "karmada_api" {
  autoscaling_group_name = var.autoscaling_group_name
  lb_target_group_arn    = aws_lb_target_group.karmada_api.arn
}
# A standalone rule rather than an inline ingress block, because this group is the EKS cluster security
# group and EKS adds its own control-plane-to-node rules to it - an inline block is authoritative over the
# whole group and would remove them on the next apply (rules.md F-2).
resource "aws_vpc_security_group_ingress_rule" "karmada_api_node_port" {
  security_group_id = var.node_security_group_id
  description       = "Karmada API server node port from the load balancer"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  # The VPC, which is where the load balancer's own interfaces live. This is only as narrow as it is because
  # preserve_client_ip is off on the target group above; with it on, the source would be the original client
  # and an internet-facing load balancer would need 0.0.0.0/0 here.
  cidr_ipv4 = var.ingress_cidr_block
}
