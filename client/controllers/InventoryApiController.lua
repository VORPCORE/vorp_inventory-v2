-- InventoryApiController server to client events
-- idont know why these events are called vorp core
RegisterNetEvent("vorpCoreClient:addItem", INVENTORY_API_SERVICE.ADD_ITEM)
RegisterNetEvent("vorpCoreClient:subItem", INVENTORY_API_SERVICE.SUB_ITEM)
RegisterNetEvent("vorpCoreClient:subWeapon", INVENTORY_API_SERVICE.SUB_WEAPON)
RegisterNetEvent("vorpCoreClient:subBullets", INVENTORY_API_SERVICE.SUB_WEAPON_BULLETS)

RegisterNetEvent("vorp_inventory:addComponent", INVENTORY_API_SERVICE.ADD_COMPONENT)
RegisterNetEvent("vorp_inventory:addComponents", INVENTORY_API_SERVICE.ADD_COMPONENTS)
RegisterNetEvent("vorp_inventory:subComponent", INVENTORY_API_SERVICE.SUB_COMPONENT)
RegisterNetEvent("vorp_inventory:subComponents", INVENTORY_API_SERVICE.SUB_COMPONENTS)
RegisterNetEvent("vorp_inventory:SetItemMetadata", INVENTORY_API_SERVICE.SET_ITEM_METADATA)
RegisterNetEvent("vorp_inventory:SetItemDurability", INVENTORY_API_SERVICE.SET_ITEM_DURABILITY)

--ammo
RegisterNetEvent("vorpinventory:recammo", AMMO_SERVICE.UPDATE_AMMO)
RegisterNetEvent("vorpinventory:loadammo", AMMO_SERVICE.LOAD_AMMO)
RegisterNetEvent("vorpinventory:weaponClipUnloaded", AMMO_SERVICE.REMOVE_BULLETS_FROM_WEAPON)
RegisterNetEvent("vorpinventory:setWeaponAmmoType", AMMO_SERVICE.SET_AMMO_TYPE_FOR_WEAPON)
RegisterNetEvent("vorpinventory:ammoUpdateToggle", AMMO_SERVICE.AMMO_TOGGLE)
