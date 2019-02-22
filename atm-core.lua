--
-- Minetest lurkcoin mod - ATMs
--
-- © 2019 by luk3yx
--

local open_atms = {}

local function e(text)
    return minetest.formspec_escape(tostring(text))
end

local formspecs = {}

-- 0.4 compatibility
lurkcoin.formspec_prepend = ''
if minetest.get_modpath('default') and rawget(_G, 'default') and
  default.gui_bg and default.gui_bg_img and default.gui_slots then
    lurkcoin.formspec_prepend = default.gui_bg .. default.gui_bg_img ..
        default.gui_slots
end

-- The formspec code is based on something random I did in 2017(?) for
--  lurkcoinV1, formspecs are weird and I somehow got it right™ then.
local function get_formspec(name, page, params)
    -- The formspec template
    local formspec = 'size[8,9;]' .. lurkcoin.formspec_prepend ..
        'label[0.5,1.75;Your balance: ' ..
            e(lurkcoin.bank.getbal(name)) .. 'cr.]' ..
        'image_button[2,0.55;4,0.5;default_dirt.png^\\[colorize:#343434;y;' ..
            'Welcome to a ' .. e(lurkcoin.server_name) .. ' ATM!]'          ..
        'label[0.5,2.25;Exchange rate: \xc2\xa41.00 is equal to '           ..
            e(lurkcoin.exchange_rate) .. 'cr.]'                             ..
        'image_button[1.75,1.05;4.5,0.5;default_dirt.png^\\[colorize:'      ..
            '#343434;y; Your account: ' .. e(name) .. ']'                   ..
        'image[0.5,0.5;1,1;default_mese_crystal.png]'                       ..
        'image[6.5,0.5;1,1;default_mese_crystal.png]'

    -- Get the page formspec
    local page = formspecs[page] or formspecs.main
    if type(page) == 'string' then
        formspec = formspec .. page
    elseif type(page) == 'function' then
        formspec = formspec .. page(name, params)
    end

    -- Return the generated formspec
    return formspec
end

-- The formspecs (depending on installed mods)
local withdrawls = false

-- Payment screen
function formspecs.pay(name, fields)
    fields = fields or {}
    local formspec =
        'field[0.8,3.5;7,1;user;User to pay;' .. e(fields.user or '') .. ']' ..
        'field_close_on_enter[user;false]' ..
        'field[0.8,4.8;7,1;server;Server the user is on;' ..
            e(fields.server or lurkcoin.server_name) .. ']' ..
        'field_close_on_enter[server;false]' ..
        'field[0.8,6.15;7,1;amount;Amount to pay (in cr);' ..
            e(fields.amount or '5.00') .. ']' ..
        'field_close_on_enter[amount;false]'

    if fields._err then
        formspec = formspec ..
            'label[0.5,7;' .. e(fields._err) .. ']' ..
            'button[0.5,8;3.5,1;payuser;Cancel]' ..
            'button[4,8;3.5,1;paysubmit;Try again]'
    elseif fields.paysubmit then
        formspec = formspec ..
            'label[0.5,7;Please confirm the above values.'
        if fields.server ~= lurkcoin.server_name then
            local r = (tonumber(fields.amount) or 0) / lurkcoin.exchange_rate
            r = tostring(math.floor(r * 100) / 100)
            formspec = formspec ..
                '\n' .. fields.amount .. 'cr is equal to \xc2\xa4' .. r .. '.'
        end
        formspec = formspec .. ']' ..
            'button[0.5,8;3.5,1;payuser;Cancel]' ..
            'button[4,8;3.5,1;payconfirm;Confirm and pay]'
    else
        formspec = formspec ..
            'button[0.5,7;7,1;paysubmit;Pay the user!]'

        if withdrawls then
            formspec = formspec ..
                'button[0.5,8;3.5,1;home;Go back]' ..
                'button_exit[4,8;3.5,1;quit;Quit]'
        else
            formspec = formspec ..
                'button_exit[0.5,8;7,1;quit;Quit]'
        end
    end
    return formspec
end

