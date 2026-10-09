local fs=require 'nixio.fs'
local json=require 'luci.jsonc'
local uci=require 'luci.model.uci'
local C=dofile('/usr/libexec/codex-game/endpoint-common.lua')
local M={}
local function run(cmd) assert(C.run(cmd),'Deployment operation failed') end
local function set(cursor,package,id,kind,values)
 local current=cursor:get_all(package,id)
 assert(not current or current.etgame_owner=='1','An existing unowned section conflicts: '..package..'.'..id)
 cursor:delete(package,id); values.etgame_owner='1'; cursor:section(package,kind,id,values)
end
function M.preflight(cfg,previous)
 local cursor=uci.cursor()
 local targets={{'firewall','etgame_zt'},{'firewall','etgame_forward'}}
 if cfg.role=='home' then
  for _,id in ipairs({'codex_game_fec','etgame_home'}) do targets[#targets+1]={'firewall',id} end
 else
  for _,item in ipairs({{'network','wg_game'},{'network','etgame_peer'},{'firewall','etgame_client'}}) do targets[#targets+1]=item end
  if not (previous and previous.manager_owned) then
   local rules=C.command('ip -4 rule show')
   for _,priority in ipairs({11020,11030}) do
    assert(not ('\n'..rules):match('\n'..priority..':'),'Reserved policy priority already exists; migrate it explicitly before deploying')
   end
  end
 end
 for _,item in ipairs(targets) do
  local current=cursor:get_all(item[1],item[2])
  assert(not current or current.etgame_owner=='1','An existing unowned section conflicts: '..item[1]..'.'..item[2])
 end
 return true
end
function M.apply(cfg)
 local cursor=uci.cursor()
 local root='/usr/libexec/codex-game'
 assert(cfg.udpspeeder==root..'/udpspeeder' and cfg.easytier_core==root..'/easytier-core' and cfg.easytier_cli==root..'/easytier-cli','First version managed deployment uses the documented binary directory')
 set(cursor,'firewall','etgame_zt','rule',{name='ET game authenticated discovery',src='wan',proto='udp',dest_port='9993',target='ACCEPT'})
 if cfg.role=='home' then
  local prefixes={}; local seen={}
  for _,peer in ipairs(C.peer_addresses()) do local prefix=C.prefix(peer.address); if prefix and not seen[prefix] then prefixes[#prefixes+1]=prefix; seen[prefix]=true end end
  assert(#prefixes>0,'No authenticated global IPv6 path for the client; wait for discovery before opening the FEC entry')
  set(cursor,'firewall','codex_game_fec','rule',{name='ET game IPv6 FEC',src='wan',proto='udp',dest_port=cfg.fec_port,family='ipv6',src_ip=prefixes,target='ACCEPT'})
  set(cursor,'firewall','etgame_home','zone',{name='etgame_home',device={'etgame'},input='ACCEPT',output='ACCEPT',forward='REJECT'})
  set(cursor,'firewall','etgame_forward','forwarding',{src='etgame_home',dest='wan'})
  cursor:commit('firewall')
  local existing=C.read('/etc/codex-game/home.toml')
  if not existing then
   local uuid=(C.command('cat /proc/sys/kernel/random/uuid')):match('[%x%-]+')
   assert(uuid and #uuid==36,'Could not create a stable private instance identity')
   local private=cfg.network_secret~='' and cfg.network_secret or ((C.command('cat /proc/sys/kernel/random/uuid')):match('[%x%-]+'))
   local source='instance_id = '..json.stringify(uuid)..'\nhostname = "home-game"\nipv4 = '..json.stringify(cfg.home_probe)..'\nlisteners = []\n[network_identity]\nnetwork_name = '..json.stringify(cfg.network_name)..'\nnetwork_secret = '..json.stringify(private)..'\n[flags]\nprivate_mode = true\n'
   C.atomic('/etc/codex-game/home.toml',source); fs.chmod('/etc/codex-game/home.toml','600')
  end
  run('/etc/init.d/firewall reload'); run('/etc/codex-game-home-nat.sh')
  run('/etc/init.d/codex-game-home enable'); run('/etc/init.d/codex-game-home reload')
 else
  assert(cfg.wg_private_key~='' and cfg.home_public_key~='','Import the private home portal profile first')
  set(cursor,'network','wg_game','interface',{proto='wireguard',private_key=cfg.wg_private_key,addresses={cfg.wg_address},mtu=cfg.mtu})
  set(cursor,'network','etgame_peer','wireguard_wg_game',{description='ET game home gateway',public_key=cfg.home_public_key,allowed_ips={'0.0.0.0/0'},route_allowed_ips='0',endpoint_host='127.0.0.1',endpoint_port=cfg.local_port,persistent_keepalive='15'})
  set(cursor,'firewall','etgame_client','zone',{name='etgame_client',network={'wg_game'},input='ACCEPT',output='ACCEPT',forward='REJECT'})
  set(cursor,'firewall','etgame_forward','forwarding',{src=cfg.game_zone,dest='etgame_client'})
  cursor:commit('network'); cursor:commit('firewall')
  run('ifup wg_game')
  run('ip rule del priority 11030 2>/dev/null || true')
  run('ip rule add priority 11030 from '..C.quote(cfg.game_cidr)..' fwmark 0x80000000/0x80000000 lookup 2848')
  run('/etc/init.d/codex-game-fec enable'); run('/etc/init.d/codex-game-fec reload')
  run('/etc/init.d/codex-game-route enable'); run('/etc/init.d/codex-game-route restart')
 end
end
return M
