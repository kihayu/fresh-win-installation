#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Automates the setup of a Windows machine for web development and general productivity.
.DESCRIPTION
    This script performs the following actions:
    - Sets ExecutionPolicy to Bypass for the current process.
    - Sets global ErrorActionPreference to Stop and ProgressPreference to SilentlyContinue.
    - Checks for Internet connectivity using Test-Connection (PS5.1) or Test-NetConnection (PS7+).
    - Checks for Windows build compatibility with WSL 2.
    - Configures Windows Updates to notify before download and install.
    - Enables necessary Windows features for WSL 2.
    - Installs WSL 2, sets it as default, and installs the latest Ubuntu distribution.
    - Installs a suite of development tools and utilities using Winget, including Bun JavaScript runtime.
    - Attempts to install the latest LTS version of Node.js using NVM.
    - Sets the system app color theme to dark.
    - Adds Windows Defender exclusions for common development directories and processes.
    - Creates a transcript log of its operations.
.PARAMETER SkipWSL
    If specified, skips the WSL installation steps.
.PARAMETER SkipUpdates
    If specified, skips the Windows Updates configuration.
.PARAMETER CustomTools
    Optional hashtable of additional tools to install. Format: @{"Tool Name" = "Package.Id"}
.PARAMETER RebootWhenDone
    If specified, automatically reboots the system after script completion.
.PARAMETER Resume
    If specified, attempts to resume from the last successful step.
.PARAMETER NoDefenderExclusions
    If specified, skips adding Windows Defender exclusions for development directories.
.PARAMETER SkipGitConfig
    If specified, skips the Git configuration steps.
.EXAMPLE
    .\fresh-install.ps1 -CustomTools @{"WebStorm" = "JetBrains.WebStorm"}
.NOTES
    Version: 1.0
    Author: Keanu Hie/AI
    Purpose: To streamline the setup of a new Windows environment for web developers.
#>

param (
    [switch]$SkipWSL,
    [switch]$SkipUpdates,
    [hashtable]$CustomTools,
    [switch]$RebootWhenDone,
    [switch]$Resume,
    [switch]$NoDefenderExclusions,
    [switch]$SkipGitConfig
)

function Write-Log {
    param (
        [string]$Message,
        [string]$Type = "INFO" # INFO, WARNING, ERROR, SUCCESS
    )
    $Color = switch ($Type) {
        "INFO"    { "White" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host "[$Type] $Message" -ForegroundColor $Color
}

$CheckpointFile = Join-Path -Path $env:TEMP -ChildPath "windows-dev-setup-checkpoint.json"
$CompletedSteps = @{}

if ($Resume -and (Test-Path $CheckpointFile)) {
    try {
        $CompletedSteps = Get-Content -Path $CheckpointFile -Raw | ConvertFrom-Json -AsHashtable
        # Convert string keys back to boolean if needed
        if ($CompletedSteps.Count -gt 0) {
            Write-Log "Resuming setup from checkpoint. Previously completed steps will be skipped."
        }
    }
    catch {
        Write-Log "Failed to load checkpoint file. Starting fresh." -Type "WARNING"
        $CompletedSteps = @{}
    }
}

function Save-Checkpoint {
    param (
        [string]$StepName
    )
    $CompletedSteps[$StepName] = $true
    $CompletedSteps | ConvertTo-Json | Set-Content -Path $CheckpointFile
}

function Test-StepCompleted {
    param (
        [string]$StepName
    )
    return $CompletedSteps.ContainsKey($StepName) -and $CompletedSteps[$StepName] -eq $true
}


try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Write-Log "Execution policy for current process set to Bypass."
}
catch {
    Write-Log "Failed to set execution policy to Bypass. Script may not run if policy is too restrictive. Error: $($_.Exception.Message)" -Type "WARNING"
}

$Global:ErrorActionPreference = 'Stop'
$Global:ProgressPreference = 'SilentlyContinue'

$TranscriptLogPath = Join-Path -Path $env:USERPROFILE -ChildPath "windows-dev-setup-log.txt"
try {
    Start-Transcript -Path $TranscriptLogPath -Append
    Write-Log "Transcript logging started to: $TranscriptLogPath"
}
catch {
    Write-Log "Failed to start transcript logging to $TranscriptLogPath. Error: $($_.Exception.Message)" -Type "WARNING"
}

Write-Log "Performing initial system checks..."

Write-Log "Checking for Administrator privileges..."
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script needs to be run as Administrator. Please re-run with elevated privileges." -Type "ERROR"
    Write-Log "Right-click the script and select 'Run as administrator'."
    Start-Sleep -Seconds 10
    try { Stop-Transcript } catch {}
    Exit 1
}
Write-Log "Administrator privileges confirmed." -Type "SUCCESS"

