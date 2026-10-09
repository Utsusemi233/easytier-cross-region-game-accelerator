# Optional, explicitly allowlisted games only. No unrelated application connections are closed.
if(-not('EasyTierAppReconnect' -as [type])){
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class EasyTierAppReconnect {
 [StructLayout(LayoutKind.Sequential)] public struct Row {public uint State,LocalAddress,LocalPort,RemoteAddress,RemotePort;}
 [DllImport("iphlpapi.dll")] static extern uint SetTcpEntry(ref Row row);
 public static uint Close(string local,int localPort,string remote,int remotePort){
  var r=new Row{State=12,LocalAddress=BitConverter.ToUInt32(System.Net.IPAddress.Parse(local).GetAddressBytes(),0),RemoteAddress=BitConverter.ToUInt32(System.Net.IPAddress.Parse(remote).GetAddressBytes(),0),LocalPort=(uint)(((localPort&255)<<8)|(localPort>>8)),RemotePort=(uint)(((remotePort&255)<<8)|(remotePort>>8))};
  return SetTcpEntry(ref r);
 }
}
'@
}
function Get-ScopedAppReconnectPlan {
    param([object[]]$Connections,[string]$TunnelIPv4,[string]$TunnelAlias)
    @($Connections|Where-Object {$_.local -ne $TunnelIPv4 -and $_.local -notmatch '^127\.' -and $_.route_alias -eq $TunnelAlias -and $_.local -match '^\d+\.\d+\.\d+\.\d+$'})
}
function Reset-ScopedAppConnections {
    param([string[]]$Executables,[string]$TunnelIPv4,[string]$TunnelAlias)
    if(-not $Executables.Count -or -not $TunnelIPv4){return 0}
    $allowed=@(Get-Process|Where-Object {$_.Path -and $_.Path -in $Executables})
    $tunnelIndex=(Get-NetIPInterface -InterfaceAlias $TunnelAlias -AddressFamily IPv4 -ErrorAction Stop|Select-Object -First 1).InterfaceIndex
    $reset=0
    foreach($process in $allowed){
        $connections=@(Get-NetTCPConnection -OwningProcess $process.Id -State Established -ErrorAction SilentlyContinue)
        foreach($connection in $connections){
            if($connection.RemoteAddress -notmatch '^\d+\.\d+\.\d+\.\d+$' -or $connection.LocalAddress -eq $TunnelIPv4 -or $connection.LocalAddress -match '^127\.') {continue}
            $routeIndex=[EasyTierScopedRoutes]::BestIndex($connection.RemoteAddress)
            $alias=if($routeIndex -eq $tunnelIndex){$TunnelAlias}else{''}
            $plan=@(Get-ScopedAppReconnectPlan @([pscustomobject]@{local=$connection.LocalAddress;route_alias=$alias}) $TunnelIPv4 $TunnelAlias)
            if($plan.Count -and [EasyTierAppReconnect]::Close($connection.LocalAddress,$connection.LocalPort,$connection.RemoteAddress,$connection.RemotePort) -eq 0){$reset++}
        }
    }
    return $reset
}
