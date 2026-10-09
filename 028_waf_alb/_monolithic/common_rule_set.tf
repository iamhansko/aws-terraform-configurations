# Generated from 028_waf_alb/common_rule_set.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}
variable "stack_name" {
  type        = string
  default     = "common-rule-set"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "amazon_linux2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}
variable "default_vpc_id" {
  type = string
}
variable "default_vpc_public_subnet1_id" {
  type = string
}
variable "default_vpc_public_subnet2_id" {
  type = string
}
# --- Mappings / Conditions ---
locals {
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_lb_target_group_attachment" "alb_target_group" {
  target_group_arn = aws_lb_target_group.alb_target_group.arn
  target_id        = aws_instance.app_server_ec2.id
  port             = 5000
}
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# CloudFormation stores the generated private key in SSM at /ec2/keypair/<key-pair-id>; mirrored below.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
# --- Resources ---
resource "aws_instance" "app_server_ec2" {
  ami           = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  instance_type = "t3.small"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "app-server"
  }
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf groupinstall -yq "Development Tools"
dnf install -yq python3.13
ln -s /usr/bin/python3.13 /usr/bin/python
python -m ensurepip --upgrade
python -m pip install flask

mkdir -p /home/ec2-user/utils
cat <<EOF > /home/ec2-user/utils/query_builder.py
def obscure_query(mode, **kwargs):
  if mode == "login":
      name = kwargs["name"]
      secret = kwargs["secret"]
      parts = ["SELECT", "*", "FROM", "secret_users", "WHERE"]
      parts.append(f"name='{name}'")
      parts.append("AND")
      parts.append(f"secret='{secret}'")
      return " ".join(parts)

  elif mode == "lookup":
      user_id = kwargs["id"]
      return f"""SELECT id, name, secret FROM secret_users WHERE id = {user_id}"""

  elif mode == "inspect":
      table = kwargs["table"]
      return f"""SELECT * FROM {table}"""

  return "SELECT 1"
EOF

cat <<EOF > /home/ec2-user/main.py
from flask import Flask, request, jsonify
from utils.query_builder import obscure_query
import sqlite3
import os

app = Flask(__name__)
DB_FILE = "challenge.db"

def get_db():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn

def init():
    if os.path.exists(DB_FILE):
        os.remove(DB_FILE)
    conn = get_db()
    cur = conn.cursor()
    cur.execute("CREATE TABLE secret_users (id INTEGER, name TEXT, secret TEXT)")
    cur.executemany("INSERT INTO secret_users VALUES (?, ?, ?)", [
        (1, 'admin', 'supersecret'),
        (2, 'alice', 'flag{alice_flag}'),
        (3, 'bob', 'flag{bob_flag}')
    ])
    conn.commit()

@app.route("/", methods=["GET"])
def index():
    return '''
    <h2>유저관리 시스템</h2>

    <form action="/login" method="get">
        <h4>로그인</h4>
        이름: <input type="text" name="name"><br>
        비밀번호: <input type="text" name="secret"><br>
        <input type="submit" value="로그인">
    </form><hr>

    <form action="/lookup" method="get">
        <h4>ID 조회</h4>
        ID: <input type="text" name="id">
        <input type="submit" value="조회">
    </form><hr>
    '''

@app.route("/login", methods=["GET"])
def login():
    name = request.args.get("name", "")
    passwd = request.args.get("secret", "")
    q = obscure_query("login", name=name, secret=passwd)
    conn = get_db()
    try:
        res = conn.execute(q).fetchone()
        if res:
            return f"✅ 환영합니다, {res['name']} 님!"
        else:
            return "❌ 로그인 실패"
    except Exception as e:
        return f"❗ 오류 발생: {str(e)}"

@app.route("/lookup", methods=["GET"])
def lookup():
    id = request.args.get("id", "")
    q = obscure_query("lookup", id=id)
    conn = get_db()
    try:
        res = conn.execute(q).fetchall()
        return jsonify([dict(row) for row in res])
    except Exception as e:
        return jsonify(error=str(e))

if __name__ == "__main__":
    init()
    app.run(host="0.0.0.0", port=5000, debug=True)
EOF
chown ec2-user:ec2-user /home/ec2-user/main.py

nohup python /home/ec2-user/main.py &

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource AppServerEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = var.default_vpc_public_subnet1_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.app_server_security_group.id]
}
resource "aws_security_group" "app_server_security_group" {
  description = "Security Group"
  vpc_id      = var.default_vpc_id
  ingress {
    protocol    = "tcp"
    from_port   = 5000
    to_port     = 5000
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_lb" "alb" {
  name               = "alb"
  load_balancer_type = "application"
  subnets            = [var.default_vpc_public_subnet1_id, var.default_vpc_public_subnet2_id]
  security_groups    = [aws_security_group.alb_security_group.id]
  internal           = false
}
resource "aws_security_group" "alb_security_group" {
  description = "Security Group"
  vpc_id      = var.default_vpc_id
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_lb_listener" "alb_listener" {
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn
  }
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
}
resource "aws_lb_target_group" "alb_target_group" {
  name        = "alb-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = var.default_vpc_id
  target_type = "instance"
  health_check {
    path = "/"
  }
}
resource "aws_wafv2_web_acl" "waf" {
  name  = "waf"
  scope = "REGIONAL"
  default_action {
    allow {}
  }
  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "waf"
  }
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "sqli-rule"
    }
  }
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "base-rule"
    }
  }
}
resource "aws_wafv2_web_acl_association" "waf_association" {
  resource_arn = aws_lb.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.waf.arn
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT7M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  iam_instance_profile = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  ami                  = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  instance_type        = "t3.small"
  key_name             = aws_key_pair.key_pair.key_name
  tags = {
    Name = "bastion"
  }
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf groupinstall -yq "Development Tools"
dnf install -yq python3.13
dnf install -y python3-pip
ln -sf /usr/bin/python3.13 /usr/bin/python
python -m ensurepip --upgrade

wget https://github.com/coder/code-server/releases/download/v4.100.3/code-server-4.100.3-linux-amd64.tar.gz
tar -xzf code-server-4.100.3-linux-amd64.tar.gz
mv code-server-4.100.3-linux-amd64 /usr/local/lib/code-server
ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

mkdir -p /home/ec2-user/.config/code-server
cat <<EOF > /home/ec2-user/.config/code-server/config.yaml
bind-addr: 0.0.0.0:8000
auth: none
cert: false
EOF
chown -R ec2-user:ec2-user /home/ec2-user/.config

cat <<EOF > /etc/systemd/system/code-server.service
[Unit]
Description=VS Code Server
After=network.target
[Service]
Type=simple
User=ec2-user
ExecStart=/usr/local/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml /home/ec2-user
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable code-server
systemctl start code-server

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = var.default_vpc_public_subnet1_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
}
resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group for Bastion EC2 SSH Connection"
  name        = "bastion-sg"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8000
    protocol    = "tcp"
    to_port     = 8000
  }
  vpc_id = var.default_vpc_id
}
resource "aws_iam_role" "bastion_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.bastion_ec2.public_ip}:8000"
  description = "VsCode on BastionEC2"
}
# CloudFormation output: KeyPairValue
output "key_pair_value" {
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/systems-manager/parameters/%252Fec2%252Fkeypair%252F${aws_key_pair.key_pair.key_pair_id}"
  description = "KeyPair Value"
}
