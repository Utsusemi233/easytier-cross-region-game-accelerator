# Windows IP Helper API; only callers' explicit IPv4 prefixes/interface/next hop are touched.
if (-not ('EasyTierScopedRoutes' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Runtime.InteropServices;
public static class EasyTierScopedRoutes {
 [StructLayout(LayoutKind.Explicit, Size=28)] public struct Address {
  [FieldOffset(0)] public ushort Family;
  [FieldOffset(4)] public uint IPv4;
 }
 [StructLayout(LayoutKind.Sequential)] public struct Prefix { public Address Address; public byte Length; }
 [StructLayout(LayoutKind.Sequential)] public struct Row {
  public ulong Luid; public uint Index; public Prefix Destination; public Address NextHop;
  public byte SitePrefixLength; public uint ValidLifetime; public uint PreferredLifetime; public uint Metric; public uint Protocol;
  public byte Loopback; public byte Autoconfigure; public byte Publish; public byte Immortal;
  public uint Age; public uint Origin;
 }
 [DllImport("iphlpapi.dll")] static extern void InitializeIpForwardEntry(ref Row row);
 [DllImport("iphlpapi.dll")] static extern uint CreateIpForwardEntry2(ref Row row);
 [DllImport("iphlpapi.dll")] static extern uint DeleteIpForwardEntry2(ref Row row);
 [DllImport("iphlpapi.dll")] static extern uint GetBestRoute2(IntPtr luid,uint index,IntPtr source,ref Address destination,uint options,out Row best,out Address bestSource);
 static Address IPv4(string ip) {
  var address=IPAddress.Parse(ip);
  if(address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork) throw new ArgumentException("IPv4 required");
  return new Address{Family=2,IPv4=BitConverter.ToUInt32(address.GetAddressBytes(),0)};
 }
 static Row Build(uint index,string cidr,string nextHop,uint metric) {
  if(Marshal.SizeOf(typeof(Row))!=104) throw new InvalidOperationException("Unexpected Windows route layout");
  var parts=cidr.Split('/'); if(parts.Length!=2) throw new ArgumentException("IPv4 CIDR required");
  int length=int.Parse(parts[1]); if(length<0||length>32) throw new ArgumentException("Invalid IPv4 prefix length");
  Row row=new Row(); InitializeIpForwardEntry(ref row);
  row.Index=index; row.Luid=0; row.Destination=new Prefix{Address=IPv4(parts[0]),Length=(byte)length};
  row.NextHop=IPv4(nextHop);row.Metric=metric;row.Protocol=3;row.Origin=0;
  return row;
 }
 public static uint Add(uint index,string cidr,string nextHop,uint metric) {var r=Build(index,cidr,nextHop,metric);return CreateIpForwardEntry2(ref r);}
 public static uint Remove(uint index,string cidr,string nextHop,uint metric) {var r=Build(index,cidr,nextHop,metric);return DeleteIpForwardEntry2(ref r);}
 public static int RowSize(){return Marshal.SizeOf(typeof(Row));}
 public static uint BestIndex(string destination){var address=IPv4(destination);Row best;Address source;var code=GetBestRoute2(IntPtr.Zero,0,IntPtr.Zero,ref address,0,out best,out source);if(code!=0)throw new InvalidOperationException("Route lookup failed: "+code);return best.Index;}
}
'@
}

function Set-ScopedIPv4Routes {
    param([int]$InterfaceIndex,[string[]]$Prefixes,[int]$Metric,[bool]$Enabled)
    $wanted=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($prefix in $Prefixes){[void]$wanted.Add($prefix)}
    $matching=@(Get-NetRoute -AddressFamily IPv4 -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue | Where-Object {$wanted.Contains($_.DestinationPrefix) -and $_.NextHop -eq '0.0.0.0' -and $_.RouteMetric -eq $Metric})
    if($Enabled){
        $present=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($route in $matching){[void]$present.Add($route.DestinationPrefix)}
        foreach($prefix in $wanted){
            if(-not $present.Contains($prefix)){
                $code=[EasyTierScopedRoutes]::Add($InterfaceIndex,$prefix,'0.0.0.0',$Metric)
                if($code -ne 0 -and $code -ne 5010){throw "Scoped route creation failed: $code"}
            }
        }
    }else{
        foreach($route in $matching){
            $code=[EasyTierScopedRoutes]::Remove($InterfaceIndex,$route.DestinationPrefix,'0.0.0.0',$Metric)
            if($code -ne 0 -and $code -ne 1168){throw "Scoped route removal failed: $code"}
        }
    }
}
