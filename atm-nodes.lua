--
-- Minetest lurkcoin mod - ATM nodes
--
-- © 2019 by luk3yx
--

minetest.register_node('lurkcoin:atm', {
    description = 'ATM',
    groups = {cracky = 1},
    tiles = {'lurkcoin_atm_side.png', 'lurkcoin_atm_side.png',
        'lurkcoin_atm_side.png', 'lurkcoin_atm_side.png',
        'lurkcoin_atm_side.png', 'lurkcoin_atm_side.png^lurkcoin_atm_top.png'},

    paramtype2 = 'facedir',

    on_construct = function(pos)
        local meta = minetest.get_meta(pos)
        meta:set_string('infotext', 'ATM')
        meta:set_string('version', tostring(lurkcoin.version))
        if meta.mark_as_private then
            meta:mark_as_private('version')
        end
    end,

    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        return lurkcoin.show_atm(clicker:get_player_name())
    end,
})
