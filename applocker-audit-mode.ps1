Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "Setting AppLocker to Audit mode (non-blocking)..." -ForegroundColor Cyan

try {
    $collections = @("Exe", "Script", "Msi", "Dll", "Appx")
    foreach ($c in $collections) {
        $key = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2\$c"
        if (Test-Path $key) {
            Set-ItemProperty -Path $key -Name "EnforcementMode" -Value 0 -Type DWord
            Write-Host "  $c -> Audit mode" -ForegroundColor Gray
        }
    }
    gpupdate /force | Out-Null
    Write-Host "AppLocker is now in Audit mode — executables are logged but not blocked." -ForegroundColor Green
    Write-Host "Note: domain Group Policy may revert this on next gpupdate." -ForegroundColor Yellow
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
