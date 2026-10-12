# The blueprint's AlbConstruct, less the routing: the internet-facing ALB and its security group, the HTTP
# listener that redirects to HTTPS, the self-signed certificate, the HTTPS listener, and the target group the
# ComfyUI task registers in. The listener rules that route to ComfyUI and to the admin functions need the
# Cognito user pool, which needs this ALB's address, so they are declared where both are known - the root
# and modules/admin_functions.
resource "aws_security_group" "alb" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
locals {
  # The two ports this load balancer answers on, named once. The listeners below read the same numbers, so a
  # port cannot be opened in the security group and not listened on, or the reverse (rules.md B-5).
  listener_ports = {
    https = 443
    http  = 80
  }
  # One rule per port per source address.
  #
  # The blueprint opened both to 0.0.0.0/0 - 443 by its own rule, 80 by the one CDK adds for the redirect
  # listener - and left Cognito as the only thing in front of ComfyUI. The sources are the caller's now, and
  # the caller passes the address it appears as from outside.
  #
  # The keys are "<port>-<index in the list>" rather than the address itself. Both are known at plan
  # (rules.md B-8), but an address in the key makes a changed address a destroy and create, where this rule
  # supports changing cidr_ipv4 in place - and that change happens every time the apply runs from a different
  # network.
  ingress_rules = merge([
    for name, port in local.listener_ports : {
      for index, cidr in var.ingress_cidr_blocks : "${name}-${index}" => {
        port = port
        cidr = cidr
      }
    }
  ]...)
}
# Standalone rules (rules.md F-2).
resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.alb.id
  description       = "Port ${each.value.port} from ${each.value.cidr}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}
# All outbound, as the blueprint's allow_all_outbound. The ALB's outbound traffic is the target port to the
# task and, for the authenticate-cognito action, HTTPS to Cognito's token endpoint - which is on the internet.
resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_lb" "alb" {
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.subnet_ids
  enable_deletion_protection = false
  tags = {
    Name = var.name
  }
}

# --- Certificate ----------------------------------------------------------------------------------------

# The blueprint's RegisterSelfSignedCert custom resource: a Python Lambda that generated a 4096-bit RSA key
# and a self-signed certificate with pyOpenSSL and imported them into ACM, plus the Provider framework's own
# Lambda and two roles to run it. The same certificate is three resources here.
#
# The private key is ephemeral and reaches the certificate and ACM through write-only arguments, so it is in
# neither the plan nor the state - which is what the custom resource achieved by never writing it anywhere but
# ACM. The cost is that the key exists only during an apply: both resources take it from the same ephemeral
# instance in that apply, which is what keeps them a matching pair, and re-issuing means changing
# certificate_version, which replaces both together.
ephemeral "tls_private_key" "certificate" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "tls_self_signed_cert" "certificate" {
  private_key_pem_wo         = ephemeral.tls_private_key.certificate.private_key_pem
  private_key_pem_wo_version = var.certificate_version
  validity_period_hours      = var.certificate_validity_hours
  # The blueprint's certificate was a bare X.509 v1 with no extensions. This resource requires the key usages
  # to be listed, so the usual set for a TLS server is; the ALB does not check either way.
  allowed_uses = ["key_encipherment", "digital_signature", "server_auth"]

  subject {
    common_name         = var.certificate_subject.common_name
    email_address       = var.certificate_subject.email_address
    country             = var.certificate_subject.country
    province            = var.certificate_subject.state
    locality            = var.certificate_subject.city
    organization        = var.certificate_subject.organization
    organizational_unit = var.certificate_subject.organizational_unit
  }
}
# ACM accepts a certificate only while it is valid, and it compares the certificate's notBefore against its
# own clock:
#
#   ValidationException: The certificate is valid in the future.
#   You can Import a certificate only during its validity period.
#
# notBefore is the clock of the machine running terraform. tls_self_signed_cert stamps it with time.Now() and
# offers no argument to move it, and the import lands under a second later - so a machine whose clock is a
# second or two ahead of AWS fails here. That much drift is ordinary and stays well inside the five minutes
# SigV4 tolerates, so every other call in the apply succeeds and nothing in the plan hints at it. The next
# apply then works, because the certificate in state has aged past the difference.
#
# There is nothing to wait for instead. No API answers "is this certificate valid yet", and the import is the
# test - it fails rather than waits. rules.md D-5 rejects a timer standing in for a completion signal and that
# holds wherever a signal exists; this is a case where none does, as with the role propagation wait in 112.
#
# It costs nothing in practice. The only thing that consumes the certificate is the HTTPS listener, which also
# waits for the load balancer to become active - a couple of minutes - and this runs alongside that.
resource "time_sleep" "certificate_valid" {
  create_duration = var.certificate_import_delay

  # Waits again when the certificate is reissued, rather than being a one-off that later applies skip. The id
  # is the certificate's serial number, so a reissued certificate is a new value here.
  triggers = {
    certificate = tls_self_signed_cert.certificate.id
  }
}
resource "aws_acm_certificate" "certificate" {
  certificate_body       = tls_self_signed_cert.certificate.cert_pem
  private_key_wo         = ephemeral.tls_private_key.certificate.private_key_pem
  private_key_wo_version = var.certificate_version
  tags = {
    Name = var.name
  }

  lifecycle {
    # A new certificate before the old one goes, because ACM refuses to delete a certificate the listener
    # still uses. And a new ACM certificate whenever the TLS certificate is re-issued, rather than an
    # in-place re-import that would have to pick the new key out of a write-only argument nobody changed.
    create_before_destroy = true
    replace_triggered_by  = [tls_self_signed_cert.certificate]
  }

  # certificate_body references the certificate, which orders this after it but not after the wait above
  # (rules.md D-1).
  depends_on = [time_sleep.certificate_valid]
}

# --- Target group and listeners -------------------------------------------------------------------------

# Declared here rather than with the ECS service, where the blueprint had it, because it is the listener's
# rules that point at it - and ECS refuses to create a service on a target group that is not yet attached to
# a load balancer.
resource "aws_lb_target_group" "comfyui" {
  name        = var.target_group_name
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  # The blueprint's health check: ComfyUI's /system_stats on the container port.
  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = tostring(var.target_port)
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}
# The blueprint's add_redirect: plain HTTP is answered with a permanent redirect to HTTPS.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = local.listener_ports.http
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = tostring(local.listener_ports.https)
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = local.listener_ports.https
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = aws_acm_certificate.certificate.arn

  # A fixed 403 where the blueprint forwarded to ComfyUI. Every request matches the authenticated /* rule in
  # the root, so in steady state the default is never reached either way. What differs is the window before
  # that rule exists or while it is being replaced: the blueprint's default sent those requests to ComfyUI
  # with no login in front of it. The ECS service waits for the /* rule instead, which is what attaches the
  # target group to this load balancer.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}