Write-Log "Checking Internet connectivity (pinging 8.8.8.8)..."
$PingHost = "8.8.8.8"
$ConnectivityConfirmed = $false
try {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Log "Using Test-NetConnection (PowerShell 7+ method)..."
        if (Test-NetConnection -ComputerName $PingHost -InformationLevel Quiet -Count 1) { # PS7+ specific parameters
            $ConnectivityConfirmed = $true
        }
    } else {
        Write-Log "Using Test-Connection (PowerShell 5.1 compatible method)..."
        if (Test-Connection -ComputerName $PingHost -Quiet -Count 2) { # PS5.1 compatible
            $ConnectivityConfirmed = $true
        }
    }

    if ($ConnectivityConfirmed) {
        Write-Log "Internet connectivity confirmed." -Type "SUCCESS"
    } else {
        Write-Log "Internet connectivity test to $PingHost failed (no reply or command failed)." -Type "ERROR"
        try { Stop-Transcript } catch {}
        Exit 1
    }
}
catch {
    Write-Log "Internet connectivity check to $PingHost failed with an exception: $($_.Exception.Message)" -Type "ERROR"
    Write-Log "Please ensure you have an active internet connection and try again." -Type "WARNING"
    try { Stop-Transcript } catch {}
    Exit 1
}

Write-Log "Checking Windows Build version for WSL 2 compatibility..."
try {
    $BuildNumber = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name CurrentBuildNumber).CurrentBuildNumber
    if ([int]$BuildNumber -lt 19041) { # WSL 2 requires Windows 10 build 19041+ or Windows 11
        Write-Log "WSL 2 requires Windows 10 build 19041+ or Windows 11. Your build is $BuildNumber." -Type "ERROR"
        Write-Log "Please update Windows and try again." -Type "WARNING"
        try { Stop-Transcript } catch {}
        Exit 1
    }
    Write-Log "Windows build $BuildNumber is compatible with WSL 2." -Type "SUCCESS"
}
catch {
    Write-Log "Could not determine Windows build number: $($_.Exception.Message)" -Type "ERROR"
    Write-Log "Proceeding, but WSL 2 installation might fail if the build is too old." -Type "WARNING"
}

Write-Log "Starting setup process. This may take a while and might require a reboot."

Write-Log "=================================================================="
Write-Log "                   WINDOWS DEV SETUP WIZARD                      "
Write-Log "=================================================================="

