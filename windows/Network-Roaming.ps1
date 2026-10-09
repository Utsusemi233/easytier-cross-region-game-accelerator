param([string]$ConfigPath)
$ErrorActionPreference = 'Stop'

function Get-RoamingRoutePlan {
    param($Physical, [string[]]$Endpoints, [object[]]$Owned)
    $desired = @()
    if ($Physical) {
        $desired = @($Endpoints | Sort-Object -Unique | ForEach-Object {
            [pscustomobject]@{ destination = $_ + '/32'; interface_index = [int]$Physical.index; next_hop = $Physical.gateway; route_metric = 17 }
        })
    }
    $remove = @($Owned | Where-Object { $null -ne $_ } | Where-Object {
        $old = $_
        -not @($desired | Where-Object { $_.destination -eq $old.destination -and $_.interface_index -eq $old.interface_index -and $_.next_hop -eq $old.next_hop }).Count
    })
    [pscustomobject]@{ desired = $desired; remove = $remove }
}

function Get-RoamingPhysicalNetwork {
    param([string]$TunnelAlias)
    $candidates = @()
    foreach ($adapter in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne 'Up' -or $adapter.Name -eq $TunnelAlias -or ($adapter.Name + ' ' + $adapter.Description) -match 'ZeroTier|Loopback|OpenVPN|TAP-|TUN|WireGuard') { continue }
        $properties = $adapter.GetIPProperties()
        $gateway = @($properties.GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0' }) | Select-Object -First 1
        if (-not $gateway) { continue }
        $index = $properties.GetIPv4Properties().Index
        $metric = (Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $index -ErrorAction SilentlyContinue).InterfaceMetric
        $addresses = @($properties.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.Address.ToString() } | Sort-Object)
        $candidates += [pscustomobject]@{ index = $index; gateway = $gateway.Address.ToString(); addresses = $addresses; metric = $metric }
    }
    $candidates | Sort-Object metric | Select-Object -First 1
}

function Get-RoamingTransportEndpoints {
    param($Config)
    $token = [IO.File]::ReadAllText((Join-Path $Config.zerotier_directory 'authtoken.secret')).Trim()
    $port = [IO.File]::ReadAllText((Join-Path $Config.zerotier_directory 'zerotier-one.port')).Trim()
    $response = Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:' + $port + '/peer') -Headers @{ 'X-ZT1-Auth' = $token } -TimeoutSec 2
    $peers = @($response.Content | ConvertFrom-Json)
    @($peers | ForEach-Object { $_.paths } | Where-Object { $_.active -and -not $_.expired } | ForEach-Object { ($_.address -split '/')[0] } | Where-Object {
        $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^(0\.|10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)'
    } | Sort-Object -Unique)
}

function Remove-RoamingOwnedRoute {
    param($Entry)
    Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $Entry.destination -InterfaceIndex $Entry.interface_index -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -eq $Entry.next_hop -and $_.RouteMetric -eq $Entry.route_metric } | Remove-NetRoute -Confirm:$false
}

function Write-RoamingJson {
    param([string]$Path, $Value)
    $temporary = $Path + '.new'
    [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $Value -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Set-RoamingAcceleration {
    param($Config, [bool]$Enabled)
    $interface = Get-NetIPInterface -InterfaceAlias $Config.tunnel_alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not $interface) { return }
    foreach ($prefix in $Config.full_routes) {
        $current = @(Get-NetRoute -InterfaceIndex $interface.InterfaceIndex -AddressFamily IPv4 -DestinationPrefix $prefix -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -eq '0.0.0.0' -and $_.RouteMetric -eq $Config.full_route_metric })
        if ($Enabled -and $current.Count -eq 0) {
            New-NetRoute -InterfaceIndex $interface.InterfaceIndex -AddressFamily IPv4 -DestinationPrefix $prefix -NextHop '0.0.0.0' -RouteMetric $Config.full_route_metric -PolicyStore ActiveStore | Out-Null
        } elseif (-not $Enabled -and $current.Count -gt 0) {
            $current | Remove-NetRoute -Confirm:$false
        }
    }
}

function Test-RoamingNativeGateway {
    param($Config)
    $interface = Get-NetIPInterface -InterfaceAlias $Config.tunnel_alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not $interface -or $interface.ConnectionState -ne 'Connected') { return $false }
    $ping = [Net.NetworkInformation.Ping]::new()
    try { return $ping.Send($Config.gateway_virtual_ipv4,800).Status -eq 'Success' } catch { return $false } finally { $ping.Dispose() }
}

function Test-RoamingInternet {
    param($Config)
    foreach ($url in $Config.health_urls) {
        try {
            # Check IPv4 explicitly; working physical IPv6 must not mask a failed IPv4 gateway.
            $code = & curl.exe --ipv4 --noproxy '*' --head --silent --output NUL --write-out '%{http_code}' --connect-timeout 2 --max-time 3 $url 2>$null
            if ($LASTEXITCODE -eq 0 -and $code -match '^\d{3}$' -and [int]$code -ge 200 -and [int]$code -lt 400) { return $true }
        } catch { }
    }
    return $false
}

