local json = require 'luci.jsonc'
local M = {}
M.config_path = '/etc/codex-game/endpoint-config.json'
M.runtime_path = '/var/run/codex-game-endpoints.json'
M.saved_path = '/etc/codex-game/endpoints.json'
M.validated_path = '/var/run/codex-game-endpoint-validated'
M.wake_path = '/var/run/codex-game-endpoint-wake'
function M.quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
function M.read(path)
 local f = io.open(path, 'r'); if not f then return nil end
 local s = f:read('*a'); f:close(); return s
end
function M.load(path) return json.parse(M.read(path) or '') end
function M.atomic(path, value)
 local text = type(value) == 'table' and json.stringify(value) or value
 local f = assert(io.open(path .. '.new', 'w')); assert(f:write(text)); f:close()
 assert(require('nixio.fs').chmod(path .. '.new','600'))
 assert(os.rename(path .. '.new', path))
end
function M.run(cmd) return os.execute(cmd .. ' >/dev/null 2>&1') == 0 end
function M.command(cmd)
 local f = io.popen(cmd .. ' 2>/dev/null', 'r'); if not f then return '' end
 local text = f:read('*a'); f:close(); return text
end
function M.log(text) M.run('logger -t codex-game-endpoints ' .. M.quote(text)) end
function M.ipv6(address)
 if type(address) ~= 'string' or #address > 39 or not address:match('^[%x:]+$') then return nil end
 if address:find(':::') then return nil end
 if (address:sub(1,1)==':' and address:sub(1,2)~='::') or (address:sub(-1)==':' and address:sub(-2)~='::') then return nil end
 local groups, count = {}, 0
 local compression = address:find('::', 1, true)
 if compression and address:find('::', compression + 2, true) then return nil end
 if not compression and (address:sub(1,1)==':' or address:sub(-1)==':') then return nil end
 for segment in address:gmatch('[^:]+') do
  if #segment > 4 then return nil end
  count = count + 1; groups[count] = tonumber(segment,16)
 end
 if (compression and count >= 8) or (not compression and count ~= 8) then return nil end
 if compression then
  local left, right = {}, {}
  for s in address:sub(1,compression-1):gmatch('[^:]+') do left[#left+1]=tonumber(s,16) end
  for s in address:sub(compression+2):gmatch('[^:]+') do right[#right+1]=tonumber(s,16) end
  groups = left
  for i=1,8-count do groups[#groups+1]=0 end
  for _,v in ipairs(right) do groups[#groups+1]=v end
 end
 if #groups ~= 8 or groups[1] < 0x2000 or groups[1] > 0x3fff then return nil end
 for i,v in ipairs(groups) do groups[i]=string.format('%x',v) end
 return table.concat(groups,':')
end
function M.config() return assert(M.load(M.config_path), 'endpoint configuration missing') end
function M.ready()
 local conf=M.config(); local state=M.load(M.runtime_path) or {}; local proof=state.validation
 local marker=(M.read(M.validated_path) or ''):match('^%s*(.-)%s*$')
 return conf.enabled~=false and state.applied and marker==state.signature and proof and proof.internet==true and tonumber(proof.verified_at) and os.time()-proof.verified_at>=0 and os.time()-proof.verified_at<=(conf.probe_ttl or 180)
end
function M.ensure_neighbor()
 local conf=M.config(); local peer=conf.role=='home' and conf.my_zt or conf.home_zt
 if not conf.peer_mac or not conf.zt_interface then return end
 assert(conf.peer_mac:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$'))
 assert(conf.zt_interface:match('^[%w_]+$'))
 local current=M.command('ip neigh show '..peer..' dev '..conf.zt_interface)
 if not current:find(conf.peer_mac,1,true) or not current:find('PERMANENT',1,true) then
  M.run('ip neigh replace '..peer..' lladdr '..conf.peer_mac..' dev '..conf.zt_interface..' nud permanent')
 end
end
function M.prime_peer()
 M.ensure_neighbor()
 local conf=M.config(); local n=require 'nixio'
 local local_ip=conf.role=='home' and conf.home_zt or conf.my_zt
 local peer_ip=conf.role=='home' and conf.my_zt or conf.home_zt
 local socket=n.socket('inet','dgram'); if not socket then return end
 if socket:bind(local_ip,0) then socket:sendto('codex-endpoint-presence-v1',peer_ip,51849) end
 socket:close()
end
function M.peer_addresses()
 local conf=M.config(); local peers=json.parse(M.command('zerotier-cli -j listpeers')) or {}
 local found={}; local result={}; local now=os.time()*1000
 for _,peer in ipairs(peers) do
  if peer.address==conf.peer_node then
   for _,path in ipairs(peer.paths or {}) do
    local address=M.ipv6((path.address or ''):match('^(.-)/%d+$'))
    local received=tonumber(path.lastReceive) or 0
    if address and path.active and not path.expired and received>0 and now-received<180000 then
     local old=found[address]
     if not old or received>old.received then found[address]={address=address,received=received,preferred=path.preferred or false} end
    end
   end
  end
 end
 for _,entry in pairs(found) do result[#result+1]=entry end
 table.sort(result,function(a,b) if a.preferred~=b.preferred then return a.preferred end; return a.received>b.received end)
 return result
end
function M.prefix(address)
 local valid=M.ipv6(address); if not valid then return nil end
 local pieces={}; for piece in valid:gmatch('[^:]+') do pieces[#pieces+1]=piece end
 return table.concat({pieces[1],pieces[2],pieces[3],pieces[4]},':')..'::/64'
end
function M.interface(name)
 assert(name:match('^[%w_]+$'))
 return json.parse(M.command('ubus call network.interface.' .. name .. ' status')) or {}
end
function M.snapshot()
 local conf = M.config(); local v6 = M.interface(conf.wan6 or 'wan6'); local v4 = M.interface(conf.wan4 or 'wan')
 local candidates, all = {}, {}
 if v6.up then
  for _,entry in ipairs(v6['ipv6-address'] or {}) do
   local address = M.ipv6(entry.address)
   if address and (entry.preferred or 0)>0 and (entry.valid or 0)>0 then
    candidates[#candidates+1]={address=address,mask=entry.mask or 64}; all[#all+1]=address
   end
  end
 end
 table.sort(candidates,function(a,b) if a.mask==b.mask then return a.address<b.address end return a.mask>b.mask end)
 table.sort(all)
 local chosen = candidates[1] and candidates[1].address or ''
 local preference = M.ipv6((M.read('/etc/codex-game/endpoint-preferred') or ''):match('^%s*(.-)%s*$'))
 if preference then for _,item in ipairs(candidates) do if item.address==preference then chosen=preference end end end
 local gateway = ''
 for _,route in ipairs(v4.route or {}) do if route.target=='0.0.0.0' and route.mask==0 then gateway=route.nexthop or '' end end
 local ipv4 = (v4['ipv4-address'] or {})[1]
 return {address=chosen,addresses=all,device=v6.l3_device or '',ipv4=ipv4 and ipv4.address or '',wan_device=v4.l3_device or '',gateway=gateway}
end
function M.signature(local_state, home_state)
 return table.concat({local_state.address,home_state.address,local_state.ipv4 or '',local_state.wan_device or '',local_state.gateway or '',home_state.ipv4 or '',home_state.wan_device or '',home_state.gateway or ''},'|')
end
function M.save(state)
 M.atomic(M.runtime_path,state)
 local previous = M.load(M.saved_path)
 if not previous or previous.signature~=state.signature then M.atomic(M.saved_path,state) end
end
if arg and arg[0] and arg[0]:match('([^/]+)$')=='endpoint-common.lua' then
 if arg[1]=='ready' then os.exit(M.ready() and 0 or 1)
 elseif arg[1]=='address' then print(M.snapshot().address)
 elseif arg[1]=='all-addresses' then for _,address in ipairs(M.snapshot().addresses) do print(address) end
 elseif arg[1]=='stored-home' then
  local state=M.load(M.runtime_path) or M.load(M.saved_path) or {}; print(M.ipv6((state.home or {}).address) or '')
 elseif arg[1]=='snapshot' then print(json.stringify(M.snapshot()))
 elseif arg[1]=='peer-addresses' then print(json.stringify(M.peer_addresses()))
 elseif arg[1]=='validate-address' then assert(M.ipv6(arg[2]),'invalid global IPv6'); print(M.ipv6(arg[2]))
 else error('invalid endpoint helper operation') end
end
return M
