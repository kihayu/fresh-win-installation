# 🚀 Fresh Windows Development Environment Setup

## 📋 Overview
Automate the setup of a Windows machine for web development and general productivity with this PowerShell script. Perfect for getting a new machine or fresh Windows installation ready for development work quickly and consistently.

## ✨ Features

### 🔍 System Preparation
- ✅ Runs prerequisite checks (admin privileges, internet connectivity, Windows version)
- ✅ Sets appropriate PowerShell execution policies
- ✅ Creates detailed logs of all operations

### 🔄 Windows Configuration
- ⚙️ Configures Windows Updates to notify before download and install
- 🌙 Sets system app color theme to dark mode
- 🛡️ Adds Windows Defender exclusions for development directories and processes

### 🐧 WSL 2 Setup
- 🔌 Enables necessary Windows features for WSL 2
- 📦 Installs WSL 2 and sets it as default
- 🐧 Installs the latest Ubuntu distribution
- 🔧 Sets up the WSL environment with essential tools

### 🛠️ Development Tools
- 📦 Installs a suite of development tools using Winget:
  - Git, VS Code, Docker Desktop
  - Browsers (Chrome, Firefox, Edge)
  - Terminal utilities and productivity tools
- 📊 Installs Bun JavaScript runtime
- 📚 Installs Node.js LTS using NVM
- 🔄 Configures Git with sensible defaults

## 📋 Prerequisites
- Windows 10 (build 19041+) or Windows 11
- Administrator privileges
- Internet connection
- PowerShell 5.1 or later

## 💻 Usage

### Basic Usage
```powershell
.\fresh-install.ps1
```

### Advanced Usage
```powershell
.\fresh-install.ps1 -CustomTools @{"WebStorm" = "JetBrains.WebStorm"} -RebootWhenDone
```

## ⚙️ Parameters

| Parameter | Description |
|-----------|-------------|
| `-SkipWSL` | Skip the WSL installation steps |
| `-SkipUpdates` | Skip Windows Updates configuration |
| `-CustomTools` | Hashtable of additional tools to install `@{"Tool Name" = "Package.Id"}` |
| `-RebootWhenDone` | Automatically reboot after script completion |
| `-Resume` | Resume from the last successful step |
| `-NoDefenderExclusions` | Skip adding Windows Defender exclusions |
| `-SkipGitConfig` | Skip Git configuration steps |

## 📝 Post-Installation
After running the script, you may want to:

1. 🔄 **Reboot your system** (if not done automatically)
2. 🐳 **Configure Docker Desktop** - Launch and accept terms
3. 📝 **Set up VS Code** - Install recommended extensions:
   - Remote - WSL
   - ESLint, Prettier
   - Language-specific extensions

4. 🔑 **Complete Git Configuration** - Set your username and email if prompted

## 🚨 Troubleshooting
- Check the log file created in your user profile directory
- If a step fails, you can use the `-Resume` parameter to continue from the last successful step
- For WSL issues, refer to the Microsoft documentation

## 👥 Contributing
Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License
This project is open source and available under the MIT License.