Write-Log "=================================================================="
Write-Log "                     [STEP 1/8] WINDOWS UPDATES                   "
Write-Log "=================================================================="
if (Test-StepCompleted -StepName "WindowsUpdates") {
    Write-Log "STEP 1: Windows Updates configuration already completed. Skipping..."
} elseif ($SkipUpdates) {
    Write-Log "STEP 1: Windows Updates configuration skipped as requested."
    Save-Checkpoint -StepName "WindowsUpdates"
} else {
    Write-Log "STEP 1: Configuring Windows Updates to 'Notify for download and notify for install'..."
    try {
        Write-Log "Setting Windows Update service (wuauserv) to Automatic (Delayed Start)..."
        Set-Service -Name wuauserv -StartupType Automatic
        $null = & sc.exe config wuauserv start= delayed-auto
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue

        Write-Log "Setting Update Orchestrator Service (UsoSvc) to Manual..."
        Set-Service -Name UsoSvc -StartupType Manual
        Start-Service -Name UsoSvc -ErrorAction SilentlyContinue

        $RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        If (-NOT (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
        }
        Set-ItemProperty -Path $RegistryPath -Name "NoAutoUpdate" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $RegistryPath -Name "AUOptions" -Value 2 -Type DWord -Force
        Set-ItemProperty -Path $RegistryPath -Name "ScheduledInstallDay" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $RegistryPath -Name "ScheduledInstallTime" -Value 3 -Type DWord -Force

        Write-Log "Windows Update configured to notify before download and install." -Type "SUCCESS"
        Save-Checkpoint -StepName "WindowsUpdates"
    }
    catch {
        Write-Log "Error configuring Windows Updates: $($_.Exception.Message)" -Type "ERROR"
    }
}

Write-Log "=================================================================="
Write-Log "                     [STEP 2/8] WSL SETUP                        "
Write-Log "=================================================================="
if (Test-StepCompleted -StepName "WSL") {
    Write-Log "STEP 2: WSL setup already completed. Skipping..."
} elseif ($SkipWSL) {
    Write-Log "STEP 2: WSL setup skipped as requested."
    Save-Checkpoint -StepName "WSL"
} else {
    Write-Log "STEP 2: Enabling WSL Features, setting up WSL 2, and installing Ubuntu..."
    try {
        Write-Log "Enabling 'Microsoft-Windows-Subsystem-Linux' feature..."
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
        Write-Log "'Microsoft-Windows-Subsystem-Linux' feature enabled (or already enabled)." -Type "SUCCESS"

        Write-Log "Enabling 'VirtualMachinePlatform' feature..."
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
        Write-Log "'VirtualMachinePlatform' feature enabled (or already enabled)." -Type "SUCCESS"

        Write-Log "Ensuring WSL 2 is the default version for new distributions..."
        wsl --set-default-version 2
        Write-Log "WSL default version set to 2." -Type "SUCCESS"

        Write-Log "Installing Ubuntu (default WSL distro)... This may take some time."
        wsl --install -d Ubuntu --no-launch

        Write-Log "WSL and Ubuntu installation process initiated." -Type "SUCCESS"
        Write-Log "A reboot might be required by Windows after this step for all WSL changes to be fully functional." -Type "WARNING"
        Write-Log "After reboot, launch 'Ubuntu' from the Start Menu to complete its setup (create user/password)."

        Write-Log "Creating WSL Ubuntu initialization script for first launch..."
        $WSLSetupScript = @"
#!/bin/bash

echo "Setting up WSL Ubuntu with development tools..."

sudo apt update

sudo apt install -y build-essential curl wget git

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

echo "Sourcing NVM and attempting to install Node.js LTS..."
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
nvm install --lts
nvm alias default lts
echo "Node.js LTS should now be installed in WSL. Please open a new WSL terminal to use it."

if ! grep -q 'NVM_DIR' ~/.bashrc; then
  echo 'export NVM_DIR="\$HOME/.nvm"' >> ~/.bashrc
  echo '[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"' >> ~/.bashrc
  echo '[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"' >> ~/.bashrc
fi

echo "WSL Ubuntu setup complete!"
echo "Restart your WSL terminal and run 'nvm install --lts' to install Node.js."
"@

        $WSLSetupScriptPath = "$env:USERPROFILE\wsl-setup.sh"
        $WSLSetupScript | Out-File -FilePath $WSLSetupScriptPath -Encoding utf8 -Force
        Write-Log "Created WSL setup script at: $WSLSetupScriptPath" -Type "SUCCESS"
        Write-Log "After setting up your Ubuntu WSL user, run: 'cp /mnt/c/Users/$(whoami)/wsl-setup.sh ~/ && chmod +x ~/wsl-setup.sh && ~/wsl-setup.sh'"

        Save-Checkpoint -StepName "WSL"
    }
    catch {
        Write-Log "Error during WSL/Ubuntu setup: $($_.Exception.Message)" -Type "ERROR"
        Write-Log "Ensure virtualization (Intel VT-x or AMD-V) is enabled in your system's BIOS/UEFI." -Type "WARNING"
        Write-Log "A reboot might be necessary if Windows Optional Features were just enabled and kernel components updated." -Type "WARNING"
    }
}

Write-Log "=================================================================="
Write-Log "                     [STEP 3/8] TOOL INSTALLATION                 "
Write-Log "=================================================================="
if (Test-StepCompleted -StepName "Tools") {
    Write-Log "STEP 3: Tool installation already completed. Skipping..."
} else {
    Write-Log "STEP 3: Installing tools and utilities using Winget..."

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Winget CLI (winget.exe) not found in PATH. Please install 'App Installer' from the Microsoft Store." -Type "ERROR"
    } else {
        Write-Log "Winget found." -Type "SUCCESS"
        # Define default tools for web development
        $tools = @{
            "Visual Studio Code"    = "Microsoft.VisualStudioCode"
            "Windsurf"    = "Codeium.Windsurf"
            "Git"                   = "Git.Git"
            "Docker Desktop"        = "Docker.DockerDesktop"
            "NVM for Windows"       = "CoreyButler.NVMforWindows"
            "Bun"                   = "Oven-sh.Bun"
            "Warp Terminal"         = "Warp.Warp"
            "VLC Media Player"      = "VideoLAN.VLC"
            "Microsoft PowerToys"   = "Microsoft.PowerToys"
            "Microsoft Teams"       = "Microsoft.Teams"
            "Postman"               = "Postman.Postman"
            "Firefox Developer Edition" = "Mozilla.Firefox.DeveloperEdition"
        }

        if ($CustomTools -and $CustomTools.Count -gt 0) {
            Write-Log "Adding $($CustomTools.Count) custom tools to installation list..."
            foreach ($toolName in $CustomTools.Keys) {
                $packageId = $CustomTools[$toolName]
                if (-not $tools.ContainsKey($toolName)) {
                    $tools[$toolName] = $packageId
                    Write-Log "Added custom tool: $toolName ($packageId)"
                } else {
                    Write-Log "Custom tool '$toolName' overrides default package ID" -Type "WARNING"
                    $tools[$toolName] = $packageId
                }
            }
        }

        $installedCount = 0
        $totalTools = $tools.Count

        foreach ($toolName in $tools.Keys) {
            $packageId = $tools[$toolName]
            $installedCount++
            Write-Log "Installing $toolName ($packageId)... [$installedCount of $totalTools]"

            try {
                $ArgumentList = @(
                    'install', '--id', $packageId, '--silent',
                    '--accept-source-agreements', '--accept-package-agreements', '-e'
                )
                $process = Start-Process winget -ArgumentList $ArgumentList -Wait -PassThru

                if ($process.ExitCode -eq 0) {
                    Write-Log "$toolName installed successfully." -Type "SUCCESS"
                } else {
                    Write-Log "Winget process for $toolName exited with code $($process.ExitCode)." -Type "WARNING"
                    Write-Log "This might mean the tool is already installed, requires a reboot, or an error occurred."
                }
            }
            catch {
                Write-Log "Error installing $toolName ($packageId): $($_.Exception.Message)" -Type "ERROR"
            }
        }

        Save-Checkpoint -StepName "Tools"
    }
}

