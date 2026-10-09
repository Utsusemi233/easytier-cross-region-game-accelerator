-- Transaction rendering test: substitute UCI, filesystem and commands;
-- no system network, firewall or service is changed by this process.
local json=require 'luci.jsonc'
local calls,stored,sections={},{},{network={},firewall={}}
local policy=''
local cursor={}
function cursor:get_all(pkg,id) return sections[pkg][id] end
function cursor:delete(pkg,id) sections[pkg][id]=nil end
function cursor:section(pkg,kind,id,values) values['.type']=kind; sections[pkg][id]=values end
function cursor:commit() return true end
local C={}
function C.quote(s) return "'"..s:gsub("'","'\\''").."'" end
function C.run(cmd) calls[#calls+1]=cmd; return true end
function C.command(cmd) return cmd=='ip -4 rule show' and policy or '12345678-1234-1234-1234-123456789abc' end
function C.read(path) return stored[path] end
function C.atomic(path,data) stored[path]=data end
function C.peer_addresses() return {{address='2001:db8:1::1'}} end
function C.prefix() return '2001:db8:1::/64' end
package.loaded['luci.model.uci']={cursor=function() return cursor end}
package.loaded['nixio.fs']={chmod=function() return true end}
local original=dofile
function dofile(path)
 if path=='/usr/libexec/codex-game/endpoint-common.lua' then return C end
 return original(path)
end
local D=original('/usr/lib/lua/luci/model/easytier_home_game_deploy.lua')
local cfg={role='client',udpspeeder='/usr/libexec/codex-game/udpspeeder',easytier_core='/usr/libexec/codex-game/easytier-core',easytier_cli='/usr/libexec/codex-game/easytier-cli',wg_private_key='fixture',home_public_key='fixture',wg_address='10.147.18.2/24',mtu='1200',local_port='14432',game_zone='game',game_cidr='192.168.50.0/24',fec_port='443',network_name='fixture-network',network_secret='',home_probe='10.147.17.1'}
policy='11030: from all lookup unrelated\n'
assert(not pcall(D.preflight,cfg,nil),'An existing policy priority was not rejected')
assert(#calls==0 and not next(sections.network),'Preflight mutated the system')
policy=''; sections.network.wg_game={proto='unrelated'}
assert(not pcall(D.preflight,cfg,nil),'An unowned interface conflict was not rejected')
sections.network.wg_game=nil
assert(D.preflight(cfg,nil)); D.apply(cfg)
assert(sections.network.wg_game.etgame_owner=='1')
assert(sections.network.etgame_peer.route_allowed_ips=='0','Deployment would replace the main default route')
assert(sections.firewall.etgame_forward.src=='game')
assert(not sections.network.wan and not sections.firewall.wan,'Deployment replaced the WAN')
for _,cmd in ipairs(calls) do assert(not cmd:match('ip route.-table main') and not cmd:match('network restart'),'Global network restart') end
cfg.role='home'; calls={}; sections={network={},firewall={}}
assert(D.preflight(cfg,nil)); D.apply(cfg)
local identity=stored['/etc/codex-game/home.toml']
assert(identity:find('network_secret',1,true) and identity:find('instance_id',1,true))
assert(sections.firewall.etgame_home.device[1]=='etgame')
assert(sections.firewall.etgame_forward.dest=='wan')
D.apply(cfg)
assert(stored['/etc/codex-game/home.toml']==identity,'Redeployment rotated portal identity')
print('PASS: isolated client/home deployment, owned sections, conflict preflight, scoped routes and stable identity')
