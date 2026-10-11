$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\Network-SwitchGuard.ps1')
function Assert-Guard {param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message}}
$validConfig=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\network-switch-guard.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-NetworkSwitchGuardConfig $validConfig
$validConfig.profiles[1].alias=$validConfig.profiles[0].alias
$rejected=$false
try { Assert-NetworkSwitchGuardConfig $validConfig } catch { $rejected=$true }
Assert-Guard $rejected 'Duplicate aliases passed configuration validation.'
$validConfig.profiles[1].alias='RegionGateway'
$validConfig.profiles[0].status_file='relative-state.json'
$rejected=$false
try { Assert-NetworkSwitchGuardConfig $validConfig } catch { $rejected=$true }
Assert-Guard $rejected 'A relative proof path passed configuration validation.'
$now=[DateTime]::UtcNow
$state=[pscustomobject]@{pending_signature=$null;pending_since_utc=$null;applied_signature=$null;needs_flush=$false}
$online=[pscustomobject]@{online=$true;signature='game-wifi'}
$state=Update-SwitchGuardState $state $online $now 3
Assert-Guard (-not $state.needs_flush) 'Startup flushed before the network settled.'
$state=Update-SwitchGuardState $state $online $now.AddSeconds(3) 3
Assert-Guard $state.needs_flush 'Stable startup did not request a refresh.'
$state.applied_signature=$online.signature
$state=Update-SwitchGuardState $state $online $now.AddSeconds(50) 3
Assert-Guard (-not $state.needs_flush) 'Unchanged network repeatedly refreshed DNS.'
$offline=[pscustomobject]@{online=$false;signature='offline'}
$state=Update-SwitchGuardState $state $offline $now.AddSeconds(51) 3
$state=Update-SwitchGuardState $state $offline $now.AddSeconds(60) 3
Assert-Guard (-not $state.needs_flush) 'Offline network requested a refresh.'
$changed=[pscustomobject]@{online=$true;signature='normal-wifi'}
$state=Update-SwitchGuardState $state $changed $now.AddSeconds(61) 3
Assert-Guard (-not $state.needs_flush) 'Reconnection did not debounce.'
$state=Update-SwitchGuardState $state $online $now.AddSeconds(62) 3
$state=Update-SwitchGuardState $state $online $now.AddSeconds(70) 3
Assert-Guard $state.needs_flush 'Reconnect to the same SSID after an offline interval did not refresh DNS.'
$state.applied_signature=$online.signature
$state=Update-SwitchGuardState $state $changed $now.AddSeconds(71) 3
$state=Update-SwitchGuardState $state $online $now.AddSeconds(72) 3
$state=Update-SwitchGuardState $state $online $now.AddSeconds(75) 3
Assert-Guard (-not $state.needs_flush) 'A transient online switch back to the applied network flushed again.'
foreach($signature in @('normal-wifi','normal-wifi+tunnel-waiting','normal-wifi+tunnel-routed','normal-wifi')){
    $now=$now.AddSeconds(80);$snapshot=[pscustomobject]@{online=$true;signature=$signature}
    $state=Update-SwitchGuardState $state $snapshot $now 3
    Assert-Guard (-not $state.needs_flush) 'A switch skipped the settle interval.'
    $state=Update-SwitchGuardState $state $snapshot $now.AddSeconds(3) 3
    Assert-Guard $state.needs_flush 'A Wi-Fi/TUN/verified-route/off transition was missed.'
    $state.applied_signature=$signature
}
$status=[pscustomobject]@{observed_utc=$now.ToString('o');verified_utc=$now.ToString('o');accelerated_prefixes=5495;source_ipv4='10.1.2.3';state='gateway_verified'}
Assert-Guard ((Get-SwitchProfilePhase $status @('10.1.2.3') $now 30) -eq 'routed') 'Fresh route proof was rejected.'
Assert-Guard ((Get-SwitchProfilePhase $status @('10.1.2.4') $now 30) -eq 'local') 'Proof for an old TUN address was accepted.'
Assert-Guard ((Get-SwitchProfilePhase $status @('10.1.2.3') $now.AddSeconds(31) 30) -eq 'local') 'Expired proof was accepted.'
Assert-Guard ((Get-SwitchProfilePhase $status @('10.1.2.3') $now.AddSeconds(-3) 30) -eq 'local') 'Future-dated proof was accepted.'
$status.state='profile_conflict'
Assert-Guard ((Get-SwitchProfilePhase $status @('10.1.2.3') $now 30) -eq 'local') 'Conflicting profiles were treated as routed.'
'PASS: stable transitions, debounce, offline recovery, no repeated flush, and fresh address-bound route proof.'
