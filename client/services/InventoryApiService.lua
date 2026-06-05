local InventoryApi = {
    ADD_ITEM = function(itemData)
        local itemId <const> = itemData.id
        local itemAmount <const> = itemData.count
        local item <const> = PLAYER_INVENTORY.ITEMS[itemId]

        if item then
            item:setCount(itemAmount)
        else
            local newItem <const> = ITEM:Register(itemData)
            PLAYER_INVENTORY.ITEMS[itemId] = newItem
        end
        NUI_SERVICE.INVENTORY.UPDATE_ITEM(itemId)
    end,

    SUB_ITEM = function(id, qty)
        local item <const> = PLAYER_INVENTORY.ITEMS[id]
        if not item then return end

        item:setCount(qty)
        if item:getCount() == 0 then
            PLAYER_INVENTORY.ITEMS[id] = nil
            NUI_SERVICE.SHARED.REMOVE(id, item.type)
        else
            NUI_SERVICE.INVENTORY.UPDATE_ITEM(id)
        end
    end,

    SET_ITEM_METADATA = function(id, metadata)
        local item <const> = PLAYER_INVENTORY.ITEMS[id]
        if not item then return end

        item:setMetadata(metadata)
        NUI_SERVICE.INVENTORY.UPDATE_ITEM(id)
    end,

    SET_ITEM_DURABILITY = function(id, durability)
        local item <const> = PLAYER_INVENTORY.ITEMS[id]
        if not item then return end
        item:setDurability(durability)
        NUI_SERVICE.INVENTORY.UPDATE_ITEM(id)
    end,

    SUB_WEAPON = function(weaponId)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        if weapon then
            if weapon:getUsed() then
                weapon:UnequipWeapon(true)
            end
            PLAYER_INVENTORY.WEAPONS[weaponId] = nil
        end
        NUI_SERVICE.SHARED.REMOVE(weaponId, "item_weapon")
    end,

    SUB_WEAPON_BULLETS = function(weaponId, bulletType, qty)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        if weapon then
            weapon:subAmmo(bulletType, qty)
            if weapon:getUsed() then
                SetPedAmmoByType(CACHE.Ped, joaat(bulletType), weapon:getAmmo(bulletType))
            end
        end
        NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
    end,

    ADD_COMPONENT = function(weaponId, component, category)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        if not weapon then return end

        weapon:addComponent(component, category)
        NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
    end,
    ADD_COMPONENTS = function(weaponId, components)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        if not weapon then return end
        for category, component in pairs(components) do
            weapon:addComponent(component, category)
        end
        NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
    end,

    SUB_COMPONENT = function(weaponId, component, category)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        if not weapon then return end

        weapon:removeComponent(component, category)
        NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
    end,

    SUB_COMPONENTS = function(weaponId, components)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        if not weapon then return end
        for category, component in pairs(components) do
            weapon:removeComponent(component, category)
        end
        NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
    end,
}

INVENTORY_API_SERVICE = InventoryApi
