local n=require 'nixio'
local M=dofile('/usr/libexec/codex-game/endpoint-common.lua')
local conf=M.config(); local previous,logged_error=nil,''
local function update_firewall()
 local prefixes,seen={},{}
 for _,peer in ipairs(M.peer_addresses()) do
  local prefix=M.prefix(peer.address)
  if prefix and not seen[prefix] then prefixes[#prefixes+1]=prefix; seen[prefix]=true end
 end
 if #prefixes==0 then return end
 table.sort(prefixes)
 local expected=table.concat(prefixes,' ')
 local current=M.command('uci -q get firewall.codex_game_fec.src_ip'):gsub('%s+$','')
 if current==expected then return end
 M.run('uci -q delete firewall.codex_game_fec.src_ip')
 for _,prefix in ipairs(prefixes) do assert(M.run('uci add_list firewall.codex_game_fec.src_ip='..M.quote(prefix))) end
 assert(M.run('uci commit firewall'),'firewall commit failed')
 assert(M.run('/etc/init.d/firewall reload'),'home firewall refresh failed')
 assert(M.run('/etc/codex-game-home-nat.sh'),'home NAT refresh after firewall failed')
 M.log('Authenticated MY node IPv6 prefixes synchronized: '..expected)
end
local function cycle()
 conf=M.config()
 if conf.enabled==false then
  if previous~='paused' then
   for _,address in ipairs(M.snapshot().addresses) do M.run('/etc/init.d/codex-game-home stop '..M.quote('fec_'..address:gsub(':','_'))) end
   previous='paused'; M.log('Home FEC entries paused; core identity preserved')
  end
  return
 end
 if previous=='paused' then previous=nil end
 M.prime_peer()
 local own=M.snapshot()
 own.signature=table.concat(own.addresses,',')..'|'..own.ipv4..'|'..own.wan_device..'|'..own.gateway
 if not previous or previous.signature~=own.signature then
  assert(M.run('/etc/init.d/codex-game-home reload'),'home FEC listeners refresh failed')
  if not previous or previous.wan_device~=own.wan_device then assert(M.run('/etc/codex-game-home-nat.sh'),'home NAT refresh failed') end
  previous=own
  M.atomic(M.runtime_path,{home=own,updated_at=os.time()})
  M.log('Home listeners synchronized with current preferred WAN IPv6 addresses: '..table.concat(own.addresses,','))
 end
 update_firewall()
end
M.log('Home endpoint monitor started: authenticated ZeroTier peer address discovery')
while true do
 local started=os.time()
 local ok,err=pcall(cycle)
 if not ok and tostring(err)~=logged_error then M.log('Home endpoint refresh failed: '..tostring(err)); logged_error=tostring(err) elseif ok then logged_error='' end
 for i=1,conf.poll_seconds do
  if M.read(M.wake_path) then os.remove(M.wake_path); break end
  if os.time()-started>=conf.poll_seconds then break end
  n.nanosleep(1,0)
 end
end
