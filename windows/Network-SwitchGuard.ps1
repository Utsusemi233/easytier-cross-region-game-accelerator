param([string]$ConfigPath)
$ErrorActionPreference = 'Stop'

function Assert-NetworkSwitchGuardConfig {
    param($Config)
    if (-not $Config -or $Config.poll_seconds -lt 1 -or $Config.settle_seconds -lt 1 -or
        -not [IO.Path]::IsPathRooted([string]$Config.state_directory)) { throw 'Invalid guard configuration.' }
    $aliases = @{}
    foreach ($profile in $Config.profiles) {
        if ($profile.alias -notmatch '^[A-Za-z0-9_-]{1,32}$' -or $aliases.ContainsKey([string]$profile.alias) -or
            -not [IO.Path]::IsPathRooted([string]$profile.status_file) -or
            $profile.proof_ttl_seconds -lt 5 -or $profile.proof_ttl_seconds -gt 60) { throw 'Invalid owned profile configuration.' }
        $aliases[[string]$profile.alias] = $true
    }
}

function Get-SwitchProfilePhase {
    param($Status, [string[]]$Addresses, [DateTime]$Now, [int]$TtlSeconds)
    if (-not $Status -or -not $Addresses.Count) { return 'local' }
    $observed = [DateTime]::MinValue; $verified = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Status.observed_utc, [ref]$observed) -or
        -not [DateTime]::TryParse([string]$Status.verified_utc, [ref]$verified)) { return 'local' }
    $age = ($Now - $observed.ToUniversalTime()).TotalSeconds
    $proofAge = ($Now - $verified.ToUniversalTime()).TotalSeconds
    if ($age -lt -2 -or $age -gt 15 -or $proofAge -lt -2 -or $proofAge -gt $TtlSeconds -or
        [int]$Status.accelerated_prefixes -le 0 -or $Status.source_ipv4 -notin $Addresses -or
        $Status.state -eq 'profile_conflict') { return 'local' }
    return 'routed'
}

function Get-SwitchSnapshot {
    param($Config, [DateTime]$Now)
    $physical = @(); $tunnels = @()
    $interfaces = @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces())
    $aliases = @($Config.profiles | ForEach-Object { $_.alias })
    foreach ($adapter in $interfaces) {
        if ($adapter.OperationalStatus -ne 'Up') { continue }
        $properties = $adapter.GetIPProperties()
        $addresses = @($properties.UnicastAddresses | Where-Object {
            $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -notmatch '^(127\.|169\.254\.)'
        } | ForEach-Object { $_.Address.ToString() } | Sort-Object)
        if ($adapter.Name -in $aliases) {
            $profile = $Config.profiles | Where-Object { $_.alias -eq $adapter.Name } | Select-Object -First 1
            $status = $null
            if (Test-Path -LiteralPath $profile.status_file) {
                $status = [IO.File]::ReadAllText($profile.status_file) | ConvertFrom-Json
            }
            $tunnels += [ordered]@{ alias=$adapter.Name; addresses=$addresses; phase=(Get-SwitchProfilePhase $status $addresses $Now $profile.proof_ttl_seconds) }
            continue
        }
        if (($adapter.Name + ' ' + $adapter.Description) -match 'ZeroTier|Loopback|OpenVPN|TAP-|TUN|WireGuard|Wintun|sing-box|mihomo|clash' -or
            $adapter.NetworkInterfaceType -in @('Loopback','Tunnel')) { continue }
        $gateways = @($properties.GatewayAddresses | ForEach-Object { $_.Address.ToString() } | Where-Object { $_ -notin @('0.0.0.0','::') } | Sort-Object)
        if (-not $gateways.Count) { continue }
        $index = $properties.GetIPv4Properties().Index
        $names = @((Get-NetConnectionProfile -InterfaceIndex $index -ErrorAction Stop).Name | Sort-Object)
        $dns = @($properties.DnsAddresses | ForEach-Object { $_.ToString() } | Sort-Object)
        $v6Prefixes = @($properties.UnicastAddresses | Where-Object {
            $_.Address.AddressFamily -eq 'InterNetworkV6' -and -not $_.Address.IsIPv6LinkLocal -and -not $_.Address.IsIPv6Multicast
        } | ForEach-Object { [BitConverter]::ToString($_.Address.GetAddressBytes(),0,8) } | Sort-Object -Unique)
        $physical += [ordered]@{ name=$adapter.Name; index=$index; profiles=$names; ipv4=$addresses; gateways=$gateways; dns=$dns; ipv6_prefixes=$v6Prefixes }
    }
    $physical = @($physical | Sort-Object { $_.name })
    $tunnels = @($tunnels | Sort-Object { $_.alias })
    $signature = ConvertTo-Json -InputObject ([ordered]@{ physical=$physical; tunnels=$tunnels }) -Depth 8 -Compress
    [pscustomobject]@{ online=($physical.Count -gt 0); signature=$signature; physical=$physical; tunnels=$tunnels }
}

