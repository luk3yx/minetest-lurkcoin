--
-- Minetest lurkcoin mod - Core
--
-- © 2019 by luk3yx
--

-- Change this if you are hosting your own lurkcoin-core instance
local baseurl = 'https://us.xeroxirc.net:7000'

lurkcoin.version = 3
lurkcoin.timeout = 10
lurkcoin.exchange_rate = 1

local function log(level, text)
    if text then
        text = text:gsub('[\r\n]', '  ')
    else
        level, text = 'action', level:gsub('[\r\n]', '  ')
    end
    return minetest.log(level, '[lurkcoin] ' .. text)
end

local function logf(text, ...)
    return log(text:format(...))
end

-- Get the username and API token
lurkcoin.server_name = minetest.settings:get('lurkcoin.username')
local token = minetest.settings:get('lurkcoin.token')

-- Make sure lurkcoin.server_name exists
if not lurkcoin.server_name then
    lurkcoin.server_name = '<unknown>'
    log('warning', 'lurkcoin.server_name is not set!')
end

-- Make sure the HTTP API exists
local http = ...
if not http then
    log('warning', 'lurkcoin is not allowed to use the HTTP API! ' ..
        'Please add lurkcoin to secure.http_mods in minetest.conf.')
end

-- This user agent is not strictly required, however I might do something
--  with the lurkcoin mod version later.
lurkcoin.user_agent = 'Minetest ' .. minetest.get_version().string ..
    ' (with lurkcoin mod v' .. tostring(lurkcoin.version) .. ')'

-- Create the HTTP header list
local headers
if token then
    local raw = lurkcoin.server_name:gsub(':', '_') .. ':' .. token
    local auth = minetest.encode_base64(raw)
    headers = {
        -- minetest.encode_base64() doesn't add padding
        'Authorization: Basic ' .. auth .. ('='):rep(4 - #auth % 4),
        'Content-Type: application/json',
        'X-Force-OK: true'
    }
end

local function E(code, msg)
    return {sucess = false, error = code, message = msg}
end

-- Download functions
local function get(url, data, callback)
    -- To prevent race conditions, these callbacks wait until at least the next
    --  globalstep.
    if not http then
        minetest.after(0, callback, E('ERR_CONNECTIONFAILED',
            'The lurkcoin mod is not in secure.http_mods!'))
        return
    elseif not headers then
        minetest.after(0, callback, E('ERR_INVALIDLOGIN',
            'The lurkcoin mod does not have (correct) credentials!'))
        return
    end

    http.fetch({
        url = baseurl .. '/v3/' .. url,
        timeout = lurkcoin.timeout,
        post_data = data and minetest.write_json(data),
        user_agent = lurkcoin.user_agent,
        extra_headers = headers
    }, function(http_res)
        local res
        if http_res.timeout then
            log('warning', 'Could not connect to lurkcoin!')
            res = E('ERR_CONNECTIONFAILED', 'Could not connect to lurkcoin!')
        else
            res = minetest.parse_json(http_res.data)
            if type(data) ~= 'table' then data = nil end
        end

        local ok, msg = pcall(callback, res or E('ERR_UNKNOWNERROR', '???'))
        if not ok then
            log('error', msg)
        end
    end)
end

-- Process incoming transactions.
local acknowledged_transactions = {}

local function sync_callback(res)
    if not res.success then return end

    -- Process any unprocessed transactions
    local reject = {}
    for _, t in ipairs(res.result) do
        local id = t.id
        if not acknowledged_transactions[id] then
            if lurkcoin.bank.user_exists(t.target) then
                acknowledged_transactions[id] = true
                logf('[%s] \194\164%s (sent %s, received %scr) - ' ..
                    'Transaction from %q on %q to %q.',
                    t.id, t.amount, t.sent_amount, t.received_amount, t.source,
                    t.source_server, t.target)
                lurkcoin.bank.add(t.target, t.received_amount)
            else
                logf('Rejecting transaction %s, user %q does not exist.',
                    t.id, t.target)
                table.insert(reject, t.id)
            end
        end
    end

    -- Acknowledge transactions (if any)
    if next(acknowledged_transactions) then
        local ack = {}
        for id, _ in pairs(acknowledged_transactions) do
            table.insert(ack, id)
        end
        get('acknowledge_transactions', {transactions = ack}, function(res2)
            if res2.success then
                for _, id in ipairs(ack) do
                    acknowledged_transactions[id] = nil
                end
            end
        end)
    end

    -- Reject transactions (if any)
    if #reject > 0 then
        get('reject_transactions', {transactions = reject}, function() end)
    end
end

-- Periodically sync with lurkcoin.
local exchange_rate_set
local function sync()
    get('pending_transactions', nil, sync_callback)

    -- Only set lurkcoin.exchange_rate once
    if not exchange_rate_set then
        get('exchange_rates', {source = '', target = lurkcoin.server_name,
                amount = 1}, function(res)
            if res.success and type(res.result) == 'number' then
                lurkcoin.exchange_rate = res.result
                exchange_rate_set = true
            end
        end)
    end
    minetest.after(300, sync)
end
minetest.after(0, sync)

-- Get an exchange rate
function lurkcoin.get_exchange_rate(amount, target, callback)
    assert(callback)
    get('exchange_rates', {
        source = lurkcoin.server_name,
        target = target or '',
        amount = amount,
    }, function(res)
        if res.success then
            callback(res.result, nil)
        elseif res.error == 'ERR_TARGETSERVERNOTFOUND' then
            callback(nil, 'That server does not exist!')
        else
            callback(nil, tostring(res.message))
        end
    end)
end

-- Pay a user (cross-server)
function lurkcoin.pay(source, target, target_server, amount, callback)
    assert(type(amount) == 'number' and callback)

    -- Run lurkcoin.bank.pay() if this is not a cross-server transaction.
    if not target_server or target_server == '' or
            target_server:lower() == lurkcoin.server_name:lower() then
        return callback(lurkcoin.bank.pay(source, target, amount))
    end

    -- Sanity checks
    amount = math.floor(amount * 100) / 100
    if not lurkcoin.bank.user_exists(source) then
        return callback(false, 'ERROR: The "from" user does not exist!')
    elseif amount ~= amount or amount <= 0 then
        return callback(false, 'ERROR: Invalid number!')
    elseif amount > lurkcoin.bank.getbal(source) then
        return callback(false, 'ERROR: You cannot afford to do that!')
    end

    if not lurkcoin.bank.subtract(source, amount, 'Transaction to "' ..
            source .. '" on server "' .. target_server .. '".') then
        return callback(false, 'ERROR: Transaction failed!')
    end

    -- Send the request
    return get('pay', {
        source = source,
        target = target,
        target_server = target_server,
        amount = amount,
        local_currency = true
    }, function(res)
        if res.success then
            logf('User %q paid %q (on server %q) %scr.', source, target,
                target_server, amount)
            return callback(true, 'Transaction sent!')
        end
        lurkcoin.bank.add(source, amount, 'Reverting failed transaction.')
        if res.code == 'ERR_CANNOTAFFORD' then
            res.message = 'This server cannot afford to do that!'
        end
        return callback(false, 'ERROR: ' .. tostring(res.message))
    end)
end

-- Nuke lurkcoin.modpath
lurkcoin.modpath = nil
