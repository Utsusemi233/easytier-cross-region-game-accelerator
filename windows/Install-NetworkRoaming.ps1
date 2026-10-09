param([Parameter(Mandatory=$true)][string]$ConfigPath, [switch]$Apply, [switch]$Remove)
$ErrorActionPreference='Stop'
if ($Apply -and $Remove) { throw 'Choose Apply or Remove, not both.' }
$configFile=(Resolve-Path -LiteralPath $ConfigPath).Path
$config=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
$scriptFile=Join-Path $PSScriptRoot 'Network-Roaming.ps1'
if (-not (Test-Path -LiteralPath $scriptFile)) { throw 'The matching Network-Roaming.ps1 file is required.' }
if (@($config.full_routes | Where-Object {$_ -notin @('0.0.0.0/1','128.0.0.0/1')}).Count -or @($config.full_routes).Count -ne 2) { throw 'Inspect the two /1 gateway-mode routes before installation.' }
$taskName='EasyTier Cross-Region Network Recovery'
if (-not $Apply -and -not $Remove) {
    [pscustomobject]@{task=$taskName;mode='plan';client_replaced=$false;scope='Owned IPv4 underlay routes and native gateway availability';config=$configFile}
    return
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this explicit installation or removal from an Administrator terminal.' }
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($Remove) {
    if ($existing) {
        if (-not @($existing.Actions | Where-Object {$_.Arguments.Contains($configFile) -and $_.Arguments.Contains('Network-Roaming.ps1')}).Count) { throw 'An existing task does not belong to this configuration.' }
        Stop-ScheduledTask -TaskName $taskName
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    . $scriptFile
    Set-RoamingAcceleration $config $false
    $ownedFile=Join-Path $config.state_directory 'owned-routes.private.json'
    if (Test-Path $ownedFile) {
        foreach ($entry in @(Get-Content $ownedFile -Raw -Encoding UTF8 | ConvertFrom-Json)) { Remove-RoamingOwnedRoute $entry }
        Write-RoamingJson $ownedFile @()
    }
    'Removed the matching task and scoped routes; official client and unrelated routes retained.'
    return
}
if ($existing) { throw 'Task already exists. Inspect or remove its matching deployment before replacing it.' }
New-Item -ItemType Directory -Path $config.state_directory -Force | Out-Null
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$scriptFile+'" -ConfigPath "'+$configFile+'"')
$triggers=@(New-ScheduledTaskTrigger -AtStartup;New-ScheduledTaskTrigger -AtLogOn)
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 10 -RestartInterval ([TimeSpan]::FromMinutes(1)) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings -User SYSTEM -RunLevel Highest -Description 'Network-change recovery for the official EasyTier client, using authorized ZeroTier transport and scoped routes.' | Out-Null
Start-ScheduledTask -TaskName $taskName
'Installed the explicit background route-maintenance component. Validate its status and real network recovery separately.'