-- The main formspec
if minetest.get_modpath('currency') then
    formspecs.main =
        'button[0.5,3.25;7,1;deposit;Deposit money]' ..
        'field[0.8,4.85;6,1;withdraw;Withdraw money (in Mg);5.00]' ..
        'field_close_on_enter[withdraw;false]' ..
        'button[6.5,4.55;1,1;wd;Next >]' ..
        'field[0.8,6.1;6,1;user;Pay someone;]' ..
        'field_close_on_enter[user;false]' ..
        'button[6.5,5.8;1,1;payuser;Next >]' ..
        'button_exit[0.5,8;7,1;quit;Quit]'

    -- Create a withdrawls list with available currency.
    withdrawls = {
        [0.05] = 'currency:minegeld_cent_5',
        [0.10] = 'currency:minegeld_cent_10',
        [0.25] = 'currency:minegeld_cent_25',
        [1]    = 'currency:minegeld',
        [5]    = 'currency:minegeld_5',
        [10]   = 'currency:minegeld_10',
        [20]   = 'currency:minegeld_20', -- The original mod now has 20Mg notes.
        [50]   = 'currency:minegeld_50',
        [100]  = 'currency:minegeld_100',
    }

    -- Remove non-registered notes
    for id, note in pairs(withdrawls) do
        if not minetest.registered_items[note] then
            withdrawls[id] = nil
        end
    end
    assert(#withdrawls > 0, 'The "currency" mod did not register any notes!')

    -- Create a detached inventory for depositing
    local inv = minetest.create_detached_inventory('lurkcoin:atm_deposit', {
        on_put = function(inv, listname, index, stack, player)
            local name = stack:get_name()
            if name:sub(1, 17) == 'currency:minegeld' then
                local m = name:sub(19)
                if #m > 0 then
                    if m:sub(1, 5) == 'cent_' then
                        m = tonumber(m:sub(6))
                        if m then m = m / 100 end
                    else
                        m = tonumber(m)
                    end
                else
                    m = 1
                end

                if type(m) == 'number' and m == m then
                    m = m * stack:get_count()
                    local pname = player:get_player_name()
                    if not lurkcoin.bank.add(pname, m, 'Deposit') then
                        player:get_inventory():add_item('main', stack)
                    end
                    core.log('action', 'Player ' .. pname .. ' deposts ' ..
                        stack:to_string() .. ' into an ATM.')
                end
            end
            inv:set_list(listname, {})
            lurkcoin.show_atm(player:get_player_name(), 'deposit')
        end,

        allow_put = function(inv, listname, index, stack, player)
            local name = stack:get_name()
            if name:sub(1, 17) == 'currency:minegeld' then
                return stack:get_count()
            else
                return 0
            end
        end,

        allow_take = function() return 0 end,
    })
    inv:set_size("lurkcoin", 1)

    -- Depositing
    formspecs.deposit =
        'list[current_player;main;0,4.85;8,1;]'  ..
        'list[current_player;main;0,6.08;8,3;8]' ..
        'list[detached:lurkcoin:atm_deposit;lurkcoin;3.5,3;1,1;]' ..
        'listring[]' ..
        'image_button[0,3;3.5,1;default_dirt.png^\\[colorize:#343434;' ..
            'ignore;Deposit money here →]' ..
        'button[5.25,3;2,1;home;Finish]'
else
    -- When there is no physical currency, the only thing you can do is pay
    --  others.
    formspecs.main = formspecs.pay
end

-- "Transaction accepted" screen
function formspecs.success(name, text)
    return 'image[2.1,3;4.5,4.5;lurkcoin_success.png]' ..
        'image_button[1,7;6,1;default_dirt.png^\\[colorize:#343434;' ..
            'ignore;' .. e(text or 'Transaction sent!') .. ']' ..
        'button[0.5,8;3.5,1;home;Go back]' ..
        'button_exit[4,8;3.5,1;quit;Quit]'
end

-- "Transaction failed" screen
function formspecs.error(name, text)
    return 'image[2.1,3;4.5,4.5;lurkcoin_error.png]' ..
        'image_button[1,7;6,1;default_dirt.png^\\[colorize:#343434;' ..
            'ignore;' .. e(text or 'An error has occurred!') .. ']' ..
        'button[0.5,8;3.5,1;home;Go back]' ..
        'button_exit[4,8;3.5,1;quit;Quit]'
end

-- Processing screen
formspecs.processing =
    'image[2.1,3;4.5,4.5;lurkcoin_processing.png]' ..
    'image_button[1,7;6,1;default_dirt.png^\\[colorize:#343434;' ..
    'ignore;Processing your transaction...]' ..
    'image_button[1,8;6,1;default_dirt.png^\\[colorize:#343434;' ..
    'ignore;This should only take a few seconds.]'

-- A wrapper function
function lurkcoin.show_atm(name, page, params)
    minetest.show_formspec(name, 'lurkcoin:atm', get_formspec(name,
        page, params))
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname == 'lurkcoin:atm' then
        local name = player:get_player_name()

        if withdrawls then
            if fields.deposit then
                return lurkcoin.show_atm(name, 'deposit')
            elseif fields.wd then
                local amount = tonumber(fields.withdraw)
                if not amount or amount ~= amount or amount <= 0 then
                    return lurkcoin.show_atm(name, 'error',
                        'ERROR: Invalid number!')
                end
                local bal = lurkcoin.bank.getbal(name)
                if amount > bal then
                    return lurkcoin.show_atm(name, 'error',
                        'ERROR: You cannot afford to do that!')
                end

                local note = false
                for id, item in pairs(withdrawls) do
                    if (not note or id > note) and
                      math.floor(amount / id) * id == amount then
                        local def = minetest.registered_items[item]
                        if def and amount / id <= (def.stack_max or 99) then
                            note = id
                        end
                    end
                end

                if not note then
                    return lurkcoin.show_atm(name, 'error',
                        'ERROR: I cannot store that amount of\nmoney in a ' ..
                        'single stack of notes/coins!')
                end

                local stack = ItemStack({
                    name  = withdrawls[note],
                    count = amount / note,
                })
                local inv = player:get_inventory()
                if not inv:room_for_item('main', stack) then
                    return lurkcoin.show_atm(name, 'error',
                        'ERROR: You do not have enough inventory space!')
                end

                lurkcoin.bank.subtract(name, amount)
                inv:add_item('main', stack)

                return lurkcoin.show_atm(name, 'success')
            end
        end

        if fields.payconfirm and open_atms[name] and open_atms[name].pay then
            local data = open_atms[name]
            for k, v in pairs(data) do
                if type(v) == 'number' then fields[k] = tonumber(fields[k]) end
                if k ~= 'pay' and fields[k] ~= v then
                    if k ~= 'amount' then
                        k = 'target ' .. k
                    end
                    fields._err = 'The ' .. k ..
                        ' was modified before pressing confirm!'
                    lurkcoin.show_atm(name, 'pay', fields)
                    return
                end
            end
            lurkcoin.show_atm(name, 'processing')
            lurkcoin.pay(name, data.user, data.server, data.amount,
                function(success, msg)
                    local page = success and 'success' or 'error'
                    return lurkcoin.show_atm(name, page, msg)
                end
            )
        elseif fields.payuser or fields.paysubmit or fields.payconfirm then
            if fields.paysubmit then
                local amount = tonumber(fields.amount)
                if not amount or amount ~= amount or amount <= 0 then
                    fields._err = 'Invalid number!'
                    lurkcoin.show_atm(name, 'pay', fields)
                    return
                elseif lurkcoin.bank.getbal(name) - amount < 0 then
                    fields._err = 'You cannot afford to do that!'
                    lurkcoin.show_atm(name, 'pay', fields)
                    return
                elseif fields.server then
                    fields.server = fields.server:gsub('^ *(.-) *$', '%1')
                end

                if fields.user then
                    fields.user = fields.user:gsub('^ *(.-) *$', '%1')
                end

                if not fields.server or fields.server == '' then
                    fields.server = lurkcoin.server_name
                end

                open_atms[name] = {
                    pay    = true,
                    user   = fields.user or '',
                    server = fields.server,
                    amount = amount,
                }
                if open_atms[name].user == '' or (
                        fields.server == lurkcoin.server_name and
                        not lurkcoin.bank.user_exists(open_atms[name].user)
                        ) then
                    fields._err = 'That user does not exist!'
                    lurkcoin.show_atm(name, 'pay', fields)
                    return
                end
            end
            fields._err = nil
            lurkcoin.show_atm(name, 'pay', fields)
        elseif fields.home then
            lurkcoin.show_atm(name, 'main')
        elseif fields.quit then
            open_atms[name] = nil
        end
    end
end)

minetest.register_on_leaveplayer(function(player)
    -- TODO: I forgot what one register_on_leaveplayer uses and am too lazy to
    --  check.
    local name
    if type(player) == 'string' then
        name = player
    else
        name = player:get_player_name()
    end

    open_atms[name] = nil
end)
