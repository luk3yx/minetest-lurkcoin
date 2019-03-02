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

-- Tweak minetest.log for extra security, unless cloaking already has.
if not minetest.get_modpath('cloaking') or not cloaking.version then
    table.insert(minetest.registered_on_chat_messages, 1, function(name, msg)
        if msg:find('[\r\n]') then
            minetest.chat_send_player(name,
                'Error sending message: https://xkcd.com/327')
            return true
        end
    end)

    local log = minetest.log
    function minetest.log(level, text)
        level = level:gsub('[\r\n]', '  ')
        if text then
            text  = text:gsub('[\r\n]', '  ')
        else
            text  = level
            level = 'none'
        end
        return log(level, text)
    end
end

-- Display loaded message
minetest.log('action', '[lurkcoin] Loaded on server "' ..
    lurkcoin.server_name .. '".')
