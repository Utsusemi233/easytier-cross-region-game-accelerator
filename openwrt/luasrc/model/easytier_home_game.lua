local json=require 'luci.jsonc'
local fs=require 'nixio.fs'
local uci=require 'luci.model.uci'
local C=dofile('/usr/libexec/codex-game/endpoint-common.lua')
local M={}
local PACKAGE='easytier_home_game'
local CONFIG='/etc/config/'..PACKAGE
local ROOT='/etc/codex-game'
local RULES='/etc/nftables.d/96-easytier-home-game.nft'
local APPLIED=ROOT..'/panel-applied.json'
local defaults={enabled='0',role='client',mode='adopt',wan='wan',wan6='wan6',game_network='game',game_device='br-game',game_cidr='192.168.50.0/24',game_zone='game',wg_device='wg_game',wg_address='10.147.18.2/24',home_probe='10.147.17.1',portal_cidr='10.147.18.0/24',mtu='1200',fec_data='20',fec_redundant='10',fec_timeout='1',fec_interval='5',fec_port='443',local_port='14432',portal_port='51847',poll_seconds='5',probe_seconds='60',max_rtt='180',max_loss='40',settle_seconds='15',probe_ttl='180',udpspeeder='/usr/libexec/codex-game/udpspeeder',easytier_core='/usr/libexec/codex-game/easytier-core',easytier_cli='/usr/libexec/codex-game/easytier-cli',discovery='zerotier',rpc_port='15888',network_name='home-game'}
local extras={peer_node=true,local_zt=true,peer_zt=true,zt_interface=true,peer_mac=true,home_ipv6=true,wg_private_key=true,home_public_key=true,network_secret=true,allow_high_fec=true}
local secret={wg_private_key=true,network_secret=true}
local files={CONFIG,ROOT..'/endpoint-config.json',ROOT..'/endpoints.json',ROOT..'/home.toml',ROOT..'/game-route-health.sh','/etc/init.d/codex-game-fec','/etc/init.d/codex-game-home',RULES,APPLIED}
local owned_sections={network={'wg_game','etgame_peer'},firewall={'codex_game_fec','etgame_zt','etgame_client','etgame_home','etgame_forward'}}
local function require_ok(ok,message) if not ok then error(message,0) end end
local function exec(cmd) require_ok(C.run(cmd),'A network operation failed; inspect the verification report and project logs') end
local function trim(s) return (s or ''):match('^%s*(.-)%s*$') end
local function integer(s,min,max)
 local n=tonumber(s); return n and n==math.floor(n) and n>=min and n<=max and n
end
local function name(s) return type(s)=='string' and #s<=32 and s:match('^[%w_][%w_.%-]*$') end
local function ipv4(s)
 if type(s)~='string' then return nil end
 local a,b,c,d=s:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
 if not a then return nil end
 local parts={a,b,c,d}; local num=0
 for _,v in ipairs(parts) do if #v>3 or tonumber(v)>255 then return nil end; num=num*256+tonumber(v) end
 return num
end
local function cidr(s)
 if type(s)~='string' then return nil end
 local ip,mask=s:match('^([^/]+)/(%d+)$'); local num=ipv4(ip)
 local bits=integer(mask,0,32); if not num or not bits then return nil end
 return {address=ip,num=num,bits=bits,network=math.floor(num/2^(32-bits))*2^(32-bits)}
end
local function within(s,outer)
 local a,b=cidr(s),cidr(outer)
 return a and b and a.bits>=b.bits and math.floor(a.num/2^(32-b.bits))*2^(32-b.bits)==b.network
