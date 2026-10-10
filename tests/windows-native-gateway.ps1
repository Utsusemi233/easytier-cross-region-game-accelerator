$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../windows/NativeGatewayRecovery.ps1') -ConfigPath 'isolated-import'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('gateway-config-'+[guid]::NewGuid().ToString('N')+'.json')
try{
 [IO.File]::WriteAllText($temporary,'["203.0.113.0/24"]')
 $cfg=[pscustomobject]@{tunnel_alias='RegionGateway';route_metric=9001;probe_route_metric=9878;poll_seconds=1;health_ttl_seconds=30;state_directory=([IO.Path]::GetTempPath());gateway_virtual_ipv4='10.77.90.1';exit_probes=@([pscustomobject]@{host='example.com';ipv4='203.0.113.1';path='/'});prefixes_file=$temporary;conflicting_tunnel_aliases=@('RegionDirect')}
 Assert-NativeGatewayConfig $cfg
 foreach($case in @(@('route_metric',9878),@('health_ttl_seconds',61),@('tunnel_alias','bad/alias'),@('gateway_virtual_ipv4','127.1'),@('state_directory','relative'),@('conflicting_tunnel_aliases',@('RegionGateway')))){
  $copy=$cfg|ConvertTo-Json -Depth 6|ConvertFrom-Json;$copy.($case[0])=$case[1];$rejected=$false
  try{Assert-NativeGatewayConfig $copy}catch{$rejected=$true}
  if(-not $rejected){throw ('Invalid gateway config accepted: '+$case[0])}
 }
 [IO.File]::WriteAllText($temporary,'["0.0.0.0/0"]');$rejected=$false
 try{Assert-NativeGatewayConfig $cfg}catch{$rejected=$true}
 if(-not $rejected){throw 'An unreviewed global default route was accepted.'}
 'Native gateway: valid profile and 7 invalid pre-install configurations checked; no live tasks or routes modified.'
}finally{Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue}
