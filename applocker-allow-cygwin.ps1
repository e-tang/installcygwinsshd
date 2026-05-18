Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

$CygwinRoot = if ($env:CYGWIN_ROOT) { $env:CYGWIN_ROOT }
              elseif (Test-Path "HKLM:\SOFTWARE\Cygwin\setup") { (Get-ItemProperty "HKLM:\SOFTWARE\Cygwin\setup").rootdir }
              else { "C:\cygwin64" }

Write-Host "Adding AppLocker path rule to allow: $CygwinRoot\*" -ForegroundColor Cyan

try {
    $ruleId  = "{$([Guid]::NewGuid())}"
    $ruleXml = "<FilePathRule Id=`"$ruleId`" Name=`"Allow Cygwin executables`" " +
               "Description=`"Allow executables under $CygwinRoot`" " +
               "UserOrGroupSid=`"S-1-1-0`" Action=`"Allow`">" +
               "<Conditions><FilePathCondition Path=`"$CygwinRoot\*`"/></Conditions>" +
               "</FilePathRule>"

    $exeKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2\Exe"
    if (-not (Test-Path $exeKey)) {
        New-Item -Path $exeKey -Force | Out-Null
    }
    New-ItemProperty -Path $exeKey -Name $ruleId -Value $ruleXml -PropertyType String -Force | Out-Null

    gpupdate /force | Out-Null
    Write-Host "AppLocker rule added. Cygwin executables are now whitelisted." -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
