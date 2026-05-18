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

**From PowerShell (as Administrator):**

```powershell
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex
```

**From a Cygwin/Linux bash session (e.g. over SSH):**

```bash
powershell -Command "irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex"
```

Then connect from any SSH client:

```bash
ssh your-username@hostname-or-ip
```

### AppLocker / service creation issues

If `cygrunsrv` fails with `Win32 error 5: Access is denied` when creating the
sshd service, AppLocker may be blocking it. Run one of these scripts first
(as Administrator), then re-run `installsshd.ps1`:

**Option 1 — Whitelist Cygwin path (recommended)**

Adds a single AppLocker path rule to allow `$CYGWIN_ROOT\*`. Everything else
stays enforced.

*PowerShell:*
```powershell
# Default install path (C:\cygwin64)
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/applocker-allow-cygwin.ps1 | iex
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex

# Custom install path (e.g. D:\cygwin64)
$env:CYGWIN_ROOT="D:\cygwin64"; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/applocker-allow-cygwin.ps1 | iex
$env:CYGWIN_ROOT="D:\cygwin64"; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex
```

*Bash (over SSH):*
```bash
powershell -Command "irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/applocker-allow-cygwin.ps1 | iex; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex"

# Custom install path (e.g. D:\cygwin64)
powershell -Command "\$env:CYGWIN_ROOT='D:\cygwin64'; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/applocker-allow-cygwin.ps1 | iex; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex"
```

Then connect:

```bash
ssh your-username@hostname-or-ip
```

**Option 2 — Set AppLocker to Audit mode**

AppLocker logs blocked executables but no longer prevents them from running.
Useful when you want to keep visibility without blocking.

*PowerShell:*
```powershell
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/applocker-audit-mode.ps1 | iex
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex
```

*Bash (over SSH):*
```bash
powershell -Command "irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/applocker-audit-mode.ps1 | iex; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex"
```

Then connect:

```bash
ssh your-username@hostname-or-ip
```

**Option 3 — Disable AppLocker entirely**

Stops and disables the AppIDSvc service. Use this only if the other options
are not sufficient.

*PowerShell:*
```powershell
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/applocker-disable.ps1 | iex
irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex
```

*Bash (over SSH):*
```bash
powershell -Command "irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/applocker-disable.ps1 | iex; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex"
```

Then connect:

```bash
ssh your-username@hostname-or-ip
```

> **Note:** If the machine is domain-joined, Group Policy may revert these
> changes on the next `gpupdate`. Apply the fix at the domain GPO level for a
> permanent change.

### Custom install path

The script detects an existing Cygwin installation from the registry automatically.
To install to a different drive or path, set `$env:CYGWIN_ROOT` before running:

*PowerShell:*
```powershell
$env:CYGWIN_ROOT="D:\cygwin64"; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex
```

*Bash (over SSH):*
```bash
powershell -Command "\$env:CYGWIN_ROOT='D:\cygwin64'; irm https://raw.githubusercontent.com/e-tang/installcygwinsshd/refs/heads/master/installsshd.ps1 | iex"
```
