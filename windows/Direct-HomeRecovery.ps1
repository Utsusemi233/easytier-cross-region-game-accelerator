param([string]$ConfigPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Network-Roaming.ps1') -ConfigPath $ConfigPath
. (Join-Path $PSScriptRoot 'Scoped-IPv4Routes.ps1')
. (Join-Path $PSScriptRoot 'Scoped-AppReconnect.ps1')

function Get-DirectCandidates {
    param([object[]]$Peers,$Config,[bool]$HasIPv6,[long]$NowMs)
    $result=@()
    if($HasIPv6 -and $Config.transport_mode -ne 'overlay') {
        foreach($peer in @($Peers | Where-Object {$_.address -eq $Config.home_zerotier_id})) {
            foreach($path in @($peer.paths)) {
                if(-not $path.active -or $path.expired -or $path.lastReceive -le 0 -or $NowMs-[long]$path.lastReceive -gt 120000 -or [long]$path.lastReceive-$NowMs -gt 30000) {continue}
                $literal=($path.address -split '/')[0];$ip=$null
                if([Net.IPAddress]::TryParse($literal,[ref]$ip) -and $ip.AddressFamily -eq 'InterNetworkV6' -and $ip.GetAddressBytes()[0] -ge 32 -and $ip.GetAddressBytes()[0] -le 63) {
                    $result += [pscustomobject]@{endpoint=('['+$ip.ToString()+']:'+$Config.public_fec_port);kind='direct_ipv6_fec';rank=if($path.preferred){0}else{1}}
                }
            }
        }
    }
    # The stable virtual address belongs to the configured authorized private network.
    $result=@($result | Sort-Object rank,endpoint | Group-Object endpoint | ForEach-Object {$_.Group[0]})
    $result += [pscustomobject]@{endpoint=($Config.home_virtual_ipv4+':'+$Config.private_fec_port);kind='authorized_overlay_fec';rank=2}
    return $result
}

function Get-DirectPhysicalNetwork {
    param([string]$TunnelAlias)
    $physical=Get-RoamingPhysicalNetwork $TunnelAlias
    if(-not $physical){
        $ipv6Default=Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0' -ErrorAction SilentlyContinue|Where-Object {$_.InterfaceAlias -ne $TunnelAlias -and $_.InterfaceAlias -notmatch 'ZeroTier|Loopback|TAP|TUN|WireGuard'}|Sort-Object @{Expression={$_.RouteMetric+$_.InterfaceMetric}}|Select-Object -First 1
        if(-not $ipv6Default){return $null}
        $physical=[pscustomobject]@{index=[int]$ipv6Default.InterfaceIndex;gateway=$null;addresses=@();metric=$ipv6Default.RouteMetric;ipv6_gateway=$ipv6Default.NextHop}
    }
    $adapter=@([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()|Where-Object {$_.OperationalStatus -eq 'Up' -and ($_.GetIPProperties().GetIPv4Properties().Index -eq $physical.index -or $_.GetIPProperties().GetIPv6Properties().Index -eq $physical.index)}) | Select-Object -First 1
    if(-not $adapter){return $null}
    if(-not $adapter){return $null}
    $v6=@($adapter.GetIPProperties().UnicastAddresses|Where-Object {$_.Address.AddressFamily -eq 'InterNetworkV6' -and $_.Address.GetAddressBytes()[0] -ge 32 -and $_.Address.GetAddressBytes()[0] -le 63 -and $_.AddressPreferredLifetime -gt 0}|ForEach-Object {$_.Address.ToString()}|Sort-Object)
    $physical|Add-Member NoteProperty ipv6 $v6
    return $physical
}

function Get-DirectAuthorizedPeers {
    param($Config)
    $token=[IO.File]::ReadAllText((Join-Path $Config.zerotier_directory 'authtoken.secret')).Trim()
    $port=[IO.File]::ReadAllText((Join-Path $Config.zerotier_directory 'zerotier-one.port')).Trim()
    $response=Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:'+$port+'/peer') -Headers @{'X-ZT1-Auth'=$token} -TimeoutSec 2
    $parsed=ConvertFrom-Json -InputObject $response.Content
    foreach($peer in $parsed){Write-Output $peer}
}

function Get-DirectBypassIPs {
    param([object[]]$Peers)
    @($Peers|ForEach-Object {$_.paths}|Where-Object {$_.active -and -not $_.expired}|ForEach-Object {($_.address -split '/')[0]}|Where-Object {
        $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^(0\.|10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)'
    }|Sort-Object -Unique)
}

function Stop-DirectOwnedSpeeder {
    param($Config,[string]$ProcessFile)
    if(-not(Test-Path $ProcessFile)){return}
    $record=Get-Content $ProcessFile -Raw -Encoding UTF8|ConvertFrom-Json
    $process=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$record.pid) -ErrorAction SilentlyContinue
    if($process -and $process.ExecutablePath -eq $Config.speeder_exe -and $process.CommandLine.Contains('127.0.0.1:'+$Config.local_fec_port) -and $process.CreationDate.ToUniversalTime().ToString('o') -eq $record.created_utc){Stop-Process -Id $record.pid -Force}
    Remove-Item -LiteralPath $ProcessFile -Force
}

function Start-DirectSpeeder {
    param($Config,$Candidate,[string]$ProcessFile)
    Stop-DirectOwnedSpeeder $Config $ProcessFile
    $arguments=@('-c','-l',('127.0.0.1:'+$Config.local_fec_port),'-r',$Candidate.endpoint,'-k',$Config.fec_key,('-f'+$Config.fec),'--timeout',[string]$Config.timeout_ms,'--mode',[string]$Config.mode,'--sock-buf','1024','--log-level','2','--disable-color')
    $process=Start-Process -FilePath $Config.speeder_exe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $Config.state_directory 'fec.stdout.private.log') -RedirectStandardError (Join-Path $Config.state_directory 'fec.stderr.private.log')
    $info=Get-CimInstance Win32_Process -Filter ('ProcessId='+$process.Id)
    Write-RoamingJson $ProcessFile @{pid=$process.Id;created_utc=$info.CreationDate.ToUniversalTime().ToString('o');endpoint=$Candidate.endpoint;kind=$Candidate.kind}
    return $process.Id
}

