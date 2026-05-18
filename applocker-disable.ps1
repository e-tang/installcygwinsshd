Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "Disabling AppLocker..." -ForegroundColor Cyan

try {
    Stop-Service -Name AppIDSvc -Force -ErrorAction SilentlyContinue
    Set-Service -Name AppIDSvc -StartupType Disabled
    Write-Host "AppLocker service (AppIDSvc) stopped and disabled." -ForegroundColor Green
    Write-Host "Note: domain Group Policy may re-enable this on next gpupdate." -ForegroundColor Yellow
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
