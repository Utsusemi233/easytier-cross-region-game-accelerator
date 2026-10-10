param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Direct-HomeRecovery.ps1') -ConfigPath $ConfigPath

function Assert-NativeGatewayConfig {
 param($Config)
 if($Config.tunnel_alias -notmatch '^[A-Za-z0-9_-]{1,32}$' -or $Config.route_metric -lt 1 -or $Config.probe_route_metric -lt 1 -or $Config.route_metric -eq $Config.probe_route_metric){throw 'Invalid owned interface or route metrics.'}
 if($Config.poll_seconds -lt 1 -or $Config.health_ttl_seconds -lt 5 -or $Config.health_ttl_seconds -gt 60){throw 'Invalid recovery intervals.'}
 if(-not [IO.Path]::IsPathRooted($Config.state_directory) -or -not @($Config.exit_probes).Count){throw 'An absolute private state directory and exit probes are required.'}
 if(@($Config.conflicting_tunnel_aliases) -contains $Config.tunnel_alias){throw 'A gateway profile cannot conflict with its own interface.'}
 foreach($ip in @($Config.gateway_virtual_ipv4)+@($Config.exit_probes|ForEach-Object {$_.ipv4})){
  $parsed=$null
  if(-not [Net.IPAddress]::TryParse($ip,[ref]$parsed) -or $parsed.AddressFamily -ne 'InterNetwork' -or $parsed.ToString() -ne $ip){throw 'Canonical IPv4 gateway and probe addresses are required.'}
 }
 foreach($probe in @($Config.exit_probes)){if($probe.host -notmatch '^[a-zA-Z0-9.-]+$' -or $probe.path -notmatch '^/'){throw 'Invalid certificate-verified HTTPS probe.'}}
 Get-DirectRegionalPrefixes $Config.prefixes_file|Out-Null
}
if($MyInvocation.InvocationName -eq '.'){return}
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
Assert-NativeGatewayConfig $config
$prefixes=[string[]]@(Get-DirectRegionalPrefixes $config.prefixes_file)
$probes=[string[]]@($config.exit_probes|ForEach-Object {$_.ipv4+'/32'})
New-Item -ItemType Directory -Path $config.state_directory -Force|Out-Null
$statusPath=Join-Path $config.state_directory 'status.private.json'
$routesPath=Join-Path $config.state_directory 'managed-interface.private.json'
$ownedPath=Join-Path $config.state_directory 'owned-bypasses.private.json'
$created=$false;$mutex=[Threading.Mutex]::new($true,('Global\EasyTierNativeGateway-'+$config.tunnel_alias),[ref]$created)
if(-not $created){$mutex.Dispose();exit 0}
$owned=if(Test-Path $ownedPath){@(Get-Content $ownedPath -Raw -Encoding UTF8|ConvertFrom-Json)}else{@()}
$lastIndex=0;$signature=$null;$verified=[DateTime]::MinValue;$lastProbe=[DateTime]::MinValue
$routeOn=$false;$networkChanges=0;$resets=0;$gatewayGood=$false;$httpsGood=$false
try{
 if(Test-Path $routesPath){
  $old=Get-Content $routesPath -Raw -Encoding UTF8|ConvertFrom-Json
  Set-ScopedIPv4Routes $old.interface_index ([string[]]$old.prefixes) $config.route_metric $false
  Set-ScopedIPv4Routes $old.interface_index ([string[]]$old.probes) $config.probe_route_metric $false
 }
 while($true){
  $errorMessage=$null;$rtt=$null;$source=$null;$blocked=$false
  try{
   $physical=Get-DirectPhysicalNetwork $config.tunnel_alias
   $interface=Get-NetIPInterface -InterfaceAlias $config.tunnel_alias -AddressFamily IPv4 -ErrorAction SilentlyContinue|Select-Object -First 1
   $index=if($interface -and $interface.ConnectionState -eq 'Connected'){[int]$interface.InterfaceIndex}else{0}
   $source=if($index){Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue|Where-Object {$_.AddressState -eq 'Preferred' -and $_.IPAddress -ne '0.0.0.0'}|Select-Object -First 1}else{$null}
   foreach($alias in @($config.conflicting_tunnel_aliases)){
    if(Get-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue|Where-Object {$_.ConnectionState -eq 'Connected'}){$blocked=$true}
   }
   $nextSignature=if($physical){[string]$physical.index+'|'+$physical.gateway+'|'+($physical.addresses -join ',')+'|'+($physical.ipv6 -join ',')}else{'offline'}
   $nextSignature+='|'+$index+'|'+$source.IPAddress+'|'+$blocked
   if($signature -ne $nextSignature){
    if($lastIndex){Set-ScopedIPv4Routes $lastIndex $prefixes $config.route_metric $false;Set-ScopedIPv4Routes $lastIndex $probes $config.probe_route_metric $false}
    if($null -ne $signature){$networkChanges++}
    $verified=[DateTime]::MinValue;$lastProbe=[DateTime]::MinValue;$routeOn=$false;$gatewayGood=$false;$httpsGood=$false
    $signature=$nextSignature;$lastIndex=$index
    if($index){Write-RoamingJson $routesPath @{interface_index=$index;prefixes=$prefixes;probes=$probes}}
   }
   $peers=@(Get-DirectAuthorizedPeers $config)
   $plan=Get-RoamingRoutePlan $(if($physical -and $physical.gateway){$physical}else{$null}) @(Get-DirectBypassIPs $peers) $owned
   foreach($entry in $plan.remove){Remove-RoamingOwnedRoute $entry}
   $nextOwned=@()
   foreach($entry in $plan.desired){
    $wasOwned=@($owned|Where-Object {$_.destination -eq $entry.destination -and $_.interface_index -eq $entry.interface_index -and $_.next_hop -eq $entry.next_hop}).Count -gt 0
    $existing=@(Get-NetRoute -DestinationPrefix $entry.destination -InterfaceIndex $entry.interface_index -AddressFamily IPv4 -ErrorAction SilentlyContinue|Where-Object {$_.NextHop -eq $entry.next_hop})
    if(-not $existing.Count){New-NetRoute -DestinationPrefix $entry.destination -InterfaceIndex $entry.interface_index -AddressFamily IPv4 -NextHop $entry.next_hop -RouteMetric $entry.route_metric -PolicyStore ActiveStore|Out-Null;$nextOwned+=$entry}elseif($wasOwned){$nextOwned+=$entry}
   }
   $owned=$nextOwned;Write-RoamingJson $ownedPath @($owned)
   $now=[DateTime]::UtcNow
   if($physical -and $source -and -not $blocked){
    Set-ScopedIPv4Routes $index $probes $config.probe_route_metric $true
    $ping=[Net.NetworkInformation.Ping]::new()
    try{$reply=$ping.Send($config.gateway_virtual_ipv4,900);$gatewayGood=$reply.Status -eq 'Success';if($gatewayGood){$rtt=$reply.RoundtripTime}}catch{$gatewayGood=$false}finally{$ping.Dispose()}
    if(($now-$lastProbe).TotalSeconds -ge [Math]::Max(2,[Math]::Floor($config.health_ttl_seconds/3))){
     $httpsGood=Test-DirectExitHTTPS $config $source.IPAddress;$lastProbe=[DateTime]::UtcNow
     if($gatewayGood -and $httpsGood){$verified=$lastProbe}
    }
    $desired=Test-DirectProofFresh $verified ([DateTime]::UtcNow) $config.health_ttl_seconds
    if($desired -ne $routeOn){Set-ScopedIPv4Routes $index $prefixes $config.route_metric $desired;$routeOn=$desired;if($desired){$resets+=Reset-ScopedAppConnections @($config.reconnect_app_executables) $source.IPAddress $config.tunnel_alias}}
   }else{
    if($index){Set-ScopedIPv4Routes $index $prefixes $config.route_metric $false;Set-ScopedIPv4Routes $index $probes $config.probe_route_metric $false}
    $routeOn=$false;$verified=[DateTime]::MinValue;$gatewayGood=$false;$httpsGood=$false
   }
  }catch{
   $errorMessage=$_.Exception.Message;$routeOn=$false;$verified=[DateTime]::MinValue;$gatewayGood=$false;$httpsGood=$false
   try{if($lastIndex){Set-ScopedIPv4Routes $lastIndex $prefixes $config.route_metric $false}}catch{}
  }
  Write-RoamingJson $statusPath ([ordered]@{
   observed_utc=[DateTime]::UtcNow.ToString('o');state=if($blocked){'profile_conflict'}elseif($routeOn -and $gatewayGood -and $httpsGood){'gateway_verified'}elseif($routeOn){'gateway_degraded'}else{'local_fallback'}
   gateway_verified=$gatewayGood;exit_https_verified=$httpsGood;verified_utc=if($routeOn){$verified.ToString('o')}else{$null}
   gateway_rtt_ms=$rtt;accelerated_prefixes=if($routeOn){$prefixes.Count}else{0};physical=$physical;source_ipv4=$source.IPAddress
   network_changes=$networkChanges;allowlisted_tcp_resets=$resets;owned_bypass_count=@($owned).Count;error_message=$errorMessage
   scope='Official native entry to an authorized policy gateway; gateway-to-exit verification remains separate.'
  })
  Start-Sleep -Seconds $config.poll_seconds
 }
}finally{
 try{if($lastIndex){Set-ScopedIPv4Routes $lastIndex $prefixes $config.route_metric $false;Set-ScopedIPv4Routes $lastIndex $probes $config.probe_route_metric $false}}catch{}
 $mutex.ReleaseMutex();$mutex.Dispose()
}