function Test-DirectExitHTTPS {
    param($Config,[string]$SourceIPv4)
    foreach($probe in $Config.exit_probes) {
        try {
            $code=& curl.exe -4 --noproxy '*' --interface $SourceIPv4 --resolve ($probe.host+':443:'+$probe.ipv4) --head --silent --output NUL --write-out '%{http_code}' --connect-timeout 2 --max-time 4 ('https://'+$probe.host+$probe.path) 2>$null
            if($LASTEXITCODE -eq 0 -and $code -match '^\d{3}$' -and [int]$code -ge 200 -and [int]$code -lt 500){return $true}
        }catch{}
    }
    return $false
}

function Update-DirectProbeAddresses {
    param($Config)
    foreach($probe in $Config.exit_probes){
        try{
            $records=@(Resolve-DnsName -Name $probe.host -Type A -Server $Config.gateway_virtual_ipv4 -DnsOnly -QuickTimeout -ErrorAction Stop)
            $ip=@($records|Where-Object {$_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and $_.IPAddress -notmatch '^(0\.|10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|198\.(18|19)\.)'}|Select-Object -ExpandProperty IPAddress|Sort-Object)|Select-Object -First 1
            if($ip){$probe.ipv4=$ip}
        }catch{}
    }
}

function Test-DirectDNSGateway {
    param($Config)
    try{
        $records=@(Resolve-DnsName -Name $Config.exit_probes[0].host -Type A -Server $Config.gateway_virtual_ipv4 -DnsOnly -TcpOnly -QuickTimeout -ErrorAction Stop)
        return @($records|Where-Object {$_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$'}).Count -gt 0
    }catch{return $false}
}

function Get-DirectGatewayDecision {
    param([bool]$PingPassed,[bool]$DNSPassed,[bool]$HTTPSPassed)
    if($PingPassed){return 'icmp'}
    if($DNSPassed -and $HTTPSPassed){return 'dns_tcp_and_https'}
    return 'failed'
}

function Test-DirectProofFresh {
    param([DateTime]$Verified,[DateTime]$Now,[int]$TTL)
    $age=($Now-$Verified).TotalSeconds
    return $Verified -ne [DateTime]::MinValue -and $age -ge 0 -and $age -lt $TTL
}

function Get-DirectRegionalPrefixes {
    param([string]$Path)
    $text=[IO.File]::ReadAllText($Path)
    if(-not $text.TrimStart().StartsWith('[')){throw 'Selected prefixes must be a JSON array.'}
    $data=ConvertFrom-Json -InputObject $text
    $result=@()
    foreach($prefix in $data){
        if($prefix -isnot [string] -or $prefix -notmatch '^(\d+\.\d+\.\d+\.\d+)/(\d+)$'){throw 'Invalid selected IPv4 CIDR.'}
        $literal=$Matches[1];$length=[int]$Matches[2];$ip=$null
        if($length -lt 2 -or $length -gt 32 -or -not [Net.IPAddress]::TryParse($literal,[ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork' -or $ip.ToString() -ne $literal){throw 'Use canonical selected IPv4 prefixes; /0 and /1 are excluded.'}
        $bytes=$ip.GetAddressBytes()
        for($octet=0;$octet -lt 4;$octet++){
            $bits=[Math]::Max(0,[Math]::Min(8,$length-8*$octet))
            $mask=if($bits -eq 0){0}else{256-[Math]::Pow(2,8-$bits)}
            if(($bytes[$octet] -band [int]$mask) -ne $bytes[$octet]){throw 'CIDR contains host bits; supply the network address.'}
        }
        $result+=$prefix
    }
    if(-not $result.Count){throw 'Choose at least one selected IPv4 prefix.'}
    foreach($prefix in @($result|Sort-Object -Unique)){Write-Output $prefix}
}

function Assert-DirectConfig {
    param($Config)
    if($Config.home_zerotier_id -notmatch '^[0-9a-f]{10}$' -or $Config.fec_key -notmatch '^[A-Za-z0-9]{16,128}$'){throw 'Invalid private node identity or FEC key.'}
    foreach($port in @($Config.local_fec_port,$Config.public_fec_port,$Config.private_fec_port)){if($port -lt 1 -or $port -gt 65535){throw 'Invalid UDP port.'}}
    if($Config.fec -notmatch '^\d+:\d+$' -or $Config.transport_mode -notin @('auto','overlay')){throw 'Invalid FEC or transport mode.'}
    if($Config.route_metric -lt 1 -or $Config.probe_route_metric -lt 1 -or $Config.route_metric -eq $Config.probe_route_metric){throw 'Use distinct explicit route metrics.'}
    if($Config.poll_seconds -lt 1 -or $Config.retry_seconds -lt 4 -or $Config.health_ttl_seconds -gt 60 -or $Config.health_ttl_seconds -lt 5){throw 'Invalid recovery intervals.'}
    foreach($probe in @($Config.exit_probes)){if($probe.host -notmatch '^[a-zA-Z0-9.-]+$' -or $probe.ipv4 -notmatch '^\d+\.\d+\.\d+\.\d+$' -or $probe.path -notmatch '^/'){throw 'Invalid HTTPS exit probe.'}}
    if((Get-FileHash -LiteralPath $Config.speeder_exe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Config.speeder_sha256){throw 'UDPspeeder binary checksum mismatch.'}
}

if($MyInvocation.InvocationName -eq '.'){return}
if(-not $ConfigPath){throw 'Provide a private direct-exit configuration.'}
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
Assert-DirectConfig $config
$prefixes=[string[]]@(Get-DirectRegionalPrefixes $config.prefixes_file)
New-Item -ItemType Directory -Path $config.state_directory -Force|Out-Null
$ownedPath=Join-Path $config.state_directory 'owned-bypasses.private.json'
$statusPath=Join-Path $config.state_directory 'status.private.json'
$processPath=Join-Path $config.state_directory 'speeder-process.private.json'
$preferredPath=Join-Path $config.state_directory 'last-verified-endpoint.private.json'
$preferredEndpoint=if(Test-Path $preferredPath){(Get-Content $preferredPath -Raw -Encoding UTF8|ConvertFrom-Json).endpoint}else{$null}
$routesPath=Join-Path $config.state_directory 'managed-interface.private.json'
$probeRoutesPath=Join-Path $config.state_directory 'probe-prefixes.private.json'
$created=$false;$mutex=[Threading.Mutex]::new($true,'Global\EasyTierDirectHomeRecovery',[ref]$created)
if(-not $created){$mutex.Dispose();exit 0}
$owned=if(Test-Path $ownedPath){$saved=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($ownedPath));@($saved)}else{@()}
$lastSignature=$null;$current=$null;$candidateStarted=[DateTime]::MinValue;$lastHTTPS=[DateTime]::MinValue;$lastHTTPSAttempt=[DateTime]::MinValue;$lastPrimaryTry=[DateTime]::UtcNow
$httpsFailures=0
$gatewayGood=$false;$internetGood=$false;$routeOn=$false;$lastInterface=0;$failures=0;$networkChanges=0;$endpointChanges=0;$trial=0
$peers=@();$lastDiscovery=[DateTime]::MinValue;$sidecarPid=0;$appResets=0;$gatewayMethod='none'
$probePrefixes=[string[]]@($config.exit_probes|ForEach-Object {$_.ipv4+'/32'})
try {
    # Crash/restart cleanup uses the saved interface and only the explicitly managed prefixes/metric.
    if(Test-Path $routesPath){$old=Get-Content $routesPath -Raw -Encoding UTF8|ConvertFrom-Json;$cleanupPrefixes=if($old.prefixes){[string[]]$old.prefixes}else{$prefixes};Set-ScopedIPv4Routes $old.interface_index $cleanupPrefixes $config.route_metric $false;$oldProbes=if(Test-Path $probeRoutesPath){[string[]](ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($probeRoutesPath)))}else{$probePrefixes};Set-ScopedIPv4Routes $old.interface_index $oldProbes $config.probe_route_metric $false}
    Stop-DirectOwnedSpeeder $config $processPath
    while($true) {
        $errorType=$null;$errorMessage=$null
        try {
            $now=[DateTime]::UtcNow
            $physical=Get-DirectPhysicalNetwork $config.tunnel_alias
            $signature=if($physical){[string]$physical.index+'|'+$physical.gateway+'|'+($physical.addresses -join ',')+'|'+($physical.ipv6 -join ',')}else{'offline'}
            $interface=Get-NetIPInterface -InterfaceAlias $config.tunnel_alias -AddressFamily IPv4 -ErrorAction SilentlyContinue|Select-Object -First 1
            $index=if($interface -and $interface.ConnectionState -eq 'Connected'){[int]$interface.InterfaceIndex}else{0}
            $source=if($index){Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue|Where-Object {$_.IPAddress -ne '0.0.0.0'}|Select-Object -First 1}else{$null}
            $signature+='|'+$source.IPAddress
            $networkChanged=$signature -ne $lastSignature -or $index -ne $lastInterface
            if($networkChanged){
                if($lastInterface){Set-ScopedIPv4Routes $lastInterface $prefixes $config.route_metric $false;Set-ScopedIPv4Routes $lastInterface $probePrefixes $config.probe_route_metric $false}
                $routeOn=$false;$gatewayGood=$false;$internetGood=$false;$failures=0;$httpsFailures=0;$lastHTTPS=[DateTime]::MinValue;$lastHTTPSAttempt=[DateTime]::MinValue;$current=$null;$trial=0
                Stop-DirectOwnedSpeeder $config $processPath
                if($null -ne $lastSignature){$networkChanges++}
                $lastSignature=$signature;$lastInterface=$index
                if($index){Write-RoamingJson $routesPath @{interface_index=$index;prefixes=$prefixes}}
            }
            try{$peers=@(Get-DirectAuthorizedPeers $config);$lastDiscovery=$now}catch{if(($now-$lastDiscovery).TotalSeconds -gt 30){$peers=@()}}
            $bypassPhysical=if($physical -and $physical.gateway){$physical}else{$null}
            $plan=Get-RoamingRoutePlan $bypassPhysical @(Get-DirectBypassIPs $peers) $owned
            foreach($entry in $plan.remove){Remove-RoamingOwnedRoute $entry}
            $nextOwned=@()
            foreach($entry in $plan.desired){
                $wasOwned=@($owned|Where-Object {$_.destination -eq $entry.destination -and $_.interface_index -eq $entry.interface_index -and $_.next_hop -eq $entry.next_hop}).Count -gt 0
                if($wasOwned){$nextOwned+=$entry;continue}
                $existing=@(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $entry.destination -InterfaceIndex $entry.interface_index -ErrorAction SilentlyContinue|Where-Object {$_.NextHop -eq $entry.next_hop})
                if(-not $existing.Count){New-NetRoute -AddressFamily IPv4 -DestinationPrefix $entry.destination -InterfaceIndex $entry.interface_index -NextHop $entry.next_hop -RouteMetric $entry.route_metric -PolicyStore ActiveStore|Out-Null;$nextOwned+=$entry}
            }
            $owned=$nextOwned;Write-RoamingJson $ownedPath @($owned)
            $candidates=@(Get-DirectCandidates $peers $config ($physical -and @($physical.ipv6).Count -gt 0) ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()))
            if($physical -and $index){
                $selected=@($candidates|Where-Object {$current -and $_.endpoint -eq $current.endpoint})
                # Discovery may prune a non-preferred path while its authenticated data plane remains healthy.
                # Keep that established endpoint only with current gateway and HTTPS proof; new candidates still require discovery.
                $currentProven=$current -and $gatewayGood -and $internetGood -and ($now-$lastHTTPS).TotalSeconds -lt $config.health_ttl_seconds
                if(-not $selected.Count -and $currentProven -and ($current.kind -ne 'direct_ipv6_fec' -or @($physical.ipv6).Count -gt 0)){$selected=@($current)}
                $tryPrimary=$current -and $current.kind -eq 'authorized_overlay_fec' -and ($now-$lastPrimaryTry).TotalSeconds -ge $config.primary_retry_seconds -and @($candidates|Where-Object {$_.kind -eq 'direct_ipv6_fec'}).Count -gt 0
                $deadProcess=$sidecarPid -gt 0 -and -not(Get-Process -Id $sidecarPid -ErrorAction SilentlyContinue)
                $retry=$current -and -not $gatewayGood -and ($now-$candidateStarted).TotalSeconds -ge $config.retry_seconds
                if(-not $current -or -not $selected.Count -or $deadProcess -or $retry -or $tryPrimary){
                    if($routeOn){Set-ScopedIPv4Routes $index $prefixes $config.route_metric $false}
                    $routeOn=$false;$gatewayGood=$false;$internetGood=$false;$lastHTTPS=[DateTime]::MinValue;$lastHTTPSAttempt=[DateTime]::MinValue;$failures=0;$httpsFailures=0
                    if($retry){$trial++}elseif($tryPrimary -or -not $selected.Count){$trial=0}
                    if(-not $current -and $preferredEndpoint){for($candidateIndex=0;$candidateIndex -lt $candidates.Count;$candidateIndex++){if($candidates[$candidateIndex].endpoint -eq $preferredEndpoint -and $candidates[$candidateIndex].kind -eq 'direct_ipv6_fec'){$trial=$candidateIndex;break}}}
                    $current=$candidates[$trial%$candidates.Count]
                    $sidecarPid=Start-DirectSpeeder $config $current $processPath
                    $candidateStarted=$now;$endpointChanges++;$lastPrimaryTry=$now
                }
                Set-ScopedIPv4Routes $index $probePrefixes $config.probe_route_metric $true
                $ping=[Net.NetworkInformation.Ping]::new()
                try{$reply=$ping.Send($config.gateway_virtual_ipv4,900);$success=$reply.Status -eq 'Success';$rtt=if($success){$reply.RoundtripTime}else{$null}}catch{$success=$false;$rtt=$null}finally{$ping.Dispose()}
                if($success){$gatewayGood=$true;$failures=0;$gatewayMethod='icmp'}else{
                    $failures++
                    if($failures -ge 2){
                        $dnsPassed=Test-DirectDNSGateway $config
                        $httpsPassed=$dnsPassed -and (Test-DirectExitHTTPS $config $source.IPAddress)
                        $gatewayMethod=Get-DirectGatewayDecision $false $dnsPassed $httpsPassed
                        if($gatewayMethod -ne 'failed'){$gatewayGood=$true;$internetGood=$true;$lastHTTPS=[DateTime]::UtcNow;$lastHTTPSAttempt=$lastHTTPS;$failures=0;$httpsFailures=0}else{
                            # Retry within the existing proof window; never extend proof on a failed check.
                            $stillFresh=$internetGood -and (Test-DirectProofFresh $lastHTTPS ([DateTime]::UtcNow) $config.health_ttl_seconds)
                            $gatewayGood=$stillFresh;$internetGood=$stillFresh
                        }
                    }
                }
                $refreshAfter=[Math]::Max(2,[Math]::Floor($config.health_ttl_seconds/3))
                if($gatewayGood -and (($now-$lastHTTPSAttempt).TotalSeconds -ge $refreshAfter -or -not $internetGood)){
                    $oldProbes=$probePrefixes
                    Update-DirectProbeAddresses $config
                    $probePrefixes=[string[]]@($config.exit_probes|ForEach-Object {$_.ipv4+'/32'})
                    Set-ScopedIPv4Routes $index @($oldProbes|Where-Object {$_ -notin $probePrefixes}) $config.probe_route_metric $false
                    Write-RoamingJson $probeRoutesPath @($probePrefixes)
                    Set-ScopedIPv4Routes $index $probePrefixes $config.probe_route_metric $true
                    $httpsPassed=Test-DirectExitHTTPS $config $source.IPAddress
                    $lastHTTPSAttempt=[DateTime]::UtcNow
                    if($httpsPassed){$internetGood=$true;$lastHTTPS=$lastHTTPSAttempt;$httpsFailures=0;$preferredEndpoint=$current.endpoint;Write-RoamingJson $preferredPath @{endpoint=$current.endpoint;kind=$current.kind;verified_utc=$lastHTTPS.ToString('o')}}else{
                        $httpsFailures++
                        $internetGood=$internetGood -and (Test-DirectProofFresh $lastHTTPS $lastHTTPSAttempt $config.health_ttl_seconds)
                    }
                }
                $desired=$gatewayGood -and $internetGood -and (Test-DirectProofFresh $lastHTTPS ([DateTime]::UtcNow) $config.health_ttl_seconds)
                if($desired -ne $routeOn){Set-ScopedIPv4Routes $index $prefixes $config.route_metric $desired;$routeOn=$desired;if($desired){$appResets+=Reset-ScopedAppConnections @($config.reconnect_app_executables) $source.IPAddress $config.tunnel_alias}}
            }else{
                $gatewayGood=$false;$internetGood=$false;$routeOn=$false;$rtt=$null
            }
        }catch{
            $errorType=$_.Exception.GetType().Name;$errorMessage=$_.Exception.Message+' at '+$_.ScriptStackTrace;$gatewayGood=$false;$internetGood=$false
            try{if($lastInterface){Set-ScopedIPv4Routes $lastInterface $prefixes $config.route_metric $false}}catch{}
            $routeOn=$false
        }
        Write-RoamingJson $statusPath ([ordered]@{
            observed_utc=[DateTime]::UtcNow.ToString('o');state=if($routeOn -and $failures -eq 0 -and $httpsFailures -eq 0){'home_verified'}elseif($routeOn){'home_degraded'}else{'local_fallback'}
            gateway_verified=$gatewayGood;exit_https_verified=$internetGood;verified_utc=if($internetGood){$lastHTTPS.ToString('o')}else{$null}
            transport=if($current){$current.kind}else{$null};endpoint=if($current){$current.endpoint}else{$null};gateway_rtt_ms=$rtt;gateway_verification=$gatewayMethod
            accelerated_prefixes=if($routeOn){$prefixes.Count}else{0};physical=$physical;network_changes=$networkChanges;endpoint_changes=$endpointChanges;allowlisted_tcp_resets=$appResets
            owned_bypass_count=@($owned).Count;error_type=$errorType;error_message=$errorMessage;scope='Official GUI to authorized regional exit; selected IPv4 routes only. IPv6 remains on the physical network.'
            exit_probe_failures=$httpsFailures
        })
        Start-Sleep -Seconds $config.poll_seconds
    }
}finally{
    try{if($lastInterface){Set-ScopedIPv4Routes $lastInterface $prefixes $config.route_metric $false;Set-ScopedIPv4Routes $lastInterface $probePrefixes $config.probe_route_metric $false}}catch{}
    try{Stop-DirectOwnedSpeeder $config $processPath}catch{}
    $mutex.ReleaseMutex();$mutex.Dispose()
}
