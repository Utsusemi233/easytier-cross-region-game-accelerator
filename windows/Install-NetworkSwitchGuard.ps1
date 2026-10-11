param([Parameter(Mandatory=$true)][string]$ConfigPath,[switch]$Apply,[switch]$Remove)
$ErrorActionPreference='Stop'
if ($Apply -and $Remove) { throw 'Choose Apply or Remove.' }
$configFile=(Resolve-Path -LiteralPath $ConfigPath).Path
$config=[IO.File]::ReadAllText($configFile)|ConvertFrom-Json
$scriptFile=Join-Path $PSScriptRoot 'Network-SwitchGuard.ps1'
if (-not (Test-Path -LiteralPath $scriptFile) -or -not [IO.Path]::IsPathRooted($config.state_directory)) { throw 'Invalid installation files.' }
. $scriptFile
Assert-NetworkSwitchGuardConfig $config
$taskName='EasyTier Network Switch DNS Guard'
if (-not $Apply -and -not $Remove) {
    [pscustomobject]@{mode='plan';task=$taskName;script=$scriptFile;profiles=@($config.profiles.alias);scope='Refresh DNS cache after stable network/owned-route changes; preserve official GUI, routes and running games.'};return
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator permission is required.' }
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing -and -not @($existing.Actions|Where-Object {$_.Arguments.Contains($scriptFile) -and $_.Arguments.Contains($configFile)}).Count) { throw 'An unrelated task uses the same name.' }
if ($existing) { Stop-ScheduledTask -TaskName $taskName; Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
if ($Remove) { 'Removed only the DNS switch guard task.'; return }
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$scriptFile+'" -ConfigPath "'+$configFile+'"')
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 10 -RestartInterval ([TimeSpan]::FromMinutes(1)) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$triggers=@(New-ScheduledTaskTrigger -AtStartup;New-ScheduledTaskTrigger -AtLogOn)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings -User SYSTEM -RunLevel Highest -Description 'Refreshes stale DNS cache after Wi-Fi or owned EasyTier route changes; retains the official client and running applications.'|Out-Null
Start-ScheduledTask -TaskName $taskName
'Installed DNS cache maintenance for network and EasyTier transitions.'
