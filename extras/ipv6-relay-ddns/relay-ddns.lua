-- Dedicated IPv6 relay DDNS. DNS readback is not a proxy connectivity test.
local json = require('luci.jsonc')
local nixio = require('nixio')
local fs = require('nixio.fs')
local M = {}
local config_path = '/etc/codex-relay-ddns/config.private.json'
local runtime = '/var/run/codex-relay-ddns'

local function quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function read(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a'); f:close(); return data
end

local function run(command)
    local p = io.popen(command .. ' 2>/dev/null')
    if not p then return '' end
    local data = p:read('*a'); p:close(); return data or ''
end

local function write_private(path, data)
    local tmp = path .. '.tmp'
    local f = assert(io.open(tmp, 'wb'))
    f:write(data); f:close()
    assert(fs.chmod(tmp, '600'))
    assert(fs.rename(tmp, path))
end

function M.canonical(address)
    if type(address) ~= 'string' or not address:match('^[%x:]+$') then return nil end
    local function parts(s)
        local result = {}
        for word in s:gmatch('[^:]+') do
            if #word > 4 then return nil end
            result[#result + 1] = string.format('%04x', tonumber(word, 16))
        end
        return result
    end
    local left, right = address:match('^(.-)::(.-)$')
    local words
    if left then
        if right:find('::', 1, true) or left:find('::', 1, true) then return nil end
        local a, b = parts(left), parts(right)
        if not a or not b or #a + #b >= 8 then return nil end
        words = a
        for _ = 1, 8 - #a - #b do words[#words + 1] = '0000' end
        for _, word in ipairs(b) do words[#words + 1] = word end
    else
        words = parts(address)
        if not words or #words ~= 8 or address:match('^:') or address:match(':$') then return nil end
    end
    return table.concat(words, ':')
end

function M.parse_addresses(output)
    local stable, temporary = {}, {}
    for line in output:gmatch('[^\r\n]+') do
        local ip = line:match('inet6%s+([%x:]+)/%d+')
        if ip and M.canonical(ip) and ip:match('^[23]')
            and not line:match('deprecated') and not line:match('tentative')
            and not line:match('dadfailed') and not line:match('preferred_lft%s+0sec')
            and not line:match('valid_lft%s+0sec') then
            local list = line:match('temporary') and temporary or stable
            list[#list + 1] = ip:lower()
        end
    end
    return stable[1] or temporary[1]
end

function M.parse_response(body, address)
    -- Keep the blank IPv4 line in an AAAA-only account response.
    local lines = {}
    for line in ((body or ''):gsub('\r', '') .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
    return lines[1] == 'OK' and M.canonical(lines[3]) ~= nil
        and M.canonical(lines[3]) == M.canonical(address)
end

local function config()
    local c = assert(json.parse(read(config_path) or ''), 'Missing DDNS configuration')
    assert(c.provider == 'duckdns', 'Unsupported DDNS provider')
    assert(type(c.subdomain) == 'string' and #c.subdomain <= 63 and
        c.subdomain:match('^[a-z0-9][a-z0-9%-]*$') and not c.subdomain:match('%-$'), 'Invalid subdomain')
    assert(type(c.token) == 'string' and #c.token >= 20 and c.token:match('^[A-Za-z0-9%-]+$'), 'Invalid token')
    assert(type(c.interface) == 'string' and c.interface:match('^[A-Za-z0-9_.%-]+$'), 'Invalid interface')
    c.poll_seconds = tonumber(c.poll_seconds) or 10
    c.retry_seconds = tonumber(c.retry_seconds) or 30
    c.refresh_seconds = tonumber(c.refresh_seconds) or 1800
    c.dns_check_seconds = tonumber(c.dns_check_seconds) or 300
    c.port = tonumber(c.port) or 18443
    if c.require_listener == nil then c.require_listener = true end
    assert(type(c.require_listener) == 'boolean', 'Invalid listener requirement')
    assert(c.poll_seconds >= 5 and c.poll_seconds <= 60 and c.retry_seconds >= 15
        and c.refresh_seconds >= 300 and c.dns_check_seconds >= 30 and c.port >= 1 and c.port <= 65535, 'Invalid timing or port')
    if c.proxy_url and c.proxy_url ~= '' then
        assert(c.proxy_url:match('^http://%d+%.%d+%.%d+%.%d+:%d+$'), 'Invalid update transport proxy')
    end
    return c
end

local function curl(c, url, extra, force_direct)
    local request = runtime .. '/request.private'
    local body = runtime .. '/response.private'
    write_private(request, 'url = "' .. url .. '"\n')
    local proxy = (not force_direct and c.proxy_url and c.proxy_url ~= '')
        and (' --proxy ' .. quote(c.proxy_url) .. ' --noproxy ' .. quote(''))
        or (' --noproxy ' .. quote('*'))
    run('umask 077; curl -4 -fsS --connect-timeout 4 --max-time 10 --config '
        .. quote(request) .. proxy .. (extra or '') .. ' --output ' .. quote(body)
        .. '; printf "curl_exit=%s\\n" "$?" > ' .. quote(runtime .. '/curl-exit'))
    local ok = (read(runtime .. '/curl-exit') or ''):match('curl_exit=0') ~= nil
    local data = read(body) or ''
    fs.unlink(request); fs.unlink(body); fs.unlink(runtime .. '/curl-exit')
    return ok, data
end

local function publish(c, address)
    local url = 'https://www.duckdns.org/update?domains=' .. c.subdomain
        .. '&token=' .. c.token .. '&ipv6=' .. address .. '&verbose=true'
    local ok, body = curl(c, url, nil, true)
    if not ok then ok, body = curl(c, url) end
    return ok and M.parse_response(body, address)
end

local function verify_dns(c, address)
    local ok, body = curl(c, 'https://dns.google/resolve?name=' .. c.subdomain .. '.duckdns.org&type=AAAA',
        " --header 'accept: application/dns-json'")
    if not ok then return false end
    local answer = json.parse(body)
    if not answer or answer.Status ~= 0 then return false end
    for _, rr in ipairs(answer.Answer or {}) do
        if rr.type == 28 and M.canonical(rr.data) == M.canonical(address) then return true, rr.TTL end
    end
    return false
end

function M.loop(once)
    local c = config()
    fs.mkdir(runtime); assert(fs.chmod(runtime, '700'))
    local state = {hostname = c.subdomain .. '.duckdns.org', interface = c.interface,
        poll_seconds = c.poll_seconds, provider_accepted = false, dns_verified = false,
        proxy_connectivity = 'NOT_CHECKED_BY_DDNS'}
    -- Always republish and read back after service startup, including router reboot.
    local published_at, last_attempt, dns_checked_at, previous_status = 0, 0, 0, ''
    repeat
        local now = os.time()
        local address = M.parse_addresses(run('ip -6 -o addr show dev ' .. quote(c.interface) .. ' scope global'))
        if address ~= state.current_address then
            state.provider_accepted = false; state.dns_verified = false
            dns_checked_at = 0
        end
        state.current_address = address
        state.checked_at = now
        state.listener_present = run('netstat -lnt'):match(':' .. c.port .. '%s') ~= nil
        if not address then
            state.status = 'no_preferred_global_ipv6'
        elseif c.require_listener and not state.listener_present then
            state.status = 'proxy_listener_missing'
        else
            if (address ~= state.published_address or now - published_at >= c.refresh_seconds)
                and now - last_attempt >= c.retry_seconds then
                last_attempt = now
                if publish(c, address) then
                    state.published_address = address; state.provider_accepted = true
                    state.published_at = os.time(); published_at = state.published_at
                    dns_checked_at = 0
                else
                    state.provider_accepted = false; state.dns_verified = false
                end
            end
            if state.provider_accepted and os.time() - dns_checked_at >= c.dns_check_seconds then
                state.dns_verified, state.dns_ttl = verify_dns(c, address)
                dns_checked_at = os.time(); state.dns_checked_at = dns_checked_at
            end
            state.status = not state.provider_accepted and 'provider_update_pending'
                or (state.dns_verified and 'dns_verified' or 'waiting_for_dns')
        end
        write_private(runtime .. '/status.private.json', json.stringify(state) .. '\n')
        if state.status ~= previous_status then
            run('logger -t codex-relay-ddns ' .. quote(state.status)); previous_status = state.status
        end
        if not once then
            for _ = 1, c.poll_seconds do
                nixio.nanosleep(1)
                if fs.access(runtime .. '/wake') then fs.unlink(runtime .. '/wake'); break end
            end
        end
    until once
end

if arg and arg[1] == '--once' then M.loop(true)
elseif arg and arg[1] == '--loop' then M.loop(false)
elseif arg and arg[1] == '--status' then io.write(read(runtime .. '/status.private.json') or '{}\n')
end
return M