function Update-SwitchGuardState {
    param($State, $Snapshot, [DateTime]$Now, [int]$SettleSeconds)
    $State.needs_flush = $false
    if (-not $Snapshot.online) { $State.applied_signature = $null }
    if (-not $Snapshot.online) { $State.applied_signature = $null }
    if ($State.pending_signature -ne $Snapshot.signature) {
        $State.pending_signature = $Snapshot.signature
        $State.pending_since_utc = $Now.ToString('o')
    }
    if ($Snapshot.online -and $State.applied_signature -ne $Snapshot.signature -and
        ($Now - [DateTime]::Parse($State.pending_since_utc).ToUniversalTime()).TotalSeconds -ge $SettleSeconds) {
        $State.needs_flush = $true
    }
    return $State
}

function Write-SwitchGuardJson {
    param([string]$Path, $Value)
    [IO.File]::WriteAllText(($Path+'.new'), (ConvertTo-Json -InputObject $Value -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath ($Path+'.new') -Destination $Path -Force
}

if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $ConfigPath) { throw 'Provide -ConfigPath for this explicitly installed network switch guard.' }
$config = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $ConfigPath).Path) | ConvertFrom-Json
Assert-NetworkSwitchGuardConfig $config
New-Item -ItemType Directory -Path $config.state_directory -Force | Out-Null
$created = $false
$mutex = [Threading.Mutex]::new($true,'Global\EasyTierNetworkSwitchDnsGuard',[ref]$created)
if (-not $created) { $mutex.Dispose(); exit 0 }
$state = [pscustomobject]@{ pending_signature=$null; pending_since_utc=$null; applied_signature=$null; needs_flush=$false }
$flushes = 0; $lastFlush = $null; $lastSnapshot = $null
$historyPath = Join-Path $config.state_directory 'events.private.jsonl'
try {
    while ($true) {
        $errorMessage = $null; $action = 'observing'
        try {
            $now = [DateTime]::UtcNow
            $snapshot = Get-SwitchSnapshot $config $now
            $lastSnapshot = $snapshot
            $state = Update-SwitchGuardState $state $snapshot $now $config.settle_seconds
            if ($state.needs_flush) {
                Clear-DnsClientCache -ErrorAction Stop
                $state.applied_signature = $snapshot.signature
                $state.needs_flush = $false
                $flushes++; $lastFlush = [DateTime]::UtcNow.ToString('o'); $action = 'cache_refreshed'
                if ((Test-Path -LiteralPath $historyPath) -and (Get-Item -LiteralPath $historyPath).Length -gt 131072) {
                    Move-Item -LiteralPath $historyPath -Destination ($historyPath+'.previous') -Force
                }
                $event = [ordered]@{ observed_utc=$lastFlush; action=$action; physical=$snapshot.physical; tunnels=$snapshot.tunnels }
                [IO.File]::AppendAllText($historyPath,((ConvertTo-Json -InputObject $event -Depth 8 -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
            } elseif (-not $snapshot.online) { $action = 'offline' }
            elseif ($state.applied_signature -ne $snapshot.signature) { $action = 'settling' }
        } catch { $errorMessage=$_.Exception.Message; $action='error' }
        Write-SwitchGuardJson (Join-Path $config.state_directory 'status.private.json') ([ordered]@{
            observed_utc=[DateTime]::UtcNow.ToString('o'); state=$action; flush_count=$flushes; last_flush_utc=$lastFlush
            physical=if($lastSnapshot){$lastSnapshot.physical}else{@()}; tunnels=if($lastSnapshot){$lastSnapshot.tunnels}else{@()}
            error_message=$errorMessage; scope='DNS cache refresh after physical network or owned EasyTier route transitions; no app termination or DNS/route configuration changes.'
        })
        Start-Sleep -Seconds $config.poll_seconds
    }
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
