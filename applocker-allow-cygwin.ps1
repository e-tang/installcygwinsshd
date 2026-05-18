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
    $xml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="$(New-Guid)" Name="Allow Cygwin executables" Description="Allow executables under $CygwinRoot" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="$CygwinRoot\*"/></Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
    Set-AppLockerPolicy -XmlPolicy $xml -Merge
    gpupdate /force | Out-Null
    Write-Host "AppLocker rule added. Cygwin executables are now whitelisted." -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
