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

### AppLocker / service creation issues

If `cygrunsrv` fails with `Win32 error 5: Access is denied` when creating the
sshd service, AppLocker may be blocking it. Run one of these scripts first
(as Administrator), then re-run `installsshd.ps1`:

| Script | Effect |
|--------|--------|
| `applocker-allow-cygwin.ps1` | Adds a path rule to allow `$CYGWIN_ROOT\*` (recommended) |
| `applocker-audit-mode.ps1` | Sets AppLocker to Audit mode (logs only, not blocking) |
| `applocker-disable.ps1` | Disables AppLocker entirely |

```powershell
# Example — whitelist Cygwin on D:\
$env:CYGWIN_ROOT="D:\cygwin64"; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/applocker-allow-cygwin.ps1 | iex
```

> **Note:** If the machine is domain-joined, Group Policy may revert these
> changes on the next `gpupdate`. Apply the fix at the domain GPO level for a
> permanent change.

### Custom install path

The script detects an existing Cygwin installation from the registry automatically.
To install to a different drive or path, set `$env:CYGWIN_ROOT` before running:

```powershell
$env:CYGWIN_ROOT = "D:\cygwin64"
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex
```
