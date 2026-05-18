# Install Cygwin SSHD on Windows

Automatically installs Cygwin (with `openssh` and `git`) and configures it as a Windows SSH service.

## What it does

1. Downloads and installs Cygwin if not already present
2. Runs `ssh-host-config` to set up the SSHD service
3. Opens port 22 in the Windows Firewall
4. Starts the `sshd` service and sets it to start automatically

## Requirements

- Windows 10 / Windows Server 2016 or later
- PowerShell 5.1 or later
- Must be run as **Administrator**

## Usage

Open PowerShell **as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex
```

The window will stay open when the script finishes. Press **Enter** to close it.

### Custom install path

The script detects an existing Cygwin installation from the registry automatically.
To install to a different drive or path, set `$env:CYGWIN_ROOT` before running:

```powershell
$env:CYGWIN_ROOT = "D:\cygwin64"
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex
```
