resource "aws_security_group" "windows_ec2" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than the inline dynamic "ingress" block the
# _monolithic template had (rules.md F-2), and an explicit egress rule it did not
# have - the defect that broke RDP login on 101_ubuntu_xrdp.
#
# The CloudFormation group named one ingress rule and no SecurityGroupEgress,
# and kept EC2's default allow-all egress. The converted group had none:
# aws_security_group revokes that default rule right after it creates any VPC
# group, whatever the configuration contains (the provider's NOTE on egress
# rules; internal/service/ec2/vpc_security_group.go). The inline ingress block
# is not what removed it - with inbound_from_anywhere "False" and no block at
# all, the result was the same. Either way the instance had no outbound path.
#
# Every step of the setup is outbound and none of it reports failure: the
# PowerShell Gallery, Secrets Manager, Chocolatey, GitHub and S3 all fail inside
# the try block with ErrorActionPreference Continue. No workshop account, no
# clone, no server.zip, no Lambda/code.zip - and SSM Agent cannot register
# either, so the association that waits on the upload never even starts.
resource "aws_vpc_security_group_ingress_rule" "rdp" {
  # toset is safe: the CIDRs are literals in configuration (rules.md B-8).
  for_each = toset(var.rdp_ingress_cidr_blocks)

  security_group_id = aws_security_group.windows_ec2.id
  description       = "RDP from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.rdp_port
  to_port           = var.rdp_port
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.windows_ec2.id
  description       = "All outbound, the default the CloudFormation group kept"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "windows_ec2" {
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
# for_each over the ARN list (rules.md B-7); literal ARNs, so toset is safe
# (rules.md B-8). See the variable for why AdministratorAccess stays.
resource "aws_iam_role_policy_attachment" "windows_ec2" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.windows_ec2.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "windows_ec2" {
  # One role name string, not the list CloudFormation's InstanceProfile Roles
  # property takes; the conversion already had this right (rules.md A-3).
  role = aws_iam_role.windows_ec2.name
}
# ---------------------------------------------------------------------------
# The setup script, reproduced from the _monolithic template's <powershell>
# block. Explanations live here rather than inside the heredoc, because EC2
# caps user data at 16 KB and a comment in the template is paid for in that
# budget; user_data_byte_length is an output and the precondition on the
# instance turns the limit into a plan error.
#
# What it does, in order. Everything runs as SYSTEM under EC2Launch, inside one
# try block, with ErrorActionPreference Continue - so a failing cmdlet or a
# non-zero native command (choco, git, aws) does not stop the script and does
# not reach the catch. Only a terminating error does.
#
#    1. NuGet provider and AWS.Tools.SecretsManager from the PowerShell Gallery,
#       then Get-SECSecretValue for the workshop password.
#    2. netsh: the dynamic port range to 49152-60000.
#    3. RDP on, TermService started, the Remote Desktop firewall group enabled.
#    4. The workshop account, in Administrators and Remote Desktop Users.
#    5. Profile path discovery and the workshop directory.
#    6. Chocolatey, then git, the AWS CLI and Python 3.14 from it, then a PATH
#       refresh and an `aws --version` check.
#    7. A wait for git on PATH, then the clone.
#    8. The server's config.ini (SQS region and URL, fleet role ARN), server.zip,
#       and its upload.
#    9. The whole clone to the game source bucket - which is the only way
#       Lambda/code.zip reaches S3 - then main.js patched and the web folder to
#       the website bucket.
#   10. Both clients' config.ini (API URL, player name and password), client.zip
#       and its upload.
#   11. The first-logon script that puts two client shortcuts on the desktop,
#       registered under HKLM Run.
#
# The AWS CLI is installed by the script itself (step 6), so nothing that uses
# it can run earlier. The root's association polls S3 with the same CLI and is
# ordered by the marker, which is written after step 11 - by then the CLI is
# on the machine PATH. It refreshes PATH itself, because SSM Agent's process
# environment predates the install.
#
# What differs from the conversion:
#
#   - No cfn-signal, in the catch block or at the end. There is no stack, and
#     the CreationPolicy that consumed the signal was already dropped. The
#     signal is the marker file now: written as the very last action of the
#     script, so its existence means every step above has returned. The catch
#     block writes the failure marker with the error instead, so the waiting
#     association can fail with the reason rather than time out.
#   - The secret id is quoted. A Secrets Manager ARN is full of colons, which
#     PowerShell can read as a parameter separator in some positions; the RDP
#     credential depends on this one call parsing.
#   - foreach ($UserProfile ...) rather than foreach ($profile ...). $profile is
#     a PowerShell automatic variable and the loop was overwriting it.
#   - The clone directory is named explicitly and every path built from one
#     variable, where the template hard-coded aws-gamelift-sample in a dozen
#     places and let git choose the name from the URL.
#   - main.js gets its /prod/ rewritten to the stage name as well as the API id
#     and region, so api_stage_name is a real variable and not one the page
#     ignores.
#   - The region is the module's input rather than data.aws_region interpolated
#     at each use.
#
# Reproduced and worth knowing, not fixed:
#
#   - Step 2 is on the wrong machine. Its comment (the template's) is right
#     that a GameLift Windows fleet accepts ports only up to 60000 while
#     Windows hands out ephemeral ports up to 65535 - but GomokuServer.exe is
#     launched with no port argument, so it is the fleet instances' ephemeral
#     range that matters, and this script runs on the participant's desktop.
#     The fix would be an install.bat in server.zip, which GameLift runs on
#     each fleet instance; that changes the build and has not been tried.
#   - The whole clone is uploaded, .git included, which is most of the time
#     the association waits. Narrowing it to Lambda/ would change what lands
#     in the bucket.
#   - The first-logon script is registered under HKLM, so whoever logs in first
#     gets the shortcuts and deletes the script. Log in as Administrator first
#     and the workshop account's desktop comes up empty.
#
# How the indentation works: this is an indented heredoc, so Terraform strips
# the smallest indentation across its non-blank lines - four spaces. Lines that
# PowerShell needs at column zero - the body and the closing '@ of every @'...'@
# here-string - are therefore written at exactly four. A closing '@ with
# anything before it does not close, and the here-string swallows the rest of
# the script (the same failure as the CRLF case in rules.md A-4). There are no
# %{ } directives for the same reason 102_windows_rdp avoids them: a strip
# marker leaves the following line with its source indentation.
# ---------------------------------------------------------------------------
locals {
  user_data_max_bytes = 16384

  clone_dir           = "${var.workshop_dir}\\${var.clone_directory_name}"
  marker_file         = "${var.workshop_dir}\\${var.marker_file_name}"
  failure_marker_file = "${var.workshop_dir}\\${var.failure_marker_file_name}"
  setup_log_file      = "${var.workshop_dir}\\setup.log"

  # Built from the API id and the stage name rather than taken from the stage's
  # invoke_url: the stage cannot exist until the functions do, and they wait
  # for this instance to upload their code.
  api_base_url = "https://${var.rest_api_id}.execute-api.${var.aws_region}.amazonaws.com/${var.api_stage_name}"

  user_data = <<-EOT
    <powershell>
    $ErrorActionPreference = "Continue"
    $ProgressPreference = "SilentlyContinue"
    $LogFile = "${local.setup_log_file}"
    New-Item -ItemType Directory -Path "${var.workshop_dir}" -Force

    function Write-Log {
        param([string]$Message)
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogMessage = "[$Timestamp] $Message"
        Write-Host $LogMessage
        Add-Content -Path $LogFile -Value $LogMessage -ErrorAction SilentlyContinue
    }

    Write-Log "Starting Gamelift Workshop Windows Setup"

    try {
        # Install AWS PowerShell Module
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
        Install-Module -Name AWS.Tools.SecretsManager -Force -AllowClobber -Scope AllUsers
        Import-Module AWS.Tools.SecretsManager -Force
        Set-DefaultAWSRegion -Region ${var.aws_region}

        $SecretValue = Get-SECSecretValue -SecretId "${var.secret_id}" -Region ${var.aws_region}
        $WorkshopPassword = ($SecretValue.SecretString | ConvertFrom-Json).password
        Write-Log "Password Retrieved"

        # Restrict Windows dynamic (ephemeral) port range to match the GameLift Fleet's
        # EC2InboundPermissions (49152-60000). GameLift Windows fleets only support port
        # ranges up to 60000, but Windows Server's default ephemeral range extends to 65535.
        # Without this, GameLift server processes that bind to a port above 60000 will fail
        # ProcessReady() and exit (SERVER_PROCESS_CRASHED).
        Write-Log "Restricting dynamic port range to 49152-60000"
        netsh int ipv4 set dynamicport tcp start=49152 num=10849
        netsh int ipv6 set dynamicport tcp start=49152 num=10849

        # Enable RDP
        Write-Log "Configuring RDP"
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
        Set-Service -Name "TermService" -StartupType Automatic
        Start-Service -Name "TermService" -ErrorAction SilentlyContinue
        netsh advfirewall firewall set rule group="Remote Desktop" new enable=yes

        # Create Workshop User
        Write-Log "Creating Workshop User"
        Remove-LocalUser -Name "${var.workshop_username}" -ErrorAction SilentlyContinue
        $Password = ConvertTo-SecureString $WorkshopPassword -AsPlainText -Force
        $User = New-LocalUser -Name "${var.workshop_username}" -Password $Password -FullName "Workshop User" -PasswordNeverExpires -AccountNeverExpires
        Add-LocalGroupMember -Group "Administrators" -Member "${var.workshop_username}" -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group "Remote Desktop Users" -Member "${var.workshop_username}" -ErrorAction SilentlyContinue

        # Setup Directories - Enhanced domain handling
        Write-Log "Finding Workshop User Profile"
        $UserProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object {
            $_.LocalPath -like "*${var.workshop_username}*" -and
            $_.LocalPath -notlike "*.bak" -and
            $_.LocalPath -notlike "*temp*"
        }

        if ($UserProfiles) {
            # Find workshop.ComputerName Pattern Specifically
            $ComputerName = $env:COMPUTERNAME
            $PreferredPattern = "${var.workshop_username}.$ComputerName"

            $PreferredProfile = $UserProfiles | Where-Object {$_.LocalPath -like "*$PreferredPattern*" -and $_.LocalPath -notlike "*.000" -and $_.LocalPath -notlike "*.001"}

            if ($PreferredProfile) {
                $UserProfilePath = $PreferredProfile[0].LocalPath
                Write-Log "Selected Preferred Profile: $UserProfilePath"
            } else {
                # Fallback to the shortest Path
                $UserProfilePath = ($UserProfiles.LocalPath | Sort-Object Length)[0]
                Write-Log "Selected Fallback Profile: $UserProfilePath"
            }

            # Log all found Profiles for Debugging
            foreach ($UserProfile in $UserProfiles) {
                Write-Log "Found ${var.workshop_username} Profile: $($UserProfile.LocalPath)"
            }
        } else {
            # Deterministically Construct workshop.ComputerName Path
            $ComputerName = $env:COMPUTERNAME
            $UserProfilePath = "C:\Users\${var.workshop_username}.$ComputerName"
            Write-Log "Using Constructed Path: $UserProfilePath"
        }

        $WorkshopDir = "${var.workshop_dir}"
        $CloneDir = "${local.clone_dir}"
        $TempDir = "$WorkshopDir\temp"
        New-Item -ItemType Directory -Path $TempDir -Force

        # Install Chocolatey
        Write-Log "Installing Chocolatey"
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        Write-Log "Installing Git"
        choco install git -y

        Write-Log "Installing AWS CLI"
        choco install awscli -y

        Write-Log "Installing Python 3.14"
        choco install python314 -y

        # Refresh Environment Variables after Installations
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        try {
            $awsVersion = aws --version
            Write-Log "AWS CLI Installed: $awsVersion"
        } catch {
            Write-Log "AWS CLI Verification Failed"
        }

        # Set Permissions
        icacls $WorkshopDir /grant "${var.workshop_username}:F" /T /Q
        if (Test-Path $UserProfilePath) {
            icacls "$UserProfilePath" /grant "${var.workshop_username}:F" /T /Q
        }

        $maxRetries = ${var.git_available_retries}
        $retryCount = 0
        do {
            Start-Sleep -Seconds 3
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            $gitAvailable = Get-Command git -ErrorAction SilentlyContinue
            $retryCount++
        } while (-not $gitAvailable -and $retryCount -lt $maxRetries)

        if ($gitAvailable) {
            $gitVersion = git --version
            Write-Log "Git installed: $gitVersion"
            Set-Location $WorkshopDir
            git clone ${var.git_clone_url} ${var.clone_directory_name}
        } else {
            Write-Log "Git Unavailable"
        }

        Set-Location $CloneDir
        @'
    [config]
    # GameResult SQS
    SQS_REGION = ${var.aws_region}
    SQS_ENDPOINT = ${var.game_result_queue_url}
    ROLE_ARN = ${var.fleet_role_arn}
    '@ | Out-File -FilePath $CloneDir\bin\FlexMatch\GomokuServer\Binaries\Win64\config.ini -Encoding ascii
        Set-Location $CloneDir\bin\FlexMatch\GomokuServer
        Compress-Archive -Path .\* -DestinationPath .\server.zip -Force
        aws s3 cp .\server.zip s3://${var.game_source_bucket_name}/${var.server_build_s3_key}
        Set-Location $CloneDir
        aws s3 cp --recursive $CloneDir s3://${var.game_source_bucket_name}

        (Get-Content $CloneDir\web\main.js) -replace 'niop6gw2v0', '${var.rest_api_id}' -replace 'us-east-1', '${var.aws_region}' -replace '/prod/', '/${var.api_stage_name}/' | Set-Content $CloneDir\web\main.js
        aws s3 cp --recursive $CloneDir\web\ s3://${var.web_bucket_name}

        Set-Location $CloneDir\bin\FlexMatch

        @'
    [config]
    MATCH_SERVER_API = ${local.api_base_url}
    PLAYER_NAME = ${var.game_client_player_names[0]}
    PLAYER_PASSWD = ${var.game_client_player_password}
    '@ | Out-File -FilePath $CloneDir\bin\FlexMatch\Client_player1\config.ini -Encoding ascii

        @'
    [config]
    MATCH_SERVER_API = ${local.api_base_url}
    PLAYER_NAME = ${var.game_client_player_names[1]}
    PLAYER_PASSWD = ${var.game_client_player_password}
    '@ | Out-File -FilePath $CloneDir\bin\FlexMatch\Client_player2\config.ini -Encoding ascii

        Compress-Archive -Path $CloneDir\bin\FlexMatch\Client_player1, $CloneDir\bin\FlexMatch\Client_player2 -DestinationPath "$CloneDir\client.zip" -Force
        aws s3 cp "$CloneDir\client.zip" s3://${var.game_source_bucket_name}/${var.client_archive_s3_key}

        Write-Log "Creating Workshop User Logon Script"
        $LogonScript = '# Workshop User First Logon Setup' + "`n"
        $LogonScript += '$LogFile = "${var.workshop_dir}\logon.log"' + "`n"
        $LogonScript += 'function Write-LogonLog { param([string]$Message); Add-Content -Path $LogFile -Value "[$((Get-Date))] $Message" }' + "`n"
        $LogonScript += '$DesktopPath = [Environment]::GetFolderPath("Desktop")' + "`n"
        $LogonScript += 'Write-LogonLog "Desktop path: $DesktopPath"' + "`n"
        $LogonScript += '$GameClientPath = "${local.clone_dir}\bin\FlexMatch"' + "`n"
        $LogonScript += '$WshShell = New-Object -comObject WScript.Shell' + "`n"
        $LogonScript += 'if (Test-Path "${local.clone_dir}\bin\FlexMatch\Client_player1") {' + "`n"
        $LogonScript += '    $GameClient1Shortcut = $WshShell.CreateShortcut("$DesktopPath\Game Client 1.lnk")' + "`n"
        $LogonScript += '    $GameClient1Shortcut.TargetPath = "$GameClientPath\Client_player1"' + "`n"
        $LogonScript += '    $GameClient1Shortcut.Save()' + "`n"
        $LogonScript += '    Write-LogonLog "Game Client 1 Shortcut Created"' + "`n"
        $LogonScript += '}' + "`n"
        $LogonScript += 'if (Test-Path "${local.clone_dir}\bin\FlexMatch\Client_player2") {' + "`n"
        $LogonScript += '    $GameClient2Shortcut = $WshShell.CreateShortcut("$DesktopPath\Game Client 2.lnk")' + "`n"
        $LogonScript += '    $GameClient2Shortcut.TargetPath = "$GameClientPath\Client_player2"' + "`n"
        $LogonScript += '    $GameClient2Shortcut.Save()' + "`n"
        $LogonScript += '    Write-LogonLog "Game Client 2 Shortcut Created"' + "`n"
        $LogonScript += '}' + "`n"
        $LogonScript += 'Write-LogonLog "Workshop User Setup Completed"' + "`n"
        $LogonScript += 'Remove-Item $MyInvocation.MyCommand.Path -Force' + "`n"

        $LogonScriptPath = "$WorkshopDir\${var.workshop_username}-setup.ps1"
        Set-Content -Path $LogonScriptPath -Value $LogonScript
        $LogonKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $LogonKey -Name "WorkshopSetup" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$LogonScriptPath`"" -Force
    } catch {
        Write-Log "Setup Failed: $($_.Exception.Message)"
        Set-Content -Path "${local.failure_marker_file}" -Value $_.Exception.Message
        throw
    }

    Write-Log "Setup Completed"
    New-Item -ItemType File -Path "${local.marker_file}" -Force | Out-Null
    </powershell>
    EOT
}
resource "aws_instance" "windows_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = [aws_security_group.windows_ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.windows_ec2.name
  user_data                   = local.user_data
  user_data_replace_on_change = var.user_data_replace_on_change

  tags = {
    Name = var.instance_name
  }
  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = var.root_volume_encrypted
  }

  # The group and profile references order this after the group and the role,
  # not after their contents (rules.md D-1). Booting before the egress rule
  # exists leaves every download in the setup failing; booting before the policy
  # attachment makes Get-SECSecretValue an AccessDenied. Both happen inside the
  # try block, so apply would report success either way.
  depends_on = [
    aws_vpc_security_group_egress_rule.all_outbound,
    aws_vpc_security_group_ingress_rule.rdp,
    aws_iam_role_policy_attachment.windows_ec2,
  ]

  lifecycle {
    # The 16 KB user data limit as a plan error rather than an
    # InvalidParameterValue partway through apply. length() counts characters;
    # the script is ASCII, so that is also bytes, unless a non-ASCII value is
    # interpolated into it.
    precondition {
      condition     = length(local.user_data) <= local.user_data_max_bytes
      error_message = "Rendered user_data exceeds the 16384 bytes EC2 accepts."
    }
  }
}
