$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../windows/Direct-HomeRecovery.ps1')
function Assert-Direct($Condition,$Message){if(-not $Condition){throw $Message}}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$cfg=[pscustomobject]@{home_zerotier_id='abcdef1234';home_virtual_ipv4='192.0.2.10';public_fec_port=11022;private_fec_port=11023;transport_mode='auto'}
$valid=[pscustomobject]@{address='abcdef1234';paths=@([pscustomobject]@{address='2001:db8::1/9993';active=$true;expired=$false;lastReceive=$now;preferred=$true})}
$untrusted=[pscustomobject]@{address='1234567890';paths=$valid.paths}
$c=@(Get-DirectCandidates @($valid,$untrusted) $cfg $true $now)
Assert-Direct ($c.Count -eq 2 -and $c[0].endpoint -eq '[2001:db8::1]:11022') 'Only the configured authenticated home identity may supply an IPv6 endpoint.'
$valid.paths[0].expired=$true
Assert-Direct (@(Get-DirectCandidates @($valid) $cfg $true $now).Count -eq 1) 'Expired IPv6 discovery must not be reused.'
$valid.paths[0].expired=$false;$valid.paths[0].lastReceive=$now-120001
Assert-Direct (@(Get-DirectCandidates @($valid) $cfg $true $now).Count -eq 1) 'Stale discovery must not be reused.'
$valid.paths[0].lastReceive=$now+30001
Assert-Direct (@(Get-DirectCandidates @($valid) $cfg $true $now).Count -eq 1) 'Future timestamps outside clock tolerance are invalid.'
$valid.paths[0].lastReceive=$now;$valid.paths[0].address='fd00::1/9993'
Assert-Direct (@(Get-DirectCandidates @($valid) $cfg $true $now).Count -eq 1) 'ULA addresses must not be selected as public IPv6.'
$valid.paths[0].address='2001:db8::1/9993'
Assert-Direct (@(Get-DirectCandidates @($valid) $cfg $false $now).Count -eq 1) 'IPv4-only underlays must use the authorized overlay candidate.'
$cfg.transport_mode='overlay'
Assert-Direct (@(Get-DirectCandidates @($valid) $cfg $true $now)[0].kind -eq 'authorized_overlay_fec') 'Explicit overlay mode must not silently select IPv6.'
$cfg.transport_mode='auto';$valid.paths+=$valid.paths[0]
Assert-Direct (@(Get-DirectCandidates @($valid) $cfg $true $now).Count -eq 2) 'Duplicate authenticated paths must not duplicate candidates.'
$connections=@([pscustomobject]@{local='192.0.2.20';route_alias='RegionTravel'},[pscustomobject]@{local='10.10.10.2';route_alias='RegionTravel'},[pscustomobject]@{local='127.0.0.1';route_alias='RegionTravel'},[pscustomobject]@{local='192.0.2.20';route_alias='WLAN'})
$plan=@(Get-ScopedAppReconnectPlan $connections '10.10.10.2' 'RegionTravel')
Assert-Direct ($plan.Count -eq 1 -and $plan[0].local -eq '192.0.2.20') 'App reconnection must only select old-source connections whose current route belongs to the configured tunnel.'
Assert-Direct ((Get-DirectGatewayDecision $false $true $true) -eq 'dns_tcp_and_https') 'A real DNS/TCP gateway plus bound HTTPS success must not be discarded solely for ICMP loss.'
Assert-Direct ((Get-DirectGatewayDecision $false $true $false) -eq 'failed') 'Gateway DNS alone must not masquerade as a working Internet exit.'
Assert-Direct ((Get-DirectGatewayDecision $false $false $true) -eq 'failed') 'An HTTPS response without the virtual gateway probe is insufficient.'
$valid.paths=@([pscustomobject]@{address='2001:db8:2::2/9993';active=$true;expired=$false;lastReceive=$now;preferred=$true})
Assert-Direct (@(Get-DirectCandidates @($valid) $cfg $true $now)[0].endpoint -eq '[2001:db8:2::2]:11022') 'A changed authenticated IPv6 must replace the old candidate without a fixed local address.'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('direct-cidr-'+[guid]::NewGuid().ToString('N')+'.json')
try{
 [IO.File]::WriteAllText($temporary,'["203.0.113.0/24","203.0.113.0/24"]')
 Assert-Direct (@(Get-DirectRegionalPrefixes $temporary).Count -eq 1) 'Canonical selected prefixes must be accepted and deduplicated.'
 foreach($bad in @('0.0.0.0/0','128.0.0.0/1','203.0.113.9/24','203.0.113.0/33','999.0.0.0/24')){
  [IO.File]::WriteAllText($temporary,('["'+$bad+'"]'));$rejected=$false
  try{Get-DirectRegionalPrefixes $temporary|Out-Null}catch{$rejected=$true}
  Assert-Direct $rejected 'Unsafe or malformed selected prefixes must be rejected before installation.'
 }
}finally{Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue}
$utc=[DateTime]::UtcNow
Assert-Direct (Test-DirectProofFresh $utc.AddSeconds(-10) $utc 30) 'A temporary retry must retain a still-current successful proof.'
Assert-Direct (-not(Test-DirectProofFresh $utc.AddSeconds(-30) $utc 30)) 'Failed checks must never extend expired proof.'
Assert-Direct (-not(Test-DirectProofFresh $utc.AddSeconds(1) $utc 30)) 'Future proof timestamps must not validate an exit.'
Assert-Direct (-not(Test-DirectProofFresh ([DateTime]::MinValue) $utc 30)) 'A new network must require its own successful proof.'
'Direct recovery: 23 identity, freshness, endpoint-change, CIDR, scoped app and gateway-check assertions passed; no live tasks, routes or processes modified.'
