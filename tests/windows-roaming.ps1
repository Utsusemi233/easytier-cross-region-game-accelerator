$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../windows/Network-Roaming.ps1')
function Assert-Roaming($Condition, $Message) { if (-not $Condition) { throw $Message } }
$old = [pscustomobject]@{ destination='203.0.113.9/32'; interface_index=7; next_hop='192.168.8.1'; route_metric=17 }
$new = [pscustomobject]@{ index=11; gateway='192.168.43.1' }
$plan = Get-RoamingRoutePlan $new @('203.0.113.9','203.0.113.9','198.51.100.4') @($old)
Assert-Roaming ($plan.desired.Count -eq 2) 'Duplicate discovery paths must not duplicate routes.'
Assert-Roaming ($plan.remove.Count -eq 1) 'An owned route on the old interface must be removed.'
Assert-Roaming (@($plan.desired | Where-Object { $_.interface_index -ne 11 -or $_.next_hop -ne '192.168.43.1' }).Count -eq 0) 'Every replacement must use the new interface and gateway.'
$same = Get-RoamingRoutePlan ([pscustomobject]@{index=7;gateway='192.168.8.1'}) @('203.0.113.9') @($old)
Assert-Roaming ($same.remove.Count -eq 0) 'Unchanged transport must not churn owned routes.'
$renew = Get-RoamingRoutePlan ([pscustomobject]@{index=7;gateway='192.168.9.1'}) @('203.0.113.9') @($old)
Assert-Roaming ($renew.remove.Count -eq 1 -and $renew.desired[0].next_hop -eq '192.168.9.1') 'A same-interface gateway change must replace the old next hop.'
$offline = Get-RoamingRoutePlan $null @('203.0.113.9') @($old)
Assert-Roaming ($offline.desired.Count -eq 0 -and $offline.remove.Count -eq 1) 'Offline state must not retain an owned dead underlay route.'
$expired = Get-RoamingRoutePlan $new @('198.51.100.4') @($old)
Assert-Roaming ($expired.remove.Count -eq 1) 'A withdrawn transport endpoint must release its owned route.'
Assert-Roaming (@($plan.remove | Where-Object { $_.destination -eq '198.51.100.77/32' }).Count -eq 0) 'Unowned routes must not be selected for cleanup.'
$initial = Get-RoamingRoutePlan $new @('203.0.113.9') $null
Assert-Roaming ($initial.remove.Count -eq 0 -and $initial.desired.Count -eq 1) 'First startup with no ownership journal must not attempt to remove a null route.'
'Windows roaming: 9 route-planning assertions passed; no live routes or tasks modified.'
