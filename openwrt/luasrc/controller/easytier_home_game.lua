module('luci.controller.easytier_home_game',package.seeall)
function index()
 local fs=require 'nixio.fs'
 if not fs.access('/etc/config/easytier') or not fs.access('/etc/config/easytier_home_game') then return end
 entry({'admin','vpn','easytier','home_game'},template('easytier/home_game'),'跨地区游戏加速',6).leaf=true
 entry({'admin','vpn','easytier','home_game_status'},call('status')).leaf=true
 entry({'admin','vpn','easytier','home_game_action'},call('action')).leaf=true
 entry({'admin','vpn','easytier','home_game_job'},call('job')).leaf=true
end
local function reply(result,code)
 local http=require 'luci.http'; if code then http.status(code) end
 http.header('Cache-Control','no-store'); http.prepare_content('application/json'); http.write_json(result)
end
function status()
 local ok,result=pcall(function() return require('luci.model.easytier_home_game').status() end)
 reply(ok and result or {ok=false,error=tostring(result)},ok and 200 or 500)
end
function job()
 local http=require 'luci.http'; local fs=require 'nixio.fs'
 local id=http.formvalue('id') or ''
 if not id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') then reply({ok=false,error='Invalid job'},400); return end
 local path='/tmp/et-game-jobs/'..id..'.json'
 local source=fs.readfile(path)
 if not source then reply({ok=true,done=false}); return end
 local C=dofile('/usr/libexec/codex-game/endpoint-common.lua')
 C.run('ubus call service delete '..C.quote(require('luci.jsonc').stringify({name='et-game-verify-'..id})))
 reply({ok=true,done=true,result=require('luci.jsonc').parse(source) or {ok=false,error='Verification process did not return JSON'}})
end
local function verify_job()
 local fs=require 'nixio.fs'; local C=dofile('/usr/libexec/codex-game/endpoint-common.lua')
 local dir='/tmp/et-game-jobs'; fs.mkdir(dir,'700'); fs.chmod(dir,'700')
 for file in fs.dir(dir) do
  local info=fs.stat(dir..'/'..file)
  if file:match('^[%x%-]+%.json%.?n?e?w?$') and info and os.time()-info.mtime>300 then os.remove(dir..'/'..file) end
 end
 local id=C.command('cat /proc/sys/kernel/random/uuid'):match('[%x%-]+')
 assert(id and #id==36,'Could not allocate verification job')
 local path=dir..'/'..id..'.json'
 -- The LuCI ucode bridge can block SIGALRM. A CGI child inherits that mask,
 -- which prevents BusyBox ping timers from running. Start via procd instead.
 local command='umask 077; /usr/sbin/et-game verify >'..C.quote(path..'.new')..'; mv '..C.quote(path..'.new')..' '..C.quote(path)
 local service={name='et-game-verify-'..id,instances={check={command={'/bin/sh','-c',command}}}}
 assert(C.run('ubus call service add '..C.quote(require('luci.jsonc').stringify(service))),'Could not start verification through procd')
 return {ok=true,job=id,message='Verification running in a separate process'}
end
function action()
 local http=require 'luci.http'
 if http.getenv('REQUEST_METHOD')~='POST' then reply({ok=false,error='POST required'},405); return end
 if not require('luci.dispatcher').test_post_security() then return end
 local manager=require 'luci.model.easytier_home_game'
 local op=http.formvalue('operation') or http.formvalue('action'); local allowed={doctor=true,verify=true,plan=true,apply=true,adopt=true,pause=true,resume=true,backup=true,rollback=true}
 local ok,result=pcall(function()
  if op=='verify' then return verify_job() end
  if op=='save' or op=='import-profile' then
   local raw=http.formvalue('payload') or ''; assert(#raw<=16384,'Payload too large')
   local value=assert(require('luci.jsonc').parse(raw),'Invalid JSON payload')
   return op=='save' and manager.save(value) or manager.import_profile(value)
  end
  if op=='export-profile' then
   local path='/tmp/et-game-export-'..require('nixio').getpid()..'.pair.json'
   manager.export_profile(path); local data=assert(require('nixio.fs').readfile(path)); os.remove(path)
   return {download=data}
  end
  assert(allowed[op],'Unknown action'); return manager[op](http.formvalue('backup_id'))
 end)
 -- Lua 5.1 HTTP writes may yield. Do not send the download inside pcall.
 if ok and result.download then
  http.header('Cache-Control','no-store'); http.header('Content-Disposition','attachment; filename="home-game.private.pair.json"')
  http.prepare_content('application/json'); http.write(result.download); return
 end
 reply(ok and result or {ok=false,error=tostring(result)},ok and 200 or 400)
end
