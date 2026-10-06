# Generated from 016_eks_argocd_github_action/pipeline.yaml by tools/cfn2tf.
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
  default     = "pipeline"
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
variable "git_hub_user" {
  type = string
}
variable "git_hub_token" {
  type = string
}
variable "git_hub_repo" {
  type    = string
  default = "argocd-repo"
}
variable "git_hub_action" {
  type    = string
  default = "argocd"
}
variable "eks_cluster" {
  type    = string
  default = "cluster"
}
variable "eks_version" {
  type    = string
  default = 1.32
}
variable "eks_nodegroup" {
  type    = string
  default = "app-ng"
}
variable "eks_node_instance_type" {
  type    = string
  default = "t3.medium"
}
variable "eks_node_name" {
  type    = string
  default = "app-node"
}
# --- Mappings / Conditions ---
locals {
  mappings = {
    AzMapping = {
      a = {
        PublicSubnetCidr  = "10.0.0.0/24"
        PrivateSubnetCidr = "10.0.2.0/24"
      }
      b = {
        PublicSubnetCidr  = "10.0.1.0/24"
        PrivateSubnetCidr = "10.0.3.0/24"
      }
    }
  }
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
}
# --- Resources split out of composite CloudFormation resources ---
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
resource "aws_iam_role_policy_attachment" "code_build_iam_role" {
  role       = aws_iam_role.code_build_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
resource "aws_ecr_repository" "ecr" {
  name = "app-repo"
}
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "ws2025-cicd-vpc"
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "ws2025-cicd-igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "ws2025-cicd-public-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
resource "aws_subnet" "public_subneta" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = local.mappings["AzMapping"]["a"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "ws2025-cicd-public-subnet-a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subneta_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subneta.id
}
resource "aws_subnet" "public_subnetb" {
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = local.mappings["AzMapping"]["b"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "ws2025-cicd-public-subnet-b"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnetb_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnetb.id
}
resource "aws_subnet" "private_subneta" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["a"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "ws2025-cicd-private-subnet-a"
  }
}
resource "aws_route_table" "private_subneta_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "ws2025-cicd-private-rt-a"
  }
}
resource "aws_eip" "natgatewaya_elastic_ip" {}
resource "aws_nat_gateway" "nat_gatewaya" {
  allocation_id = aws_eip.natgatewaya_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subneta.id
  tags = {
    Name = "natgw-a"
  }
}
resource "aws_route_table_association" "private_subneta_route_table_association" {
  route_table_id = aws_route_table.private_subneta_route_table.id
  subnet_id      = aws_subnet.private_subneta.id
}
resource "aws_route" "private_subneta_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gatewaya.id
  route_table_id         = aws_route_table.private_subneta_route_table.id
}
resource "aws_subnet" "private_subnetb" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["b"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}b"
  tags = {
    Name = "ws2025-cicd-private-subnet-b"
  }
}
resource "aws_route_table" "private_subnetb_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "ws2025-cicd-private-rt-b"
  }
}
resource "aws_eip" "natgatewayb_elastic_ip" {}
resource "aws_nat_gateway" "nat_gatewayb" {
  allocation_id = aws_eip.natgatewayb_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnetb.id
  tags = {
    Name = "natgw-b"
  }
}
resource "aws_route_table_association" "private_subnetb_route_table_association" {
  route_table_id = aws_route_table.private_subnetb_route_table.id
  subnet_id      = aws_subnet.private_subnetb.id
}
resource "aws_route" "private_subnetb_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gatewayb.id
  route_table_id         = aws_route_table.private_subnetb_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT7M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  instance_type        = "t3.medium"
  key_name             = aws_key_pair.key_pair.key_name
  ami                  = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  iam_instance_profile = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  tags = {
    Name = "cicd-bastion"
  }
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq

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
  subnet_id                   = aws_subnet.public_subneta.id
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
  vpc_id = aws_vpc.vpc.id
}
resource "aws_iam_role" "bastion_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  role = jsonencode([aws_iam_role.bastion_ec2_iam_role.name])
}
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc_security_group_ingress_rule" "bastion_ec2_security_group_ingress" {
  ip_protocol                  = -1
  referenced_security_group_id = aws_security_group.bastion_ec2_security_group.id
  security_group_id            = aws_security_group.bastion_ec2_security_group.id
}
resource "aws_ssm_association" "git_hub_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 900
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << EOF\nmkdir -p /home/ec2-user/${var.git_hub_repo}/.github/workflows\nmkdir -p /home/ec2-user/${var.git_hub_repo}/manifest\ncd /home/ec2-user/${var.git_hub_repo}\n\necho $'name: ${var.git_hub_action}\npermissions:\n  contents: write\non:\n  push:\n    branches: [ \"master\" ]\n    paths: [ \"index.html\" ]\njobs:\n  codebuild:\n    runs-on:\n      - codebuild-project${element(split("-", element(split("/", local.stack_id), 2)), 3)}-\\$${{ github.run_id }}-\\$${{ github.run_attempt }}\n    steps:\n      - name: Check out the repo\n        uses: actions/checkout@v4\n      - name: ECR Login\n        id: login-ecr\n        uses: aws-actions/amazon-ecr-login@v2\n      - name: Docker Build adn Push\n        env:\n          REGISTRY: \\$${{ steps.login-ecr.outputs.registry }}\n          REPOSITORY: ${aws_ecr_repository.ecr.name}\n        run: |\n          echo \\'FROM nginx:latest\n          COPY index.html /usr/share/nginx/html/index.html\n          CMD [\"nginx\", \"-g\", \"daemon off;\"]\\' > Dockerfile\n          IMAGE_TAG=\\$(cat version)\n          docker build -t \\$REGISTRY/\\$REPOSITORY:\\$IMAGE_TAG .\n          docker push \\$REGISTRY/\\$REPOSITORY:\\$IMAGE_TAG\n          echo \"IMAGE=\\$REGISTRY/\\$REPOSITORY:\\$IMAGE_TAG\" >> \\$GITHUB_ENV\n      - name: Deployment Update\n        id: update-deployment\n        uses: mikefarah/yq@master\n        with:\n          cmd: yq -i \\'.spec.template.spec.containers[0].image = \\\"\\$${{ env.IMAGE }}\\\"\\' ./manifest/deployment.yaml\n      - name: Git Commit and Push\n        run: |\n          git config --global user.email \"abc@abc.com\"\n          git config --global user.name \"GitHubAction\"\n          git add ./manifest\n          git commit -m \"Update Deployment Image\"\n          git push' > ./.github/workflows/codebuild.yaml\n\necho '<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n    <meta charset=\"UTF-8\">\n    <title>Nginx Test Page - v1</title>\n    <style>\n        body {\n            font-family: Arial, sans-serif;\n            text-align: center;\n            padding-top: 100px;\n            background-color: #f0f0f0;\n        }\n        h1 {\n            color: #333;\n        }\n        .version {\n            font-size: 20px;\n            color: #555;\n            margin-top: 20px;\n        }\n    </style>\n</head>\n<body>\n    <h1>Welcome to Nginx!</h1>\n    <div class=\"version\">Version: v1</div>\n</body>\n</html>' > ./index.html\n\necho 'v1.0.0' > ./version\n\necho 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: nginx-deploy\n  labels:\n    app: nginx\nspec:\n  replicas: 3\n  selector:\n    matchLabels:\n      app: nginx\n  template:\n    metadata:\n      labels:\n        app: nginx\n    spec:\n      containers:\n      - name: nginx\n        image: nginx:latest\n' > ./manifest/deployment.yaml\n\necho 'apiVersion: v1\nkind: Service\nmetadata:\n  name: nginx-service\nspec:\n  selector:\n    app: nginx\n  ports:\n    - protocol: TCP\n      port: 80\n      targetPort: 80' > ./manifest/service.yaml\n\necho 'apiVersion: networking.k8s.io/v1\nkind: Ingress\nmetadata:\n  name: nginx-ingress\n  annotations:\n    alb.ingress.kubernetes.io/load-balancer-name: cicd-alb\n    alb.ingress.kubernetes.io/scheme: internet-facing\n    alb.ingress.kubernetes.io/target-type: ip\nspec:\n  ingressClassName: alb\n  rules:\n  - http:\n      paths:\n      - path: /\n        pathType: Prefix\n        backend:\n          service:\n            name: nginx-service\n            port:\n              number: 80' > ./manifest/ingress.yaml\n\nzip -r src.zip . \"./*\"\naws s3 cp src.zip s3://${aws_s3_bucket.source_s3_bucket.id}\n\nEOF\n"])
  }
}
resource "aws_s3_bucket" "source_s3_bucket" {
  bucket = "github-runner-bucket-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
}
# === GitHubRepository (AWS::CodeStar::GitHubRepository) NOT CONVERTED ===
# Legacy CodeStar resource; the AWS provider has no equivalent. Use the GitHub provider.
# Original CloudFormation definition:
# # {
# #   "Type": "AWS::CodeStar::GitHubRepository",
# #   "DependsOn": [
# #     "GitHubSsmAssociation"
# #   ],
# #   "Properties": {
# #     "EnableIssues": true,
# #     "IsPrivate": false,
# #     "RepositoryAccessToken": {
# #       "Ref": "GitHubToken"
# #     },
# #     "RepositoryName": {
# #       "Ref": "GitHubRepo"
# #     },
# #     "RepositoryOwner": {
# #       "Ref": "GitHubUser"
# #     },
# #     "Code": {
# #       "S3": {
# #         "Bucket": {
# #           "Ref": "SourceS3Bucket"
# #         },
# #         "Key": "src.zip"
# #       }
# #     }
# #   }
# # }
resource "aws_codestarconnections_connection" "git_hub_connection" {
  name          = "github-connection"
  provider_type = "GitHub"
}
resource "aws_codebuild_source_credential" "git_hub_credential" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.git_hub_token
  user_name   = var.git_hub_user
}
resource "aws_codebuild_project" "code_build_project" {
  name         = "project${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  service_role = aws_iam_role.code_build_iam_role.arn
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
  }
  source {
    type     = "GITHUB"
    location = "https://github.com/${var.git_hub_user}/${var.git_hub_repo}.git"
    auth {
      type     = "OAUTH"
      resource = aws_codestarconnections_connection.git_hub_connection.id
    }
  }
  # TODO cfn2tf: unmapped CloudFormation property 'Triggers' of AWS::CodeBuild::Project
  # # {
  # #   "Webhook": true,
  # #   "FilterGroups": [
  # #     [
  # #       {
  # #         "Type": "EVENT",
  # #         "Pattern": "WORKFLOW_JOB_QUEUED"
  # #       },
  # #       {
  # #         "Type": "WORKFLOW_NAME",
  # #         "Pattern": {
  # #           "Ref": "GitHubAction"
  # #         }
  # #       }
  # #     ]
  # #   ]
  # # }
}
resource "aws_iam_role" "code_build_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codebuild.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_ssm_association" "eks_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 3600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'EOF'\nexport HOME=\"/home/ec2-user\"\n\ncurl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.32.3/2025-04-17/bin/linux/amd64/kubectl\nchmod +x ./kubectl\nmkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH\necho 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc\n\nARCH=amd64\nPLATFORM=$(uname -s)_$ARCH\ncurl -sLO \"https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz\"\ntar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz\nsudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl\n\ncurl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3\nchmod 700 get_helm.sh\n./get_helm.sh\nhelm version\n\necho 'apiVersion: eksctl.io/v1alpha5\nkind: ClusterConfig\nmetadata:\n  name: ${var.eks_cluster}\n  region: ${data.aws_region.current.region}\n  version:\t\"${var.eks_version}\"\niam:\n  withOIDC:\ttrue\n  serviceAccounts:\n    - metadata:\n        name: aws-load-balancer-controller\n        namespace: kube-system\n      wellKnownPolicies:\n        awsLoadBalancerController: true\n      roleName: AmazonEKSLoadBalancerControllerRole\nvpc:\n  id:\t${aws_vpc.vpc.id}\n  subnets:\n    public:\n      public1:\n        id: ${aws_subnet.public_subneta.id}\n      public2:\n        id: ${aws_subnet.public_subnetb.id}\n    private:\n      private1:\n        id: ${aws_subnet.private_subneta.id}\n      private2:\n        id: ${aws_subnet.private_subnetb.id}\n  clusterEndpoints:\n    privateAccess: true\n    publicAccess: true\n  controlPlaneSecurityGroupIDs:\n    - ${aws_security_group.bastion_ec2_security_group.id}\ncloudWatch:\n  clusterLogging:\n    enableTypes:\n      - api\n      - audit\n      - authenticator\n      - controllerManager\n      - scheduler\nmanagedNodeGroups:\n  - name: ${var.eks_nodegroup}\n    amiFamily: AmazonLinux2023\n    instanceType: ${var.eks_node_instance_type}\n    minSize: 2\n    desiredCapacity: 2\n    maxSize: 2\n    privateNetworking: true\n    instanceName: ${var.eks_node_name}\n    iam:\n      attachPolicyARNs:\n        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy\n        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy\n        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly\n        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore\n    preBootstrapCommands:\n      - timedatectl set-timezone Asia/Seoul\naddons:\n  - name: coredns\n    resolveConflicts: overwrite\n  - name: kube-proxy\n    resolveConflicts: overwrite\n  - name: vpc-cni\n    resolveConflicts: overwrite\n' > cluster.yaml\n\neksctl create cluster -f cluster.yaml\n\nexport LBC_VERSION=\"1.13.0\"\nhelm repo add eks https://aws.github.io/eks-charts\nhelm repo update eks\nhelm install aws-load-balancer-controller eks/aws-load-balancer-controller \\\n-n kube-system \\\n--set clusterName=${var.eks_cluster} \\\n--set serviceAccount.create=false \\\n--set serviceAccount.name=aws-load-balancer-controller \\\n--version $LBC_VERSION \\\n--set region=${data.aws_region.current.region} \\\n--set vpcId=${aws_vpc.vpc.id}\nkubectl -n kube-system rollout status deployment aws-load-balancer-controller\n\nkubectl -n kube-system rollout status daemonset aws-node\nkubectl -n kube-system rollout status daemonset kube-proxy\nkubectl -n kube-system rollout status deployment coredns\nsleep 120\n\ncurl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64\nsudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd\nrm argocd-linux-amd64\n\nkubectl create namespace argocd\nkubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml\nsleep 10\nkubectl patch svc argocd-server -n argocd -p '{\"spec\": {\"type\": \"LoadBalancer\"}}'\n# Use ELB or kube-proxy\nsleep 120\n\necho '#!/bin/bash\nexport ARGOCD_SERVER_DOMAIN=$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')\nexport ARGOCD_SERVER_PASSWORD=$(argocd admin initial-password -n argocd | cut -d \" \" -f1 | tr -d \"\\n\")\nargocd login $ARGOCD_SERVER_DOMAIN --insecure --username admin --password $ARGOCD_SERVER_PASSWORD\nsleep 60\nargocd login $ARGOCD_SERVER_DOMAIN --insecure --username admin --password $ARGOCD_SERVER_PASSWORD\nsleep 60\nargocd login $ARGOCD_SERVER_DOMAIN --insecure --username admin --password $ARGOCD_SERVER_PASSWORD\nargocd cluster add $(kubectl config get-contexts -o name) -y\nkubectl config set-context --current --namespace=argocd\nargocd app create argo-app --sync-policy automated --self-heal --repo https://github.com/${var.git_hub_user}/${var.git_hub_repo}.git --path manifest --dest-server https://kubernetes.default.svc --dest-namespace default\n# argocd app sync argo-app\nkubectl config set-context --current --namespace=default' > argocd.sh\nchmod +x argocd.sh\n./argocd.sh\n\nEOF"])
  }
}
