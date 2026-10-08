# Generated from 102_windows_rdp/spirit_of_kiro.yaml by tools/cfn2tf.
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
  default     = "spirit-of-kiro"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "username" {
  type    = string
  default = "kiro"
}
variable "git_clone_url" {
  type    = string
  default = "https://github.com/iamhansko/spirit-of-kiro.git"
}
variable "git_clone_branch" {
  type    = string
  default = "challenge"
}
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
  default     = "/aws/service/ami-windows-latest/Windows_Server-2025-Korean-Full-Base"
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
resource "aws_iam_role_policy_attachment" "windows_ec2_iam_role" {
  role       = aws_iam_role.windows_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# The original template carried a SecretPlaintextLambda custom resource here
# (IAM role + inline policy + AWSLambdaBasicExecutionRole + archive_file +
# aws_lambda_function + aws_lambda_invocation) whose only job was to read the
# generated password back out of Secrets Manager, because CloudFormation has no
# way to resolve a secret's value into an output. Terraform does not need any of
# it - the password is generated here by random_password, so its value is in
# state already and the 03Password output reads it directly.
#
# Do not reinstate it. Two things were wrong with the converted form, and only
# the first one produced an error message:
#
#   1. index.py imported cfnresponse, which AWS injects into the runtime only
#      for functions whose code CloudFormation inlined via ZipFile. Code shipped
#      as a zip - which is what archive_file produces - has no such module, so
#      every invocation failed with
#      "Unable to import module 'index': No module named 'cfnresponse'".
#   2. Even with that module vendored in, the handler speaks the CloudFormation
#      custom resource protocol: it reads event['RequestType'] and
#      event['ResourceProperties'], and returns its payload by POSTing to the
#      presigned event['ResponseURL'] rather than by returning it.
#      aws_lambda_invocation does a synchronous RequestResponse invoke and reads
#      the returned payload, and the input it sent was a flat
#      {ServiceTimeout, SecretArn} object. So the handler would have raised
#      KeyError on 'RequestType' and the invocation's result would have been
#      null - jsondecode("null")["password"] fails.
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
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "public-rt"
  }
  vpc_id = aws_vpc.vpc.id
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
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
  depends_on             = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "windows_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "m5.2xlarge"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "windows"
  }
  iam_instance_profile        = aws_iam_instance_profile.windows_ec2_instance_profile.name
  user_data                   = <<EOT
<powershell>
# Kiro Workshop Windows Setup - Simplified
$ErrorActionPreference = "Continue"
$ProgressPreference = 'SilentlyContinue'
$LogFile = "C:\ProgramData\KiroWorkshop\setup.log"
New-Item -ItemType Directory -Path "C:\ProgramData\KiroWorkshop" -Force

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage -ErrorAction SilentlyContinue
}

Write-Log "Starting Kiro Workshop Windows Setup"

