--
-- Minetest lurkcoin mod - Bank
--
-- © 2019 by luk3yx
--

-- Add a function to automatically change the bank
function lurkcoin.change_bank(bank)
    -- Sanity checks
    assert(type(bank) == 'table')
    assert(bank.getbal and bank.setbal)

    -- Set lurkcoin.bank to the new bank
    lurkcoin.bank = bank
    bank = nil

    -- Get the current mod name
    if not lurkcoin.bank.mod then
        lurkcoin.bank.mod = minetest.get_current_modname() or '???'
    end

    -- Make sure "getbal" has a consistent return result and add user_exists if
    --  it doesn't.
    if type(lurkcoin.bank.getbal('\xc2\xa4 Fake user')) ~= 'number' then
        local getbal = lurkcoin.bank.getbal
        if not lurkcoin.bank.user_exists then
            function lurkcoin.bank.user_exists(name)
                return getbal(name) and true or false
            end
        end

        function lurkcoin.bank.getbal(name)
            return getbal(name) or 0
        end
    end

    assert(lurkcoin.bank.user_exists)

    -- Make sure "setbal" has a consistent return value.
    do
        local setbal = lurkcoin.bank.setbal
        function lurkcoin.bank.setbal(name, amount, reason)
            if type(amount) ~= 'number' or amount ~= amount then
                return false
            end

            local success = setbal(name, amount, reason)
            if success == nil then
                return true
            end
            return success
        end
    end

    -- Make sure "changebal" exists
    if not lurkcoin.bank.changebal then
        if lurkcoin.bank.add and lurkcoin.bank.subtract then
            function lurkcoin.bank.changebal(name, amount, reason)
                if amount == 0 then
                    return true
                elseif type(amount) ~= 'number' or amount ~= amount then
                    return false
                end

                if amount > 0 then
                    return lurkcoin.bank.add(name, amount, reason)
                else
                    return lurkcoin.bank.subtract(name, amount, reason)
                end
            end
        else
            function lurkcoin.bank.changebal(name, amount, reason)
                if amount == 0 then
                    return true
                elseif type(amount) ~= 'number' or amount ~= amount then
                    print('Not a number')
                    return false
                end

                local resulting_bal = lurkcoin.bank.getbal(name) + amount
                if resulting_bal < 0 then
                    print('Cannot afford to do that')
                    return false
                end

                return lurkcoin.bank.setbal(name, resulting_bal, reason)
            end
        end
    end

    -- Make sure "add" exists
    if not lurkcoin.bank.add then
        function lurkcoin.bank.add(name, amount, reason)
            if amount < 0 then
                return false
            end

            return lurkcoin.bank.changebal(name, amount, reason)
        end
    end

    -- Make sure "subtract" exists
    if not lurkcoin.bank.subtract then
        function lurkcoin.bank.subtract(name, amount, reason)
            if amount < 0 then
                return false
            end

            return lurkcoin.bank.changebal(name, 0 - amount, reason)
        end
    end

    -- Make sure "pay" exists, and if so, make sure it has consistent return
    --   values.
    if lurkcoin.bank.pay then
        local pay = lurkcoin.bank.pay
        function lurkcoin.bank.pay(from, to, amount)
            if type(amount) ~= 'number' or amount ~= amount then
                return false, 'Invalid number!'
            end

            local success, msg = pay(from, to, amount)
            if success or success == nil then
                return true, msg or 'Transaction sent!'
            else
                return false, msg or 'Error processing transaction!'
            end
        end
    else
        function lurkcoin.bank.pay(from, to, amount)
            if type(amount) == 'number' then
                amount = math.floor(amount * 100) / 100
            end

            if not lurkcoin.bank.user_exists(from) or not
                   lurkcoin.bank.user_exists(to) then
                return false, 'The specified user does not exist!'
            elseif type(amount) ~= 'number' or amount ~= amount or
              amount <= 0 then
                return false, 'Invalid number!'
            elseif lurkcoin.bank.getbal(from) - amount < 0 then
                return false, 'You cannot afford to do that!'
            end

            local success = false
            if lurkcoin.bank.subtract(from, amount, 'Transaction to ' ..
              to) then
                success = lurkcoin.bank.add(to, amount, 'Transaction from ' ..
                    from)

                -- Revert failed transactions
                if not success and success ~= nil then
                    lurkcoin.bank.add(from, amount,
                        'Reverting failed transaction.')
                end
            end

            if success or success == nil then
                minetest.log('action', '[lurkcoin] User ' .. from .. ' paid ' ..
                    to .. ' ' .. tostring(amount) .. 'cr.')
                return true, 'Transaction sent!'
            end
            return false, 'Error processing transaction!'
        end
    end
end

-- Built-in mod integrations
-- These should be in alphabetical order (except ones that use the "money"
--  global).

if minetest.get_modpath('atm') and rawget(_G, 'atm') and atm.balance then
    -- ATM mod from https://git.gpcf.eu/?p=atm.git;a=tree
    -- Add (really) basic wrapper functions that should be replaced in
    --  change_bank().
    lurkcoin.change_bank({
        mod    = 'atm',
        getbal = function(name)
            return atm.balance[name]
        end,
        setbal = function(name, bal)
            atm.balance[name] = bal
            atm.saveaccounts()
        end
    })
elseif minetest.get_modpath('bank_accounts') and rawget(_G, 'accounts') and
  accounts.balance and accounts.pin and accounts.credit then
    -- https://github.com/Tmanyo/bank_accounts

    lurkcoin.change_bank({
        mod    = 'bank_accounts',
        getbal = function(name)
            return accounts.balance[name]
        end,
        setbal = function(name, bal)
            accounts.balance[name] = bal
        end
    })
elseif minetest.get_modpath('economy') and rawget(_G, 'economy') and
  economy.balance and economy.accountlog then
    -- https://github.com/orwell96/economy
    -- economy.moneyof() automatically adds non-existent entries, therefore it
    --  is not used by default.

    lurkcoin.change_bank({
        mod    = 'economy',
        getbal = function(name)
            return economy.balance[name]
        end,
        setbal = function(name, amount, reason)
            local difference = amount - economy.balance[name]
            economy.balance[name] = amount
            local symbol
            if difference >= 0 then
                symbol = '+'
            else
                symbol = '-'
                difference = 0 - difference
            end
            if not economy.accountlog[name] then
                economy.accountlog[name] = {}
            end
            if not reason then
                reason = 'Transaction on ' .. os.date('%Y-%m-%d %H:%M:%S')
            end
            table.insert(economy.accountlog[name], 1, {
                action = reason,
                amount = symbol .. ' ' .. tostring(difference)
            })
        end,
    })
elseif rawget(_G, 'money') then
    -- Mods that (incorrectly) use the "money" global variable.

    if minetest.get_modpath('economy') and money.get_money then
        lurkcoin.change_bank({
            mod         = 'economy',
            user_exists = money.exist,
            getbal      = money.get_money,
            setbal      = money.set_money,
        })
    elseif minetest.get_modpath('money2') and money.get then
        -- money.add and money.dec have a different return value system.
        lurkcoin.change_bank({
            mod         = 'money2',
            user_exists = money.has_credit,
            getbal      = money.get,
            setbal      = function(...)
                money.set(...)
                return true
            end,
            pay         = function(from, to, amount)
                local err = money.transfer(from, to, amount)
                return not err, err
            end
        })
    end
end
