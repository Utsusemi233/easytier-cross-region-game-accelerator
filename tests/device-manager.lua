local M=require('luci.model.easytier_home_game')
local T=M._test
assert(T.equal({enabled='1',rules={}}, {enabled='1',rules={}}))
assert(not T.equal({enabled='1',fec='2:30'}, {enabled='1',fec='20:10'}))
assert(not T.equal({rules={{destination='203.0.113.1/32'}}}, {rules={}}))
local temporary='/tmp/et-game-atomic-test-'..require('nixio').getpid()
T.common.atomic(temporary,{value='atomic-write-check'})
assert(T.common.load(temporary).value=='atomic-write-check','Atomic state storage failed')
os.remove(temporary)
assert(T.ipv4('192.0.2.1') and not T.ipv4('192.0.2.999'))
assert(not T.ipv4('192.0.2.1;reboot'))
assert(T.within('192.168.50.10/32','192.168.50.0/24'))
assert(not T.within('192.168.1.1/32','192.168.50.0/24'))
assert(not T.within('0.0.0.0/0','192.168.50.0/24'))
assert(T.ports('443,30000-30100') and T.ports(''))
assert(T.canonical_cidr('203.0.113.129/24')=='203.0.113.0/24')
local nft_single={expr={
 {match={op='==',left={meta={key='iifname'}},right='br-game'}},
 {match={op='==',left={payload={protocol='ip',field='saddr'}},right='192.0.2.107'}},
 {match={op='==',left={payload={protocol='ip',field='daddr'}},right='203.0.113.42'}},
 {match={op='==',left={payload={protocol='tcp',field='dport'}},right=443}},
 {counter={packets=0,bytes=0}},
 {mangle={key={meta={key='mark'}},value={['|']={{meta={key='mark'}},2147483648}}}},
 {mangle={key={ct={key='mark'}},value={['|']={{ct={key='mark'}},2147483648}}}}
}}
local nft_rule={source='192.0.2.107/32',destination='203.0.113.42/32',protocol='tcp',ports='443'}
local nft_config={game_device='br-game',game_cidr='192.0.2.0/24'}
assert(T.nft_rule_matches(nft_single,nft_config,nft_rule),'nft optimized single-port expression was rejected')
nft_rule.ports='80'; assert(not T.nft_rule_matches(nft_single,nft_config,nft_rule),'Wrong installed port was accepted')
nft_rule.ports='443'; nft_rule.id='fixture'; nft_rule.enabled='1'; nft_single.comment='etgame:fixture'
local actual_command=T.common.command
local snapshot={nftables={{chain={name='etgame_additional_rules',type='filter',hook='prerouting',prio=-151,policy='accept'}},{rule=nft_single}}}
nft_config.role='client'
T.common.command=function(command)
 if command:match('^nft ') then return require('luci.jsonc').stringify(snapshot) end
 if command:match('^ip %-4 rule') then return '11030: from 192.0.2.0/24 fwmark 0x80000000/0x80000000 lookup 2848\n' end
 return 'default dev wg_game scope link\n'
end
assert(M.rule_runtime(nft_config,{nft_rule}).all_loaded,'Valid installed rule rejected')
local duplicate={rule=require('luci.jsonc').parse(require('luci.jsonc').stringify(nft_single))}; snapshot.nftables[#snapshot.nftables+1]=duplicate
assert(not M.rule_runtime(nft_config,{nft_rule}).all_loaded,'Duplicate actual rule accepted')
snapshot.nftables[#snapshot.nftables]=nil
assert(not M.rule_runtime(nft_config,{}).all_loaded,'Deleted orphan still installed but reported clean')
assert(M.rule_runtime(nft_config,{}).unexpected_rules==1,'Orphan count omitted')
T.common.command=actual_command
for _,bad in ipairs({'0','65536','443,,80','300-200','443;reboot',',443','443,'}) do assert(not T.ports(bad),bad) end
local C=T.common; local signature='fixture-signature'
C.load=function() return {enabled=true,probe_ttl=180} end
C.read=function() return signature..'\n' end
local state={applied=true,signature=signature,validation={internet=true,verified_at=os.time()}}
assert(T.runtime_ready(state),'Fresh matching proof was rejected')
state.validation.verified_at=os.time()-181
assert(not T.runtime_ready(state),'Stale proof was accepted')
state.validation.verified_at=os.time()+10
assert(not T.runtime_ready(state),'Future proof was accepted')
state.validation.verified_at=os.time(); state.signature='different'
assert(not T.runtime_ready(state),'Mismatched proof marker was accepted')
state.signature=signature; state.validation.internet=false
assert(not T.runtime_ready(state),'Tunnel-only proof was accepted')
state.validation.internet=true; C.load=function() return {enabled=false} end
assert(not T.runtime_ready(state),'Paused routing was accepted')
C.config=function() return {enabled=true,probe_ttl=180} end
C.load=function() return state end
assert(C.ready(),'Production health gate rejected fresh proof')
state.validation.verified_at=os.time()-181
assert(not C.ready(),'Production health gate accepted expired proof')
state.validation.verified_at=os.time(); state.signature='other'
assert(not C.ready(),'Production health gate accepted mismatched marker')
print('PASS: device CIDR scope, port injection/range and fresh/current/Internet/paused proof gates')