try {
    # Get region and password
    $Token = Invoke-RestMethod -Uri "http://169.254.169.254/latest/api/token" -Method PUT -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -TimeoutSec 30
    $Region = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/placement/region" -Headers @{"X-aws-ec2-metadata-token" = $Token} -TimeoutSec 30
    Write-Log "Region: $Region"

    # Install AWS PowerShell module
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
    Install-Module -Name AWS.Tools.SecretsManager -Force -AllowClobber -Scope AllUsers
    Import-Module AWS.Tools.SecretsManager -Force
    Set-DefaultAWSRegion -Region $Region

    $SecretValue = Get-SECSecretValue -SecretId ${aws_secretsmanager_secret.windows_user_password.id} -Region $Region
    $WorkshopPassword = ($SecretValue.SecretString | ConvertFrom-Json).password
    Write-Log "Password retrieved"

    # Enable RDP - Minimal configuration
    Write-Log "Configuring RDP..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
    Set-Service -Name "TermService" -StartupType Automatic
    Start-Service -Name "TermService" -ErrorAction SilentlyContinue
    netsh advfirewall firewall set rule group="Remote Desktop" new enable=yes

    # Create workshop user
    Write-Log "Creating workshop user..."
    Remove-LocalUser -Name "${var.username}" -ErrorAction SilentlyContinue
    $Password = ConvertTo-SecureString $WorkshopPassword -AsPlainText -Force
    $User = New-LocalUser -Name "${var.username}" -Password $Password -FullName "Workshop User" -PasswordNeverExpires -AccountNeverExpires
    Add-LocalGroupMember -Group "Administrators" -Member "${var.username}" -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member "${var.username}" -ErrorAction SilentlyContinue

    # Setup directories - Enhanced domain handling
    Write-Log "Finding workshop user profile..."
    $UserProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object {
        $_.LocalPath -like "*${var.username}*" -and
        $_.LocalPath -notlike "*.bak" -and
        $_.LocalPath -notlike "*temp*"
    }

    if ($UserProfiles) {
        # Find workshop.ComputerName pattern specifically
        $ComputerName = $env:COMPUTERNAME
        $PreferredPattern = "${var.username}.$ComputerName"

        $PreferredProfile = $UserProfiles | Where-Object {$_.LocalPath -like "*$PreferredPattern*" -and $_.LocalPath -notlike "*.000" -and $_.LocalPath -notlike "*.001"}

        if ($PreferredProfile) {
            $UserProfilePath = $PreferredProfile[0].LocalPath
            Write-Log "Selected preferred profile: $UserProfilePath"
        } else {
            # Fallback to shortest path
            $UserProfilePath = ($UserProfiles.LocalPath | Sort-Object Length)[0]
            Write-Log "Selected fallback profile: $UserProfilePath"
        }

        # Log all found profiles for debugging
        foreach ($profile in $UserProfiles) {
            Write-Log "Found ${var.username} profile: $($profile.LocalPath)"
        }
    } else {
        # Deterministically construct workshop.ComputerName path
        $ComputerName = $env:COMPUTERNAME
        $UserProfilePath = "C:\Users\${var.username}.$ComputerName"
        Write-Log "Using constructed path: $UserProfilePath"
    }

    $WorkshopDir = "C:\ProgramData\KiroWorkshop"
    $TempDir = "$WorkshopDir\temp"
    New-Item -ItemType Directory -Path $TempDir -Force

    # Install Chocolatey FIRST
    Write-Log "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Install development tools via Chocolatey
    Write-Log "Installing Git..."
    choco install git -y

    Write-Log "Installing AWS CLI..."
    choco install awscli -y

    Write-Log "Installing Node.js..."
    choco install nodejs-lts --version="22.19.0" -y

    Write-Log "Installing Python 3.13"
    choco install python313 -y

    # Refresh environment variables after installations
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    python --version
    Set-Location $TempDir
    python -m venv .venv
    .\.venv\Scripts\activate
    python -m pip install boto3 requests requests_aws4auth
    echo "import json
    import os
    import boto3
    import requests
    from requests_aws4auth import AWS4Auth
    if __name__ == '__main__':
      session = boto3.Session()
      credentials = session.get_credentials()
      result = {
        "access_key": credentials.access_key,
        "secret_key": credentials.secret_key,
        "token": credentials.token
      }
      print(json.dumps(result))" > init.py
    # $PYTHON_RESULT = python init.py | ConvertFrom-Json
    deactivate

    # Clone project AFTER Git is installed
    Write-Log "Cloning Spirit of Kiro project..."
    $GitUrl = "${var.git_clone_url}"
    $GitBranch = "${var.git_clone_branch}"
    Write-Log "Git URL: $GitUrl, Branch: $GitBranch"

    # Wait for git to be available in PATH
    $maxRetries = 10
    $retryCount = 0
    do {
        Start-Sleep -Seconds 3
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $gitAvailable = Get-Command git -ErrorAction SilentlyContinue
        $retryCount++
    } while (-not $gitAvailable -and $retryCount -lt $maxRetries)

    if ($gitAvailable) {
        Set-Location $WorkshopDir
        git clone --branch $GitBranch $GitUrl $GitBranch
        Write-Log "Git clone completed"

        # Navigate to cloned project directory and run setup commands
        Set-Location "$WorkshopDir\$GitBranch"
        Write-Log "Running project setup commands..."

        # Install Bun and run npm commands
        irm bun.sh/install.ps1 | iex
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        Write-Log "Project setup completed"
        Set-Location "$WorkshopDir\${var.git_clone_branch}\server"
        npm cache clean --force
        bun install
        Set-Location "$WorkshopDir\${var.git_clone_branch}\client"
        npm cache clean --force
        bun install

        @'
Set-Location C:\ProgramData\KiroWorkshop\${var.git_clone_branch}\server
$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
  irm bun.sh/install.ps1 | iex
  $Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}
npm cache clean --force
bun install
$Env:AWS_REGION="${data.aws_region.current.region}"
$Env:COGNITO_USER_POOL_ID="${aws_cognito_user_pool.user_pool.id}"
$Env:COGNITO_CLIENT_ID="${aws_cognito_user_pool_client.user_pool_client.id}"
$Env:COGNITO_USER_POOL_ARN="${aws_cognito_user_pool.user_pool.arn}"
$Env:ITEM_IMAGES_SERVICE_URL="https://d16sw0kh78rbrs.cloudfront.net"
$Env:DYNAMODB_TABLE_ITEMS="${aws_dynamodb_table.items_table.name}"
$Env:DYNAMODB_TABLE_INVENTORY="${aws_dynamodb_table.inventory_table.name}"
$Env:DYNAMODB_TABLE_LOCATION="${aws_dynamodb_table.location_table.name}"
$Env:DYNAMODB_TABLE_USERS="${aws_dynamodb_table.users_table.name}"
$Env:DYNAMODB_TABLE_USERNAMES="${aws_dynamodb_table.usernames_table.name}"
$Env:DYNAMODB_TABLE_PERSONA="${aws_dynamodb_table.persona_table.name}"
bun --watch server.ts
'@ | Out-File -FilePath "C:\ProgramData\KiroWorkshop\temp\server.ps1"

        @'
Set-Location C:\ProgramData\KiroWorkshop\${var.git_clone_branch}\client
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
  irm bun.sh/install.ps1 | iex
  $Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}