Write-Log "=================================================================="
Write-Log "                     [STEP 4/8] NODE.JS SETUP                    "
Write-Log "=================================================================="
if (Test-StepCompleted -StepName "NodeJS") {
    Write-Log "STEP 4: Node.js installation already completed. Skipping..."
} else {
    Write-Log "STEP 4: Attempting to install Node.js LTS via NVM..."
    try {
        Write-Log "Ensuring NVM environment variables are set correctly..."

        $NVM_HOME = Join-Path $env:APPDATA "nvm"
        $NVM_SYMLINK = Join-Path $env:APPDATA "nvm\current"

        if (Test-Path $NVM_HOME) {
            [System.Environment]::SetEnvironmentVariable("NVM_HOME", $NVM_HOME, [System.EnvironmentVariableTarget]::User)
            [System.Environment]::SetEnvironmentVariable("NVM_SYMLINK", $NVM_SYMLINK, [System.EnvironmentVariableTarget]::User)
            Write-Log "NVM environment variables set: NVM_HOME=$NVM_HOME, NVM_SYMLINK=$NVM_SYMLINK" -Type "SUCCESS"
        } else {
            Write-Log "NVM directory not found at $NVM_HOME. Skipping environment variable setup." -Type "WARNING"
        }

        Write-Log "Refreshing environment variables for the current session to detect NVM..."
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $env:NVM_HOME = $NVM_HOME
        $env:NVM_SYMLINK = $NVM_SYMLINK

        if (Get-Command nvm -ErrorAction SilentlyContinue) {
            Write-Log "NVM command found. Proceeding with Node.js LTS installation."

            Write-Log "Executing: nvm install lts"
            & cmd.exe /c "nvm install lts" | ForEach-Object { Write-Log $_ }
            Start-Sleep -Seconds 2

            Write-Log "Executing: nvm use lts"
            & cmd.exe /c "nvm use lts" | ForEach-Object { Write-Log $_ }
            Start-Sleep -Seconds 2

            Write-Log "Executing: nvm alias default lts (to set LTS as default for new shells)"
            & cmd.exe /c "nvm alias default lts" | ForEach-Object { Write-Log $_ }

            Write-Log "Verifying Node.js installation..."
            try {
                $nodeVersion = & cmd.exe /c "node --version" 2>&1
                if ($nodeVersion -match "v\d+\.\d+\.\d+") {
                    Write-Log "Node.js $nodeVersion successfully installed and accessible." -Type "SUCCESS"
                } else {
                    Write-Log "Node.js verification failed. Output: $nodeVersion" -Type "WARNING"
                }
            } catch {
                Write-Log "Failed to verify Node.js installation: $($_.Exception.Message)" -Type "WARNING"
            }

            $nodeBinDir = Join-Path $NVM_SYMLINK ""
            if ((Test-Path $nodeBinDir) -and -not ($env:Path -split ";" -contains $nodeBinDir)) {
                Write-Log "Adding Node.js bin directory to PATH: $nodeBinDir"
                $newPath = $env:Path + ";" + $nodeBinDir
                [System.Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::User)
            }

            Write-Log "Node.js LTS installation via NVM completed." -Type "SUCCESS"
            Write-Log "IMPORTANT: Open a NEW terminal window after script completion for Node.js and NVM to be fully available." -Type "WARNING"
        } else {
            Write-Log "NVM command not found. Node.js installation via NVM skipped." -Type "WARNING"
            Write-Log "Ensure NVM for Windows installed correctly. You may need to install Node.js manually using NVM in a new terminal."
        }

        Save-Checkpoint -StepName "NodeJS"
    }
    catch {
        Write-Log "Error during NVM Node.js LTS installation: $($_.Exception.Message)" -Type "ERROR"
    }
}

