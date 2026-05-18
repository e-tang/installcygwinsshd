Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
$ErrorActionPreference = "Stop"

$ScriptVersion = "1.0.0"
$ScriptBuild    = "20260518"
Write-Host "Install Cygwin SSHD v$ScriptVersion (build $ScriptBuild)" -ForegroundColor Cyan

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then try again." -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit"
    exit 1
}

try {
    # Resolution order: env override → registry (existing install) → default
    if ($env:CYGWIN_ROOT) {
        $CygwinRoot = $env:CYGWIN_ROOT
        Write-Host "Using CYGWIN_ROOT override: $CygwinRoot" -ForegroundColor Cyan
    } elseif (Test-Path "HKLM:\SOFTWARE\Cygwin\setup") {
        $CygwinRoot = (Get-ItemProperty "HKLM:\SOFTWARE\Cygwin\setup" -ErrorAction SilentlyContinue).rootdir
        Write-Host "Detected existing Cygwin installation at: $CygwinRoot" -ForegroundColor Cyan
    } else {
        $CygwinRoot = "C:\cygwin64"
    }

    $Bash        = "$CygwinRoot\bin\bash.exe"
    $CygwinSetup = "$env:TEMP\cygwin-setup-x86_64.exe"

    if (-not (Test-Path $Bash)) {
        Write-Host "=== Cygwin not found. Installing Cygwin... ===" -ForegroundColor Cyan

        if (Test-Path $CygwinRoot) {
            Write-Host "Removing leftover Cygwin directory..." -ForegroundColor Yellow
            Remove-Item -Recurse -Force $CygwinRoot
        }

        Write-Host "Removing Cygwin registry entries..." -ForegroundColor Yellow
        $regKeys = @(
            "HKLM:\SOFTWARE\Cygwin",
            "HKLM:\SOFTWARE\WOW6432Node\Cygwin",
            "HKCU:\SOFTWARE\Cygwin"
        )
        foreach ($key in $regKeys) {
            if (Test-Path $key) {
                Remove-Item -Recurse -Force $key
                Write-Host "  Removed $key" -ForegroundColor Gray
            }
        }
        try {
            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "CYGWIN" -ErrorAction SilentlyContinue
        } catch {}

        Write-Host "Downloading Cygwin installer..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "https://cygwin.com/setup-x86_64.exe" -OutFile $CygwinSetup -UseBasicParsing

        $CygwinPkgDir = "$env:TEMP\cygwin-packages"
        New-Item -ItemType Directory -Force -Path $CygwinPkgDir | Out-Null

        Write-Host "Running Cygwin installer (this may take several minutes)..." -ForegroundColor Yellow
        $setupArgs = @(
            "--quiet-mode",
            "--no-shortcuts",
            "--no-startmenu",
            "--no-desktop",
            "--root", $CygwinRoot,
            "--local-package-dir", $CygwinPkgDir,
            "--site", "https://mirrors.kernel.org/sourceware/cygwin/",
            "--packages", "base-cygwin,base-files,libiconv2,openssh,git"
        )
        $proc = Start-Process -FilePath $CygwinSetup -ArgumentList $setupArgs -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -ne 0) {
            $CygwinLog = "$CygwinRoot\var\log\setup.log"
            if (Test-Path $CygwinLog) {
                Write-Host "`nCygwin setup log (last 30 lines):" -ForegroundColor Yellow
                Get-Content $CygwinLog | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
            }
            throw "Cygwin installation failed with exit code $($proc.ExitCode)."
        }

        if (-not (Test-Path $Bash)) {
            throw "Cygwin installation completed but bash.exe not found at $Bash."
        }

        Write-Host "Cygwin installed successfully." -ForegroundColor Green
    }

    function Invoke-Cygwin($cmd) {
        $result = & $Bash --login -c $cmd 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Cygwin command failed (exit $LASTEXITCODE): $cmd`nOutput: $result"
        }
        return $result
    }

    Write-Host "=== Step 1: Running ssh-host-config ===" -ForegroundColor Cyan

    $existingSvc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
    if ($null -ne $existingSvc) {
        Write-Host "Removing stale sshd service..." -ForegroundColor Yellow
        Stop-Service -Name "sshd" -Force -ErrorAction SilentlyContinue
        & sc.exe delete sshd
        Write-Host "Waiting for service to be fully removed..." -ForegroundColor Yellow
        $timeout = 30
        $elapsed = 0
        while ((Get-Service -Name "sshd" -ErrorAction SilentlyContinue) -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 2
            $elapsed += 2
            Write-Host "  Still waiting... ($elapsed s)" -ForegroundColor Gray
        }
        if (Get-Service -Name "sshd" -ErrorAction SilentlyContinue) {
            throw "sshd service could not be removed after $timeout seconds. Try rebooting and re-running."
        }
        Write-Host "Service removed." -ForegroundColor Green
    }

    # Run ssh-host-config as SYSTEM via a scheduled task — SYSTEM always has
    # full SCM rights to create services, bypassing UAC token filtering.
    $taskName = "CygwinSSHDSetup"
    $sshdLog  = "$CygwinRoot\tmp\sshd-setup.log"
    New-Item -ItemType Directory -Force -Path "$CygwinRoot\tmp" | Out-Null

    $taskArg   = "--login -c `"ssh-host-config --yes --cygwin ntsec --name sshd --port 22 > /tmp/sshd-setup.log 2>&1`""
    $action    = New-ScheduledTaskAction -Execute $Bash -Argument $taskArg
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

    Write-Host "Running ssh-host-config as SYSTEM..." -ForegroundColor Yellow
    Start-ScheduledTask -TaskName $taskName

    $timeout = 60; $elapsed = 0
    while ((Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State -eq "Running" -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 2; $elapsed += 2
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null

    if (Test-Path $sshdLog) {
        Write-Host (Get-Content $sshdLog -Raw)
    }

    Write-Host "=== Step 2: Setting CYGWIN environment variable ===" -ForegroundColor Cyan
    try {
        & reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v CYGWIN /t REG_SZ /d ntsec /f 2>&1 | Out-Null
    } catch {
        Write-Host "Warning: could not set CYGWIN env var (non-fatal, ntsec is the default in modern Cygwin)." -ForegroundColor Yellow
    }

    Write-Host "=== Step 3: Configuring Windows Firewall ===" -ForegroundColor Cyan
    $ruleName = "Cygwin SSHD"
    if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null
        Write-Host "Firewall rule created." -ForegroundColor Green
    } else {
        Write-Host "Firewall rule already exists." -ForegroundColor Yellow
    }

    Write-Host "=== Step 4: Starting sshd service ===" -ForegroundColor Cyan
    $svc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        throw "sshd service not found. ssh-host-config may have failed."
    }

    Set-Service -Name "sshd" -StartupType Automatic
    Start-Service -Name "sshd"

    $svc = Get-Service -Name "sshd"
    if ($svc.Status -eq "Running") {
        Write-Host "sshd service is RUNNING." -ForegroundColor Green
    } else {
        Write-Host "sshd service failed to start. Status: $($svc.Status)" -ForegroundColor Red
    }

} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
} finally {
    Read-Host "`nPress Enter to exit"
}