$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
npm cache clean --force
bun install
$Env:VITE_WS_URL="http://localhost:8080/"
bun run dev
'@ | Out-File -FilePath "C:\ProgramData\KiroWorkshop\temp\client.ps1"
    } else {
        Write-Log "Git not available, skipping clone"
    }

    # Verify installations
    Write-Log "Verifying installations..."
    try {
        $gitVersion = git --version
        Write-Log "Git installed: $gitVersion"
    } catch {
        Write-Log "Git verification failed"
    }

    try {
        $awsVersion = aws --version
        Write-Log "AWS CLI installed: $awsVersion"
    } catch {
        Write-Log "AWS CLI verification failed"
    }

    try {
        $nodeVersion = node --version
        Write-Log "Node.js installed: $nodeVersion"
    } catch {
        Write-Log "Node.js verification failed"
    }

    # Set permissions
    icacls $WorkshopDir /grant "${var.username}:F" /T /Q
    if (Test-Path $UserProfilePath) {
        icacls "$UserProfilePath" /grant "${var.username}:F" /T /Q
    }

    # Create logon script for workshop user (runs after first login)
    Write-Log "Creating workshop user logon script..."
    $LogonScript = '# Workshop User First Logon Setup' + "`n"
    $LogonScript += '$LogFile = "C:\ProgramData\KiroWorkshop\logon.log"' + "`n"
    $LogonScript += 'function Write-LogonLog { param([string]$Message); Add-Content -Path $LogFile -Value "[$((Get-Date))] $Message" }' + "`n"
    $LogonScript += 'Write-LogonLog "Workshop user first logon setup started"' + "`n"
    $LogonScript += '$DesktopPath = [Environment]::GetFolderPath("Desktop")' + "`n"
    $LogonScript += 'Write-LogonLog "Desktop path: $DesktopPath"' + "`n"
    $LogonScript += '$WshShell = New-Object -comObject WScript.Shell' + "`n"
    $LogonScript += 'if (Test-Path "C:\ProgramData\Kiro\Kiro.exe") {' + "`n"
    $LogonScript += '    $KiroShortcut = $WshShell.CreateShortcut("$DesktopPath\Kiro IDE.lnk")' + "`n"
    $LogonScript += '    $KiroShortcut.TargetPath = "C:\ProgramData\Kiro\Kiro.exe"' + "`n"
    $LogonScript += '    $KiroShortcut.WorkingDirectory = "C:\ProgramData\Kiro"' + "`n"
    $LogonScript += '    $KiroShortcut.Save()' + "`n"
    $LogonScript += '    Write-LogonLog "Kiro IDE shortcut created"' + "`n"
    $LogonScript += '}' + "`n"
    $LogonScript += 'if (Test-Path "C:\ProgramData\KiroWorkshop\${var.git_clone_branch}") {' + "`n"
    $LogonScript += '    $ProjectShortcut = $WshShell.CreateShortcut("$DesktopPath\Workshop Project.lnk")' + "`n"
    $LogonScript += '    $ProjectShortcut.TargetPath = "C:\ProgramData\KiroWorkshop\${var.git_clone_branch}"' + "`n"
    $LogonScript += '    $ProjectShortcut.Save()' + "`n"
    $LogonScript += '    Write-LogonLog "Project shortcut created"' + "`n"
    $LogonScript += '}' + "`n"
    $LogonScript += 'if (Test-Path "C:\ProgramData\KiroWorkshop\temp\server.ps1") {' + "`n"
    $LogonScript += '    $ServerShortcut = $WshShell.CreateShortcut("$DesktopPath\01 GameServer.lnk")' + "`n"
    $LogonScript += '    $ServerShortcut.TargetPath = "powershell.exe"' + "`n"
    $LogonScript += '    $ServerShortcut.Arguments = "-ExecutionPolicy Bypass -NoExit -File C:\ProgramData\KiroWorkshop\temp\server.ps1"' + "`n"
    $LogonScript += '    $ServerShortcut.Save()' + "`n"
    $LogonScript += '    $ServerShortcutBytes = [System.IO.File]::ReadAllBytes("$DesktopPath\01 GameServer.lnk")' + "`n"
    $LogonScript += '    $ServerShortcutBytes[0x15] = $ServerShortcutBytes[0x15] -bor 0x20' + "`n"
    $LogonScript += '    [System.IO.File]::WriteAllBytes("$DesktopPath\01 GameServer.lnk", $ServerShortcutBytes)' + "`n"
    $LogonScript += '    Write-LogonLog "Game Server shortcut created"' + "`n"
    $LogonScript += '}' + "`n"
    $LogonScript += 'if (Test-Path "C:\ProgramData\KiroWorkshop\temp\client.ps1") {' + "`n"
    $LogonScript += '    $ClientShortcut = $WshShell.CreateShortcut("$DesktopPath\02 GameClient.lnk")' + "`n"
    $LogonScript += '    $ClientShortcut.TargetPath = "powershell.exe"' + "`n"
    $LogonScript += '    $ClientShortcut.Arguments = "-ExecutionPolicy Bypass -NoExit -File C:\ProgramData\KiroWorkshop\temp\client.ps1"' + "`n"
    $LogonScript += '    $ClientShortcut.Save()' + "`n"
    $LogonScript += '    $ClientShortcutBytes = [System.IO.File]::ReadAllBytes("$DesktopPath\02 GameClient.lnk")' + "`n"
    $LogonScript += '    $ClientShortcutBytes[0x15] = $ClientShortcutBytes[0x15] -bor 0x20' + "`n"
    $LogonScript += '    [System.IO.File]::WriteAllBytes("$DesktopPath\02 GameClient.lnk", $ClientShortcutBytes)' + "`n"
    $LogonScript += '    Write-LogonLog "Game Client shortcut created"' + "`n"
    $LogonScript += '}' + "`n"
    $LogonScript += 'Write-LogonLog "Workshop user setup completed"' + "`n"
    $LogonScript += 'Remove-Item $MyInvocation.MyCommand.Path -Force' + "`n"

    $LogonScriptPath = "C:\ProgramData\KiroWorkshop\${var.username}-setup.ps1"
    Set-Content -Path $LogonScriptPath -Value $LogonScript

    # Set logon script in registry for workshop user
    $LogonKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $LogonKey -Name "WorkshopSetup" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$LogonScriptPath`"" -Force

    # Install Kiro IDE - Minimal approach
    Write-Log "Installing Kiro IDE..."
    $KiroUrl = "https://prod.download.desktop.kiro.dev/releases/stable/win32-x64/signed/0.7.45/kiro-ide-0.7.45-stable-win32-x64.exe"
    $KiroInstaller = "$TempDir\kiro-installer.exe"
    Invoke-WebRequest -Uri $KiroUrl -OutFile $KiroInstaller -TimeoutSec 300
    $proc = Start-Process $KiroInstaller -ArgumentList "/VERYSILENT", "/NORESTART" -PassThru
    Wait-Process -Id $proc.Id
    Get-Process | Where-Object {$_.ParentProcessId -eq $proc.Id} | Stop-Process -Force -ErrorAction SilentlyContinue

    # Move Kiro from Administrator AppData to ProgramData
    Write-Log "Configuring Kiro IDE for workshop user..."
    $KiroInstallDir = "C:\Users\Administrator\AppData\Local\Programs\Kiro"
    $ProgramDataKiroPath = "C:\ProgramData\Kiro"
    if (Test-Path $KiroInstallDir) {
        robocopy "$KiroInstallDir" "$ProgramDataKiroPath" /E /R:1 /W:1 /NP
        icacls "$ProgramDataKiroPath" /grant "${var.username}:F" /T /Q
    }
} catch {
    Write-Log "Setup failed: $($_.Exception.Message)"
    cfn-signal --success false --stack ${var.stack_name} --resource WindowsEc2 --region ${data.aws_region.current.region}
    throw
}

cfn-signal --success true --stack ${var.stack_name} --resource WindowsEc2 --region ${data.aws_region.current.region}
shutdown /r /t 5 /c "Kiro Workshop setup completed"
</powershell>
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.windows_ec2_security_group.id]
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = false
  }
  # Everything this userdata needs at boot is reached through a value reference
  # that stops short of the thing that actually has to be ready, so each one is
  # named explicitly (rules.md D-1).
  #
  #   - The secret is referenced as ...secret.windows_user_password.id, which
  #     orders this instance after the empty container rather than after the
  #     version holding the password. Boot first and Get-SECSecretValue raises
  #     ResourceNotFoundException.
  #   - The security group is referenced as ...security_group.id, which orders
  #     this instance after the group but not after its rules. The group is
  #     created with no rules at all, so booting before the egress rule exists
  #     means no outbound path for the PowerShell Gallery, Secrets Manager or
  #     GitHub.
  #
  # Both failures land inside the userdata's try block, so apply reports the
  # instance as created either way and the only symptom is RDP rejecting the
  # credentials this stack outputs.
  depends_on = [
    aws_secretsmanager_secret_version.windows_user_password,
    aws_vpc_security_group_egress_rule.windows_ec2_egress,
    aws_vpc_security_group_ingress_rule.windows_ec2_rdp_ingress,
  ]
}
resource "aws_security_group" "windows_ec2_security_group" {
  description = "Security Group"
  name        = "windows-sg"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = "windows-sg"
  }
}
# Standalone rule resources rather than the inline dynamic "ingress" the
# conversion produced, because inline ingress/egress blocks are authoritative
# over the group's entire rule set (rules.md F-2).
#
# That authority is what broke RDP. The template's AWS::EC2::SecurityGroup
# declared SecurityGroupIngress and no SecurityGroupEgress, which in
# CloudFormation leaves the allow-all egress rule EC2 puts on every new group.
# Converted to an inline block, the same shape means the opposite: Terraform
# owns the whole group, sees no egress declared, and deletes that default rule.
# The group came out with "Egress": [] and the instance had no outbound path at
# all - so Install-PackageProvider, Install-Module, Get-SECSecretValue and the
# git clone in the userdata all failed, New-LocalUser never ran, and the kiro
# account did not exist. Port 3389 still answered, because Windows Server has
# RDP on by default and the ingress rule was fine, so the only symptom was a
# login prompt rejecting correct-looking credentials. It also kept SSM Agent
# from registering, which is why the instance was not reachable to diagnose.
resource "aws_vpc_security_group_ingress_rule" "windows_ec2_rdp_ingress" {
  count = local.cond_security_group_inbound_from_anywhere ? 1 : 0

  security_group_id = aws_security_group.windows_ec2_security_group.id
  description       = "RDP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 3389
  to_port           = 3389
  cidr_ipv4         = "0.0.0.0/0"
}
# Restores what CloudFormation left in place implicitly. The userdata needs
# outbound HTTPS to the PowerShell Gallery, Secrets Manager, GitHub and the SSM
# endpoints, and this is also what lets SSM Agent register the instance.
resource "aws_vpc_security_group_egress_rule" "windows_ec2_egress" {
  security_group_id = aws_security_group.windows_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "windows_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "windows_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.windows_ec2_iam_role.name
}
resource "aws_secretsmanager_secret" "windows_user_password" {
  # GenerateSecretString has no Terraform equivalent: aws_secretsmanager_secret
  # only declares the container, and asking Secrets Manager to invent the value
  # would put it somewhere Terraform cannot read. The generation moves to
  # random_password below and the value is written as a secret version, which
  # reproduces what the template's GenerateSecretString block asked for.
  #
  # Leaving it unmapped did not fail anything that reported an error. The secret
  # was created with zero versions, so the instance's Get-SECSecretValue call
  # raised ResourceNotFoundException inside the userdata's try block - the
  # workshop user was never created and RDP had no password, while apply had
  # already reported success for the instance.

  # Demo teardown: without this, destroy only schedules deletion and the secret
  # lingers for 30 days.
  recovery_window_in_days = 0
}
# PasswordLength: 20, RequireEachIncludedType: true, ExcludeCharacters: "@/\ and
# IncludeSpace: false, carried over from the template's GenerateSecretString.
# override_special is Secrets Manager's default punctuation set with those four
# characters removed; space is absent from it, which is what IncludeSpace: false
# means. The min_* values are RequireEachIncludedType.
resource "random_password" "windows_user_password" {
  length           = 20
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#$%&'()*+,-.:;<=>?[]^_`{|}~"
}
# SecretStringTemplate {"username": "<Username>"} with the generated value under
# GenerateStringKey "password". The instance's userdata parses this shape:
# (Get-SECSecretValue ... | ConvertFrom-Json).password.
resource "aws_secretsmanager_secret_version" "windows_user_password" {
  secret_id = aws_secretsmanager_secret.windows_user_password.id
  secret_string = jsonencode({
    username = var.username
    password = random_password.windows_user_password.result
  })
}
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
  schema {
    name                = "preferred_username"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
  username_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }
  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }
}
resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id                  = aws_cognito_user_pool.user_pool.id
  name                          = "${var.stack_name}-client"
  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows           = ["USER_PASSWORD_AUTH"]
  access_token_validity         = 1
  id_token_validity             = 1
  refresh_token_validity        = 30
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}
resource "aws_dynamodb_table" "items_table" {
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "id"
    type = "S"
  }
  hash_key = "id"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-items-table"
}
resource "aws_dynamodb_table" "inventory_table" {
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "id"
    type = "S"
  }
  attribute {
    name = "itemId"
    type = "S"
  }
  hash_key  = "id"
  range_key = "itemId"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-inventory-table"
}
resource "aws_dynamodb_table" "location_table" {
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "itemId"
    type = "S"
  }
  attribute {
    name = "location"
    type = "S"
  }
  hash_key  = "itemId"
  range_key = "location"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-location-table"
}
resource "aws_dynamodb_table" "users_table" {
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "userId"
    type = "S"
  }
  hash_key = "userId"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-users-table"
}
resource "aws_dynamodb_table" "usernames_table" {
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "username"
    type = "S"
  }
  hash_key = "username"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-usernames-table"
}
resource "aws_dynamodb_table" "persona_table" {
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "detail"
    type = "S"
  }
  hash_key  = "userId"
  range_key = "detail"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-persona-table"
}
# --- Outputs ---
# CloudFormation output: 01RdpUrl
output "out_01_rdp_url" {
  value = "${aws_instance.windows_ec2.public_ip}:3389"
}
# CloudFormation output: 02Username
output "out_02_username" {
  value = var.username
}
# CloudFormation output: 03Password
# Printed in the clear, the way the CloudFormation stack's 03Password output was
# - this is the RDP password a workshop participant has to be able to read off
# the end of apply.
#
# nonsensitive() is required, not cosmetic: random_password.result carries a
# sensitive mark, and an output holding a marked value must either declare
# sensitive = true or strip the mark, or Terraform rejects the configuration
# with "Output refers to sensitive values". Stripping it here is deliberate and
# the narrowest way to do it - the mark stays on secret_string below, so the
# password does not turn up in plan diffs, only in this one output.
#
# What that costs: the value lands in the apply summary, terminal scrollback and
# any CI log that captures them. That is accepted for a demo stack whose whole
# point is handing this password to a person, and it is not where the exposure
# starts anyway - terraform.tfstate holds it in plaintext regardless. Do not
# copy this into anything with a real credential.
output "out_03_password" {
  value = nonsensitive(random_password.windows_user_password.result)
}
