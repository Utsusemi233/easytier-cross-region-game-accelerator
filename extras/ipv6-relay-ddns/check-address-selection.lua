arg = {}
local m = dofile(assert(os.getenv('RELAY_DDNS_MODULE')))
local function eq(a, b, title) assert(a == b, title) end
local a = '2001:db8:10::1'
local b = '2001:db8:11::1'
eq(m.parse_addresses('1: eth1 inet6 fd39:aaaa::1/64 scope global preferred_lft forever'), nil, 'ULA must not publish')
eq(m.parse_addresses('1: eth1 inet6 ' .. a .. '/64 scope global deprecated preferred_lft 0sec\n'
    .. '1: eth1 inet6 ' .. b .. '/64 scope global preferred_lft 3600sec'), b, 'Preferred new prefix must replace deprecated old prefix')
eq(m.parse_addresses('1: eth1 inet6 ' .. b .. '/64 scope global tentative preferred_lft 300sec'), nil, 'DAD pending address must not publish')
eq(m.parse_addresses('1: eth1 inet6 2001:db8:10::abcd/64 scope global temporary preferred_lft 300sec\n'
    .. '1: eth1 inet6 ' .. a .. '/64 scope global preferred_lft 300sec'), a, 'Stable address must beat temporary')
eq(m.parse_addresses('1: eth1 inet6 ' .. a .. '/64 scope global preferred_lft 0sec'), nil, 'Expired address must not publish')
eq(m.parse_response('OK\n\n' .. a .. '\nUPDATED\n', a), true, 'AAAA-only blank IPv4 response must succeed')
eq(m.parse_response('OK\r\n192.0.2.1\r\n' .. a .. '\r\nNOCHANGE\r\n', a), true, 'CRLF and unchanged record must succeed')
eq(m.parse_response('OK\n\n' .. b .. '\nUPDATED\n', a), false, 'Wrong address response must fail')
eq(m.parse_response('KO\n', a), false, 'Provider rejection must fail')
eq(m.parse_response('OK\n\n\n', a), false, 'Missing IPv6 must fail')
eq(m.canonical('2001:db8::1'), m.canonical('2001:0db8:0000:0000:0000:0000:0000:0001'), 'IPv6 compression must compare correctly')
print('PASS: 11 address-selection and provider-response checks')