end
local function address_number(n)
 local parts={}
 for i=3,0,-1 do parts[#parts+1]=tostring(math.floor(n/2^(8*i))%256) end
 return table.concat(parts,'.')
end
local function canonical_cidr(s)
 local value=cidr(s)
 return value and address_number(value.network)..'/'..value.bits
end
local function ports(s)
 if s=='' or s==nil then return true end
 if type(s)~='string' or #s>160 then return false end
 for part in s:gmatch('[^,]+') do
  local a,b=part:match('^(%d+)%-(%d+)$')
  if a then if not integer(a,1,65535) or not integer(b,1,65535) or tonumber(a)>tonumber(b) then return false end
  elseif not integer(part,1,65535) then return false end
 end
 return s:match('^[%d,%-]+$') and not s:find(',,') and s:sub(1,1)~=',' and s:sub(-1)~=','
end
local function key(s) return type(s)=='string' and #s==44 and s:match('^[A-Za-z0-9+/]+=$') end
local function path(s) return type(s)=='string' and s:match('^/[%w_./%-]+$') and not s:find('%.%.') end
function M.config()
 local cursor=uci.cursor(); local out={}
 for k,v in pairs(defaults) do out[k]=cursor:get(PACKAGE,'main',k) or v end
 for k in pairs(extras) do out[k]=cursor:get(PACKAGE,'main',k) or '' end
 return out
end
function M.rules()
 local out={}; uci.cursor():foreach(PACKAGE,'rule',function(s)
  out[#out+1]={id=s['.name'],label=s.label or s['.name'],enabled=s.enabled or '1',source=s.source or '',destination=s.destination or '',protocol=s.protocol or 'udp',ports=s.ports or ''}
 end); return out
end
function M.validate(cfg,rules)
 require_ok(cfg.role=='home' or cfg.role=='client','Choose home or client role')
 require_ok(cfg.mode=='adopt' or cfg.mode=='managed','Invalid deployment mode')
 require_ok(cfg.enabled=='0' or cfg.enabled=='1','Invalid enable state')
 for _,field in ipairs({'wan','wan6','game_network','game_device','game_zone','wg_device','zt_interface'}) do
  if cfg[field]~='' then require_ok(name(cfg[field]),'Invalid interface/section: '..field) end
 end
 for _,field in ipairs({'wan','wan6','game_network','zt_interface'}) do require_ok(cfg[field]:match('^[%w_]+$'),'Invalid logical interface: '..field) end
 require_ok(cfg.wg_device=='wg_game','First version uses wg_game; other names are not verified')
 require_ok(cidr(cfg.game_cidr) and cidr(cfg.wg_address) and cidr(cfg.portal_cidr),'Invalid IPv4 subnet')
 require_ok(within(cfg.wg_address,cfg.portal_cidr),'WG address must belong to portal subnet')
 require_ok(ipv4(cfg.home_probe),'Invalid home probe IPv4')
 for field,range in pairs({mtu={576,1420},fec_data={1,200},fec_redundant={0,200},fec_timeout={0,100},fec_interval={0,100},fec_port={1,65535},local_port={1024,65535},portal_port={1024,65535},rpc_port={1024,65535},poll_seconds={1,30},probe_seconds={15,120},max_rtt={20,1000},max_loss={0,40},settle_seconds={15,60},probe_ttl={60,300}}) do
  require_ok(integer(cfg[field],range[1],range[2]),'Invalid number: '..field)
 end
 require_ok(tonumber(cfg.fec_data)+tonumber(cfg.fec_redundant)<=255,'FEC block exceeds 255 packets')
 require_ok(tonumber(cfg.probe_ttl)>=tonumber(cfg.probe_seconds)+30,'Probe expiry must exceed interval by at least 30 seconds')
 require_ok(tonumber(cfg.fec_redundant)/tonumber(cfg.fec_data)<=2 or cfg.allow_high_fec=='1','High FEC requires explicit bandwidth acknowledgement')
 for _,field in ipairs({'udpspeeder','easytier_core','easytier_cli'}) do require_ok(path(cfg[field]),'Invalid executable path: '..field) end
 require_ok(cfg.discovery=='zerotier','First version requires authenticated ZeroTier IPv6 discovery')
 require_ok(cfg.peer_node:match('^%x%x%x%x%x%x%x%x%x%x$'),'Peer node must be a ten-digit ZeroTier identity')
 require_ok(ipv4(cfg.local_zt) and ipv4(cfg.peer_zt) and name(cfg.zt_interface),'Complete the ZeroTier addresses and interface')
 require_ok(cfg.peer_mac:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$'),'Invalid peer virtual MAC')
 if cfg.home_ipv6~='' then require_ok(C.ipv6(cfg.home_ipv6),'Invalid fallback home IPv6') end
 if cfg.wg_private_key~='' then require_ok(key(cfg.wg_private_key),'Invalid private key') end
 if cfg.home_public_key~='' then require_ok(key(cfg.home_public_key),'Invalid home public key') end
 require_ok(name(cfg.network_name),'Invalid private EasyTier network name')
 require_ok(#rules<=128,'Maximum 128 additional rules')
 local seen={}
 for _,rule in ipairs(rules) do
  require_ok(name(rule.id) and #rule.label<=100,'Invalid rule identifier or label')
  require_ok(not seen[rule.id],'Duplicate rule identifier: '..rule.id); seen[rule.id]=true
  require_ok(rule.enabled=='0' or rule.enabled=='1','Invalid rule enable state')
  require_ok(cidr(rule.destination),'Rule needs an IPv4 destination/CIDR')
  require_ok(rule.source=='' or within(rule.source,cfg.game_cidr),'Device scope must be within the accelerated network')
  require_ok(rule.protocol=='udp' or rule.protocol=='tcp' or rule.protocol=='both','Invalid rule protocol')
  require_ok(ports(rule.ports),'Invalid destination ports')
 end
 return true
end
local function public_config(cfg)
 local out={}; for k,v in pairs(cfg) do if secret[k] then out[k..'_present']=v~='' else out[k]=v end end
 return out
end
local function add(checks,id,passed,detail,skip)
 checks[#checks+1]={id=id,status=skip and 'skipped' or (passed and 'passed' or 'failed'),detail=detail}
end
local function finish(checks)
 local good=true; for _,item in ipairs(checks) do if item.status=='failed' then good=false end end
 return {ok=good,checked_at=os.time(),checks=checks}
end
local function runtime_ready(state)
 local conf=C.load(C.config_path) or {}; local marker=trim(C.read(C.validated_path))
 local proof=state and state.validation
 return conf.enabled~=false and state and state.applied and state.signature==marker and proof and proof.internet==true and tonumber(proof.verified_at) and os.time()-proof.verified_at>=0 and os.time()-proof.verified_at<=(conf.probe_ttl or 180)
end
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function port_intervals(value)
 local intervals={}
 local function visit(v)
  if type(v)=='number' then intervals[#intervals+1]={v,v}
  elseif type(v)=='table' and v.range then intervals[#intervals+1]={v.range[1],v.range[2]}
  elseif type(v)=='table' and v.set then for _,item in ipairs(v.set) do visit(item) end
  else return false end
  return true
 end
 if type(value)=='string' then
  for part in value:gmatch('[^,]+') do
   local a,b=part:match('^(%d+)%-(%d+)$')
   intervals[#intervals+1]={tonumber(a or part),tonumber(b or a or part)}
  end
 elseif not visit(value) then return nil end
 table.sort(intervals,function(a,b) return a[1]<b[1] end)
 local merged={}
 for _,range in ipairs(intervals) do
  local previous=merged[#merged]
  if previous and range[1]<=previous[2]+1 then previous[2]=math.max(previous[2],range[2])
  else merged[#merged+1]={range[1],range[2]} end
 end
 return merged
end
local function nft_cidr(value)
 if type(value)=='string' then return canonical_cidr(value..'/32') end
 if type(value)=='table' and value.prefix then return canonical_cidr(value.prefix.addr..'/'..value.prefix.len) end
end
local function nft_rule_matches(actual,cfg,rule)
 local found={}; local unexpected=false
 for _,expr in ipairs(actual.expr or {}) do
  if expr.match then
   local m=expr.match; local left=m.left or {}; local slot
   if m.op~='==' and m.op~='in' then unexpected=true
   elseif left.meta and left.meta.key=='iifname' then slot='device'; found[slot]=m.right==cfg.game_device
   elseif left.payload and left.payload.protocol=='ip' and left.payload.field=='saddr' then slot='source'; found[slot]=nft_cidr(m.right)==canonical_cidr(rule.source~='' and rule.source or cfg.game_cidr)
   elseif left.payload and left.payload.protocol=='ip' and left.payload.field=='daddr' then slot='destination'; found[slot]=nft_cidr(m.right)==canonical_cidr(rule.destination)
   elseif left.meta and left.meta.key=='l4proto' then
    slot='protocol'
    if rule.protocol=='both' then
     local protocols=type(m.right)=='table' and m.right.set
     found[slot]=protocols and #protocols==2 and ((protocols[1]=='tcp' and protocols[2]=='udp') or (protocols[1]=='udp' and protocols[2]=='tcp')) or false
    else found[slot]=m.right==rule.protocol end
   elseif left.payload and left.payload.field=='dport' then
    -- nft removes the explicit l4proto test when tcp/udp dport implies it.
    if found.protocol==nil and left.payload.protocol==rule.protocol then found.protocol=true end
    slot='ports'; found[slot]=(left.payload.protocol=='th' or left.payload.protocol==rule.protocol) and equal(port_intervals(m.right),port_intervals(rule.ports))
   else unexpected=true end
  elseif expr.mangle then
   local key=expr.mangle.key or {}; local v=expr.mangle.value or {}; local pair=v['|']
   if key.meta and key.meta.key=='mark' then found.mark=pair and equal(pair[1],{meta={key='mark'}}) and pair[2]==2147483648 or false
   elseif key.ct and key.ct.key=='mark' then found.ctmark=pair and equal(pair[1],{ct={key='mark'}}) and pair[2]==2147483648 or false
   else unexpected=true end
  elseif not expr.counter then unexpected=true end
 end
 return not unexpected and found.device and found.source and found.destination and found.protocol and found.mark and found.ctmark and (rule.ports=='' and found.ports==nil or rule.ports~='' and found.ports==true) and true or false
end
function M.rule_runtime(cfg,rules,applied)
 if cfg.role~='client' then return {supported=false,reason='Rules are managed on the overseas client',items={}} end
 local active=(applied and applied.config) or cfg
 local raw=C.command('nft -j list chain inet fw4 etgame_additional_rules 2>/dev/null')
 local parsed=json.parse(raw); local chain_valid=false; local installed={}; local unexpected_rules=0
 local expected={}; for _,rule in ipairs(rules) do if rule.enabled=='1' then expected[rule.id]=true end end
 for _,item in ipairs(parsed and parsed.nftables or {}) do
  if item.chain then local chain=item.chain; chain_valid=chain.name=='etgame_additional_rules' and chain.type=='filter' and chain.hook=='prerouting' and chain.prio==-151 and chain.policy=='accept' end
  if item.rule then
   local id=type(item.rule.comment)=='string' and item.rule.comment:match('^etgame:([%w_.%-]+)$')
   if not id or not expected[id] or installed[id] then unexpected_rules=unexpected_rules+1 end
   if id then installed[id]=item.rule end
  end
 end
 local policy=false
 for line in C.command('ip -4 rule show'):gmatch('[^\n]+') do
  if line:find('from '..active.game_cidr,1,true) and line:find('fwmark 0x80000000/0x80000000',1,true) and line:find('lookup 2848',1,true) then policy=true end
 end
 local route=C.command('ip -4 route show table 2848')
 local home_route=policy and route:match('default dev wg_game[%s\n]')~=nil
 local saved_applied={}; for _,rule in ipairs(applied and applied.rules or {}) do saved_applied[rule.id]=rule end
 local items={}; local verified=chain_valid and unexpected_rules==0
 for _,rule in ipairs(rules) do
  local actual=installed[rule.id]; local prior=saved_applied[rule.id]
  local loaded=actual and chain_valid and nft_rule_matches(actual,active,rule) or false
  local packets,bytes=0,0
  if actual then for _,expr in ipairs(actual.expr or {}) do if expr.counter then packets=expr.counter.packets or 0; bytes=expr.counter.bytes or 0 end end end
  local state
  if applied and (not prior or not equal(prior,rule) or active.game_device~=cfg.game_device or active.game_cidr~=cfg.game_cidr) then state='pending'
  elseif rule.enabled=='0' then state=actual and 'unexpected' or 'disabled'
  elseif not loaded then state=actual and 'mismatch' or 'missing'
  else state=packets>0 and 'matched' or 'loaded' end
  if rule.enabled=='1' and not loaded or rule.enabled=='0' and actual then verified=false end
  items[#items+1]={id=rule.id,state=state,loaded=loaded,packets=packets,bytes=bytes,handle=actual and actual.handle or json.null}
 end
 return {supported=true,chain_loaded=parsed~=nil,chain_valid=chain_valid,all_loaded=verified,unexpected_rules=unexpected_rules,policy_ready=policy,home_route_ready=home_route,checked_at=os.time(),applied_at=applied and applied.applied_at or json.null,items=items}
end
function M.status()
 local cfg=M.config(); local state=C.load(C.runtime_path) or {}
 local active=C.load(C.config_path) or {}; local applied=C.load(APPLIED)
 local pending=not applied or not equal(applied.config,cfg) or not equal(applied.rules,M.rules())
 local peer=C.command('wg show '..C.quote(cfg.wg_device)..' latest-handshakes'):match('%s(%d+)%s*$')
 local route=trim(C.read('/var/run/codex-game-route.state'))
 local data=tonumber(active.fec_data or cfg.fec_data); local redundant=tonumber(active.fec_redundant or cfg.fec_redundant)
 local total=data+redundant
 return {ok=true,role=active.role or cfg.role,deployed=next(active)~=nil,enabled=active.enabled~=false,pending_apply=pending,route=route,endpoint=state,validated=runtime_ready(state) and true or false,handshake_age=peer and os.time()-tonumber(peer) or json.null,config=public_config(cfg),rules=M.rules(),rule_runtime=M.rule_runtime(cfg,M.rules(),applied),last_verification=C.load('/var/run/et-game-verification.json') or json.null,fec={data=data,redundant=redundant,packet_multiplier=total/data,extra_percent=redundant/data*100,measured_bytes=false},legacy={game_udp=cfg.role=='client' and C.run('uci -q get firewall.game_wg_cn_udp >/dev/null') or false,application_dns=fs.access('/etc/init.d/codex-app-dns') and true or false},compatibility={firmware=trim(C.read('/etc/openwrt_release')),architecture=trim(C.command('uname -m')),firewall=C.run('command -v fw4 >/dev/null') and 'fw4' or 'fw3'},updated_at=os.time()}
end
function M.doctor()
 local cfg,checks=M.config(),{}
 local ok,err=pcall(M.validate,cfg,M.rules()); add(checks,'configuration',ok,ok and 'Validated interface, IPv4 scope, numbers, FEC and known discovery peer' or tostring(err))
 for _,tool in ipairs({'ubus','ip','curl','jsonfilter','zerotier-cli'}) do add(checks,'dependency_'..tool,C.run('command -v '..tool..' >/dev/null'),'Required: '..tool) end
 add(checks,'fec_binary',fs.access(cfg.udpspeeder,'x'),cfg.udpspeeder)
 local wan6=C.interface(cfg.wan6); local count=0
 for _,a in ipairs(wan6['ipv6-address'] or {}) do if C.ipv6(a.address) and (a.preferred or 0)>0 and (a.valid or 0)>0 then count=count+1 end end
 add(checks,'global_ipv6',wan6.up and count>0,'Current preferred global WAN IPv6 addresses: '..count)
 if cfg.role=='client' then
  add(checks,'fw4',C.run('command -v fw4 >/dev/null'),'First-version client requires fw4')
  add(checks,'wireguard',C.run('command -v wg >/dev/null'),'WireGuard tools; kernel support is checked when applying')
  add(checks,'conntrack',C.run('command -v conntrack >/dev/null'),'Clear only connections affected by a route change')
  add(checks,'game_network',C.interface(cfg.game_network).up,'Existing accelerated network must be up')
 else
  add(checks,'fw3',C.run('command -v fw3 >/dev/null') and not C.run('command -v fw4 >/dev/null'),'First-version fresh home deployment requires fw3')
  add(checks,'core_binary',fs.access(cfg.easytier_core,'x'),cfg.easytier_core)
  add(checks,'cli_binary',fs.access(cfg.easytier_cli,'x'),cfg.easytier_cli)
  add(checks,'tun',fs.access('/dev/net/tun'),'Existing TUN support')
 end
 add(checks,'full_reboot',false,'A real router reboot must be tested separately',true)
 add(checks,'isp_prefix_renewal',false,'An actual ISP prefix replacement must be tested separately',true)
 return finish(checks)
end
function M.verify()
 local cfg,checks=M.config(),{}
 C.log('Verification started for '..cfg.role)
 if cfg.role=='client' then
  local state=C.load(C.runtime_path) or {}; add(checks,'current_validation',runtime_ready(state),'Current signature, verified Internet and non-expired proof')
  local source=assert(cidr(cfg.wg_address)).address
  C.log('Verification: tunnel probe')
  local text=C.command('ping -I '..C.quote(source)..' -c 5 -W 1 -s 128 '..C.quote(cfg.home_probe))
  local loss=tonumber(text:match('(%d+)%% packet loss')); local average=tonumber(text:match('=%s*[%d%.]+/([%d%.]+)/'))
  add(checks,'tunnel',loss and average and loss<=tonumber(cfg.max_loss) and average<=tonumber(cfg.max_rtt),{loss_percent=loss or json.null,average_ms=average or json.null,source=source,target=cfg.home_probe})
  C.log('Verification: home HTTPS probe')
  local answer=json.parse(C.command('curl -4 --noproxy '..C.quote('*')..' --interface '..C.quote(source)..' --resolve dns.alidns.com:443:223.5.5.5 --connect-timeout 3 --max-time 6 -fsS '..C.quote('https://dns.alidns.com/resolve?name=www.bilibili.com&type=A')))
  add(checks,'home_internet',answer and answer.Status==0 and type(answer.Answer)=='table' and #answer.Answer>0,'HTTPS DNS request explicitly bound to WG diagnostic source')
  C.log('Verification: local HTTPS probe')
  local code=tonumber(C.command('curl -4 --noproxy '..C.quote('*')..' --connect-timeout 3 --max-time 6 -sS -I -o /dev/null -w '..C.quote('%{http_code}')..' https://www.baidu.com/'))
  add(checks,'local_internet',code and code>=200 and code<500,'Separate unmarked local HTTPS request')
  local cursor=uci.cursor(); local preserved=true
  for _,field in ipairs({'ra','dhcpv6','ndp'}) do if cursor:get('dhcp',cfg.game_network,field)~='relay' then preserved=false end end
  add(checks,'ipv6_relay',preserved,'Check existing accelerated network RA/DHCPv6/NDP relay; other setups require their own acceptance')
  add(checks,'active_route',trim(C.read('/var/run/codex-game-route.state'))=='home','Current selected-route mode')
  local runtime=M.rule_runtime(cfg,M.rules(),C.load(APPLIED))
  add(checks,'additional_rules',runtime.chain_valid and runtime.all_loaded,'Actual installed matches and disabled-rule removal')
  add(checks,'routing_policy',runtime.policy_ready and runtime.home_route_ready,'Actual marked IPv4 policy and WireGuard default route')
  C.log('Verification: firewall syntax')
  add(checks,'rule_syntax',C.run('fw4 check'),'Check actual fw4 syntax')
 else
  add(checks,'core_running',trim(C.command('pidof easytier-core'))~='','EasyTier core process; not sufficient on its own')
  local iface=C.interface(cfg.wan); local dev=iface.l3_device or ''
  add(checks,'home_nat',name(dev) and C.run('iptables -t nat -C POSTROUTING -s '..C.quote(cfg.portal_cidr)..' -o '..C.quote(dev)..' -m comment --comment codex-game-wg-home -j MASQUERADE'),'Project portal subnet NAT on actual WAN device')
  add(checks,'fec_listeners',trim(C.command('pidof udpspeeder'))~='','IPv6 FEC listener processes')
  add(checks,'client_traffic',false,'Run the client verify and the real game to prove forwarding',true)
 end
 add(checks,'normal_ssid_and_game',false,'Requires the user or an attached device to test the actual normal SSID and game scene',true)
 add(checks,'fec_bandwidth',false,'Packet multiplier is an estimate; a same-window byte measurement is separate',true)
 local result=finish(checks); C.atomic('/var/run/et-game-verification.json',result); return result
end
function M.backup()
 exec('mkdir -p '..C.quote(ROOT..'/backups'))
 local id='panel-'..os.date('%Y%m%d-%H%M%S')..'-'..require('nixio').getpid(); local dir=ROOT..'/backups/'..id
 exec('mkdir -m 700 '..C.quote(dir)); local manifest={id=id,created_at=os.time(),files={}}
 for index,file in ipairs(files) do
  local existed=fs.access(file) and true or false; local entry={path=file,stored=tostring(index),existed=existed}
  if existed then exec('cp -p '..C.quote(file)..' '..C.quote(dir..'/'..index)) end
  manifest.files[#manifest.files+1]=entry
 end
 C.atomic(dir..'/manifest.json',manifest); fs.chmod(dir..'/manifest.json','600')
 local cursor=uci.cursor(); manifest.uci={}
 for package,ids in pairs(owned_sections) do
  manifest.uci[package]={}
  for _,id in ipairs(ids) do local previous=cursor:get_all(package,id); manifest.uci[package][id]={existed=previous~=nil,owned=previous and previous.etgame_owner=='1' or false,section=previous} end
 end
 C.atomic(dir..'/manifest.json',manifest)
 fs.chmod(dir..'/manifest.json','600')
 C.atomic(ROOT..'/panel-backup-path',dir..'\n')
 return {ok=true,id=id,path=dir}
end
function M.save(input)
 require_ok(type(input)=='table' and type(input.config)=='table' and type(input.rules)=='table','Expected config and rules')
 local cfg=M.config(); for k,v in pairs(input.config) do
  require_ok(defaults[k]~=nil or extras[k],'Unknown field: '..tostring(k))
  require_ok(type(v)=='string' and #v<=512,'Invalid field data'); if not secret[k] then cfg[k]=v end
 end
 local current=C.load(C.config_path)
 require_ok(not current or cfg.role==current.role,'Changing an active router role requires separate deployment')
 M.validate(cfg,input.rules); local backup=M.backup(); local cursor=uci.cursor()
 for k,v in pairs(cfg) do cursor:set(PACKAGE,'main',k,v) end
 local remove={}; cursor:foreach(PACKAGE,'rule',function(s) remove[#remove+1]=s['.name'] end)
 for _,id in ipairs(remove) do cursor:delete(PACKAGE,id) end
 for _,rule in ipairs(input.rules) do cursor:section(PACKAGE,'rule',rule.id,{label=rule.label,enabled=rule.enabled,source=rule.source,destination=rule.destination,protocol=rule.protocol,ports=rule.ports}) end
 cursor:commit(PACKAGE)
 fs.chmod(CONFIG,'600')
 return {ok=true,backup=backup.id,message='Saved. Run plan and apply to change the running service.'}
end
function M.adopt()
 local existing=assert(C.load(C.config_path),'No existing endpoint module to adopt'); local cfg=M.config()
 cfg.role=existing.role; cfg.mode='adopt'; cfg.enabled=existing.enabled==false and '0' or '1'
 cfg.wan=existing.wan4 or 'wan'; cfg.wan6=existing.wan6 or 'wan6'; cfg.peer_node=existing.peer_node or ''
 cfg.local_zt=cfg.role=='home' and existing.home_zt or existing.my_zt
 cfg.peer_zt=cfg.role=='home' and existing.my_zt or existing.home_zt
 cfg.zt_interface=existing.zt_interface or ''; cfg.peer_mac=existing.peer_mac or ''
 local file=cfg.role=='home' and '/etc/init.d/codex-game-home' or '/etc/init.d/codex-game-fec'
 local source=C.read(file) or ''; local data,redundant=source:match('%-f%s+(%d+):(%d+)')
 if data then cfg.fec_data=data; cfg.fec_redundant=redundant end
 cfg.allow_high_fec=tonumber(cfg.fec_redundant)/tonumber(cfg.fec_data)>2 and '1' or '0'
 local state=C.load(C.runtime_path) or {}; cfg.home_ipv6=state.home and state.home.address or ''
 M.validate(cfg,M.rules()); local backup=M.backup(); local cursor=uci.cursor()
 for k,v in pairs(cfg) do cursor:set(PACKAGE,'main',k,v) end; cursor:commit(PACKAGE); fs.chmod(CONFIG,'600')
 return {ok=true,backup=backup.id,message='Existing tunnel, keys, rules, IPv6 and FEC were adopted without restarting the tunnel.'}
end
function M.plan()
 local cfg=M.config(); M.validate(cfg,M.rules())
 return {ok=true,role=cfg.role,mode=cfg.mode,network=cfg.game_network,device=cfg.game_device,source=cfg.game_cidr,additional_rules=#M.rules(),fec=cfg.fec_data..':'..cfg.fec_redundant,packet_multiplier=1+tonumber(cfg.fec_redundant)/tonumber(cfg.fec_data),changes={"Own endpoint configuration and detection services","Own FEC parameters; both ends must match","Own additional IPv4 rules, with existing rules preserved"},preserved={'Existing SSIDs and IPv6 settings','Existing application DNS and destinations','Existing WireGuard/EasyTier identity in adopt mode'},backup_required=true}
end
local function endpoint_config(cfg)
 local source=assert(cidr(cfg.wg_address)).address
 return {role=cfg.role,enabled=cfg.enabled=='1',wan4=cfg.wan,wan6=cfg.wan6,poll_seconds=tonumber(cfg.poll_seconds),probe_seconds=tonumber(cfg.probe_seconds),probe_ttl=tonumber(cfg.probe_ttl),settle_seconds=tonumber(cfg.settle_seconds),max_rtt=tonumber(cfg.max_rtt),max_loss=tonumber(cfg.max_loss),wg_source=source,home_probe=cfg.home_probe,game_cidr=cfg.game_cidr,game_device=cfg.game_device,portal_cidr=cfg.portal_cidr,fec_port=tonumber(cfg.fec_port),local_port=tonumber(cfg.local_port),portal_port=tonumber(cfg.portal_port),fec_data=tonumber(cfg.fec_data),fec_redundant=tonumber(cfg.fec_redundant),fec_timeout=tonumber(cfg.fec_timeout),fec_interval=tonumber(cfg.fec_interval),home_ipv6=cfg.home_ipv6,peer_node=cfg.peer_node,zt_interface=cfg.zt_interface,peer_mac=cfg.peer_mac,my_zt=cfg.role=='client' and cfg.local_zt or cfg.peer_zt,home_zt=cfg.role=='home' and cfg.local_zt or cfg.peer_zt}
end
local function write_rules(cfg,rules)
 local lines={'chain etgame_additional_rules {',' type filter hook prerouting priority -151; policy accept;'}
 for _,rule in ipairs(rules) do if rule.enabled=='1' then
  local proto=rule.protocol=='both' and 'meta l4proto { tcp, udp }' or 'meta l4proto '..rule.protocol
  local port=rule.ports~='' and ' th dport { '..rule.ports:gsub(',',', ')..' }' or ''
  lines[#lines+1]=' iifname "'..cfg.game_device..'" ip saddr '..canonical_cidr(rule.source~='' and rule.source or cfg.game_cidr)..' ip daddr '..canonical_cidr(rule.destination)..' '..proto..port..' counter meta mark set meta mark | 0x80000000 ct mark set ct mark | 0x80000000 comment "etgame:'..rule.id..'"'
 end end
 lines[#lines+1]='}'
 local mss=tonumber(cfg.mtu)-40
 lines[#lines+1]='chain etgame_tcp_mss { type filter hook forward priority -149; policy accept;'
 for _,direction in ipairs({'iifname','oifname'}) do lines[#lines+1]=' meta nfproto ipv4 '..direction..' "wg_game" tcp flags & (fin | syn | rst) == syn tcp option maxseg size > '..mss..' counter tcp option maxseg size set '..mss end
 lines[#lines+1]='}'
 C.atomic(RULES,table.concat(lines,'\n')..'\n')
 require_ok(C.run('fw4 check'),'Generated firewall syntax failed; restore the recorded backup')
 local ok=C.run('fw4 reload')
 require_ok(ok or (not fs.access('/etc/firewall.include') and C.run('nft list chain inet fw4 etgame_additional_rules >/dev/null')),'Firewall reload failed')
 local loaded=M.rule_runtime(cfg,rules)
 require_ok(loaded.chain_valid and loaded.all_loaded,'Runtime rule check failed; restore the recorded backup')
end
local function tune_adopted_fec(cfg)
 local file=cfg.role=='home' and '/etc/init.d/codex-game-home' or '/etc/init.d/codex-game-fec'
 local source=assert(C.read(file),'Existing FEC service missing')
 local changed
 source,changed=source:gsub('%-f%s+%d+:%d+','-f '..cfg.fec_data..':'..cfg.fec_redundant)
 require_ok(changed>0,'Existing FEC init is not a supported prototype; do not overwrite it')
 source=source:gsub('%-%-timeout%s+%d+','--timeout '..cfg.fec_timeout):gsub('%-i%s+%d+','-i '..cfg.fec_interval)
 C.atomic(file,source); fs.chmod(file,'755')
 exec('sh -n '..C.quote(file)); exec(file..' reload')
end
function M.apply()
 local cfg=M.config(); M.validate(cfg,M.rules()); require_ok(M.doctor().ok,'Doctor has failed checks; fix them before applying')
 local old=C.load(C.config_path)
 require_ok(cfg.mode~='managed' or not old or old.manager_owned,'Existing prototype must be adopted, not overwritten by a new deployment')
 require_ok(cfg.mode~='adopt' or (cfg.fec_port=='443' and cfg.local_port=='14432' and cfg.portal_port=='51847'),'Adopt mode preserves the tested ports; migrate separately to change ports')
 if cfg.mode=='adopt' then
  for _,field in ipairs({'game_cidr','game_device','portal_cidr','home_probe'}) do
   require_ok(cfg[field]==(old and old[field] or defaults[field]),'Adopt mode preserves active addressing: '..field..'; migrate separately')
  end
  if cfg.role=='client' then require_ok(cfg.wg_address==(uci.cursor():get('network','wg_game','addresses') or {defaults.wg_address})[1],'Adopt mode preserves the active WireGuard address') end
 else
  require('luci.model.easytier_home_game_deploy').preflight(cfg,old)
 end
 local backup=M.backup()
 local succeeded,result=pcall(function()
 exec('/etc/init.d/codex-game-endpoints stop')
 local endpoint=endpoint_config(cfg); endpoint.manager_owned=cfg.mode=='managed' or (old and old.manager_owned) or false
 C.atomic(C.config_path,endpoint); fs.chmod(C.config_path,'600')
 if cfg.role=='client' then
  os.remove(C.validated_path); exec('/etc/codex-game/game-route-health.sh --force-direct')
  local state=C.load(C.runtime_path)
  if state then state.applied=false; state.updated_at=os.time(); state.validation=nil; C.atomic(C.runtime_path,state) end
 end
 if cfg.mode=='adopt' then
  tune_adopted_fec(cfg)
 else
  require('luci.model.easytier_home_game_deploy').apply(cfg)
 end
 if cfg.role=='client' then write_rules(cfg,M.rules()) end
 if cfg.role=='client' and cfg.mode=='adopt' then
  local file=ROOT..'/game-route-health.sh'; local source=assert(C.read(file))
  source=source:gsub('endpoint_ready%(%) { [^\n]* }','endpoint_ready() { lua /usr/libexec/codex-game/endpoint-common.lua ready; }')
  source=source:gsub('%[ %-e /var/run/codex%-game%-endpoint%-validated %]','lua /usr/libexec/codex-game/endpoint-common.lua ready')
  C.atomic(file,source); fs.chmod(file,'755'); exec('sh -n '..C.quote(file))
  exec('/etc/init.d/codex-game-route restart')
 end
 exec('/etc/init.d/codex-game-endpoints enable'); exec('/etc/init.d/codex-game-endpoints restart')
 C.atomic(APPLIED,{config=cfg,rules=M.rules(),applied_at=os.time()})
 return {ok=true,backup=backup.id,rules_loaded=cfg.role=='client' and true or nil,message='Applied and runtime rules checked. Home routing still requires a fresh tunnel and Internet verification.'}
 end)
 if not succeeded then
  local restored,restore_error=pcall(M.rollback,backup.id)
  error(tostring(result)..'; backup '..backup.id..(restored and ' restored automatically' or ('; restore failed: '..tostring(restore_error))),0)
 end
 return result
end
function M.pause()
 local cfg=M.config(); require_ok(C.load(C.config_path),'No deployed endpoint module')
 local cursor=uci.cursor(); cursor:set(PACKAGE,'main','enabled','0'); cursor:commit(PACKAGE)
 local conf=C.config(); conf.enabled=false; C.atomic(C.config_path,conf); os.remove(C.validated_path)
 local applied=C.load(APPLIED); if applied and applied.config then applied.config.enabled='0'; C.atomic(APPLIED,applied) end
 if cfg.role=='client' then exec('/etc/codex-game/game-route-health.sh --force-direct') end
 C.atomic(C.wake_path,'pause\n'); return {ok=true,message=cfg.role=='client' and 'Selected traffic uses the local exit; automatic home recovery is paused.' or 'Home FEC entries are paused; the client should fall back to its local exit.'}
end
function M.resume()
 local cursor=uci.cursor(); cursor:set(PACKAGE,'main','enabled','1'); cursor:commit(PACKAGE)
 local conf=C.config(); conf.enabled=true; C.atomic(C.config_path,conf)
 local applied=C.load(APPLIED); if applied and applied.config then applied.config.enabled='1'; C.atomic(APPLIED,applied) end
 exec('/etc/init.d/codex-game-endpoints restart'); return {ok=true,message='Automatic verification resumed; home routing waits for a successful fresh proof.'}
end
function M.rollback(id)
 require_ok(type(id)=='string' and id:match('^panel%-%d+%-%d+%-%d+$'),'Invalid backup ID')
 local dir=ROOT..'/backups/'..id; local manifest=assert(C.load(dir..'/manifest.json'),'Backup not found')
 local allowed={}; for _,file in ipairs(files) do allowed[file]=true end
 local cursor=uci.cursor(); local removed_wg=false
 local was_first_home=false
 for _,entry in ipairs(manifest.files or {}) do
  if entry.path==C.config_path and not entry.existed then
   local current=C.load(C.config_path)
   was_first_home=current and current.manager_owned and current.role=='home'
  end
 end
 if was_first_home then C.run('/etc/codex-game-home-nat.sh --remove') end
 for package,ids in pairs(owned_sections) do
  for _,name in ipairs(ids) do
   local before=manifest.uci and manifest.uci[package] and manifest.uci[package][name]
   local current=cursor:get_all(package,name)
   if before and before.owned then
    local values={}; for k,v in pairs(before.section) do if k:sub(1,1)~='.' then values[k]=v end end
    cursor:delete(package,name); cursor:section(package,before.section['.type'],name,values)
   elseif before and not before.existed and current and current.etgame_owner=='1' then
    if package=='network' and name=='wg_game' then C.run('ifdown wg_game'); removed_wg=true end
    cursor:delete(package,name)
   end
  end
  cursor:commit(package)
 end
 for _,entry in ipairs(manifest.files or {}) do
  require_ok(allowed[entry.path] and tostring(entry.stored):match('^%d+$'),'Unexpected backup target')
  if entry.existed then exec('cp -p '..C.quote(dir..'/'..entry.stored)..' '..C.quote(entry.path)) else os.remove(entry.path) end
 end
 if C.run('command -v fw4 >/dev/null') then C.run('fw4 reload') else C.run('/etc/init.d/firewall reload') end
 if not C.load(C.config_path) then
  for _,svc in ipairs({'codex-game-endpoints','codex-game-fec','codex-game-home','codex-game-route'}) do C.run('/etc/init.d/'..svc..' stop'); C.run('/etc/init.d/'..svc..' disable') end
  if removed_wg then for _,priority in ipairs({11020,11030}) do C.run('ip rule del priority '..priority) end end
  return {ok=true,message='First deployment removed; only project-owned sections and services were restored.'}
 end
 local role=(C.load(C.config_path) or {}).role
 if role=='client' then C.run('/etc/init.d/codex-game-fec reload'); C.run('/etc/init.d/codex-game-route restart')
 elseif role=='home' then C.run('/etc/init.d/codex-game-home reload') end
 C.run('/etc/init.d/codex-game-endpoints restart')
 return {ok=true,message='Project files restored. Global firewall/network configuration was not overwritten. Verify before acceptance.'}
end
function M.export_profile(destination)
 local cfg=M.config(); require_ok(cfg.role=='home','Export from the home gateway')
 require_ok(path(destination) and destination:match('%.pair%.json$'),'Use an absolute private .pair.json path')
 local portal=C.command(C.quote(cfg.easytier_cli)..' --rpc-portal 127.0.0.1:'..cfg.rpc_port..' vpn-portal')
 local private=trim(portal:match('PrivateKey%s*=%s*([^\r\n]+)')); local public=trim(portal:match('PublicKey%s*=%s*([^\r\n]+)'))
 require_ok(key(private) and key(public),'Could not read the private local WireGuard portal; do not use an unverified profile')
 local profile={version=1,home_public_key=public,wg_private_key=private,home_probe=cfg.home_probe,portal_cidr=cfg.portal_cidr,fec_data=cfg.fec_data,fec_redundant=cfg.fec_redundant,fec_timeout=cfg.fec_timeout,fec_interval=cfg.fec_interval,fec_port=cfg.fec_port,portal_port=cfg.portal_port,mtu=cfg.mtu,warning='Private pairing file. Never publish or paste into logs.'}
 C.atomic(destination,profile); fs.chmod(destination,'600'); return {ok=true,path=destination,private=true}
end
function M.import_profile(input)
 local cfg=M.config(); require_ok(cfg.role=='client','Import on the overseas client')
 local profile=type(input)=='table' and input or C.load(input)
 require_ok(profile and profile.version==1 and key(profile.wg_private_key) and key(profile.home_public_key),'Invalid private pairing profile')
 for _,field in ipairs({'wg_private_key','home_public_key','home_probe','portal_cidr','fec_data','fec_redundant','fec_timeout','fec_interval','fec_port','portal_port','mtu'}) do
  require_ok(type(profile[field])=='string','Invalid profile field: '..field); cfg[field]=profile[field]
 end
 cfg.allow_high_fec=tonumber(cfg.fec_redundant)/tonumber(cfg.fec_data)>2 and '1' or '0'
 M.validate(cfg,M.rules()); local backup=M.backup(); local cursor=uci.cursor()
 for k,v in pairs(cfg) do cursor:set(PACKAGE,'main',k,v) end; cursor:commit(PACKAGE); fs.chmod(CONFIG,'600')
 return {ok=true,backup=backup.id,message='Private profile imported without printing keys. Check the client IP and plan before applying.'}
end
M._test={ipv4=ipv4,cidr=cidr,canonical_cidr=canonical_cidr,within=within,ports=ports,runtime_ready=runtime_ready,common=C,equal=equal,nft_rule_matches=nft_rule_matches,port_intervals=port_intervals}
local locked=false
local function with_lock(fn,...)
 if locked then return fn(...) end
 local folder='/var/lock/et-game-manager'
 if not fs.mkdir(folder,'700') then
  local pid=trim(C.read(folder..'/pid'))
  if pid:match('^%d+$') and not C.run('kill -0 '..pid) then os.remove(folder..'/pid'); fs.rmdir(folder) end
  require_ok(fs.mkdir(folder,'700'),'Another project operation is running; wait for its result')
 end
 C.atomic(folder..'/pid',tostring(require('nixio').getpid()))
 locked=true; local ok,result=pcall(fn,...); locked=false
 os.remove(folder..'/pid'); fs.rmdir(folder)
 if not ok then error(result,0) end
 return result
end
for _,op in ipairs({'save','adopt','apply','backup','pause','resume','rollback','export_profile','import_profile'}) do
 local original=M[op]; M[op]=function(...) return with_lock(original,...) end
end
return M
