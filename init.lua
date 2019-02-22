--
-- Minetest lurkcoin mod
--
-- © 2019 by luk3yx
--

lurkcoin = {}

local modpath = minetest.get_modpath('lurkcoin')

-- Load bank.lua
dofile(modpath .. '/bank.lua')

-- Load the minibank submod thing if required
if not lurkcoin.bank then
    dofile(modpath .. '/minibank.lua')
end

-- Request the HTTP(S) API and load core.lua.
local http = minetest.request_http_api()
assert(loadfile(modpath .. '/core.lua'))(http)

-- Load the ATM core code
dofile(modpath .. '/atm-core.lua')

-- Load the ATM blocks
dofile(modpath .. '/atm-nodes.lua')

-- Display loaded message
minetest.log('action', '[lurkcoin] Loaded on server "' ..
    lurkcoin.server_name .. '".')
