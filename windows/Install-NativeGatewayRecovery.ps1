param([Parameter(Mandatory=$true)][string]$ConfigPath,[switch]$Apply,[switch]$Remove)
$ErrorActionPreference='Stop'
if($Apply -and $Remove){throw 'Choose Apply or Remove.'}
$configFile=(Resolve-Path -LiteralPath $ConfigPath).Path
$config=Get-Content $configFile -Raw -Encoding UTF8|ConvertFrom-Json
. (Join-Path $PSScriptRoot 'NativeGatewayRecovery.ps1') -ConfigPath $configFile
Assert-NativeGatewayConfig $config
$prefixes=[string[]]@(Get-DirectRegionalPrefixes $config.prefixes_file)
$taskName='EasyTier Native Gateway Recovery '+$config.tunnel_alias
$scriptFile=Join-Path $PSScriptRoot 'NativeGatewayRecovery.ps1'
if(-not $Apply -and -not $Remove){[pscustomobject]@{mode='plan';task=$taskName;interface=$config.tunnel_alias;prefixes=$prefixes.Count;scope='Owned selected IPv4 routes and physical-underlay recovery; official GUI retained'};return}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator permission is required.'}
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($existing -and -not @($existing.Actions|Where-Object {$_.Arguments.Contains($configFile) -and $_.Arguments.Contains('NativeGatewayRecovery.ps1')}).Count){throw 'An unrelated task uses the same name.'}
if($existing){Stop-ScheduledTask -TaskName $taskName;Unregister-ScheduledTask -TaskName $taskName -Confirm:$false;Start-Sleep -Milliseconds 500}
if($Remove){
 $path=Join-Path $config.state_directory 'managed-interface.private.json'
 if(Test-Path $path){$record=Get-Content $path -Raw -Encoding UTF8|ConvertFrom-Json;Set-ScopedIPv4Routes $record.interface_index ([string[]]$record.prefixes) $config.route_metric $false;Set-ScopedIPv4Routes $record.interface_index ([string[]]$record.probes) $config.probe_route_metric $false}
 $path=Join-Path $config.state_directory 'owned-bypasses.private.json'
 if(Test-Path $path){foreach($entry in @(Get-Content $path -Raw -Encoding UTF8|ConvertFrom-Json)){Remove-RoamingOwnedRoute $entry};Write-RoamingJson $path @()}
 'Removed only this gateway profile maintenance and owned routes.';return
}
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$scriptFile+'" -ConfigPath "'+$configFile+'"')
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 10 -RestartInterval ([TimeSpan]::FromMinutes(1)) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$triggers=@(New-ScheduledTaskTrigger -AtStartup;New-ScheduledTaskTrigger -AtLogOn)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings -User SYSTEM -RunLevel Highest -Description 'Verified selected IPv4 routing for the official native gateway profile.'|Out-Null
Start-ScheduledTask -TaskName $taskName
'Installed gateway profile maintenance; verify the gateway backend and actual application path separately.'
