-- Inventory Service Controller
RegisterServerEvent("vorpinventory:getItemsTable", INVENTORY_SERVICE.ITEM.GET_SERVER_ITEMS)
RegisterServerEvent("vorpinventory:getInventory", INVENTORY_SERVICE.INVENTORY.GET)
RegisterServerEvent("vorpinventory:serverGiveItem", INVENTORY_SERVICE.GIVE.ITEM)
RegisterServerEvent("vorpinventory:serverGiveWeapon", INVENTORY_SERVICE.GIVE.WEAPON)
RegisterServerEvent("vorpinventory:onPickup", INVENTORY_SERVICE.PICKUP.ITEM)
RegisterServerEvent("vorpinventory:onPickupMoney", INVENTORY_SERVICE.PICKUP.MONEY)
RegisterServerEvent("vorpinventory:onPickupGold", INVENTORY_SERVICE.PICKUP.GOLD)
RegisterServerEvent("vorpinventory:onPickupRoll", INVENTORY_SERVICE.PICKUP.ROLL)
RegisterServerEvent("vorpinventory:setUsedWeapon", INVENTORY_SERVICE.WEAPON.USED)
RegisterServerEvent("vorpinventory:giveMoneyToPlayer", INVENTORY_SERVICE.GIVE.MONEY)
RegisterServerEvent("vorpinventory:giveGoldToPlayer", INVENTORY_SERVICE.GIVE.GOLD)
RegisterServerEvent("vorp_inventory:useItem", INVENTORY_SERVICE.ITEM.USE)
RegisterServerEvent("vorp_inventory:MoveToCustom", INVENTORY_SERVICE.SECONDARY.MOVE_TO)
RegisterServerEvent("vorp_inventory:TakeFromCustom", INVENTORY_SERVICE.SECONDARY.TAKE_FROM)
RegisterServerEvent("vorp_inventory:MoveToPlayer", INVENTORY_SERVICE.SECONDARY.MOVE_TO_PLAYER)
RegisterServerEvent("vorp_inventory:TakeFromPlayer", INVENTORY_SERVICE.SECONDARY.TAKE_FROM_PLAYER)
RegisterNetEvent("vorpinventory:servergiveammo", INVENTORY_SERVICE.GIVE.AMMO)
RegisterServerEvent("vorpinventory:updateammo", INVENTORY_SERVICE.AMMO.UPDATE)
RegisterServerEvent("vorpinventory:AddBulletFromWeapon", INVENTORY_SERVICE.WEAPON.ADD_BULLET)
RegisterServerEvent("vorpinventory:updateweapons", INVENTORY_SERVICE.WEAPON.UPDATE)
RegisterServerEvent("vorpinventory:weaponReloaded", INVENTORY_SERVICE.WEAPON.RELOADED)
RegisterServerEvent("vorpinventory:setWeaponAmmoType", INVENTORY_SERVICE.WEAPON.SET_AMMO_TYPE)
RegisterServerEvent("vorpinventory:saveWeaponStatus", INVENTORY_SERVICE.WEAPON.SAVE_STATUS)
RegisterNetEvent("vorp:PlayerForceRespawn", INVENTORY_SERVICE.FORCE_RESPAWN)

RegisterServerEvent("vorpinventory:dropThrowableWeapon", INVENTORY_SERVICE.DROP_THROWABLE_WEAPON)
RegisterServerEvent("vorpinventory:pickUpThrowableWeapon", INVENTORY_SERVICE.PICK_UP_THROWABLE_WEAPON)
RegisterServerEvent("vorpinventory:removeLasso", INVENTORY_SERVICE.REMOVE_LASSO)


AddEventHandler("vorp_NewCharacter", INVENTORY_SERVICE.ON_NEW_CHARACTER)


-- shared and for dev mode --
RegisterServerEvent("vorpCore:LoadAllAmmo", INVENTORY_SERVICE.AMMO.LOAD_ALL)
-------------------------

-- CALLBACKS
CORE.Callback.Register("vorp_inventory:callback:GetAmmoInfo", INVENTORY_SERVICE.AMMO.GET_INFO)
CORE.Callback.Register("vorp_inventory:callback:HandCrafting", INVENTORY_SERVICE.CRAFTING.HAND_CRAFTING)
CORE.Callback.Register("vorp_inventory:callback:DropRoll", INVENTORY_SERVICE.DROP.SHARE_ROLL)
CORE.Callback.Register("vorp_inventory:callback:DropMoney", INVENTORY_SERVICE.DROP.SHARE_MONEY)
CORE.Callback.Register("vorp_inventory:callback:DropGold", INVENTORY_SERVICE.DROP.SHARE_GOLD)
CORE.Callback.Register("vorp_inventory:callback:DropWeapon", INVENTORY_SERVICE.DROP.SHARE_WEAPON)
CORE.Callback.Register("vorp_inventory:callback:DropItem", INVENTORY_SERVICE.DROP.SHARE_ITEM)
CORE.Callback.Register("vorp_inventory:callback:AddWeaponComponent", INVENTORY_SERVICE.WEAPON.ADD_COMPONENT)
CORE.Callback.Register("vorp_inventory:callback:RemoveWeaponComponent", INVENTORY_SERVICE.WEAPON.REMOVE_COMPONENT)
CORE.Callback.Register("vorp_inventory:callback:cleanWeapon", INVENTORY_SERVICE.WEAPON.CLEAN)