# Dot sourcing imports pure planning and scoped maintenance functions for tests.
if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $ConfigPath) { throw 'Provide a private configuration file with -ConfigPath.' }
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'Windows curl.exe is required for IPv4 HTTPS health checks.' }
if (@($config.full_routes | Where-Object { $_ -notin @('0.0.0.0/1','128.0.0.0/1') }).Count -or @($config.full_routes).Count -ne 2) { throw 'This gateway mode requires the two explicitly managed /1 routes.' }
if ($config.full_route_metric -lt 1 -or $config.tunnel_alias -match '[\\/]' -or -not $config.state_directory) { throw 'Invalid scoped route configuration.' }
New-Item -ItemType Directory -Path $config.state_directory -Force | Out-Null
$ownedPath = Join-Path $config.state_directory 'owned-routes.private.json'
$statusPath = Join-Path $config.state_directory 'status.private.json'
if (Test-Path $ownedPath) { $owned = @(Get-Content $ownedPath -Raw -Encoding UTF8 | ConvertFrom-Json) } else { $owned = @() }
$created = $false
$mutex = [Threading.Mutex]::new($true, 'Global\EasyTierCrossRegionNetworkRoaming', [ref]$created)
if (-not $created) { $mutex.Dispose(); exit 0 }
$lastSignature = $null
$lastProbe = [DateTime]::MinValue
$lastInternet = [DateTime]::MinValue
$gatewayGood = $false
$internetGood = $false
$failures = 0
$successes = 0
$networkChanges = 0
$events = 'EasyTierCrossRegionPhysicalNetwork'
try {
    try { Register-WmiEvent -Query "SELECT * FROM __InstanceModificationEvent WITHIN 1 WHERE TargetInstance ISA 'Win32_NetworkAdapterConfiguration'" -SourceIdentifier $events | Out-Null } catch { }
    while ($true) {
        $iterationError = $null
        try {
            $physical = Get-RoamingPhysicalNetwork $config.tunnel_alias
            $signature = if ($physical) { [string]$physical.index + '|' + $physical.gateway + '|' + ($physical.addresses -join ',') } else { 'offline' }
            $changed = $null -ne $lastSignature -and $signature -ne $lastSignature
            if ($changed) {
                Set-RoamingAcceleration $config $false
                $gatewayGood = $false; $internetGood = $false; $successes = 0; $failures = 0
                $lastProbe = [DateTime]::MinValue; $lastInternet = [DateTime]::MinValue
                $networkChanges++
            }
            $lastSignature = $signature
            $endpoints = @(Get-RoamingTransportEndpoints $config)
            $plan = Get-RoamingRoutePlan $physical $endpoints $owned
            foreach ($entry in $plan.remove) { Remove-RoamingOwnedRoute $entry }
            $nextOwned = @()
            $liveRoutes = @(Get-NetRoute -AddressFamily IPv4)
            foreach ($entry in $plan.desired) {
                $existing = @($liveRoutes | Where-Object { $_.DestinationPrefix -eq $entry.destination -and $_.InterfaceIndex -eq $entry.interface_index -and $_.NextHop -eq $entry.next_hop })
                $wasOwned = @($owned | Where-Object { $_.destination -eq $entry.destination -and $_.interface_index -eq $entry.interface_index -and $_.next_hop -eq $entry.next_hop }).Count -gt 0
                if ($existing.Count -eq 0) {
                    New-NetRoute -AddressFamily IPv4 -DestinationPrefix $entry.destination -InterfaceIndex $entry.interface_index -NextHop $entry.next_hop -RouteMetric $entry.route_metric -PolicyStore ActiveStore | Out-Null
                    $nextOwned += $entry
                } elseif ($wasOwned) { $nextOwned += $entry }
            }
            $owned = $nextOwned
            Write-RoamingJson $ownedPath @($owned)
            $now = [DateTime]::UtcNow
            if (($now - $lastProbe).TotalSeconds -ge $config.probe_interval_seconds) {
                $lastProbe = $now
                if ($physical -and (Test-RoamingNativeGateway $config)) {
                    $gatewayGood = $true; $successes++; $failures = 0
                } else { $successes = 0; $failures++; if ($failures -ge 2 -or -not $physical) { $gatewayGood = $false; $internetGood = $false } }
            }
            if ($gatewayGood -and $successes -ge 1) {
                Set-RoamingAcceleration $config $true
                if (($now - $lastInternet).TotalSeconds -ge $config.internet_probe_interval_seconds) {
                    $lastInternet = $now
                    $internetGood = Test-RoamingInternet $config
                }
                if (-not $internetGood) { Set-RoamingAcceleration $config $false; $lastInternet = [DateTime]::MinValue }
            } elseif (-not $gatewayGood) { Set-RoamingAcceleration $config $false }
        } catch {
            $iterationError = $_.Exception.GetType().Name
            $gatewayGood = $false; $internetGood = $false; $successes = 0
            try { Set-RoamingAcceleration $config $false } catch { }
        }
        Write-RoamingJson $statusPath ([ordered]@{
            observed_utc = [DateTime]::UtcNow.ToString('o')
            state = if ($gatewayGood -and $internetGood -and $successes -ge 1) { 'entry_verified' } elseif ($gatewayGood -and $internetGood) { 'entry_degraded' } else { 'local_fallback' }
            gateway_verified = $gatewayGood; internet_verified = $internetGood
            network_changes = $networkChanges; owned_bypass_count = @($owned).Count
            error_type = $iterationError
            scope = 'Windows native entry and Internet; regional FEC exit is verified separately on the router.'
        })
        Wait-Event -SourceIdentifier $events -Timeout $config.poll_seconds -ErrorAction SilentlyContinue | Out-Null
        Get-Event -SourceIdentifier $events -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    }
} finally {
    try { Set-RoamingAcceleration $config $false } catch { }
    Unregister-Event -SourceIdentifier $events -ErrorAction SilentlyContinue
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