Write-Log "=================================================================="
Write-Log "                     [STEP 5/8] DARK THEME                       "
Write-Log "=================================================================="
if (Test-StepCompleted -StepName "DarkTheme") {
    Write-Log "STEP 5: Dark theme setting already completed. Skipping..."
} else {
    Write-Log "STEP 5: Setting system apps color theme to Dark..."
    try {
        $RegistryPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        If (-NOT (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
        }
        Set-ItemProperty -Path $RegistryPath -Name "AppsUseLightTheme" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $RegistryPath -Name "SystemUsesLightTheme" -Value 0 -Type DWord -Force
        Write-Log "System apps color theme set to Dark. May require sign out/in." -Type "SUCCESS"
        Save-Checkpoint -StepName "DarkTheme"
    }
    catch {
        Write-Log "Error setting dark theme: $($_.Exception.Message)" -Type "ERROR"
    }
}

Write-Log "=================================================================="
Write-Log "                     [STEP 6/8] GIT CONFIGURATION                "
Write-Log "=================================================================="
if ((-not $SkipGitConfig) -and (-not (Test-StepCompleted -StepName "GitConfig"))) {
    Write-Log "STEP 6: Configuring Git..."
    try {
        # Check if git is installed first
        $gitVersion = & git --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Git does not appear to be installed. Skipping Git configuration." -Type "WARNING"
        } else {
            Write-Log "Git found: $gitVersion"

            # Check if Git username and email are already configured
            $existingUserName = & git config --global --get user.name 2>$null
            $existingUserEmail = & git config --global --get user.email 2>$null
            $needsConfiguration = [string]::IsNullOrWhiteSpace($existingUserName) -or [string]::IsNullOrWhiteSpace($existingUserEmail)

            if ($needsConfiguration) {
                Write-Log "Git user information not fully configured. Prompting for details..."

                # Only prompt for username if not already set
                if ([string]::IsNullOrWhiteSpace($existingUserName)) {
                    $gitUserName = Read-Host "Enter your Git username"
                    if (-not [string]::IsNullOrWhiteSpace($gitUserName)) {
                        & git config --global user.name "$gitUserName"
                        Write-Log "Git user.name set to: $gitUserName" -Type "SUCCESS"
                    } else {
                        Write-Log "No Git username provided, skipping user.name configuration" -Type "WARNING"
                    }
                } else {
                    Write-Log "Git user.name already configured as: $existingUserName"
                }

                # Only prompt for email if not already set
                if ([string]::IsNullOrWhiteSpace($existingUserEmail)) {
                    $gitUserEmail = Read-Host "Enter your Git email"
                    if (-not [string]::IsNullOrWhiteSpace($gitUserEmail)) {
                        & git config --global user.email "$gitUserEmail"
                        Write-Log "Git user.email set to: $gitUserEmail" -Type "SUCCESS"
                    } else {
                        Write-Log "No Git email provided, skipping user.email configuration" -Type "WARNING"
                    }
                } else {
                    Write-Log "Git user.email already configured as: $existingUserEmail"
                }


                & git config --global credential.helper manager
                Write-Log "Git credential helper set to: manager" -Type "SUCCESS"

                # Configure Git default branch
                & git config --global init.defaultBranch main
                Write-Log "Git default branch set to: main" -Type "SUCCESS"

                & git config --global pull.rebase false
                & git config --global core.autocrlf true
                Write-Log "Additional Git configurations applied" -Type "SUCCESS"

                # Set Git to use VSCode as default editor if available
                if (Get-Command code -ErrorAction SilentlyContinue) {
                    & git config --global core.editor "code --wait"
                    Write-Log "Git default editor set to: VSCode" -Type "SUCCESS"
                }
            } else {
                Write-Log "Git user information already configured. Username: $existingUserName, Email: $existingUserEmail"

                & git config --global credential.helper manager
                & git config --global init.defaultBranch main
                & git config --global pull.rebase false
                & git config --global core.autocrlf true
                Write-Log "Git configurations applied" -Type "SUCCESS"
            }

            Save-Checkpoint -StepName "GitConfig"
            Write-Log "Git configuration completed successfully." -Type "SUCCESS"
        }
    } catch {
        Write-Log "Failed to configure Git: $($_.Exception.Message)" -Type "ERROR"
    }
} elseif (Test-StepCompleted -StepName "GitConfig") {
    Write-Log "STEP 6: Git configuration already completed. Skipping..."
} else {
    Write-Log "STEP 6: Git configuration skipped due to -SkipGitConfig parameter."
}

