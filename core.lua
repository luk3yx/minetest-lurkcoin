--
-- Minetest lurkcoin mod - Core
--
-- © 2019 by luk3yx
--

lurkcoin.version = 0
lurkcoin.timeout = 10
lurkcoin.exchange_rate = 1

-- Do not allow other mods to modify this, or they may be able to bypass mod
--   security restrictions!
local baseurl = 'https://nz.xeroxirc.net:7000/v2'

-- Get the username and API token
lurkcoin.server_name = minetest.settings:get('lurkcoin.username')
local token          = minetest.settings:get('lurkcoin.token')

-- Make sure lurkcoin.server_name exists
if not lurkcoin.server_name then
    lurkcoin.server_name = '<unknown>'
    minetest.log('warning', 'lurkcoin has no server name set!')
end

-- Make sure the HTTP API exists
local http = ...
if not http then
    minetest.log('warning', 'lurkcoin is not allowed to use the HTTP API! ' ..
        'Please add lurkcoin to secure.http_mods in minetest.conf.')
end

-- Download functions
lurkcoin.user_agent = 'Minetest ' .. minetest.get_version().string ..
    ' (with lurkcoin mod v' .. tostring(lurkcoin.version) .. ')'
local function get(url, data, callback)
    if not data then
        data = {}
    elseif not http then
        return callback({
            completed = true,
            succeeded = false,
            timeout   = true,
            code      = 500,
            data      = 'ERROR: The lurkcoin mod is not in secure.http_mods!'
        })
    elseif not lurkcoin.server_name or not token then
        return callback({
            completed = true,
            succeeded = false,
            timeout   = true,
            code      = 401,
            data      = 'ERROR: The lurkcoin mod does not have (correct) ' ..
                'account credentials!'
        })
    end

    data.name  = lurkcoin.server_name
    data.token = token

    -- Minetest eats any non-200 code.
    data.force_200 = '200'

    http.fetch({
        url         = baseurl .. '/' .. url,
        timeout     = lurkcoin.timeout,
        post_data   = data,
        user_agent  = lurkcoin.user_agent,
    }, function(res)
        if res.timeout then
            minetest.log('warning', '[lurkcoin] Could not connect to lurkcoin!')
            res.code = 500
            res.data = 'ERROR: Could not connect to lurkcoin!'
        elseif res.code == 401 or res.code == 418 then
            minetest.log('warning', '[lurkcoin] Invalid username or API token!')
            lurkcoin.server_name, token = '<unknown>', nil
        elseif res.code == 200 and res.data:sub(1, 7) == 'ERROR: ' then
            res.code = 501
        end

        local success, msg = pcall(callback, res)
        if not success then
            minetest.log('error', '[lurkcoin] Error: ' .. msg)
        end
    end)
end

-- Process incoming transactions.
local handled_transactions = {}

local function _sync(res)
    if res.code == 200 then
        local data = minetest.parse_json(res.data)

        -- Update the exchange rate
        assert(type(data.exchange_rate) == 'number')
        assert(data.exchange_rate == data.exchange_rate)
        lurkcoin.exchange_rate = data.exchange_rate

        -- Process any unprocessed transactions
        for _, t in ipairs(data.transactions) do
            assert(type(t[3]) == 'number')
            local id = minetest.serialize(t)
            if not handled_transactions[id] then
                handled_transactions[id] = true
                core.log('action', '[lurkcoin] ' .. t[4])
                lurkcoin.bank.add(t[2], t[3])
            end
        end

        -- Tell lurkcoin to remove processed transactions
        if #data.transactions > 0 then
            get('remove_transactions', {count = tostring(#data.transactions)},
            function(res)
                if res.code == 200 then
                    for _, t in ipairs(data.transactions) do
                        handled_transactions[minetest.serialize(t)] = nil
                    end
                end
            end)
        end
    end
end

-- Periodically sync with lurkcoin.
local function sync()
    get('get_transactions', {as_object = 'true'}, _sync)
    minetest.after(300, sync)
end

-- Start syncing once the game is loaded.
minetest.after(0, sync)

-- Get an exchange rate
function lurkcoin.get_exchange_rate(amount, to, callback)
    assert(callback)
    amount = amount and tonumber(amount)
    if not amount or amount ~= amount then return callback(nil) end

    get('exchange_rates', {
        from    = lurkcoin.server_name,
        to      = to or 'lurkcoin',
        amount  = tostring(amount),
    }, function(res)
        if res.code == 200 then
            local amount = tonumber(res.data)
            if amount == amount then return callback(amount) end
        end
        return callback(nil)
    end)
end

-- Pay a user (cross-server)
function lurkcoin.pay(from, to, server, amount, callback)
    assert(type(amount) == 'number' and callback)

    -- Run lurkcoin.bank.pay() if this is not a cross-server transaction.
    if not server or server == '' or server:lower() ==
      lurkcoin.server_name:lower() then
        return callback(lurkcoin.bank.pay(from, to, amount))
    end

    -- Sanity checks
    amount = math.floor(amount * 100) / 100
    if not lurkcoin.bank.user_exists(from) then
        return callback(false, 'ERROR: The "from" user does not exist!')
    elseif amount ~= amount or amount <= 0 then
        return callback(false, 'ERROR: Invalid number!')
    elseif lurkcoin.bank.getbal(from) - amount < 0 then
        return callback(false, 'ERROR: You cannot afford to do that!')
    end

    if not lurkcoin.bank.subtract(from, amount, 'Transaction to "' .. to ..
            '" on server "' .. server .. '".') then
        return callback(false, 'ERROR: Transaction failed!')
    end

    -- Send the request
    return get('pay', {
        target = to,
        server = server,
        amount = tostring(amount),
        local_currency = 'true'
    }, function(res)
        if res.code ~= 200 then
            lurkcoin.bank.add(from, amount, 'Reverting failed transaction.')
            if res.data == 'ERROR: You cannot afford to do that!' then
                res.data = 'ERROR: This server cannot afford to do that!'
            end
        else
            minetest.log('action', '[lurkcoin] User ' .. from .. ' paid ' ..
                to .. ' (on server ' .. server .. ') ' .. tostring(amount) .. 'cr.')
        end

        return callback(res.code == 200, res.data or 'ERROR: Unknown error!')
    end)
end

-- Nuke lurkcoin.modpath
lurkcoin.modpath = nil
