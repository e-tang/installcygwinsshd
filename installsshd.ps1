Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then try again." -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit"
    exit 1
}

try {
    $CygwinRoot  = "C:\cygwin64"
    $Bash        = "$CygwinRoot\bin\bash.exe"
    $CygwinSetup = "$env:TEMP\cygwin-setup-x86_64.exe"

    if (-not (Test-Path $Bash)) {
        Write-Host "=== Cygwin not found. Installing Cygwin... ===" -ForegroundColor Cyan

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
            "--packages", "openssh,git"
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
        return $result
    }

    Write-Host "=== Step 1: Running ssh-host-config ===" -ForegroundColor Cyan
    $configCmd = "ssh-host-config --yes --cygwin 'ntsec' --name 'sshd' --port 22 --user 'cyg_server'"
    $output = Invoke-Cygwin $configCmd
    Write-Host $output

    Write-Host "=== Step 2: Setting CYGWIN environment variable ===" -ForegroundColor Cyan
    [System.Environment]::SetEnvironmentVariable("CYGWIN", "ntsec", "Machine")

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
