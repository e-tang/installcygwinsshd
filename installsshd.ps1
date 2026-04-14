$CygwinRoot = "C:\cygwin64"
$Bash       = "$CygwinRoot\bin\bash.exe"

if (-not (Test-Path $Bash)) {
    Write-Error "Cygwin not found at $CygwinRoot. Adjust the path and re-run."
    exit 1
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
    Write-Error "sshd service not found. ssh-host-config may have failed."
    exit 1
}

Set-Service -Name "sshd" -StartupType Automatic
Start-Service -Name "sshd"

$svc = Get-Service -Name "sshd"
if ($svc.Status -eq "Running") {
    Write-Host "sshd service is RUNNING." -ForegroundColor Green
} else {
    Write-Host "sshd service failed to start. Status: $($svc.Status)" -ForegroundColor Red
}
