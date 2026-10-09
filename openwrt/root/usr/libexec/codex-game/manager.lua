local json=require 'luci.jsonc'
local M=require 'luci.model.easytier_home_game'
local command=arg[1] or 'status'
local allowed={status=true,doctor=true,verify=true,adopt=true,plan=true,apply=true,backup=true,pause=true,resume=true,rollback=true}
local ok,result=pcall(function()
 if command=='export-profile' then return M.export_profile(arg[2]) end
 if command=='import-profile' then return M.import_profile(arg[2]) end
 if command=='save' then return M.save(assert(json.parse(io.read('*a')),'Invalid JSON input')) end
 assert(allowed[command],'Unknown command'); return M[command](arg[2])
end)
if not ok then print(json.stringify({ok=false,error=tostring(result)})); os.exit(1) end
print(json.stringify(result)); os.exit(result.ok and 0 or 1)
