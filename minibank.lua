--
-- Minetest minibank (sub)mod - A very simple economy mod alternative
--
-- © 2019 by luk3yx
--

local storage = minetest.get_mod_storage()

-- Use mod storage for getbal() and setbal().
-- Store as strings because of weird bugs when using floats.
local function rawgetbal(name)
    return tonumber(storage:get_string('minibank-' .. name))
end

local setbal

local function getbal(name)
    local lname = name:lower()
    if lname ~= name and rawgetbal(name) ~= nil then
        setbal(lname, rawgetbal(name) + (rawgetbal(lname) or 0))
        storage:set_string('minibank-' .. name, '')
    end
    return rawgetbal(lname)
end

function setbal(name, balance)
    storage:set_string('minibank-' .. name:lower(), tostring(balance))
end

-- Create an empty account for new players
minetest.register_on_joinplayer(function(player)
    if lurkcoin.bank.mod ~= 'lurkcoin' then return end

    local name = player:get_player_name()
    if not lurkcoin.bank.user_exists(name) then
        setbal(name, 0)
    end
end)

-- Let bank.lua add everything else.
lurkcoin.change_bank({
    getbal      = getbal,
    setbal      = setbal
})
