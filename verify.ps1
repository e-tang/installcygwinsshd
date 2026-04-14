$CygwinRoot = "C:\cygwin64"

Write-Host "=== Service Status ===" -ForegroundColor Cyan
$svc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Name   : $($svc.Name)"
    Write-Host "Status : $($svc.Status)"
    Write-Host "Start  : $($svc.StartType)"
} else {
    Write-Host "sshd service NOT found." -ForegroundColor Red
}

Write-Host "`n=== Firewall Rules (Port 22) ===" -ForegroundColor Cyan
Get-NetFirewallRule | Where-Object { $_.DisplayName -match "ssh" } |
    Select-Object DisplayName, Enabled, Direction, Action | Format-Table -AutoSize

Write-Host "`n=== Port 22 Listening ===" -ForegroundColor Cyan
$listening = netstat -ano | Select-String ":22 "
if ($listening) {
    $listening | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "Nothing listening on port 22." -ForegroundColor Red
}

Write-Host "`n=== Cygwin sshd_config exists ===" -ForegroundColor Cyan
$sshdConfig = "$CygwinRoot\etc\sshd_config"
if (Test-Path $sshdConfig) {
    Write-Host "Found: $sshdConfig" -ForegroundColor Green
    Get-Content $sshdConfig | Where-Object { $_ -match "^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" }
} else {
    Write-Host "sshd_config NOT found. ssh-host-config has not run yet." -ForegroundColor Red
}

Write-Host "`n=== cyg_server account ===" -ForegroundColor Cyan
$u = Get-LocalUser -Name "cyg_server" -ErrorAction SilentlyContinue
if ($u) {
    Write-Host "cyg_server exists. Enabled: $($u.Enabled)"
} else {
    Write-Host "cyg_server account NOT found." -ForegroundColor Yellow
}

Write-Host "`n=== Recent sshd Event Log ===" -ForegroundColor Cyan
Get-EventLog -LogName System -Source "*sshd*","*cygsshd*" -Newest 10 -ErrorAction SilentlyContinue |
    Select-Object TimeGenerated, EntryType, Message | Format-List
