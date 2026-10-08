resource "aws_security_group" "windows_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id

  # Only changes Terraform's delete behaviour, so unlike name and description it
  # does not replace the group (rules.md F-1). False here because nothing writes
  # rules to this group except Terraform; see the variable.
  revoke_rules_on_delete = var.revoke_rules_on_delete

  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md
# F-2). No controller adds rules to this group, so the usual reason does not
# apply - but the reason this project in particular cannot use inline blocks
# does, and it is the bug that broke 101_ubuntu_xrdp.
#
# CloudFormation's AWS::EC2::SecurityGroup leaves the allow-all egress rule that
# EC2 puts on every new group alone when a template names only
# SecurityGroupIngress, which is what the source template did: one ingress rule
# for 3389 and no SecurityGroupEgress at all. Terraform's inline blocks are
# attributes-as-blocks and authoritative over the whole group, so the same shape
# means the opposite - omitting egress does not inherit that default, it revokes
# it, and the group comes out with "Egress": [].
#
# On Windows that is worse than on Linux, because more of the setup depends on
# reaching the internet and none of it reports failure: the PowerShell Gallery
# (Install-Module AWS.Tools.SecretsManager), Secrets Manager
# (Get-SECSecretValue), community.chocolatey.org, GitHub, bun.sh and the Kiro
# download host all fail inside the userdata's try block. New-LocalUser never
# runs, so the workshop account does not exist - while port 3389 still answers,
# because Windows Server has RDP on from first boot and the ingress rule is
# fine. The only symptom is a login prompt rejecting the credentials this
# project hands out. It also stops SSM Agent registering, which is what makes
# the instance unreachable to diagnose.
#
# The conversion in _monolithic already carries both directions as standalone
# resources and explains why. Both are kept here, so each direction is a
# resource that is visibly present or visibly absent in a plan.
resource "aws_vpc_security_group_ingress_rule" "windows_ec2_rdp_ingress" {
  # toset is safe here because the CIDRs are literal strings in configuration and
  # are therefore known at plan time (rules.md B-8). A security group id arriving
  # from another module could not be used this way.
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.windows_ec2_security_group.id
  description       = "RDP from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.rdp_port
  to_port           = var.rdp_port
  cidr_ipv4         = each.value
}
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
# for_each over the policy list rather than one attachment resource per policy,
# so a caller can add or remove a policy without this module changing (rules.md
# B-7). toset is safe for the same reason as the CIDRs above: managed policy
# ARNs are literals in configuration (rules.md B-8).
resource "aws_iam_role_policy_attachment" "windows_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.windows_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "windows_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here would send the literal string
  # ["terraform-..."] as roleName, which IAM rejects during apply while
  # terraform validate and plan both pass, because the attribute is a string
  # either way (rules.md A-3).
  #
  # The conversion in _monolithic already has this right and documents the trap:
  # grepping it for "jsonencode([" finds that comment and nothing else.
  role = aws_iam_role.windows_ec2_iam_role.name
}
# ---------------------------------------------------------------------------
# The setup script, reproduced from the _monolithic template's <powershell>
# block.
#
# Every explanation of why it differs is here rather than inside the heredoc,
# and that is not a style preference. EC2 rejects user data above 16 KB in its
# raw, pre-base64 form; this script renders to about 15 KB, so roughly 1 KB is
# left. A PowerShell comment inside the template is paid for in that budget, and
# three paragraphs of commentary is enough to cross the limit - which surfaces
# as InvalidParameterValue partway through an apply that has already built the
# VPC, the key pair, the secret, the pool and six tables. The precondition on
# the instance below turns that into a plan error, and user_data_byte_length is
# an output so the headroom is visible without an apply.
#
# The PowerShell comments that are in the heredoc are the template's own.
#
# How the indentation works. This is an indented heredoc, so the PowerShell can
# be read at the indentation of the surrounding HCL: Terraform strips the
# smallest indentation found across the non-blank lines, which is four spaces.
# Blank lines are excluded from that measurement, which is why the blank lines
# inside the script do not reduce the strip width to zero. The lines which must
# begin at column zero are therefore written at exactly four - the body of every
# PowerShell @'...'@ here-string and its closing '@ marker. PowerShell refuses a
# '@ terminator with anything in front of it, and the failure mode is the one
# rules.md A-4 describes for CRLF: the here-string swallows the rest of the
# script and not one line of it runs.
#
# That is also why there is no %{for} or %{if} directive in this template, even
# though rules.md B-4 prescribes the directive form for optional injection and
# the DynamoDB block is a loop. A directive closed with the whitespace-strip
# marker - %{for ...~} - consumes the newline after itself, and the line that
# follows then keeps its source indentation instead of being dedented. Written
# that way, this script rendered the six DYNAMODB_TABLE_* lines, the
# "bun --watch server.ts" after them and the "} catch {" at the end all indented
# four spaces. PowerShell ignores leading whitespace, so nothing broke - but the
# same four spaces landing in front of a '@ terminator would break everything,
# and the construct that puts them there is invisible at the line it affects.
# A join() for the loop and a conditional for the injection are single-line
# interpolations at the base indentation: whatever they expand to, including
# embedded newlines, is emitted verbatim and the dedent cannot reach into it.
# The one cost is a blank line where additional_user_data would go when it is
# null.
#
# What differs from the conversion - 1 to 6 in the order they appear in the
# script, 7 and 8 added later:
#
#   1. The secret id is quoted. The conversion passed the ARN as a bare token,
#      and a Secrets Manager ARN is full of colons, which PowerShell reads as the
#      parameter-value separator in some argument positions. Whether it parsed
#      at all depended on where the colons fell. It did parse - but this is the
#      call the entire RDP credential depends on, so it is not left to chance.
#   2. foreach ($UserProfile ...) rather than foreach ($profile ...). $profile is
#      a PowerShell automatic variable holding the profile script path, and the
#      loop was overwriting it. Harmless here only because nothing downstream
#      reads it.
#   3. .\.venv\Scripts\Activate.ps1 rather than .\.venv\Scripts\activate. The
#      conversion called the bash activation script, which PowerShell cannot
#      run: it reported CommandNotFoundException and, with
#      $ErrorActionPreference set to Continue at the top of the script, carried
#      on with the virtualenv never activated. The pip install then went into
#      the machine-wide Python and the matching deactivate failed the same way.
#      Nothing said so.
#   4. init.py is written with a quoted here-string instead of echo. That echo
#      opened a double-quoted PowerShell string around Python source containing
#      double-quoted dict keys, so the string ended at the quote before
#      access_key and the remainder was reparsed as further arguments to echo -
#      the file it wrote had those quotes stripped. Separately, every line of
#      that Python carried the surrounding HCL's four-space indent, which is an
#      IndentationError on line 2. Both were invisible because the only consumer
#      is the commented-out line underneath, so init.py was written broken and
#      never run. It is written correctly now and still not run; the comment is
#      reproduced as the template had it.
#   5. The six DYNAMODB_TABLE_* lines are generated from a map. The conversion
#      listed them one per table, which means adding a seventh table is an edit
#      in two files that nothing checks are in step. The key is uppercased into
#      the variable name, which is the constraint the dynamodb_table_names
#      variable validates.
#   6. No cfn-signal, in the catch block or at the end. There is no
#      CloudFormation stack - the template's CreationPolicy was already dropped
#      by the conversion as having no Terraform equivalent, so the signal had
#      nothing waiting on it and --stack named a stack that does not exist. On
#      Windows the binary ships in the AMI, so the call did not even fail
#      loudly: it exited non-zero against a ValidationError and the script went
#      straight on to the shutdown.
#   7. A status marker, written where the cfn-signal calls used to be: "failed"
#      in the catch block before the throw, "completed" right before the
#      shutdown. It is what the setup_check associations below wait for - the
#      same job the signal did for CreationPolicy, with something now actually
#      listening (rules.md D-5). "completed" means the script reached its end,
#      not that every step worked: with $ErrorActionPreference at Continue most
#      failures do not reach the catch block, which is why the associations
#      print the log and check the account and the files rather than only
#      reading the status.
#   8. The Chocolatey installer runs in a child scope - & ([scriptblock]::Create(...))
#      - rather than through iex. iex evaluates it in this script's scope, and
#      install.ps1 assigns $tempDir at its top level; PowerShell variable names
#      are case-insensitive, so that overwrote $TempDir with
#      C:\Users\Administrator\AppData\Local\Temp\chocolatey\chocoInstall. The
#      virtualenv, init.py, the Kiro installer and both launcher scripts all
#      landed there. The conversion made that visible: the template wrote
#      server.ps1 and client.ps1 to literal paths and survived it, the
#      conversion wrote them to "$TempDir\..." and did not - so the logon
#      script's Test-Path on ${var.workshop_dir}\temp\server.ps1 came back
#      false, and the desktop got Kiro IDE and Workshop Project but never
#      01 GameServer or 02 GameClient. Nothing failed; the files existed, in
#      the Administrator profile, where the workshop account cannot see them.
#      The bun installer gets the same treatment for a quieter reason: it
#      assigns $ErrorActionPreference = "Stop" at its top level, which under iex
#      silently turned every later non-terminating error in this script into a
#      jump to the catch block. The two launcher scripts still use iex for bun;
#      each is its own process and has nothing after the install to protect.
#
# And one thing reproduced rather than fixed: the logon script is registered
# under HKLM, which is every user's Run key rather than the workshop account's,
# and the script deletes itself on first run. Whoever logs in first gets the
# desktop shortcuts and nobody else does - log in as Administrator to diagnose
# something before the participant connects and the participant's desktop comes
# up empty. Fixing it means writing into that account's own registry hive, which
# the userdata cannot reach before the profile exists, so it stays as the
# template had it.
# ---------------------------------------------------------------------------
locals {
  user_data_max_bytes = 16384

  # Defined once and read by the setup script and by the setup_check associations
  # that wait on it, so the two cannot name different files.
  setup_log_path    = "${var.workshop_dir}\\setup.log"
  setup_status_path = "${var.workshop_dir}\\setup.status"

  user_data = <<-EOT
    <powershell>
    # Kiro Workshop Windows Setup - Simplified
    $ErrorActionPreference = "Continue"
    $ProgressPreference = 'SilentlyContinue'
    $LogFile = "${local.setup_log_path}"
    New-Item -ItemType Directory -Path "${var.workshop_dir}" -Force

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

        $SecretValue = Get-SECSecretValue -SecretId "${var.secret_id}" -Region $Region
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
        Remove-LocalUser -Name "${var.workshop_username}" -ErrorAction SilentlyContinue
        $Password = ConvertTo-SecureString $WorkshopPassword -AsPlainText -Force
        $User = New-LocalUser -Name "${var.workshop_username}" -Password $Password -FullName "Workshop User" -PasswordNeverExpires -AccountNeverExpires
        Add-LocalGroupMember -Group "Administrators" -Member "${var.workshop_username}" -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group "Remote Desktop Users" -Member "${var.workshop_username}" -ErrorAction SilentlyContinue

        # Setup directories - Enhanced domain handling
        Write-Log "Finding workshop user profile..."
        $UserProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object {
            $_.LocalPath -like "*${var.workshop_username}*" -and
            $_.LocalPath -notlike "*.bak" -and
            $_.LocalPath -notlike "*temp*"
        }

        if ($UserProfiles) {
            # Find workshop.ComputerName pattern specifically
            $ComputerName = $env:COMPUTERNAME
            $PreferredPattern = "${var.workshop_username}.$ComputerName"

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
            foreach ($UserProfile in $UserProfiles) {
                Write-Log "Found ${var.workshop_username} profile: $($UserProfile.LocalPath)"
            }
        } else {
            # Deterministically construct workshop.ComputerName path
            $ComputerName = $env:COMPUTERNAME
            $UserProfilePath = "C:\Users\${var.workshop_username}.$ComputerName"
            Write-Log "Using constructed path: $UserProfilePath"
        }

        $WorkshopDir = "${var.workshop_dir}"
        $TempDir = "$WorkshopDir\temp"
        New-Item -ItemType Directory -Path $TempDir -Force

        # Install Chocolatey FIRST
        Write-Log "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        & ([scriptblock]::Create((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')))

        # Install development tools via Chocolatey
        Write-Log "Installing Git..."
        choco install git -y

        Write-Log "Installing AWS CLI..."
        choco install awscli -y

        Write-Log "Installing Node.js..."
        choco install nodejs-lts --version="${var.nodejs_version}" -y

        Write-Log "Installing Python"
        choco install ${var.python_package} -y

        # Refresh environment variables after installations
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        python --version
        Set-Location $TempDir
        python -m venv .venv
        .\.venv\Scripts\Activate.ps1
        python -m pip install ${join(" ", var.python_packages)}
        @'
    import json
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
        print(json.dumps(result))
    '@ | Out-File -FilePath "$TempDir\init.py" -Encoding utf8
        # $PYTHON_RESULT = python init.py | ConvertFrom-Json
        deactivate

        # Clone project AFTER Git is installed
        Write-Log "Cloning Spirit of Kiro project..."
        $GitUrl = "${var.git_clone_url}"
        $GitBranch = "${var.git_clone_branch}"
        Write-Log "Git URL: $GitUrl, Branch: $GitBranch"

        # Wait for git to be available in PATH
        $maxRetries = ${var.git_available_retries}
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
            & ([scriptblock]::Create((irm bun.sh/install.ps1)))
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

            Write-Log "Project setup completed"
            Set-Location "$WorkshopDir\$GitBranch\server"
            npm cache clean --force
            bun install
            Set-Location "$WorkshopDir\$GitBranch\client"
            npm cache clean --force
            bun install

            @'
    Set-Location ${var.workshop_dir}\${var.git_clone_branch}\server
    $Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
      irm bun.sh/install.ps1 | iex
      $Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    npm cache clean --force
    bun install
    $Env:AWS_REGION="${var.aws_region}"
    $Env:COGNITO_USER_POOL_ID="${var.cognito_user_pool_id}"
    $Env:COGNITO_CLIENT_ID="${var.cognito_client_id}"
    $Env:COGNITO_USER_POOL_ARN="${var.cognito_user_pool_arn}"
    $Env:ITEM_IMAGES_SERVICE_URL="${var.item_images_service_url}"
    ${join("\n", [for key, name in var.dynamodb_table_names : format("$Env:DYNAMODB_TABLE_%s=\"%s\"", upper(key), name)])}
    bun --watch server.ts
    '@ | Out-File -FilePath "$TempDir\server.ps1"

            @'
    Set-Location ${var.workshop_dir}\${var.git_clone_branch}\client
    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
      irm bun.sh/install.ps1 | iex
      $Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    $Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    npm cache clean --force
    bun install
    $Env:VITE_WS_URL="http://localhost:${var.game_server_port}/"
    bun run dev
    '@ | Out-File -FilePath "$TempDir\client.ps1"
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
        icacls $WorkshopDir /grant "${var.workshop_username}:F" /T /Q
        if (Test-Path $UserProfilePath) {
            icacls "$UserProfilePath" /grant "${var.workshop_username}:F" /T /Q
        }

        # Create logon script for workshop user (runs after first login)
        Write-Log "Creating workshop user logon script..."
        $LogonScript = '# Workshop User First Logon Setup' + "`n"
        $LogonScript += '$LogFile = "${var.workshop_dir}\logon.log"' + "`n"
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
        $LogonScript += 'if (Test-Path "${var.workshop_dir}\${var.git_clone_branch}") {' + "`n"
        $LogonScript += '    $ProjectShortcut = $WshShell.CreateShortcut("$DesktopPath\Workshop Project.lnk")' + "`n"
        $LogonScript += '    $ProjectShortcut.TargetPath = "${var.workshop_dir}\${var.git_clone_branch}"' + "`n"
        $LogonScript += '    $ProjectShortcut.Save()' + "`n"
        $LogonScript += '    Write-LogonLog "Project shortcut created"' + "`n"
        $LogonScript += '}' + "`n"
        $LogonScript += 'if (Test-Path "${var.workshop_dir}\temp\server.ps1") {' + "`n"
        $LogonScript += '    $ServerShortcut = $WshShell.CreateShortcut("$DesktopPath\01 GameServer.lnk")' + "`n"
        $LogonScript += '    $ServerShortcut.TargetPath = "powershell.exe"' + "`n"
        $LogonScript += '    $ServerShortcut.Arguments = "-ExecutionPolicy Bypass -NoExit -File ${var.workshop_dir}\temp\server.ps1"' + "`n"
        $LogonScript += '    $ServerShortcut.Save()' + "`n"
        $LogonScript += '    $ServerShortcutBytes = [System.IO.File]::ReadAllBytes("$DesktopPath\01 GameServer.lnk")' + "`n"
        $LogonScript += '    $ServerShortcutBytes[0x15] = $ServerShortcutBytes[0x15] -bor 0x20' + "`n"
        $LogonScript += '    [System.IO.File]::WriteAllBytes("$DesktopPath\01 GameServer.lnk", $ServerShortcutBytes)' + "`n"
        $LogonScript += '    Write-LogonLog "Game Server shortcut created"' + "`n"
        $LogonScript += '}' + "`n"
        $LogonScript += 'if (Test-Path "${var.workshop_dir}\temp\client.ps1") {' + "`n"
        $LogonScript += '    $ClientShortcut = $WshShell.CreateShortcut("$DesktopPath\02 GameClient.lnk")' + "`n"
        $LogonScript += '    $ClientShortcut.TargetPath = "powershell.exe"' + "`n"
        $LogonScript += '    $ClientShortcut.Arguments = "-ExecutionPolicy Bypass -NoExit -File ${var.workshop_dir}\temp\client.ps1"' + "`n"
        $LogonScript += '    $ClientShortcut.Save()' + "`n"
        $LogonScript += '    $ClientShortcutBytes = [System.IO.File]::ReadAllBytes("$DesktopPath\02 GameClient.lnk")' + "`n"
        $LogonScript += '    $ClientShortcutBytes[0x15] = $ClientShortcutBytes[0x15] -bor 0x20' + "`n"
        $LogonScript += '    [System.IO.File]::WriteAllBytes("$DesktopPath\02 GameClient.lnk", $ClientShortcutBytes)' + "`n"
        $LogonScript += '    Write-LogonLog "Game Client shortcut created"' + "`n"
        $LogonScript += '}' + "`n"
        $LogonScript += 'Write-LogonLog "Workshop user setup completed"' + "`n"
        $LogonScript += 'Remove-Item $MyInvocation.MyCommand.Path -Force' + "`n"

        $LogonScriptPath = "${var.workshop_dir}\${var.workshop_username}-setup.ps1"
        Set-Content -Path $LogonScriptPath -Value $LogonScript

        # Set logon script in registry for workshop user
        $LogonKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $LogonKey -Name "WorkshopSetup" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$LogonScriptPath`"" -Force

        # Install Kiro IDE - Minimal approach
        Write-Log "Installing Kiro IDE..."
        $KiroUrl = "${var.kiro_installer_url}"
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
            icacls "$ProgramDataKiroPath" /grant "${var.workshop_username}:F" /T /Q
        }
    ${var.additional_user_data == null ? "" : var.additional_user_data}
    } catch {
        Write-Log "Setup failed: $($_.Exception.Message)"
        Set-Content -Path "${local.setup_status_path}" -Value "failed"
        throw
    }

    Set-Content -Path "${local.setup_status_path}" -Value "completed"
    shutdown /r /t ${var.reboot_delay_seconds} /c "Kiro Workshop setup completed"
    </powershell>
    EOT
}
resource "aws_instance" "windows_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = [aws_security_group.windows_ec2_security_group.id]
  iam_instance_profile        = aws_iam_instance_profile.windows_ec2_instance_profile.name
  user_data                   = local.user_data

  # The conversion left this at the provider default of false, which is a trap
  # for a project whose entire behaviour is in the userdata: EC2Launch runs user
  # data once, on first boot, so changing the script and applying updates the
  # attribute in state, reports a change, and does nothing to the machine. True
  # makes an edit to any of the values interpolated above rebuild the instance,
  # which is the only way the edit takes effect.
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

  # Everything this userdata needs at boot is reached through a reference that
  # stops short of the thing that actually has to be ready, so each one is named
  # explicitly (rules.md D-1). Both failures below land inside the userdata's try
  # block, so apply reports the instance as created either way and the only
  # symptom is RDP rejecting the credentials this project hands out.
  #
  #   - The security group is referenced as ...security_group.id, which orders
  #     this after the group but not after its rules. The group is created with
  #     no rules at all, so booting before the egress rule exists means no
  #     outbound path to the PowerShell Gallery, Secrets Manager or GitHub.
  #   - The instance profile reference orders this after the profile and the
  #     role, but not after the policy attachment. The conversion did not list
  #     it and should have: the first real action in this script is
  #     Get-SECSecretValue, so an instance that wins that race reads the secret
  #     through a role with no policy on it yet and gets AccessDenied.
  #
  # The third dependency the conversion listed - the secret version holding the
  # password - is deliberately not here, because the module boundary covers it.
  # The call site orders this whole module after the whole app_secret module, and
  # a module-level depends_on means "after every resource in it" (rules.md D-2),
  # so the version is included by construction rather than by naming a resource
  # this module cannot see.
  depends_on = [
    aws_vpc_security_group_egress_rule.windows_ec2_egress,
    aws_vpc_security_group_ingress_rule.windows_ec2_rdp_ingress,
    aws_iam_role_policy_attachment.windows_ec2_iam_role,
  ]

  lifecycle {
    # Catches the 16 KB user data limit at plan time instead of as an
    # InvalidParameterValue partway through apply (rules.md B-1). See the comment
    # above the locals block for why the headroom is only about 1 KB.
    #
    # length() counts characters, not bytes. The script is ASCII, so the two
    # agree here; a non-ASCII value arriving through additional_user_data or any
    # interpolated variable would make this undercount, which is the other
    # reason user_data_byte_length is an output.
    precondition {
      condition     = length(local.user_data) <= local.user_data_max_bytes
      error_message = "Rendered user_data exceeds the 16384 bytes EC2 accepts. Shorten additional_user_data or workshop_dir - the script reproduced from the _monolithic template already takes about 15 KB of that budget."
    }
  }
}
# ---------------------------------------------------------------------------
# The readiness checks, run by State Manager rather than handed out as
# send-command one-liners.
#
# Each association below runs once on its own, as soon as the instance registers
# with SSM after the first apply: nobody has to copy a command out of the
# outputs. Every check that used to be an output is one of them -
#
#   setup_log   the tail of the setup log and the status marker. Fails unless
#               the marker says "completed".
#   rdp_status  Terminal Services, the workshop account and the RDP listener.
#               Fails unless all three are ready - Running plus a missing
#               account is the case to recognise: RDP answers and the script
#               failed before New-LocalUser.
#   app_status  the launcher scripts and the clone, and whether the game server
#               and client are listening. Fails only on the first two; the last
#               two are False until a person logs in and runs the desktop
#               shortcuts, which nothing does automatically.
#
# so the association status in State Manager is the verdict, and the output
# printed alongside it is the reason. setup_check_results_command reads both.
#
# All three wait for the same status marker before checking anything, with a
# loop rather than depends_on: depends_on only orders the creation of an
# association against the instance's and says nothing about the script running
# inside it (rules.md D-5). In every run observed so far SSM Agent came online
# only after the setup's own reboot - eleven to thirteen minutes after launch -
# so the marker was already there and each command took a second. The loop is
# for the case where the agent registers earlier, and it polls every two seconds
# because the marker is written five seconds before that reboot. SSM documents
# that a reboot it did not ask for (exit 3010) can leave a command's status
# wrong, and these associations cannot ask for that one - which is why every
# check after the wait has to finish inside those five seconds, and why the
# listeners are read with Get-NetTCPConnection rather than the
# Test-NetConnection the old outputs used. On a port nothing listens on,
# Test-NetConnection falls back to an ICMP test and takes about ten seconds;
# Get-NetTCPConnection reads the listener table in a fraction of one. It also
# answers the question that was being asked - whether anything listens - rather
# than whether a loopback connect succeeds.
#
# The three checks are independent reads of the same finished state, so they
# do not wait on each other and need no marker of their own.
#
# Apply does not wait for any of them, and wait_for_success_timeout_seconds is
# deliberately not set. Right after creation an association reports
# Overview.Status "Success" with no target counted at all, because the instance
# has not registered yet; the provider's waiter (Pending -> Success) accepts
# that, and an apply with the setting returned "Creation complete after 1s". It
# would only have claimed a wait that does not happen - the provider issue
# rules.md D-5 already records.
#
# An association with no schedule runs once per target and is not repeated by
# later applies. It runs again when its parameters change, or on demand with
# aws ssm start-associations-once - useful for app_status after starting the
# game server by hand.
#
# OutputEncoding first because this is a Korean-language AMI by default, and an
# exception message the setup logged comes back from SSM as mojibake otherwise.
#
# A list rather than a map so setup_check_results_command prints the checks in
# this order rather than alphabetically. The keys are configuration literals,
# so the for_each built from them is known at plan time (rules.md B-8).
#
# Lives in this module rather than the root because every value it reads - the
# instance, the paths, the ports, the account name - is this module's own
# (rules.md C-1 is about combining modules, which this does not do).
# ---------------------------------------------------------------------------
locals {
  setup_check_preamble = <<-EOT
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $Deadline = (Get-Date).AddSeconds(${var.setup_wait_seconds})
    while (-not (Test-Path "${local.setup_status_path}") -and (Get-Date) -lt $Deadline) { Start-Sleep -Seconds 2 }
    $Status = if (Test-Path "${local.setup_status_path}") { (Get-Content "${local.setup_status_path}" -Raw).Trim() } else { "not finished within ${var.setup_wait_seconds} seconds" }
    EOT

  setup_checks = [
    {
      key      = "setup_log"
      commands = <<-EOT
        Get-Content "${local.setup_log_path}" -Tail ${var.setup_log_tail_lines} -ErrorAction SilentlyContinue
        Write-Output "Setup status: $Status"
        if ($Status -ne "completed") { exit 1 }
        EOT
    },
    {
      key      = "rdp_status"
      commands = <<-EOT
        $Service = (Get-Service -Name TermService -ErrorAction SilentlyContinue).Status
        $User = Get-LocalUser -Name "${var.workshop_username}" -ErrorAction SilentlyContinue
        $Account = if (-not $User) { "missing" } elseif ($User.Enabled) { "enabled" } else { "disabled" }
        $Listening = [bool](Get-NetTCPConnection -LocalPort ${var.rdp_port} -State Listen -ErrorAction SilentlyContinue)
        Write-Output "Setup status: $Status"
        Write-Output "TermService: $Service"
        Write-Output "Account ${var.workshop_username}: $Account"
        Write-Output "Port ${var.rdp_port} listening: $Listening"
        if ("$Service" -ne "Running" -or $Account -ne "enabled" -or -not $Listening) { exit 1 }
        EOT
    },
    {
      key      = "app_status"
      commands = <<-EOT
        $Launchers = Test-Path "${var.workshop_dir}\temp\server.ps1"
        $Clone = Test-Path "${var.workshop_dir}\${var.git_clone_branch}"
        $Server = [bool](Get-NetTCPConnection -LocalPort ${var.game_server_port} -State Listen -ErrorAction SilentlyContinue)
        $Client = [bool](Get-NetTCPConnection -LocalPort ${var.client_dev_port} -State Listen -ErrorAction SilentlyContinue)
        Write-Output "Setup status: $Status"
        Write-Output "Launcher scripts: $Launchers"
        Write-Output "Clone ${var.git_clone_branch}: $Clone"
        Write-Output "Game server on ${var.game_server_port}: $Server (False until someone runs 01 GameServer)"
        Write-Output "Game client on ${var.client_dev_port}: $Client (False until someone runs 02 GameClient)"
        if (-not ($Launchers -and $Clone)) { exit 1 }
        EOT
    },
  ]
}
resource "aws_ssm_association" "setup_check" {
  for_each = { for check in local.setup_checks : check.key => check.commands }

  name = "AWS-RunPowerShellScript"
  # Without a name all three show in the console as AWS-RunPowerShellScript and
  # an id, with nothing to tell them apart.
  association_name = "${var.association_name_prefix}-${replace(each.key, "_", "-")}"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.windows_ec2.id]
  }
  parameters = {
    # Above the loop's own deadline, so the script reports "not finished"
    # itself rather than being killed by the agent with no output.
    executionTimeout = tostring(var.setup_wait_seconds + 120)
    commands         = "${local.setup_check_preamble}${each.value}"
  }
}
