# Generated from 032_ecs_rds_dynamodb_integration/cluster.yaml by tools/cfn2tf.
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
  default     = "cluster"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "ecs_ami_id" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ecs_ami_id" {
  name = var.ecs_ami_id
}
variable "bastion_ec2_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "bastion_ec2_ami_id" {
  name = var.bastion_ec2_ami_id
}
variable "rds_username" {
  type    = string
  default = "admin"
}
variable "rds_password" {
  type      = string
  default   = "dbpassword"
  sensitive = true
}
variable "rds_database" {
  type    = string
  default = "dev"
}
# --- Mappings / Conditions ---
locals {
  mappings = {
    VpcMapping = {
      Vpc = {
        Name = "vpc"
        Cidr = "10.0.0.0/16"
      }
      Gateway = {
        IgwName         = "igw"
        NatgwNamePrefix = "natgw-"
      }
      RouteTable = {
        PublicSubnetRouteTableName        = "public-rt"
        PrivateSubnetRouteTableNamePrefix = "private-rt-"
      }
    }
    AzMapping = {
      a = {
        PublicSubnetNamePrefix  = "public-subnet-"
        PublicSubnetCidr        = "10.0.0.0/24"
        PrivateSubnetNamePrefix = "private-subnet-"
        PrivateSubnetCidr       = "10.0.1.0/24"
      }
      b = {
        PublicSubnetNamePrefix  = "public-subnet-"
        PublicSubnetCidr        = "10.0.2.0/24"
        PrivateSubnetNamePrefix = "private-subnet-"
        PrivateSubnetCidr       = "10.0.3.0/24"
      }
      c = {
        PublicSubnetNamePrefix  = "public-subnet-"
        PublicSubnetCidr        = "10.0.4.0/24"
        PrivateSubnetNamePrefix = "private-subnet-"
        PrivateSubnetCidr       = "10.0.5.0/24"
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
resource "aws_iam_role_policy_attachment" "rds_monitoring_iam_role" {
  role       = aws_iam_role.rds_monitoring_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_iam_role_0" {
  role       = aws_iam_role.ecs_task_execution_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_iam_role_1" {
  role       = aws_iam_role.ecs_task_execution_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccessV2"
}
resource "aws_iam_role_policy_attachment" "ecs_container_instance_iam_role_0" {
  role       = aws_iam_role.ecs_container_instance_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_role_policy_attachment" "ecs_container_instance_iam_role_1" {
  role       = aws_iam_role.ecs_container_instance_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
# --- Resources ---
resource "aws_ecr_repository" "user_ecr" {
  name         = "user"
  force_delete = true
}
resource "aws_ecr_repository" "product_ecr" {
  name         = "product"
  force_delete = true
}
resource "aws_ecr_repository" "stress_ecr" {
  name         = "stress"
  force_delete = true
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT7M"
# #   }
# # }
# Metadata: CloudFormation Metadata retained for reference.
# # {
# #   "AWS::CloudFormation::Init": {
# #     "configSets": {
# #       "init": [
# #         "pythonInstall",
# #         "vscodeInstall"
# #       ],
# #       "docker": [
# #         "dockerInstallandLogin",
# #         "dockerBuildandPush"
# #       ]
# #     },
# #     "pythonInstall": {
# #       "commands": {
# #         "install": {
# #           "command": {
# #             "Fn::Sub": "dnf groupinstall -yq \"Development Tools\"\ndnf install -yq python$version\nln -sf /usr/bin/python$version /usr/bin/python\n/usr/bin/python$version -m ensurepip --upgrade\n"
# #           },
# #           "env": {
# #             "version": 3.13
# #           },
# #           "ignoreErrors": true
# #         }
# #       }
# #     },
# #     "vscodeInstall": {
# #       "files": {
# #         "/home/ec2-user/.config/code-server/config.yaml": {
# #           "content": {
# #             "Fn::Sub": "bind-addr: 0.0.0.0:8000\nauth: none\ncert: false\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         },
# #         "/etc/systemd/system/code-server.service": {
# #           "content": {
# #             "Fn::Sub": "[Unit]\nDescription=VS Code Server\nAfter=network.target\n[Service]\nType=simple\nUser=ec2-user\nExecStart=/usr/local/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml /home/ec2-user\nRestart=always\n[Install]\nWantedBy=multi-user.target\n"
# #           }
# #         }
# #       },
# #       "commands": {
# #         "install": {
# #           "command": {
# #             "Fn::Sub": "wget -q https://github.com/coder/code-server/releases/download/v$version/code-server-$version-linux-amd64.tar.gz\ntar -xzf code-server-$version-linux-amd64.tar.gz\nmv code-server-$version-linux-amd64 /usr/local/lib/code-server\nchown -R ec2-user:ec2-user /home/ec2-user/.config\nln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server\nsystemctl daemon-reload\nsystemctl enable code-server\nsystemctl start code-server\n"
# #           },
# #           "env": {
# #             "version": "4.102.2"
# #           },
# #           "ignoreErrors": true
# #         }
# #       }
# #     },
# #     "dockerInstallandLogin": {
# #       "commands": {
# #         "install": {
# #           "command": {
# #             "Fn::Sub": "dnf install -yq docker\nsystemctl start docker\nsystemctl enable docker\n# usermod -aG docker ec2-user\n# newgrp docker\nchmod 666 /var/run/docker.sock\naws ecr get-login-password --region ${AWS::Region} | docker login --username AWS --password-stdin ${AWS::AccountId}.dkr.ecr.${AWS::Region}.amazonaws.com\n"
# #           },
# #           "ignoreErrors": true
# #         }
# #       }
# #     },
# #     "dockerBuildandPush": {
# #       "files": {
# #         "/home/ec2-user/user/go.mod": {
# #           "content": {
# #             "Fn::Sub": "module userapp\n\ngo 1.22\n\nrequire (\n    github.com/gin-gonic/gin v1.10.0\n    github.com/go-sql-driver/mysql v1.7.1\n)\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         },
# #         "/home/ec2-user/user/main.go": {
# #           "content": {
# #             "Fn::Sub": "package main\n\nimport (\n  \"database/sql\"\n  \"fmt\"\n  \"log\"\n  \"net/http\"\n  \"os\"\n  \"time\"\n\n  \"github.com/gin-gonic/gin\"\n  _ \"github.com/go-sql-driver/mysql\"\n)\n\ntype User struct {\n  RequestID     string `json:\"requestid\" binding:\"required\"`\n  UUID          string `json:\"uuid\" binding:\"required\"`\n  Username      string `json:\"username\" binding:\"required\"`\n  Email         string `json:\"email\" binding:\"required\"`\n  StatusMessage string `json:\"status_message\" binding:\"required\"`\n}\n\nvar (\n  db *sql.DB\n)\n\nfunc main() {\n  mysqlUser := os.Getenv(\"MYSQL_USER\")\n  mysqlPass := os.Getenv(\"MYSQL_PASSWORD\")\n  mysqlHost := os.Getenv(\"MYSQL_HOST\")\n  mysqlPort := os.Getenv(\"MYSQL_PORT\")\n  mysqlDB := os.Getenv(\"MYSQL_DBNAME\")\n\n  dsn := fmt.Sprintf(\"%s:%s@tcp(%s:%s)/%s\", mysqlUser, mysqlPass, mysqlHost, mysqlPort, mysqlDB)\n  var err error\n  db, err = sql.Open(\"mysql\", dsn)\n  if err != nil {\n    log.Fatalf(\"DB\uc5f0\uacb0 \uc2e4\ud328: %v\", err)\n  }\n  db.SetConnMaxLifetime(time.Minute * 3)\n  db.SetMaxOpenConns(10)\n  db.SetMaxIdleConns(10)\n\n  router := gin.Default()\n  router.Use(gin.Logger())\n  router.Use(gin.Recovery())\n\n  router.POST(\"/v1/user\", postUser)\n  router.GET(\"/v1/user\", getUser)\n  router.GET(\"/healthcheck\", healthCheck)\n\n  router.Run(\":8080\")\n}\n\nfunc postUser(c *gin.Context) {\n  var user User\n  if err := c.ShouldBindJSON(&user); err != nil {\n    c.JSON(http.StatusBadRequest, gin.H{\"error\": err.Error()})\n    return\n  }\n\n  _, err := db.Exec(\"INSERT INTO user (id, username, email, status_message) VALUES (?, ?, ?, ?)\",\n    user.UUID, user.Username, user.Email, user.StatusMessage)\n  if err != nil {\n    c.JSON(http.StatusInternalServerError, gin.H{\"error\": err.Error()})\n    return\n  }\n  c.JSON(http.StatusCreated, gin.H{\"status\": \"created\"})\n}\n\nfunc getUser(c *gin.Context) {\n  email := c.Query(\"email\")\n  requestid := c.Query(\"requestid\")\n  uuid := c.Query(\"uuid\")\n\n  if email == \"\" || requestid == \"\" || uuid == \"\" {\n    c.JSON(http.StatusBadRequest, gin.H{\"error\": \"Missing query parameters\"})\n    return\n  }\n\n  var id, username, statusMessage string\n  err := db.QueryRow(\"SELECT id, username, status_message FROM user WHERE email = ?\", email).Scan(&id, &username, &statusMessage)\n  if err != nil {\n    if err == sql.ErrNoRows {\n      c.JSON(http.StatusNotFound, gin.H{\"error\": \"user not found\"})\n    } else {\n      c.JSON(http.StatusInternalServerError, gin.H{\"error\": err.Error()})\n    }\n    return\n  }\n  c.JSON(http.StatusOK, gin.H{\n    \"id\":             id,\n    \"username\":       username,\n    \"email\":          email,\n    \"status_message\": statusMessage,\n  })\n}\n\nfunc healthCheck(c *gin.Context) {\n  c.JSON(http.StatusOK, gin.H{\"status\": \"ok\"})\n}\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         },
# #         "/home/ec2-user/user/Dockerfile": {
# #           "content": {
# #             "Fn::Sub": "FROM public.ecr.aws/docker/library/golang:1.22.2-alpine AS builder\nWORKDIR /app\nCOPY . .\nRUN go mod tidy\nRUN go build -o userapp main.go\nFROM public.ecr.aws/docker/library/amazonlinux:2023\nWORKDIR /app\nCOPY --from=builder /app/userapp /app/userapp\nRUN yum install -y ca-certificates && yum clean all\nEXPOSE 8080\nENTRYPOINT [\"/app/userapp\"]\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         },
# #         "/home/ec2-user/product/go.mod": {
# #           "content": {
# #             "Fn::Sub": "module productapp\n\ngo 1.22\n\nrequire (\n    github.com/aws/aws-sdk-go-v2 v1.24.0\n    github.com/aws/aws-sdk-go-v2/config v1.24.0\n    github.com/aws/aws-sdk-go-v2/service/dynamodb v1.24.0\n    github.com/gin-gonic/gin v1.10.0\n)\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         },
# #         "/home/ec2-user/product/main.go": {
# #           "content": {
# #             "Fn::Sub": "package main\n\nimport (\n    \"context\"\n    \"log\"\n    \"net/http\"\n    \"os\"\n    \"strconv\"\n\n    \"github.com/aws/aws-sdk-go-v2/config\"\n    \"github.com/aws/aws-sdk-go-v2/service/dynamodb\"\n    \"github.com/aws/aws-sdk-go-v2/service/dynamodb/types\"\n    \"github.com/gin-gonic/gin\"\n)\n\ntype Product struct {\n    RequestID string  `json:\"requestid\" binding:\"required\"`\n    UUID      string  `json:\"uuid\" binding:\"required\"`\n    ID        string  `json:\"id\" binding:\"required\"`\n    Name      string  `json:\"name\" binding:\"required\"`\n    Price     float64 `json:\"price\" binding:\"required\"`\n}\n\nvar (\n    ddbClient   *dynamodb.Client\n    tableName   string\n    indexName   string\n    ctx         = context.Background()\n)\n\nfunc main() {\n    tableName = os.Getenv(\"TABLE_NAME\")\n    if tableName == \"\" {\n        log.Fatal(\"\ud658\uacbd\ubcc0\uc218 TABLE_NAME\uc774 \uc124\uc815\ub418\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4\")\n    }\n    indexName = os.Getenv(\"TABLE_INDEX_NAME\")\n\n    cfg, err := config.LoadDefaultConfig(ctx)\n    if err != nil {\n        log.Fatalf(\"AWS config load failed: %v\", err)\n    }\n\n    ddbClient = dynamodb.NewFromConfig(cfg)\n\n    router := gin.Default()\n    router.Use(gin.Logger())\n    router.Use(gin.Recovery())\n\n    router.POST(\"/v1/product\", postProduct)\n    router.GET(\"/v1/product\", getProduct)\n    router.GET(\"/healthcheck\", healthCheck)\n\n    router.Run(\":8080\")\n}\n\nfunc postProduct(c *gin.Context) {\n    var p Product\n    if err := c.ShouldBindJSON(&p); err != nil {\n        c.JSON(http.StatusBadRequest, gin.H{\"error\": err.Error()})\n        return\n    }\n\n    item := map[string]types.AttributeValue{\n        \"id\":   &types.AttributeValueMemberS{Value: p.ID},\n        \"name\": &types.AttributeValueMemberS{Value: p.Name},\n        \"price\": &types.AttributeValueMemberN{Value: strconv.FormatFloat(p.Price, 'f', 2, 64)},\n    }\n\n    _, err := ddbClient.PutItem(ctx, &dynamodb.PutItemInput{\n        TableName: &tableName,\n        Item:      item,\n    })\n    if err != nil {\n        log.Printf(\"DynamoDB PutItem error: %v\\n\", err)\n        c.JSON(http.StatusInternalServerError, gin.H{\"error\": \"Internal Server Error\"})\n        return\n    }\n\n    c.JSON(http.StatusCreated, gin.H{\"status\": \"created\"})\n}\n\nfunc getProduct(c *gin.Context) {\n    id := c.Query(\"id\")\n    requestID := c.Query(\"requestid\")\n    uuid := c.Query(\"uuid\")\n\n    if id == \"\" || requestID == \"\" || uuid == \"\" {\n        c.JSON(http.StatusBadRequest, gin.H{\"error\": \"Missing query parameters\"})\n        return\n    }\n\n    key := map[string]types.AttributeValue{\n        \"id\": &types.AttributeValueMemberS{Value: id},\n    }\n\n    out, err := ddbClient.GetItem(ctx, &dynamodb.GetItemInput{\n        TableName: &tableName,\n        Key:       key,\n    })\n    if err != nil {\n        log.Printf(\"DynamoDB GetItem error: %v\\n\", err)\n        c.JSON(http.StatusInternalServerError, gin.H{\"error\": \"Internal Server Error\"})\n        return\n    }\n\n    if out.Item == nil {\n        c.JSON(http.StatusNotFound, gin.H{\"error\": \"product not found\"})\n        return\n    }\n\n    nameAttr, ok := out.Item[\"name\"].(*types.AttributeValueMemberS)\n    if !ok {\n        c.JSON(http.StatusInternalServerError, gin.H{\"error\": \"Malformed product data\"})\n        return\n    }\n    priceAttr, ok := out.Item[\"price\"].(*types.AttributeValueMemberN)\n    if !ok {\n        c.JSON(http.StatusInternalServerError, gin.H{\"error\": \"Malformed product data\"})\n        return\n    }\n\n    price, err := strconv.ParseFloat(priceAttr.Value, 64)\n    if err != nil {\n        c.JSON(http.StatusInternalServerError, gin.H{\"error\": \"Malformed price data\"})\n        return\n    }\n\n    c.JSON(http.StatusOK, gin.H{\n        \"id\":      id,\n        \"name\":    nameAttr.Value,\n        \"price\":   price,\n    })\n}\n\nfunc healthCheck(c *gin.Context) {\n    c.JSON(http.StatusOK, gin.H{\"status\": \"ok\"})\n}\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         },
# #         "/home/ec2-user/product/Dockerfile": {
# #           "content": {
# #             "Fn::Sub": "FROM public.ecr.aws/docker/library/golang:1.22.2-alpine AS builder\nWORKDIR /app\nCOPY . .\nRUN go mod tidy\nRUN go build -o productapp main.go\nFROM public.ecr.aws/docker/library/amazonlinux:2023\nWORKDIR /app\nCOPY --from=builder /app/productapp /app/productapp\nRUN yum install -y ca-certificates && yum clean all\nEXPOSE 8080\nENTRYPOINT [\"/app/productapp\"]\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         },
# #         "/home/ec2-user/stress/go.mod": {
# #           "content": {
# #             "Fn::Sub": "module stressapp\n\ngo 1.22\n\nrequire (\n    github.com/gin-gonic/gin v1.10.0\n)\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         },
# #         "/home/ec2-user/stress/main.go": {
# #           "content": {
# #             "Fn::Sub": "package main\n\nimport (\n    \"crypto/rand\"\n    \"encoding/hex\"\n    \"log\"\n    \"net/http\"\n\n    \"github.com/gin-gonic/gin\"\n)\n\ntype StressRequest struct {\n    RequestID string `json:\"requestid\" binding:\"required\"`\n    UUID      string `json:\"uuid\" binding:\"required\"`\n    Length    int    `json:\"length\" binding:\"required\"`\n}\n\nfunc main() {\n    router := gin.Default()\n    router.Use(gin.Logger())\n    router.Use(gin.Recovery())\n\n    router.POST(\"/v1/stress\", postStress)\n    router.GET(\"/healthcheck\", healthCheck)\n\n    router.NoRoute(noRouteHandler)\n\n    if err := router.Run(\":8080\"); err != nil {\n        log.Fatalf(\"\uc11c\ubc84 \uc2dc\uc791 \uc2e4\ud328: %v\", err)\n    }\n}\n\nfunc postStress(c *gin.Context) {\n    var req StressRequest\n    if err := c.ShouldBindJSON(&req); err != nil {\n        c.JSON(http.StatusBadRequest, gin.H{\"error\": err.Error()})\n        return\n    }\n\n    if req.Length <= 0 || req.Length > 10240 {\n        c.JSON(http.StatusBadRequest, gin.H{\"error\": \"length must be between 1 and 10240\"})\n        return\n    }\n\n    byteLen := (req.Length + 1) / 2\n\n    buf := make([]byte, byteLen)\n    _, err := rand.Read(buf)\n    if err != nil {\n        log.Printf(\"\ub79c\ub364 \uc0dd\uc131 \uc2e4\ud328: %v\", err)\n        c.JSON(http.StatusInternalServerError, gin.H{\"error\": \"Internal Server Error\"})\n        return\n    }\n    randomStr := hex.EncodeToString(buf)\n    if len(randomStr) > req.Length {\n        randomStr = randomStr[:req.Length]\n    }\n\n    c.JSON(http.StatusCreated, gin.H{\n        \"requestid\": req.RequestID,\n        \"uuid\":      req.UUID,\n        \"length\":    req.Length,\n        \"data\":      randomStr,\n    })\n}\n\nfunc healthCheck(c *gin.Context) {\n    c.JSON(http.StatusOK, gin.H{\"status\": \"ok\"})\n}\n\nfunc noRouteHandler(c *gin.Context) {\n    path := c.Request.URL.Path\n    if len(path) >= 4 && path[:4] == \"/v1/\" {\n        c.JSON(http.StatusForbidden, gin.H{\"error\": \"forbidden\"})\n    } else {\n        c.JSON(http.StatusNotFound, gin.H{\"error\": \"not found\"})\n    }\n}\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         },
# #         "/home/ec2-user/stress/Dockerfile": {
# #           "content": {
# #             "Fn::Sub": "FROM public.ecr.aws/docker/library/golang:1.22.2-alpine AS builder\nWORKDIR /app\nCOPY . .\nRUN go mod tidy\nRUN go build -o stressapp main.go\nFROM public.ecr.aws/docker/library/amazonlinux:2023\nWORKDIR /app\nCOPY --from=builder /app/stressapp /app/stressapp\nRUN yum install -y ca-certificates && yum clean all\nEXPOSE 8080\nENTRYPOINT [\"/app/stressapp\"]\n"
# #           },
# #           "owner": "ec2-user",
# #           "group": "ec2-user"
# #         }
# #       },
# #       "commands": {
# #         "userEcr": {
# #           "command": {
# #             "Fn::Sub": "cd /home/ec2-user/user\ndocker build -t ${UserEcr.RepositoryUri} .\ndocker push ${UserEcr.RepositoryUri}\n"
# #           },
# #           "ignoreErrors": true
# #         },
# #         "productEcr": {
# #           "command": {
# #             "Fn::Sub": "cd /home/ec2-user/product\ndocker build -t ${ProductEcr.RepositoryUri} .\ndocker push ${ProductEcr.RepositoryUri}\n"
# #           },
# #           "ignoreErrors": true
# #         },
# #         "stressEcr": {
# #           "command": {
# #             "Fn::Sub": "cd /home/ec2-user/stress\ndocker build -t ${StressEcr.RepositoryUri} .\ndocker push ${StressEcr.RepositoryUri}\n"
# #           },
# #           "ignoreErrors": true
# #         }
# #       }
# #     }
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  iam_instance_profile = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  ami                  = data.aws_ssm_parameter.bastion_ec2_ami_id.insecure_value
  instance_type        = "t3.small"
  key_name             = aws_key_pair.key_pair.key_name
  tags = {
    Name = "bastion"
  }
  user_data                   = <<EOT
#!/bin/bash -xe
timedatectl set-timezone Asia/Seoul
dnf update -yq
dnf install -yq git
dnf update -yq aws-cfn-bootstrap

/opt/aws/bin/cfn-init -v --stack ${var.stack_name} --resource BastionEc2 --configsets init --region ${data.aws_region.current.region}
/opt/aws/bin/cfn-init -v --stack ${var.stack_name} --resource BastionEc2 --configsets docker --region ${data.aws_region.current.region}
/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
}
resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group for Bastion EC2"
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
resource "aws_vpc" "vpc" {
  cidr_block           = local.mappings["VpcMapping"]["Vpc"]["Cidr"]
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = local.mappings["VpcMapping"]["Vpc"]["Name"]
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = local.mappings["VpcMapping"]["Gateway"]["IgwName"]
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = local.mappings["VpcMapping"]["RouteTable"]["PublicSubnetRouteTableName"]
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
    Name                     = "${local.mappings["AzMapping"]["a"]["PublicSubnetNamePrefix"]}a"
    "kubernetes.io/role/elb" = 1
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
    Name                     = "${local.mappings["AzMapping"]["b"]["PublicSubnetNamePrefix"]}b"
    "kubernetes.io/role/elb" = 1
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
    Name = "${local.mappings["AzMapping"]["a"]["PrivateSubnetNamePrefix"]}a"
  }
}
resource "aws_route_table" "private_subneta_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${local.mappings["VpcMapping"]["RouteTable"]["PrivateSubnetRouteTableNamePrefix"]}a"
  }
}
resource "aws_eip" "natgatewaya_elastic_ip" {}
resource "aws_nat_gateway" "nat_gatewaya" {
  allocation_id = aws_eip.natgatewaya_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subneta.id
  tags = {
    Name = "${local.mappings["VpcMapping"]["Gateway"]["NatgwNamePrefix"]}a"
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
    Name = "${local.mappings["AzMapping"]["b"]["PrivateSubnetNamePrefix"]}b"
  }
}
resource "aws_route_table" "private_subnetb_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${local.mappings["VpcMapping"]["RouteTable"]["PrivateSubnetRouteTableNamePrefix"]}b"
  }
}
resource "aws_eip" "natgatewayb_elastic_ip" {}
resource "aws_nat_gateway" "nat_gatewayb" {
  allocation_id = aws_eip.natgatewayb_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnetb.id
  tags = {
    Name = "${local.mappings["VpcMapping"]["Gateway"]["NatgwNamePrefix"]}b"
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
resource "aws_dynamodb_table" "dynamo_table" {
  name = "appdev-dynamo-table"
  attribute {
    name = "id"
    type = "S"
  }
  attribute {
    name = "price"
    type = "N"
  }
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  range_key    = "price"
}
resource "aws_db_instance" "rds_instance_primary" {
  allocated_storage           = 400
  allow_major_version_upgrade = true
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  backup_retention_period     = 7
  database_insights_mode      = "standard"
  instance_class              = "db.t3.micro"
  identifier                  = "apdev-rds-instance"
  db_name                     = var.rds_database
  db_subnet_group_name        = aws_db_subnet_group.rds_subnet_group.id
  engine                      = "mysql"
  engine_version              = "8.0.42"
  iops                        = 12000
  username                    = var.rds_username
  password                    = var.rds_password
  max_allocated_storage       = 1000
  monitoring_interval         = 60
  monitoring_role_arn         = aws_iam_role.rds_monitoring_iam_role.arn
  multi_az                    = true
  port                        = 3306
  storage_throughput          = 500
  storage_type                = "gp3"
  vpc_security_group_ids      = [aws_security_group.rds_instance_security_group.id]
}
resource "aws_db_instance" "rds_instance_replica" {
  allocated_storage           = 400
  allow_major_version_upgrade = true
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  backup_retention_period     = 7
  database_insights_mode      = "standard"
  instance_class              = "db.t3.micro"
  identifier                  = "apdev-rds-replica"
  iops                        = 12000
  max_allocated_storage       = 1000
  monitoring_interval         = 60
  monitoring_role_arn         = aws_iam_role.rds_monitoring_iam_role.arn
  # TODO cfn2tf: unmapped CloudFormation property 'SourceDBInstanceIdentifier' of AWS::RDS::DBInstance
  # # {
  # #   "Ref": "RdsInstancePrimary"
  # # }
  storage_throughput     = 500
  storage_type           = "gp3"
  vpc_security_group_ids = [aws_security_group.rds_instance_security_group.id]
}
resource "aws_security_group" "rds_instance_security_group" {
  description = "Security Group"
  name        = "rds-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  ingress {
    protocol        = "TCP"
    from_port       = 3306
    to_port         = 3306
    security_groups = [aws_security_group.bastion_ec2_security_group.id]
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_db_subnet_group" "rds_subnet_group" {
  description = "RDS SubnetGroup"
  name        = "rds-subnet-group"
  subnet_ids  = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
}
resource "aws_iam_role" "rds_monitoring_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["monitoring.rds.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_ecs_task_definition" "user_ecs_task_definition" {
  family = "user-taskdef"
  cpu    = "512"
  memory = "1024"
  container_definitions = jsonencode([{
    Name      = "golang"
    Image     = aws_ecr_repository.user_ecr.repository_url
    Essential = true
    HealthCheck = {
      Command  = ["CMD-SHELL", "curl -f http://localhost:8080/healthcheck || exit 1"]
      Interval = 30
      Retries  = 5
      Timeout  = 5
    }
    PortMappings = [{
      ContainerPort = 8080
      HostPort      = 8080
      Name          = "http"
    }]
    Environment = [{
      Name  = "MYSQL_USER"
      Value = var.rds_username
      }, {
      Name  = "MYSQL_PASSWORD"
      Value = var.rds_password
      }, {
      Name  = "MYSQL_HOST"
      Value = aws_db_instance.rds_instance_primary.address
      }, {
      Name  = "MYSQL_PORT"
      Value = aws_db_instance.rds_instance_primary.port
      }, {
      Name  = "MYSQL_DBNAME"
      Value = var.rds_database
    }]
  }])
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution_iam_role.arn
  depends_on         = [aws_instance.bastion_ec2]
}
resource "aws_ecs_task_definition" "product_ecs_task_definition" {
  family = "user-taskdef"
  cpu    = "512"
  memory = "1024"
  container_definitions = jsonencode([{
    Name      = "golang"
    Image     = aws_ecr_repository.product_ecr.repository_url
    Essential = true
    HealthCheck = {
      Command  = ["CMD-SHELL", "curl -f http://localhost:8080/healthcheck || exit 1"]
      Interval = 30
      Retries  = 5
      Timeout  = 5
    }
    PortMappings = [{
      ContainerPort = 8080
      HostPort      = 8080
      Name          = "http"
    }]
    Environment = [{
      Name  = "TABLE_NAME"
      Value = aws_dynamodb_table.dynamo_table.name
      }, {
      Name  = "TABLE_INDEX_NAME"
      Value = "id"
    }]
  }])
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution_iam_role.arn
  depends_on         = [aws_instance.bastion_ec2]
}
resource "aws_ecs_task_definition" "stress_ecs_task_definition" {
  family = "user-taskdef"
  cpu    = "512"
  memory = "1024"
  container_definitions = jsonencode([{
    Name      = "golang"
    Image     = aws_ecr_repository.stress_ecr.repository_url
    Essential = true
    HealthCheck = {
      Command  = ["CMD-SHELL", "curl -f http://localhost:8080/healthcheck || exit 1"]
      Interval = 30
      Retries  = 5
      Timeout  = 5
    }
    PortMappings = [{
      ContainerPort = 8080
      HostPort      = 8080
      Name          = "http"
    }]
  }])
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution_iam_role.arn
  depends_on         = [aws_instance.bastion_ec2]
}
resource "aws_iam_role" "ecs_task_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role" "ecs_task_execution_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs-cluster"
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
}
resource "aws_ecs_capacity_provider" "ecs_ec2_capacity_provider" {
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    managed_draining       = "ENABLED"
    managed_scaling {
      instance_warmup_period    = 30
      maximum_scaling_step_size = 10000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
    managed_termination_protection = "DISABLED"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ecs-ec2-capacity-provider"
}
resource "aws_ecs_cluster_capacity_providers" "ecs_ec2_capacity_provider_association" {
  capacity_providers = [aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id, "FARGATE", "FARGATE_SPOT"]
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  default_capacity_provider_strategy {
    base              = 0
    capacity_provider = aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id
    weight            = 100
  }
}
resource "aws_autoscaling_group" "ecs_asg" {
  min_size            = 3
  desired_capacity    = 3
  max_size            = 3
  vpc_zone_identifier = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = aws_launch_template.ecs_lt.latest_version
  }
  availability_zone_distribution {
    capacity_distribution_strategy = "balanced-only"
  }
  depends_on = [aws_ecs_cluster.ecs_cluster]
}
resource "aws_launch_template" "ecs_lt" {
  image_id      = data.aws_ssm_parameter.ecs_ami_id.insecure_value
  instance_type = "t3.medium"
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_container_instance_profile.name
  }
  vpc_security_group_ids = [aws_security_group.ecs_container_instance_security_group.id]
  user_data = base64encode(<<EOT
#!/bin/bash -xe
echo ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name} >> /etc/ecs/ecs.config
dnf install -y aws-cfn-bootstrap
EOT
  )
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  key_name = aws_key_pair.key_pair.key_name
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ecs-container-instance"
    }
  }
}
resource "aws_security_group" "ecs_container_instance_security_group" {
  description = "Security Group"
  name        = "ecs-container-instance-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_iam_role" "ecs_container_instance_iam_role" {
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
resource "aws_iam_instance_profile" "ecs_container_instance_profile" {
  # Single role name string, not a list (rules.md A-3).
  role = aws_iam_role.ecs_container_instance_iam_role.name
}
resource "aws_ecs_service" "user_ecs_service" {
  name            = "user-service"
  cluster         = aws_ecs_cluster.ecs_cluster.name
  launch_type     = "EC2"
  desired_count   = 1
  task_definition = aws_ecs_task_definition.user_ecs_task_definition.arn
  network_configuration {
    subnets         = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_groups = [aws_security_group.ecs_service_security_group.id]
  }
}
resource "aws_ecs_service" "product_ecs_service" {
  name            = "product-service"
  cluster         = aws_ecs_cluster.ecs_cluster.name
  launch_type     = "EC2"
  desired_count   = 1
  task_definition = aws_ecs_task_definition.product_ecs_task_definition.arn
  network_configuration {
    subnets         = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_groups = [aws_security_group.ecs_service_security_group.id]
  }
}
resource "aws_ecs_service" "stress_ecs_service" {
  name            = "stress-service"
  cluster         = aws_ecs_cluster.ecs_cluster.name
  launch_type     = "EC2"
  desired_count   = 1
  task_definition = aws_ecs_task_definition.stress_ecs_task_definition.arn
  network_configuration {
    subnets         = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_groups = [aws_security_group.ecs_service_security_group.id]
  }
}
resource "aws_security_group" "ecs_service_security_group" {
  description = "Security Group"
  name        = "ecs-service-sg"
  ingress {
    protocol    = -1
    cidr_blocks = [aws_vpc.vpc.cidr_block]
    from_port   = 0
    to_port     = 0
  }
  ingress {
    protocol        = "TCP"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.bastion_ec2_security_group.id]
  }
  vpc_id = aws_vpc.vpc.id
}
