local M=dofile('/usr/libexec/codex-game/endpoint-common.lua')
assert(M.ipv6('2001:db8:1:2::3')=='2001:db8:1:2:0:0:0:3')
assert(M.ipv6('2001:db8:3:4:1111:2222:3333:4444')=='2001:db8:3:4:1111:2222:3333:4444')
for _,bad in ipairs({'::','::1','fe80::1','fd00::1','2001::1::2','2001:::1',':2001::1','2001::1:','2001:1','2001:12345::1','2001:1:2:3:4:5:6:7:8','2001::1;reboot','2001::ffff:192.168.1.1'}) do
 assert(not M.ipv6(bad),'invalid address accepted: '..bad)
end
M.config=function() return {wan6='wan6',wan4='wan'} end
M.read=function() return nil end
M.interface=function(name)
 if name=='wan6' then return {up=true,l3_device='testwan',['ipv6-address']={
  {address='2001:db8:1::9',mask=128,preferred=0,valid=100},
  {address='2001:db8:2::3',mask=128,preferred=50,valid=100},
  {address='2001:db8:2::4',mask=64,preferred=50,valid=100},
  {address='fd00::1',mask=64,preferred=50,valid=100}}} end
 return {['ipv4-address']={{address='192.0.2.2'}},l3_device='testwan',route={{target='0.0.0.0',mask=0,nexthop='192.0.2.1'}}}
end
local state=M.snapshot()
assert(state.address=='2001:db8:2:0:0:0:0:3' and #state.addresses==2)
assert(state.ipv4=='192.0.2.2' and state.gateway=='192.0.2.1')
M.interface=function() return {up=false} end
assert(M.snapshot().address=='','down WAN selected an address')
print('IPv6 validation, deprecated/ULA exclusion, WAN selection and gateway tests passed')
M.config=function() return {peer_node='expected'} end
local now=os.time()*1000
M.command=function() return require('luci.jsonc').stringify({
 {address='other',paths={{address='2001:db8:99::1/9993',active=true,expired=false,lastReceive=now,preferred=true}}},
 {address='expected',paths={
  {address='2001:db8:2::3/9993',active=true,expired=false,lastReceive=now,preferred=true},
  {address='2001:db8:2::3/1234',active=true,expired=false,lastReceive=now-50},
  {address='2001:db8:1::3/9993',active=true,expired=false,lastReceive=now-200000},
  {address='2001:db8:3::3/9993',active=true,expired=true,lastReceive=now},
  {address='2001:db8:4::3/9993',active=false,expired=false,lastReceive=now},
  {address='fd00::1/9993',active=true,expired=false,lastReceive=now}}}}) end
local peers=M.peer_addresses()
assert(#peers==1 and peers[1].address=='2001:db8:2:0:0:0:0:3')
assert(M.prefix(peers[1].address)=='2001:db8:2:0::/64')
print('Pinned peer identity, freshness, expiry, deduplication and IPv6 prefix tests passed')
