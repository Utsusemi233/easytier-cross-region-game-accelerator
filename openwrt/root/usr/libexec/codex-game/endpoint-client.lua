local n=require 'nixio'
local json=require 'luci.jsonc'
local M=dofile('/usr/libexec/codex-game/endpoint-common.lua')
local conf=M.config()
local state=M.load(M.runtime_path) or M.load(M.saved_path)
local validated,failures,last_probe,last_log=nil,0,0,''
local failed_address,failed_at=nil,0
local function quarantine(reason)
 os.remove(M.validated_path)
 M.run('/etc/codex-game/game-route-health.sh --force-direct')
 if last_log~=reason then M.log(reason); last_log=reason end
end
local function verify()
 local source=conf.wg_source or '10.147.18.2'; local target=conf.home_probe or '10.147.17.1'
 assert(source:match('^%d+%.%d+%.%d+%.%d+$') and target:match('^%d+%.%d+%.%d+%.%d+$'))
 local ping=M.command('ping -I '..M.quote(source)..' -c 3 -W 1 -s 128 '..M.quote(target))
 local loss=tonumber(ping:match('(%d+)%% packet loss'))
 local average=tonumber(ping:match('=%s*[%d%.]+/([%d%.]+)/'))
 if not loss or loss>(conf.max_loss or 40) or not average or average>(conf.max_rtt or 180) then return nil,'tunnel probe failed' end
 local query='https://dns.alidns.com/resolve?name=www.bilibili.com&type=A'
 local raw=M.command('curl -4 --interface '..M.quote(source)..' --noproxy '..M.quote('*')..' --resolve dns.alidns.com:443:223.5.5.5 --connect-timeout 2 --max-time 4 -fsS '..M.quote(query))
 local answer=json.parse(raw)
 local internet=answer and answer.Status==0 and type(answer.Answer)=='table' and #answer.Answer>0
 if not internet then
  local status=tonumber(M.command('curl -4 --interface '..M.quote(source)..' --noproxy '..M.quote('*')..' --connect-timeout 2 --max-time 4 -sS -I -o /dev/null -w '..M.quote('%{http_code}')..' https://www.baidu.com/'))
  internet=status and status>=200 and status<500
 end
 if not internet then return nil,'home Internet egress probe failed' end
 return {loss=loss,average_ms=average,verified_at=os.time(),internet=true}
end
local function cycle()
 conf=M.config()
 if conf.enabled==false then validated=nil; quarantine('Home routing paused; using local egress'); return end
 M.prime_peer()
 local own=M.snapshot()
 if own.address=='' then validated=nil; quarantine('No preferred global WAN IPv6; using local egress'); return end
 local peers=M.peer_addresses()
 local home=state and state.home and state.home.address or M.ipv6(conf.home_ipv6)
 local found=false
 for _,peer in ipairs(peers) do if peer.address==home then found=true end end
 local settled=not state or os.time()-(state.updated_at or 0)>=(conf.settle_seconds or 15)
 if #peers>0 and settled and (not home or not found or (home==failed_address and os.time()-failed_at<30)) then
  for _,peer in ipairs(peers) do
   if peer.address~=failed_address or os.time()-failed_at>=30 or #peers==1 then home=peer.address; break end
  end
 end
 if not home then quarantine('Authenticated home endpoint discovery unavailable; retrying'); return end
 local remote={address=home,discovered_by='authenticated-zerotier-peer',node=conf.peer_node}
 local signature=M.signature(own,remote)
 if not state or state.signature~=signature then
  local old=state; validated=nil; failures=0
  quarantine('Endpoint or WAN changed; validating before home routing')
  state={version=2,signature=signature,local_state=own,home=remote,updated_at=os.time(),applied=false}
  M.save(state)
  if not old or old.local_state.address~=own.address or old.home.address~=home then
   assert(M.run('/etc/init.d/codex-game-fec reload'),'client FEC refresh failed')
  end
  assert(M.run('/usr/libexec/codex-game/refresh-game-peer.sh'),'WireGuard reauthentication failed')
  state.applied=true; M.atomic(M.runtime_path,state)
  M.log('FEC endpoints synchronized from authenticated node: '..own.address..' -> '..home)
 end
 if not state.applied then
  assert(M.run('/etc/init.d/codex-game-fec reload'),'pending FEC refresh failed')
  assert(M.run('/usr/libexec/codex-game/refresh-game-peer.sh'),'pending WireGuard reauthentication failed')
  state.applied=true; M.atomic(M.runtime_path,state)
 end
 local direct=(M.read('/var/run/codex-game-route.state') or ''):match('direct')
 if not validated or direct or os.time()-last_probe>=(conf.probe_seconds or 60) then
  local proof,reason=verify(); last_probe=os.time()
  if proof then
   failures=0; failed_address=nil; local first=validated~=state.signature; validated=state.signature
   state.validation=proof; M.atomic(M.runtime_path,state); M.atomic(M.validated_path,state.signature..'\n')
   if first or direct then
    assert(M.run('/etc/codex-game/game-route-health.sh --validated-home'),'validated home routing failed')
    M.log('Endpoint validated: authenticated tunnel plus home Internet egress; RTT='..proof.average_ms..'ms'); last_log=''
   end
  else
   failures=failures+1
   if not validated or direct or failures>=2 then
    validated=nil
    if os.time()-(state.updated_at or 0)>=(conf.settle_seconds or 15) then failed_address=home; failed_at=os.time() end
    quarantine(reason..'; allowing handshake to settle before candidate retry')
   end
  end
 end
end
os.remove(M.validated_path)
M.log('Client endpoint monitor started: independent authenticated peer discovery, no overlay data response required')
while true do
 local started=os.time()
 local ok,err=pcall(cycle); if not ok then validated=nil; quarantine('Endpoint monitor error: '..tostring(err)) end
 for i=1,conf.poll_seconds do
  if M.read(M.wake_path) then os.remove(M.wake_path); break end
  if os.time()-started>=conf.poll_seconds then break end
  n.nanosleep(1,0)
 end
end