Write-Log "=================================================================="
Write-Log "                     [STEP 7/8] DEFENDER EXCLUSIONS              "
Write-Log "=================================================================="
if (Test-StepCompleted -StepName "DefenderExclusions") {
    Write-Log "STEP 7: Windows Defender exclusions already configured. Skipping..."
} elseif ($NoDefenderExclusions) {
    Write-Log "STEP 7: Windows Defender exclusions skipped as requested."
    Save-Checkpoint -StepName "DefenderExclusions"
} else {
    Write-Log "STEP 7: Adding Windows Defender exclusions for development directories..."
    try {

        $devDirs = @(
            (Join-Path $env:USERPROFILE "source"),
            (Join-Path $env:USERPROFILE "projects"),
            (Join-Path $env:USERPROFILE "dev"),
            (Join-Path $env:USERPROFILE "git"),
            (Join-Path $env:USERPROFILE "repos"),
            (Join-Path $env:USERPROFILE "Documents\GitHub"),
            (Join-Path $env:USERPROFILE "Documents\Development"),
            (Join-Path $env:USERPROFILE "Documents\Projects"),
            (Join-Path $env:USERPROFILE "AppData\Local\npm-cache"),
            (Join-Path $env:USERPROFILE "AppData\Roaming\npm"),
            (Join-Path $env:USERPROFILE ".npm"),
            (Join-Path $env:USERPROFILE ".yarn"),
            (Join-Path $env:USERPROFILE ".bun")
        )

        foreach ($dir in $devDirs) {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                Write-Log "Created development directory: $dir"
            }
        }

        foreach ($dir in $devDirs) {
            if (Test-Path $dir) {
                Add-MpPreference -ExclusionPath $dir -ErrorAction SilentlyContinue
                Write-Log "Added Windows Defender exclusion for: $dir" -Type "SUCCESS"
            }
        }

        $processExclusions = @(
            "node.exe",
            "npm.exe",
            "npx.exe",
            "yarn.exe",
            "pnpm.exe",
            "git.exe",
            "bun.exe"
        )

        foreach ($process in $processExclusions) {
            Add-MpPreference -ExclusionProcess $process -ErrorAction SilentlyContinue
            Write-Log "Added Windows Defender exclusion for process: $process" -Type "SUCCESS"
        }

        Write-Log "Windows Defender exclusions added for development directories and processes." -Type "SUCCESS"
        Save-Checkpoint -StepName "DefenderExclusions"
    } catch {
        Write-Log "Error setting up Windows Defender exclusions: $($_.Exception.Message)" -Type "ERROR"
    }
}

