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

    # ── Diagnostics ────────────────────────────────────────────────────────────
    Write-Host "`n=== Diagnostics ===" -ForegroundColor Magenta

    Write-Host "  [1] Testing bash..." -ForegroundColor Yellow
    try {
        $r = & $Bash --login -c "echo bash_ok" 2>&1
        Write-Host "      Bash result: $r" -ForegroundColor Gray
    } catch { Write-Host "      Bash ERROR: $_" -ForegroundColor Red }

    Write-Host "  [2] Testing cygrunsrv directly from PowerShell..." -ForegroundColor Yellow
    $cygrunsrv = "$CygwinRoot\bin\cygrunsrv.exe"
    if (Test-Path $cygrunsrv) {
        $r = & $cygrunsrv --list 2>&1
        Write-Host "      cygrunsrv --list: $r" -ForegroundColor Gray
    } else {
        Write-Host "      cygrunsrv.exe not found at $cygrunsrv" -ForegroundColor Red
    }

    Write-Host "  [3] Checking AppLocker policy..." -ForegroundColor Yellow
    try {
        $alp = Get-AppLockerPolicy -Effective -ErrorAction Stop
        Write-Host "      AppLocker IS active. Rule collections:" -ForegroundColor Red
        $alp.RuleCollections | ForEach-Object {
            Write-Host "        - $($_.RuleCollectionType) ($($_.Count) rules, EnforcementMode: $($_.EnforcementMode))" -ForegroundColor Yellow
        }
    } catch { Write-Host "      AppLocker: not configured" -ForegroundColor Gray }

    Write-Host "  [4] Checking Software Restriction Policy..." -ForegroundColor Yellow
    $srpKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
    if (Test-Path $srpKey) {
        $level = (Get-ItemProperty $srpKey -ErrorAction SilentlyContinue).DefaultLevel
        Write-Host "      SRP DefaultLevel: $level (0=Disallowed, 131072=Normal, 262144=Unrestricted)" -ForegroundColor Yellow
    } else { Write-Host "      SRP: not configured" -ForegroundColor Gray }

    Write-Host "  [5] Checking WDAC (Windows Defender App Control)..." -ForegroundColor Yellow
    $wdac = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
    if ($wdac) {
        Write-Host "      CodeIntegrityPolicyEnforcementStatus: $($wdac.CodeIntegrityPolicyEnforcementStatus)" -ForegroundColor Yellow
        Write-Host "      UsermodeCodeIntegrityPolicyEnforcementStatus: $($wdac.UsermodeCodeIntegrityPolicyEnforcementStatus)" -ForegroundColor Yellow
    } else { Write-Host "      WDAC: not detectable or not active" -ForegroundColor Gray }

    Write-Host "  [6] Recent AppLocker/SRP events (last 10 min)..." -ForegroundColor Yellow
    try {
        $evts = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppLocker/EXE and DLL'; Level=2,3; StartTime=(Get-Date).AddMinutes(-10)} -MaxEvents 10 -ErrorAction Stop
        $evts | ForEach-Object { Write-Host "      $($_.TimeCreated): $($_.Message)" -ForegroundColor Red }
    } catch { Write-Host "      No AppLocker EXE/DLL block events found" -ForegroundColor Gray }

    Write-Host "  [7] Current session identity and privileges..." -ForegroundColor Yellow
    Write-Host "      User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Gray
    $privs = & whoami /priv 2>&1 | Where-Object { $_ -match "SeServiceLogon|SeCreatePermanent|SeTcb|SeDebug|ENABLED" }
    $privs | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }

    Write-Host "  [8] Testing sc.exe service creation with a system binary..." -ForegroundColor Yellow
    $scTest = & sc.exe create CygwinDiagSvc binPath= "C:\Windows\System32\cmd.exe" start= demand 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      SUCCESS — service creation with system binary works" -ForegroundColor Green
        & sc.exe delete CygwinDiagSvc 2>&1 | Out-Null
    } else {
        Write-Host "      FAILED — service creation is blocked entirely: $scTest" -ForegroundColor Red
    }

    Write-Host "  [9] Testing sc.exe service creation with D:\ binary..." -ForegroundColor Yellow
    $scTest2 = & sc.exe create CygwinDiagSvc2 binPath= "`"$CygwinRoot\bin\cygrunsrv.exe`"" start= demand 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      SUCCESS — service creation from D:\ works" -ForegroundColor Green
        & sc.exe delete CygwinDiagSvc2 2>&1 | Out-Null
    } else {
        Write-Host "      FAILED — D:\ path is blocked: $scTest2" -ForegroundColor Red
    }

    Write-Host "" -ForegroundColor Gray
    # ── End Diagnostics ────────────────────────────────────────────────────────

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

    Write-Host "=== Step 4: Registering sshd as a scheduled task ===" -ForegroundColor Cyan

    Unregister-ScheduledTask -TaskName "CygwinSSHD" -Confirm:$false -ErrorAction SilentlyContinue

    $sshdAction    = New-ScheduledTaskAction -Execute $Bash -Argument '--login -c "/usr/sbin/sshd -D"'
    $sshdTrigger   = New-ScheduledTaskTrigger -AtStartup
    $sshdPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    $sshdSettings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 0) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName "CygwinSSHD" -Action $sshdAction -Trigger $sshdTrigger `
        -Principal $sshdPrincipal -Settings $sshdSettings -Description "Cygwin OpenSSH Server" -Force | Out-Null
    Write-Host "sshd task registered (starts at boot as SYSTEM)." -ForegroundColor Green

    Start-ScheduledTask -TaskName "CygwinSSHD"
    Start-Sleep -Seconds 3

    $task = Get-ScheduledTask -TaskName "CygwinSSHD" -ErrorAction SilentlyContinue
    if ($task.State -eq "Running") {
        Write-Host "sshd is RUNNING." -ForegroundColor Green
    } else {
        Write-Host "sshd task state: $($task.State) — check Task Scheduler for details." -ForegroundColor Yellow
    }

} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
} finally {
    Read-Host "`nPress Enter to exit"
}
