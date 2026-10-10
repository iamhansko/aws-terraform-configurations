# Generated from 073_cognito_identity_pool/1_vscode.yaml by tools/cfn2tf.
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
  default     = "1-vscode"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "inbound_from_anywhere" {
  type        = string
  default     = "True"
  description = "SecurityGroup Inbound Rule (Source 0.0.0.0/0)"
  validation {
    condition     = contains(["True", "False"], var.inbound_from_anywhere)
    error_message = "InboundFromAnywhere must be one of: True, False"
  }
}
variable "ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id
}
# --- Mappings / Conditions ---
locals {
  mappings = {
    AzMapping = {
      a = {
        PublicSubnetCidr  = "10.0.0.0/24"
        PrivateSubnetCidr = "10.0.1.0/24"
      }
      b = {
        PublicSubnetCidr  = "10.0.2.0/24"
        PrivateSubnetCidr = "10.0.3.0/24"
      }
      c = {
        PublicSubnetCidr  = "10.0.4.0/24"
        PrivateSubnetCidr = "10.0.5.0/24"
      }
    }
  }
  stack_id                                  = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  cond_security_group_inbound_from_anywhere = (var.inbound_from_anywhere == "True")
}
# --- Resources split out of composite CloudFormation resources ---
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
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc"
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_subnet" "public_subneta" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = local.mappings["AzMapping"]["a"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subneta_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subneta.id
}
resource "aws_subnet" "public_subnetc" {
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = local.mappings["AzMapping"]["c"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-c"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnetc_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnetc.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "public-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT10M"
# #   }
# # }
resource "aws_instance" "vs_code_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t3.medium"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "vscode"
  }
  iam_instance_profile        = aws_iam_instance_profile.vs_code_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf install -yq git
dnf groupinstall -yq "Development Tools"

dnf install -yq git
dnf install -yq docker
systemctl enable --now docker
# usermod -aG docker ec2-user
# newgrp docker
chmod 666 /var/run/docker.sock

export VSC_VERSION="4.106.2"
wget https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
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

cd /home/ec2-user
export SAM_VERSION=1.148.0
wget -q https://github.com/aws/aws-sam-cli/releases/download/v$SAM_VERSION/aws-sam-cli-linux-x86_64.zip
unzip aws-sam-cli-linux-x86_64.zip -d sam-installation
./sam-installation/install
rm -rf sam-installation/
rm -f aws-sam-cli-linux-x86_64.zip

dnf install -yq nodejs
npm install -g esbuild

# sudo -Eu ec2-user bash << 'EOF'
# EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vs_code_ec2_security_group.id]
}
resource "aws_security_group" "vs_code_ec2_security_group" {
  description = "Security Group"
  name        = "vscode-sg"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 8000
      to_port     = 8000
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "vscode-sg"
  }
}
resource "aws_iam_role" "vs_code_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "vs_code_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.vs_code_ec2_iam_role.name
}
resource "aws_ssm_association" "ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 480
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    commands = join("\n", ["cd /home/ec2-user\nmkdir -p /home/ec2-user/workshop/cognito-web/web-app/authn\necho \"import express from 'express';\nconst router = express.Router();\nexport default router;\" > /home/ec2-user/workshop/cognito-web/web-app/authn/app.js\nmkdir -p /home/ec2-user/workshop/cognito-web/web-app/public\necho '<!doctype html>\n<html lang=\"en\">\n  <head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n    <title>Amazon Cognito SDK</title>\n    <link href=\"https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css\" rel=\"stylesheet\" integrity=\"sha384-rbsA2VBKQhggwzxH7pPCaAqO46MgnOM80zW1RWuH61DGLwZJEdK2Kadq2F9CUG65\" crossorigin=\"anonymous\">\n    <style>\n      html, body { height: 100%; }\n      body { display: flex; align-items: center; padding-top: 40px; padding-bottom: 40px; background-color: #f5f5f5; }\n      .form-signup { max-width: 600px; padding: 15px; }\n      .form-signup .form-floating:focus-within { z-index: 2; }\n      .form-signup #floatingName, .form-signup #nav-sign-in #floatingUsername, .form-signup #nav-sign-in #floatingUsername1, .form-signup #floatingBucket { margin-bottom: -1px; border-bottom-right-radius: 0; border-bottom-left-radius: 0; }\n      .form-signup input[type=\"email\"], .form-signup #nav-sign-up #floatingUsername { margin-bottom: -1px; border-radius: 0; }\n      .form-signup input[type=\"password\"], .form-signup #nav-s3 #floatingPrefix { margin-bottom: 10px; border-top-left-radius: 0; border-top-right-radius: 0; }\n      .input-group, .alert { margin: 10px 0; }\n      .tab-pane { padding: 10px 0; min-height: 350px; }\n    </style>\n  </head>\n  <body class=\"text-center\">\n    <main class=\"form-signup w-100 m-auto\">\n      <nav>\n        <div class=\"nav nav-tabs\" id=\"nav-tab\" role=\"tablist\">\n          <button class=\"nav-link active\" id=\"nav-sign-up-tab\" data-bs-toggle=\"tab\" data-bs-target=\"#nav-sign-up\" type=\"button\" role=\"tab\" aria-controls=\"nav-sign-up\" aria-selected=\"true\">Sign Up</button>\n          <button class=\"nav-link\" id=\"nav-sign-in-tab\" data-bs-toggle=\"tab\" data-bs-target=\"#nav-sign-in\" type=\"button\" role=\"tab\" aria-controls=\"nav-sign-in\" aria-selected=\"false\">Sign In</button>\n          <button class=\"nav-link\" id=\"nav-mfa-tab\" data-bs-toggle=\"tab\" data-bs-target=\"#nav-mfa\" type=\"button\" role=\"tab\" aria-controls=\"nav-mfa\" aria-selected=\"false\">Manage MFA</button>\n          <button class=\"nav-link\" id=\"nav-call-apis-tab\" data-bs-toggle=\"tab\" data-bs-target=\"#nav-call-apis\" type=\"button\" role=\"tab\" aria-controls=\"nav-call-apis\" aria-selected=\"false\">Call APIs</button>\n          <button class=\"nav-link\" id=\"nav-s3-tab\" data-bs-toggle=\"tab\" data-bs-target=\"#nav-s3\" type=\"button\" role=\"tab\" aria-controls=\"nav-s3\" aria-selected=\"false\">Access S3</button>\n        </div>\n      </nav>\n      <div class=\"tab-content\" id=\"nav-tabContent\">\n        <div class=\"tab-pane fade show active\" id=\"nav-sign-up\" role=\"tabpanel\" aria-labelledby=\"nav-sign-up-tab\" tabindex=\"0\">\n          <form class=\"needs-validation\" novalidate id=\"sign-up-form\">\n            <div class=\"form-floating\">\n              <input type=\"text\" class=\"form-control\" id=\"floatingName\" placeholder=\"Name\" required>\n              <label for=\"floatingName\">Name</label>\n            </div>\n            <div class=\"form-floating\">\n              <input type=\"text\" class=\"form-control\" id=\"floatingUsername\" placeholder=\"Username\" required>\n              <label for=\"floatingUsername\">Username</label>\n            </div>\n            <div class=\"form-floating\">\n              <input type=\"email\" class=\"form-control\" id=\"floatingEmail\" placeholder=\"name@example.com\" required>\n              <label for=\"floatingEmail\">Email address</label>\n            </div>\n            <div class=\"form-floating\">\n              <input type=\"password\" class=\"form-control\" id=\"floatingPassword\" placeholder=\"Password\" required>\n              <label for=\"floatingPassword\">Password</label>\n            </div>\n            <button class=\"w-50 btn btn-lg btn-primary\" type=\"submit\">Sign Up</button>\n          </form>\n        </div>\n        <div class=\"tab-pane fade\" id=\"nav-sign-in\" role=\"tabpanel\" aria-labelledby=\"nav-sign-in-tab\" tabindex=\"0\">\n          <form class=\"needs-validation\" novalidate id=\"sign-in-form\">\n            <div class=\"form-floating\">\n              <input type=\"text\" class=\"form-control\" id=\"floatingUsername1\" placeholder=\"Username\" required>\n              <label for=\"floatingUsername1\">Username</label>\n            </div>\n            <div class=\"form-floating\">\n              <input type=\"password\" class=\"form-control\" id=\"floatingPassword1\" placeholder=\"Password\" required>\n              <label for=\"floatingPassword1\">Password</label>\n            </div>\n            <button class=\"w-40 btn btn-lg btn-primary\" type=\"submit\">Sign In</button>\n            <button class=\"w-40 btn btn-lg btn-secondary\" type=\"submit\">Sign Out</button>\n          </form>\n        </div>\n        <div class=\"tab-pane fade\" id=\"nav-mfa\" role=\"tabpanel\" aria-labelledby=\"nav-mfa-tab\" tabindex=\"0\">\n          <form class=\"needs-validation\" novalidate id=\"mfa-form\">\n            <button class=\"w-40 btn btn-lg btn-primary\" type=\"submit\">Enable MFA</button>\n            <button class=\"w-40 btn btn-lg btn-secondary\" type=\"submit\">Disable MFA</button>\n            <div class=\"form-floating\">\n              <canvas id=\"qrcanvas\"></canvas>\n              <div><button class=\"w-40 btn btn-sm btn-primary d-none\" type=\"button\" id=\"continue-mfa\">Continue</button></div>\n            </div>\n          </form>\n        </div>\n        <div class=\"tab-pane fade\" id=\"nav-call-apis\" role=\"tabpanel\" aria-labelledby=\"nav-call-apis-tab\" tabindex=\"0\">\n          <form class=\"needs-validation\" novalidate id=\"call-apis-form\">\n            <button class=\"w-50 btn btn-lg btn-primary\" type=\"submit\">Call API Gateway</button>\n          </form>\n        </div>\n        <div class=\"tab-pane fade\" id=\"nav-s3\" role=\"tabpanel\" aria-labelledby=\"nav-s3-tab\" tabindex=\"0\">\n          <form class=\"needs-validation\" novalidate id=\"s3-form\">\n            <div class=\"form-floating\">\n              <input type=\"text\" class=\"form-control\" id=\"floatingBucket\" placeholder=\"Bucket\" required>\n              <label for=\"floatingBucket\">Bucket</label>\n            </div>\n            <div class=\"form-floating\">\n              <input type=\"text\" class=\"form-control\" id=\"floatingPrefix\" placeholder=\"Prefix\" required>\n              <label for=\"floatingPrefix\">Prefix</label>\n            </div>\n            <button class=\"w-40 btn btn-lg btn-primary\" type=\"submit\">List Files</button>\n          </form>\n        </div>\n      </div>\n      <div id=\"liveAlertPlaceholder\"></div>\n    </main>\n    <script src=\"https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js\" integrity=\"sha384-kenU1KFdBIe4zVF0s0G1M5b4hcpxyD9F7jL+jjXkk+Q2h455rYXK/7HAuoJl+0I4\" crossorigin=\"anonymous\"></script>\n    <script src=\"./cognito-sdk.js\" type=\"module\"></script>\n  </body>\n</html>' > /home/ec2-user/workshop/cognito-web/web-app/public/cognito-sdk.html\necho '<!doctype html>\n<html lang=\"en\">\n  <head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n    <title>Amazon Cognito Passwordless Workshop (Sign In)</title>\n    <link href=\"https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css\" rel=\"stylesheet\" integrity=\"sha384-rbsA2VBKQhggwzxH7pPCaAqO46MgnOM80zW1RWuH61DGLwZJEdK2Kadq2F9CUG65\" crossorigin=\"anonymous\">\n    <style>\n      html, body { height: 100%; }\n      body { display: flex; align-items: center; padding-top: 40px; padding-bottom: 40px; background-color: #f5f5f5; }\n      .form-signin { max-width: 330px; padding: 15px; }\n      .form-signin .form-floating:focus-within { z-index: 2; }\n      .form-signin input[type=\"text\"], #testButton, #clearButton { margin: 10px 0; }\n    </style>\n  </head>\n  <body class=\"text-center\">\n    <main class=\"form-signin w-100 m-auto\">\n      <form class=\"needs-validation\" novalidate id=\"zform1\">\n        <h1 class=\"h3 mb-3 fw-normal\">Please sign in</h1>\n        <div class=\"form-floating\">\n          <input type=\"text\" class=\"form-control\" id=\"floatingUsername\" placeholder=\"Username\" required>\n          <label for=\"floatingUsername\">Username</label>\n        </div>\n        <button class=\"w-100 btn btn-lg btn-primary\" type=\"submit\">Sign In</button>\n      </form>\n      <button class=\"btn btn-outline-primary\" type=\"button\" id=\"testButton\">Test</button>\n      <button class=\"btn btn-outline-secondary\" type=\"button\" id=\"clearButton\">Clear</button>\n      <div id=\"liveAlertPlaceholder\"></div>\n    </main>\n    <script src=\"https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js\" integrity=\"sha384-kenU1KFdBIe4zVF0s0G1M5b4hcpxyD9F7jL+jjXkk+Q2h455rYXK/7HAuoJl+0I4\" crossorigin=\"anonymous\"></script>\n    <script src=\"signin.js\" type=\"module\"></script>\n  </body>\n</html>' > /home/ec2-user/workshop/cognito-web/web-app/public/signin.html\necho '<!doctype html>\n<html lang=\"en\">\n  <head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n    <title>Amazon Cognito Passwordless Workshop (Sign Up)</title>\n    <link href=\"https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css\" rel=\"stylesheet\" integrity=\"sha384-rbsA2VBKQhggwzxH7pPCaAqO46MgnOM80zW1RWuH61DGLwZJEdK2Kadq2F9CUG65\" crossorigin=\"anonymous\">\n    <style>\n      html, body { height: 100%; }\n      body { display: flex; align-items: center; padding-top: 40px; padding-bottom: 40px; background-color: #f5f5f5; }\n      .form-signup { max-width: 330px; padding: 15px; }\n      .form-signup .form-floating:focus-within { z-index: 2; }\n      .form-signup #floatingUsername { margin-bottom: -1px; border-bottom-right-radius: 0; border-bottom-left-radius: 0; }\n      .form-signup input[type=\"email\"] { margin-bottom: -1px; border-radius: 0; }\n      .form-signup input[type=\"password\"] { margin-bottom: 10px; border-top-left-radius: 0; border-top-right-radius: 0; }\n      .input-group, .alert { margin: 10px 0; }\n    </style>\n  </head>\n  <body class=\"text-center\">\n    <main class=\"form-signup w-100 m-auto\">\n      <form class=\"needs-validation\" novalidate id=\"zform1\">\n        <h1 class=\"h3 mb-3 fw-normal\">Please sign up</h1>\n        <div class=\"form-floating\">\n          <input type=\"text\" class=\"form-control\" id=\"floatingUsername\" placeholder=\"Username\" required>\n          <label for=\"floatingUsername\">Username</label>\n        </div>\n        <div class=\"form-floating\">\n          <input type=\"email\" class=\"form-control\" id=\"floatingEmail\" placeholder=\"name@example.com\" required>\n          <label for=\"floatingEmail\">Email address</label>\n        </div>\n        <div class=\"form-floating\">\n          <input type=\"password\" class=\"form-control\" id=\"floatingPassword\" placeholder=\"Password\" required>\n          <label for=\"floatingPassword\">Password</label>\n        </div>\n        <button class=\"w-100 btn btn-lg btn-primary\" type=\"submit\">Sign Up</button>\n      </form>\n      <div id=\"liveAlertPlaceholder\"></div>\n    </main>\n    <script src=\"https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js\" integrity=\"sha384-kenU1KFdBIe4zVF0s0G1M5b4hcpxyD9F7jL+jjXkk+Q2h455rYXK/7HAuoJl+0I4\" crossorigin=\"anonymous\"></script>\n    <script src=\"signup.js\" type=\"module\"></script>\n  </body>\n</html>' > /home/ec2-user/workshop/cognito-web/web-app/public/signup.html\necho 'import express from \"express\";\nimport authn from \"./authn/app.js\";\nconst app = express();\nconst port = process.env[\"PORT\"] || 8080;\napp.use(express.json());\napp.use(express.static(\"public\"));\napp.use((req, res, next) => {\n  if (req.get(\"x-forwarded-proto\") &&\n      (req.get(\"x-forwarded-proto\")).split(\",\")[0] !== \"https\") {\n    return res.redirect(301, \"https://\" + req.get(\"host\"));\n  }\n  req.schema = \"https\";\n  next();\n});\napp.get(\"/\", (req, res) => {\n  res.send(\"Amazon Cognito Workshop\");\n});\napp.get(\"/callback\", (req, res) => {\n  res.type(\"html\");\n  res.status(200);\n  res.send(`\n    <!DOCTYPE html><html><body onload=\"zFunc()\"><script>\n    function zFunc() { if (window.location.hash.length > 0) window.location.replace(window.location.href.replace(\"#\", \"?\")); }\n    </script><pre style=\"background-color:#C0C0C0;padding:1em;white-space:pre-wrap;overflow-wrap:break-word\"><code>` + JSON.stringify(req.query, null, 2) + `</code></pre></body></html>\n  `);\n});\napp.use(\"/authn\", authn);\napp.listen(port);' > /home/ec2-user/workshop/cognito-web/web-app/app.js\necho '{\n  \"name\": \"cognito-ws-be\",\n  \"version\": \"1.0.0\",\n  \"description\": \"Amazon Cognito Workshop Backend\",\n  \"main\": \"app.js\",\n  \"type\": \"module\",\n  \"license\": \"MIT\",\n  \"dependencies\": {\n    \"express\": \"^5.1.0\",\n    \"base64-arraybuffer\": \"^1.0.2\",\n    \"fido2-lib\": \"^3.5.3\"\n  }\n}' > /home/ec2-user/workshop/cognito-web/web-app/package.json\necho '#!/bin/bash\nnode app.js' > /home/ec2-user/workshop/cognito-web/web-app/run.sh\nmkdir -p /home/ec2-user/workshop/cognito-web/web-ui-js\necho 'const POOL_DATA = {\n  UserPoolId: \"$${WS_USER_POOL_ID}\",\n  IdentityPoolId: \"$${WS_IDENTITY_POOL_ID}\",\n  ClientId: \"$${WS_USER_POOL_CLIENT_ID}\",\n  Region: \"$${WS_REGION}\",\n  ServiceEndpoint: \"https://$${WS_MOCK_API_ID}.execute-api.$${WS_REGION}.amazonaws.com/Prod/pets\"\n};\nexport { POOL_DATA }' > /home/ec2-user/workshop/cognito-web/web-ui-js/cognito-env-tmpl.js\necho '' > /home/ec2-user/workshop/cognito-web/web-ui-js/cognito-env.js\ncat << 'EOJS' > /home/ec2-user/workshop/cognito-web/web-ui-js/cognito-sdk.js\nimport { AuthenticationDetails, CognitoUserPool, CognitoUser, CognitoUserAttribute } from 'amazon-cognito-identity-js';\nimport { fromCognitoIdentityPool } from '@aws-sdk/credential-providers';\nimport { S3Client, ListObjectsV2Command } from '@aws-sdk/client-s3';\nimport axios from 'axios';\nimport QRCode from 'qrcode';\nimport { POOL_DATA } from './cognito-env.js';\n\nconst userPool = new CognitoUserPool(POOL_DATA);\nlet cognitoUser;\n\nconst domEls = {\nname: document.getElementById('floatingName') || {},\nusername: document.getElementById('floatingUsername') || {},\nusername1: document.getElementById('floatingUsername1') || {},\nemail: document.getElementById('floatingEmail') || {},\npassword: document.getElementById('floatingPassword') || {},\npassword1: document.getElementById('floatingPassword1') || {},\nbucket: document.getElementById('floatingBucket') || {},\nprefix: document.getElementById('floatingPrefix') || {}\n};\n\nconst parseJwt = token => {\nconst base64Url = token.split('.')[1];\nconst base64 = base64Url.replace('-', '+').replace('_', '/');\nreturn JSON.parse(window.atob(base64));\n};\n\nconst getVal = inVal => domEls[inVal].value || '';\nconst dataFmt = inVal => ({ Name: inVal, Value: getVal(inVal) });\nconst getAttr = inVal => new CognitoUserAttribute(inVal);\n\n\n/**\n* Displaying important messages on screen\n*/\nconst alert = (message, type) => {\nconst wrapper = document.createElement('div');\nconst alertPlaceholder = document.getElementById('liveAlertPlaceholder');\n\nwrapper.innerHTML = [\n    `<div class='alert alert-$${type} alert-dismissible' role='alert'>`,\n    `   <div>$${message}</div>`,\n    `   <button type='button' class='btn-close' data-bs-dismiss='alert' aria-label='Close'></button>`,\n    `</div>`\n].join('');\n\nalertPlaceholder.append(wrapper);\n}\n\n\n/**\n* Configure some listeners when the DOM is ready\n*/\n(() => {\n'use strict'\nconst signInForm = document.getElementById('sign-in-form');\nconst signUpForm = document.getElementById('sign-up-form');\nconst mfaForm = document.getElementById('mfa-form');\nconst callApisForm = document.getElementById('call-apis-form');\nconst s3Form = document.getElementById('s3-form');\n\ndocument.getElementById('continue-mfa').addEventListener('click', event => {\n    continueMFA();\n});\n\nsignInForm.addEventListener('submit', event => {\n    signInForm.classList.add('was-validated');\n    event.preventDefault();\n    event.stopPropagation();\n    if (signInForm.checkValidity()) (event.submitter.innerText === 'Sign In') ? signIn() : signOut();\n}, false);\n\nsignUpForm.addEventListener('submit', event => {\n    signUpForm.classList.add('was-validated');\n    event.preventDefault();\n    event.stopPropagation();\n    if (signUpForm.checkValidity()) signUp();\n}, false);\n\nmfaForm.addEventListener('submit', event => {\n    mfaForm.classList.add('was-validated');\n    event.preventDefault();\n    event.stopPropagation();\n    if (mfaForm.checkValidity()) (event.submitter.innerText === 'Enable MFA') ? enableMFA() : disableMFA();\n}, false);\n\ncallApisForm.addEventListener('submit', event => {\n    callApisForm.classList.add('was-validated');\n    event.preventDefault();\n    event.stopPropagation();\n    if (callApisForm.checkValidity()) callAPIGW();\n}, false);\n\ns3Form.addEventListener('submit', event => {\n    s3Form.classList.add('was-validated');\n    event.preventDefault();\n    event.stopPropagation();\n    if (s3Form.checkValidity()) listFiles();\n}, false);\n})()\n\n/**\n* Add Sign Up\n*/\nconst signUp = () => {\nconst attributeList = [];\n\nattributeList.push(getAttr(dataFmt('email')));\nattributeList.push(getAttr(dataFmt('name')));\n\nuserPool.signUp(getVal('username'), getVal('password'), attributeList, null, (err, result) => {\n    const confirmationCode = prompt('Please enter confirmation code:');\n\n    if (err) {\n    console.log(err.message || JSON.stringify(err));\n    return;\n    }\n\n    console.log('Success:', result);\n\n    result.user.confirmRegistration(confirmationCode, true, (err, result) => {\n    if (err) {\n        alert(err.message || JSON.stringify(err));\n        return;\n    }\n    console.log('call result:', result);\n    alert('Sign Up Successful!', 'success');\n    });\n});\n}\n\n/**\n* Add Sign In\n*/\nconst signIn = () => {\nconst authenticationDetails = new AuthenticationDetails (\n    { Username: getVal('username1'), Password: getVal('password1') }\n);\n\ncognitoUser = new CognitoUser({ Username: getVal('username1'), Pool: userPool });\ncognitoUser.authenticateUser(authenticationDetails, {\n    onSuccess: (result) => {\n    const idToken = result.getIdToken().getJwtToken();\n    const accessToken = result.getAccessToken().getJwtToken();\n\n    console.log('Access Token:', parseJwt(accessToken));\n    console.log('ID Token:', parseJwt(idToken));\n\n    alert('Sign In Successful', 'success');\n    },\n\n    onFailure: (err) => {\n    alert(err.message || JSON.stringify(err, null, 2), 'danger');\n    },\n\n    totpRequired: function (codeDeliveryDetails) {\n    console.log('mfaRequired:', codeDeliveryDetails);\n    const verificationCode = prompt('Please input second factor code:', '');\n    cognitoUser.sendMFACode(verificationCode, this, 'SOFTWARE_TOKEN_MFA');\n    },\n});\n}\n\n/**\n* Add Sign Out\n*/\nconst signOut = () => {\ncognitoUser.signOut();\ndocument.getElementById('sign-in-form').classList.remove('was-validated');\ndomEls.username1.value = '';\ndomEls.password1.value = '';\nalert('Signed Out.', 'success');\n}\n\n/**\n* Enable MFA\n*/\nconst enableMFA = () => {\ncognitoUser.associateSoftwareToken({\n    onSuccess: function(result) {\n    console.log(result);\n    },\n    associateSecretCode: (secretCode) => {\n    console.log('MFASecretCode: ', secretCode);\n\n    const canvas = document.getElementById('qrcanvas');\n    const tokenObj = cognitoUser.signInUserSession.idToken.payload;\n    const totpUri = 'otpauth://totp/MFA:' + tokenObj['email'] + '?secret=' + secretCode + '&issuer=CognitoJSPOC';\n\n    QRCode.toCanvas(canvas, totpUri, (error) => {\n        if (error) console.error(error);\n        console.log('QR Code Success!');\n        document.getElementById('continue-mfa').classList.remove('d-none');\n    });\n    },\n\n    onFailure: (err) => {\n    console.log(err);\n    alert(err.message || JSON.stringify(err, null, 2), 'danger');\n    }\n});\n}\n\n/**\n* Continue MFA\n*/\nconst continueMFA = () => {\nconst totpCode = prompt('Enter software token code:');\n\ncognitoUser.verifySoftwareToken(totpCode, 'SoftwareToken', {\n    onSuccess: function(result) {\n    console.log(result);\n    cognitoUser.setUserMfaPreference(\n        null,\n        { PreferredMfa : true, Enabled: true },\n        (err, result) => {\n        if (err) {\n            console.error(err);\n            alert(JSON.stringify(err.message, null, 2), 'success');\n        } else {\n            console.log('setUserMfaPreference call result:', result);\n            document.getElementById('continue-mfa').classList.add('d-none');\n            alert('MFA Enabled', 'success');\n        }\n        }\n    );\n    },\n\n    onFailure: (err) => {\n    console.log(err);\n    alert(err.message || JSON.stringify(err, null, 2), 'danger');\n    }\n});\n}\n\n/**\n* Disable MFA\n*/\nconst disableMFA = () => {\nconst mfaSettings = {\n    PreferredMfa : false,\n    Enabled : false\n};\n\ncognitoUser.setUserMfaPreference(mfaSettings, mfaSettings, (err, result) => {\n    if (err) {\n    console.error(err);\n    alert(JSON.stringify(err.message, null, 2), 'success');\n    } else {\n    console.log('Clear MFA call result:', result);\n    alert('MFA Disabled', 'success');\n    }\n});\n}\n\n/**\n* Call protected APIGW endpoint\n*\n* Important:\n* - Make sure API GW Cognito Authorizer configuration is complete\n* - Make sure the API accepts id-token (no OAuth scope defined in authorization)\n* - You can only use id-token since custom scopes are not supported when SDK is used\n*/\nconst callAPIGW = () => {\nconst headers = {\n    'Content-Type': 'application/json',\n    'Authorization': cognitoUser.signInUserSession.accessToken.jwtToken\n};\n\nconsole.log('headers:', headers);\n\naxios.get(POOL_DATA.ServiceEndpoint, { headers: headers })\n    .then((response) => {\n    console.log('API GW Response:', response.data);\n    alert(JSON.stringify(response.data, null, 2), 'success');\n    }).catch((err) => {\n    console.error('Call API GW Error:', err);\n    alert(err.message || JSON.stringify(err, null, 2), 'danger');\n    });\n}\n\n/**\n* List files in S3 bucket\n*\n* - Identity Pool created and configured to use User Pool as IdP\n* - Permissions defined on the IAM role to allow s3 list\n* - Bucket created with proper x-origin policy to allow calls\n*/\nconst listFiles = () => {\nconst client = new S3Client({\n    region: POOL_DATA.Region,\n    credentials: fromCognitoIdentityPool({\n    clientConfig: {region: POOL_DATA.Region},\n    identityPoolId: POOL_DATA.IdentityPoolId,\n    logins: { [`cognito-idp.$${POOL_DATA.Region}.amazonaws.com/$${POOL_DATA.UserPoolId}`]: cognitoUser.signInUserSession.idToken.jwtToken }\n    }),\n});\n\nconst command = new ListObjectsV2Command({\n    Bucket: getVal('bucket'),\n    Prefix: getVal('prefix')\n});\nclient.send(command)\n    .then(response => {\n    console.log('S3 List:', JSON.stringify(response.Contents, null, 2));\n    if (response.Contents === undefined) alert('There was a problem', 'danger');\n    else alert(JSON.stringify(response.Contents, null, 2), 'success');\n    }).catch((err) => {\n    console.error('S3 List Error:', err);\n    alert(err.message || JSON.stringify(err, null, 2), 'danger');\n    });\n}\nEOJS\necho '' > /home/ec2-user/workshop/cognito-web/web-ui-js/helpers.js\necho '' > /home/ec2-user/workshop/cognito-web/web-ui-js/signin.js\necho '' > /home/ec2-user/workshop/cognito-web/web-ui-js/signup.js\necho '{\n  \"name\": \"cognito-ws-fe\",\n  \"version\": \"1.0.0\",\n  \"description\": \"Amazon Cognito Workshop Front-End\",\n  \"main\": \"app.js\",\n  \"type\": \"module\",\n  \"license\": \"MIT\",\n  \"dependencies\": {\n    \"@aws-sdk/client-s3\": \"^3.787.0\",\n    \"@aws-sdk/credential-providers\": \"^3.787.0\",\n    \"amazon-cognito-identity-js\": \"^6.3.15\",\n    \"axios\": \"^1.8.4\",\n    \"base64-arraybuffer\": \"^1.0.2\",\n    \"qrcode\": \"^1.5.4\"\n  }\n}' > /home/ec2-user/workshop/cognito-web/web-ui-js/package.json\necho 'AWSTemplateFormatVersion: \"2010-09-09\"\nTransform: AWS::Serverless-2016-10-31\nDescription: >\n  cognito-webapp\n  Amazon Cognito Workshop\nResources:\n  CognitoWebApp:\n    Type: AWS::Serverless::Function\n    Properties:\n      FunctionName: !Sub $${AWS::StackName}-CognitoWebApp\n      CodeUri: web-app/\n      Handler: run.sh\n      Runtime: nodejs22.x\n      MemorySize: 1024\n      Timeout: 3\n      Architectures:\n        - x86_64\n      Environment:\n        Variables:\n          AWS_LAMBDA_EXEC_WRAPPER: /opt/bootstrap\n          RUST_LOG: info\n      Layers:\n        - !Sub arn:aws:lambda:$${AWS::Region}:753240598075:layer:LambdaAdapterLayerX86:17\n      Events:\n        RootPath:\n          Type: Api\n          Properties:\n            Path: /\n            Method: ANY\n        AnyPath:\n          Type: Api\n          Properties:\n            Path: /{proxy+}\n            Method: ANY\nOutputs:\n  CognitoWebAppURL:\n    Description: \"Cognito Workshop Web App URL\"\n    Value: !Sub \"https://$${ServerlessRestApi}.execute-api.$${AWS::Region}.$${AWS::URLSuffix}/Prod\"\n    Export:\n      Name: !Sub $${AWS::StackName}-Url\n' > /home/ec2-user/workshop/cognito-web/template.yaml\nchown -R ec2-user:ec2-user /home/ec2-user/workshop/\n\nsu - ec2-user << 'EOF'\ncd /home/ec2-user/workshop/cognito-web/web-app\nnpm install\ncd /home/ec2-user/workshop/cognito-web/web-ui-js\nnpm install\ncd /home/ec2-user/workshop/cognito-web\nsam build\nsam deploy --region ${data.aws_region.current.region} --stack-name cognito-webapp --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --resolve-s3 --no-confirm-changeset --disable-rollback --save-params\n\nmkdir -p /home/ec2-user/workshop/cognito-lambdas\ncd /home/ec2-user/workshop/cognito-lambdas\nmkdir -p /home/ec2-user/workshop/cognito-lambdas/ApiGWAuthZ/authz-lambda\nmkdir -p /home/ec2-user/workshop/cognito-lambdas/CreateAuthChallenge\nmkdir -p /home/ec2-user/workshop/cognito-lambdas/DefineAuthChallenge\nmkdir -p /home/ec2-user/workshop/cognito-lambdas/MigrateUser\nmkdir -p /home/ec2-user/workshop/cognito-lambdas/PreToken\nmkdir -p /home/ec2-user/workshop/cognito-lambdas/VerifyAuthChallenge\necho '' > ApiGWAuthZ/authz-lambda/app.py\necho '' > ApiGWAuthZ/authz-lambda/requirements.txt\necho '' > ApiGWAuthZ/template.yaml\necho '' > CreateAuthChallenge/app.mjs\necho '' > DefineAuthChallenge/app.mjs\necho '' > MigrateUser/app.mjs\necho 'export const lambdaHandler = function(event, context) {\n\n  // Processing user group info\n  const userGroup = event.request.groupConfiguration.groupsToOverride;\n\n  //Adding group to access token scopes\n  event.response = {\n    \"claimsAndScopeOverrideDetails\": {\n      \"idTokenGeneration\": {},\n      \"accessTokenGeneration\": {\n        \"claimsToAddOrOverride\": {\n        },\n        \"scopesToAdd\": userGroup\n      }\n    }\n  };\n\n  // Return to Amazon Cognito\n  context.done(null, event);\n};' > PreToken/app.mjs\necho '' > VerifyAuthChallenge/app.mjs\necho 'AWSTemplateFormatVersion: 2010-09-09\nTransform: AWS::Serverless-2016-10-31\nDescription: >\n  cognito-lambdas\n  SAM Template for cognito-lambdas\n\nGlobals:\n  Function:\n    Handler: app.lambdaHandler\n    Runtime: nodejs22.x\n    MemorySize: 1024\n    Timeout: 30\n    Tracing: Active\n    Architectures:\n      - x86_64\n\nParameters:\n  UserPoolArn:\n    Type: String\n    Default: \"\"\n  UserPoolId:\n    Type: String\n    Default: \"\"\n  ClientId:\n    Type: String\n    Default: \"\"\n\nResources:\n  PreToken:\n    Type: AWS::Serverless::Function\n    Properties:\n      FunctionName: !Sub $${AWS::StackName}-PreToken\n      CodeUri: PreToken/\n  PreTokenPermission:\n    Type: AWS::Lambda::Permission\n    Properties:\n      FunctionName: !GetAtt PreToken.Arn\n      Principal: cognito-idp.amazonaws.com\n      Action: lambda:InvokeFunction\n      SourceArn: !Ref UserPoolArn\n\nOutputs:\n  PreTokenLambdaArn:\n    Value: !GetAtt PreToken.Arn' > template.yaml\nEOF\n"])
  }
  depends_on = [aws_instance.vs_code_ec2]
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code Server EC2 instance"
}
# CloudFormation output: VsCodeEc2InstanceId
# CloudFormation Export {"Fn::Sub": "${AWS::StackName}-InstanceId"} -> consume this output via terraform_remote_state or a module output.
output "vs_code_ec2_instance_id" {
  value       = aws_instance.vs_code_ec2.id
  description = "EC2 Instance ID of the VS Code Server"
}