Write-Log "=================================================================="
Write-Log "                     SETUP COMPLETED SUCCESSFULLY                 " -Type "SUCCESS"
Write-Log "=================================================================="
try {
    if ((Get-Variable TranscriptLogPath -ErrorAction SilentlyContinue) -and (Test-Path $TranscriptLogPath)) {
     Write-Log "A transcript log of this session has been saved to: $TranscriptLogPath"
    }
} catch {}

Write-Log ""
Write-Log "                === IMPORTANT NEXT STEPS ===                      " -Type "WARNING"
Write-Log ""

Write-Log "A. SYSTEM REBOOT (Highly Recommended):"
Write-Log "   ===================================="
Write-Log "   - A full system reboot is strongly advised for all changes (WSL, Docker, NVM path, PowerToys) to take full effect."
Write-Log ""

Write-Log "B. WSL UBUNTU INITIAL SETUP:"
Write-Log "   ==========================="
Write-Log "   - After rebooting, search 'Ubuntu' in Start Menu and launch it."
Write-Log "   - Create your UNIX username and password when prompted."
if (Test-Path "$env:USERPROFILE\wsl-setup.sh") {
    Write-Log "   - Run the generated setup script in WSL with:"
    Write-Log "     cp /mnt/c/Users/$env:USERNAME/wsl-setup.sh ~/ && chmod +x ~/wsl-setup.sh && ~/wsl-setup.sh"
}
Write-Log ""

Write-Log "C. GIT CONFIGURATION:"
Write-Log "   ==================="
Write-Log "   - Git: Will be configured automatically if not set"
Write-Log "     * Automatic prompt for user.name and user.email if not configured"
Write-Log "     * Use -SkipGitConfig parameter to skip this step"

Write-Log "D. JAVASCRIPT RUNTIME VERIFICATION:"
Write-Log "   =============================="
Write-Log "   - This script attempted to install Node.js LTS and Bun JavaScript runtime."
Write-Log "   - To verify Node.js (AFTER REBOOT and in a NEW terminal):"
Write-Log "     1. Open a NEW terminal (PowerShell, CMD, or Windows Terminal)."
Write-Log "     2. NVM: 'nvm version'"
Write-Log "     3. Node.js: 'node -v'"
Write-Log "     4. npm: 'npm -v'"
Write-Log "   - If needed, run: 'nvm install lts && nvm use lts && nvm alias default lts'"
Write-Log "   - To verify Bun installation:"
Write-Log "     1. Run: 'bun --version'"
Write-Log "     2. If not found, ensure PATH includes: %USERPROFILE%\.bun\bin"
Write-Log ""

Write-Log "E. TOOL CONFIGURATION & USAGE:"
Write-Log "   ============================"
Write-Log "   - Docker Desktop: Launch, accept terms. Should use WSL 2."
Write-Log "   - VS Code: Launch. Consider these extensions:"
Write-Log "     * Remote - WSL"
Write-Log "     * ESLint"
Write-Log "     * Prettier"
Write-Log "     * GitLens"
Write-Log "   - PowerToys: Search 'PowerToys' in Start Menu to configure."
Write-Log "   - Windows Terminal: Configure profiles for WSL."
Write-Log ""

Write-Log "F. WINDOWS UPDATES & DEFENDER:"
Write-Log "   ============================"
Write-Log "   - Windows Update is configured to NOTIFY before download/install."
Write-Log "   - Windows Defender exclusions have been added for development directories and processes."
Write-Log "   - Includes exclusions for Node.js, Bun, and other development tools."
Write-Log "   - Manage via Windows Settings > Update & Security."
Write-Log ""

Write-Log "G. RESUME FUNCTIONALITY:"
Write-Log "   ======================="
Write-Log "   - If you need to run this script again, you can resume from where you left off:"
Write-Log "     .\fresh-install.ps1 -Resume"
Write-Log "   - Skip automatic Git configuration:"
Write-Log "     .\fresh-install.ps1 -SkipGitConfig"
Write-Log "   - Or you can run with custom tools:"
Write-Log "     .\fresh-install.ps1 -CustomTools @{'WebStorm' = 'JetBrains.WebStorm'}"
Write-Log ""

