param([Parameter(Mandatory=$true)][string]$ConfigPath,[switch]$Apply,[switch]$Remove)
$ErrorActionPreference='Stop'
if($Apply -and $Remove){throw 'Choose Apply or Remove.'}
$configFile=(Resolve-Path -LiteralPath $ConfigPath).Path
$config=Get-Content $configFile -Raw -Encoding UTF8|ConvertFrom-Json
. (Join-Path $PSScriptRoot 'Direct-HomeRecovery.ps1') -ConfigPath $configFile
Assert-DirectConfig $config
$checkedPrefixes=@(Get-DirectRegionalPrefixes $config.prefixes_file)
$taskName='EasyTier Direct Home Recovery'
$scriptFile=Join-Path $PSScriptRoot 'Direct-HomeRecovery.ps1'
if(-not $Apply -and -not $Remove){[pscustomobject]@{mode='plan';task=$taskName;client_replaced=$false;scope='Owned regional IPv4 routes, UDPspeeder and authenticated endpoint discovery'};return}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator permission is required for explicit installation/removal.'}
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($existing -and -not @($existing.Actions|Where-Object {$_.Arguments.Contains($configFile) -and $_.Arguments.Contains('Direct-HomeRecovery.ps1')}).Count){throw 'An unrelated task uses the same name.'}
if($existing){Stop-ScheduledTask -TaskName $taskName;Unregister-ScheduledTask -TaskName $taskName -Confirm:$false;Start-Sleep -Milliseconds 500}
if($Remove){
    $prefixData=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($config.prefixes_file))
    $prefixes=[string[]]$prefixData
    $interfaceFile=Join-Path $config.state_directory 'managed-interface.private.json'
    if(Test-Path $interfaceFile){$record=Get-Content $interfaceFile -Raw -Encoding UTF8|ConvertFrom-Json;$index=$record.interface_index;if($record.prefixes){$prefixes=[string[]]$record.prefixes};Set-ScopedIPv4Routes $index $prefixes $config.route_metric $false;$probeFile=Join-Path $config.state_directory 'probe-prefixes.private.json';$probes=if(Test-Path $probeFile){[string[]](ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($probeFile)))}else{@($config.exit_probes|ForEach-Object {$_.ipv4+'/32'})};Set-ScopedIPv4Routes $index $probes $config.probe_route_metric $false}
    $ownedFile=Join-Path $config.state_directory 'owned-bypasses.private.json'
    if(Test-Path $ownedFile){$entries=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($ownedFile));foreach($entry in $entries){Remove-RoamingOwnedRoute $entry};Write-RoamingJson $ownedFile @()}
    Stop-DirectOwnedSpeeder $config (Join-Path $config.state_directory 'speeder-process.private.json')
    'Removed this deployment task, process and owned routes.';return
}
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$scriptFile+'" -ConfigPath "'+$configFile+'"')
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 10 -RestartInterval ([TimeSpan]::FromMinutes(1)) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$triggers=@(New-ScheduledTaskTrigger -AtStartup;New-ScheduledTaskTrigger -AtLogOn)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings -User SYSTEM -RunLevel Highest -Description 'Authenticated direct-exit endpoint recovery and verified regional routing for the official EasyTier GUI.'|Out-Null
Start-ScheduledTask -TaskName $taskName
'Installed direct-exit recovery. Verify status, actual exit and network/fault recovery before acceptance.'
