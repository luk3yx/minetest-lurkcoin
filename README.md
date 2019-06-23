# The official Minetest lurkcoin mod

Adds (cross-server) ATMs to Minetest. **Transactions may take up to 5 minutes to appear.**

This mod is currently in beta, and this README probably needs rewriting.

## How to use/install

After installing, you will need to add `lurkcoin` to `secure.http_mods` in
minetest.conf to allow cross-server transactions. The minetest.conf settings
`lurkcoin.username` and `lurkcoin.token` must be set to the username and token
you get from the lurkcoin website, and should not contain leading or trailing
spaces.

## What is a "lurkcoin"?

lurkcoin is a cross-server (possibly cross-game in the future) money transfer
system.

If you're interested in how it works, ask/nag me to finish this FAQ.

### But what if someone on one server cheats with creative?

There are limits, and exchange rates are updated in realtime (and change
depending on how much you are trying to transfer) to try and prevent creative
money and imbalanced economies. There are also logs of cross-server
transactions, if you suspect fraud, PM me on IRC if possible (Freenode or
xeroxIRC).

## API

The following lurkcoin-specific functions and variables exist:

 - `lurkcoin.exchange_rate`: The raw exchange rate, *do not modify this!*
 - `lurkcoin.get_exchange_rate(amount, to, callback)`: Get an exchange rate
    from this server.
 - `lurkcoin.pay(from, to, server, amount, callback)`: Makes `from` pay someone
    `amount`cr, and calls `callback` on success/faliure. `callback` should have two
    parameters, `success` and `msg`.
 - `lurkcoin.server_name`: The account name used to log into lurkcoin.

### Bank API

This mod creates a "universal"™ bank API.

The below functions (except `getbal` and `pay`) return `true` on success and
`false` on failure.

 - `lurkcoin.bank.getbal(name)`: Gets a balance
 - `lurkcoin.bank.setbal(name, balance, reason)`: Sets a balance
 - `lurkcoin.bank.user_exists(name)`: Checks if a user exists.
 - `lurkcoin.bank.changebal(name, amount, reason)`: Changes a balance (use
    either positive or negative numbers)
 - `lurkcoin.bank.add(name, amount, reason)`: Adds `amount` to `name`'s balance.
    Will return false if `amount` is below `0`.
 - `lurkcoin.bank.subtract(name, amount, reason)`: Subtracts `amount` from
    `name`'s balance. Will return false if `amount` is below `0`.
 - `lurkcoin.bank.pay(from, to, amount)`: Makes user `from` pay a user
    `amount`cr. This will return two values, `success` (true/false) and
    `message` (a string).

#### Changing the currently used bank

By default, this mod will check for a few bank mods, and if it doesn't find any
will use the built-in (≈34 line) `minibank.lua`. `minibank` does not store any
transaction history and will disregard the `reason` parameter when updating
balances.

To change the currently used bank, use `lurkcoin.change_bank(bank)`, where
`bank` is a table containing at least `getbal`, `setbal` and `user_exists`.
`getbal` should not create users on balance checking, and if it returns `nil`
for non-existent users, `user_exists` is not required. Any other functions
implemented (except `pay`) must have the same return values as described in this
documentation, and are entirely optional (they will be automatically created if
they are not included). Any missing functions are "filled in" automatically.

*By default, payments are rounded down to the nearest 0.01cr.*