Write-Log "Enjoy your new web development environment!" -Type "SUCCESS"
Write-Log "------------------------------------------------------------------"

try { Stop-Transcript } catch {}

if ((-not $SkipGitConfig) -and (-not (Test-StepCompleted -StepName "GitUserConfig"))) {
    Write-Log "STEP 8: Checking Git configuration..."
    try {
        # Check if git is installed first
        $gitVersion = & git --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Git does not appear to be installed. Skipping Git configuration." -Type "WARNING"
        } else {
            Write-Log "Git found: $gitVersion"

            # Check if Git username and email are already configured
            $existingUserName = & git config --global --get user.name 2>$null
            $existingUserEmail = & git config --global --get user.email 2>$null
            $needsConfiguration = [string]::IsNullOrWhiteSpace($existingUserName) -or [string]::IsNullOrWhiteSpace($existingUserEmail)

            if ($needsConfiguration) {
                Write-Log "Git user information not fully configured. Prompting for details..."

                # Only prompt for username if not already set
                if ([string]::IsNullOrWhiteSpace($existingUserName)) {
                    $gitUserName = Read-Host "Enter your Git username"
                    if (-not [string]::IsNullOrWhiteSpace($gitUserName)) {
                        & git config --global user.name "$gitUserName"
                        Write-Log "Git user.name set to: $gitUserName" -Type "SUCCESS"
                    } else {
                        Write-Log "No Git username provided, skipping user.name configuration" -Type "WARNING"
                    }
                } else {
                    Write-Log "Git user.name already configured as: $existingUserName"
                }

                # Only prompt for email if not already set
                if ([string]::IsNullOrWhiteSpace($existingUserEmail)) {
                    $gitUserEmail = Read-Host "Enter your Git email"
                    if (-not [string]::IsNullOrWhiteSpace($gitUserEmail)) {
                        & git config --global user.email "$gitUserEmail"
                        Write-Log "Git user.email set to: $gitUserEmail" -Type "SUCCESS"
                    } else {
                        Write-Log "No Git email provided, skipping user.email configuration" -Type "WARNING"
                    }
                } else {
                    Write-Log "Git user.email already configured as: $existingUserEmail"
                }

                & git config --global credential.helper wincred
                Write-Log "Git credential helper set to: wincred" -Type "SUCCESS"

                # Configure Git default branch
                & git config --global init.defaultBranch main
                Write-Log "Git default branch set to: main" -Type "SUCCESS"

                # Set Git to use VSCode as default editor if available
                if (Get-Command code -ErrorAction SilentlyContinue) {
                    & git config --global core.editor "code --wait"
                    Write-Log "Git default editor set to: VSCode" -Type "SUCCESS"
                }
            } else {
                Write-Log "Git user information already configured. Username: $existingUserName, Email: $existingUserEmail"
            }

            Save-Checkpoint -StepName "GitUserConfig"
            Write-Log "Git configuration check completed successfully." -Type "SUCCESS"
        }
    } catch {
        Write-Log "Failed to configure Git user information: $($_.Exception.Message)" -Type "ERROR"
    }
} elseif (Test-StepCompleted -StepName "GitUserConfig") {
    Write-Log "STEP 8: Git configuration already completed. Skipping..."
} else {
    Write-Log "STEP 8: Git configuration skipped due to -SkipGitConfig parameter."
}

if ($RebootWhenDone) {
    Write-Log "Automatic reboot requested. System will restart in 15 seconds..." -Type "WARNING"
    Write-Log "Press Ctrl+C to cancel the reboot (not recommended)." -Type "WARNING"

    for ($i = 15; $i -gt 0; $i--) {

        Write-Host "Rebooting in $i seconds..." -ForegroundColor Yellow -NoNewline
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline
    }

    Restart-Computer -Force
} else {

    if ($Host.UI.Name -eq 'ConsoleHost') {
        $rebootNow = Read-Host "Setup script finished. Would you like to reboot now? (y/n)"
        if ($rebootNow -match "^[yY]") {
            Write-Log "Manual reboot requested. System will restart in 5 seconds..." -Type "WARNING"
            Start-Sleep -Seconds 5
            Restart-Computer -Force
        } else {
            Write-Log "Remember to reboot your system manually to complete the setup." -Type "WARNING"
            Read-Host "Press Enter to close this window..."
        }
    }
}

Exit 0

