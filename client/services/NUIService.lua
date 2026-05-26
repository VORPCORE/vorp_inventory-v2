local IS_PROCESSING_PAYMENT = false
local ITEM_TIME_USE_SPAM    = 0
local CAN_USE_DROP          = true
local CAN_USE_GIVE          = true
local inCustomInventory     = false
StoreSynMenu                = false
GenSynInfo                  = {}
IS_INV_OPEN                 = false
INVENTORY_DISABLED          = false
CHARID                      = nil
SynPending                  = false

-- SYN EVENTS
RegisterNetEvent('inv:dropstatus', function(value)
	CAN_USE_DROP = value
end)

RegisterNetEvent('inv:givestatus')
AddEventHandler('inv:givestatus', function(value)
	CAN_USE_GIVE = value
end)

local function getGuidFromItemId(inventoryId, itemData, category, slotId)
	local outItem = DataView.ArrayBuffer(8 * 13)

	if not itemData then
		itemData = 0
	end
	--InventoryGetGuidFromItemid
	local success = Citizen.InvokeNative(0x886DFD3E185C8A89, inventoryId, itemData, category, slotId, outItem:Buffer())
	if success then
		return outItem:Buffer() --Seems to not return anythign diff. May need to pull from native above
	else
		return nil
	end
end

local function addWardrobeInventoryItem(itemName, slotHash)
	local itemHash    = joaat(itemName)
	local addReason   = joaat("ADD_REASON_DEFAULT")
	local inventoryId = 1

	-- _ITEMDATABASE_IS_KEY_VALID
	local isValid     = Citizen.InvokeNative(0x6D5D51B188333FD1, itemHash, 0) --ItemdatabaseIsKeyValid
	if not isValid then
		return false
	end

	local characterItem = getGuidFromItemId(inventoryId, nil, joaat("CHARACTER"), 0xA1212100)
	if not characterItem then
		return false
	end

	local wardrobeItem = getGuidFromItemId(inventoryId, characterItem, joaat("WARDROBE"), 0x3DABBFA7)
	if not wardrobeItem then
		return false
	end

	local itemData = DataView.ArrayBuffer(8 * 13)

	-- _INVENTORY_ADD_ITEM_WITH_GUID
	local isAdded = Citizen.InvokeNative(0xCB5D11F9508A928D, inventoryId, itemData:Buffer(), wardrobeItem, itemHash, slotHash, 1, addReason)
	if not isAdded then
		return false
	end

	-- _INVENTORY_EQUIP_ITEM_WITH_GUID
	local equipped = Citizen.InvokeNative(0x734311E2852760D0, inventoryId, itemData:Buffer(), true)
	return equipped;
end



local function useWeapon(data)
	data.type = data.type or "item_weapon"
	local ped = CACHE.Ped
	local weaponId = tonumber(data.id)
	local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
	if not weapon then
		return print("Weapon not found")
	end

	if not weapon:getUsed() and not weapon:getUsed2() then
		local blocked, kind, maxAllowed = INVENTORY_SERVICE.IS_WEAPON_EQUIP_BLOCKED_BY_LIMIT(weaponId, weapon:getName())
		if blocked then
			local tplLong <const> = LANG.cannotEquipMoreLongGuns
			local tplShort <const> = LANG.cannotEquipMoreShortGuns
			local msg <const> = kind == "long" and string.format(tplLong, tostring(maxAllowed)) or string.format(tplShort, tostring(maxAllowed))
			CORE.NotifyRightTip(msg, 5000)
			NUI_SERVICE.WEAPON.UPDATE_ICON(weapon:getId())
			return
		end
	end

	local weapName = joaat(weapon:getName())
	local isWeaponAGun = Citizen.InvokeNative(0x705BE297EEBDB95D, weapName)
	local isWeaponOneHanded = Citizen.InvokeNative(0xD955FEE4B87AFA07, weapName)
	local isArmed = IsPedArmed(ped, 4) == 1
	local isThrowable = IsWeaponThrowable(weapon:getName()) == 1
	local isMelee = IsWeaponMeleeWeapon(weapon:getName()) == 1

	if (isWeaponAGun and isWeaponOneHanded) and isArmed and CONFIG.DUAL_WIELD then
		addWardrobeInventoryItem("CLOTHING_ITEM_M_OFFHAND_000_TINT_004", 0xF20B6B4A)
		addWardrobeInventoryItem("UPGRADE_OFFHAND_HOLSTER", 0x39E57B01)

		weapon:equipwep()
		weapon:loadComponents()
		weapon:setUsed(true, true)
		weapon:setUsed2(true, true)
		SetTimeout(1000, function()
			weapon:setStatus()
		end)

		TriggerServerEvent("syn_weapons:weaponused", data)
		local isDual = true
		TriggerEvent("vorp_inventory:onWeaponEquipped", weapon:getAllComponents(), weaponId, weapon:getName(), isDual, weapon.defaultAttachments)
	else
		weapon:equipwep()
		if not isThrowable and not isMelee then
			weapon:loadComponents()

			SetTimeout(1000, function()
				weapon:setStatus()
			end)
		end

		weapon:setUsed(true, true)

		TriggerServerEvent("syn_weapons:weaponused", data)
		local isDual = false
		TriggerEvent("vorp_inventory:onWeaponEquipped", weapon:getAllComponents(), weaponId, weapon:getName(), isDual, weapon.defaultAttachments)
	end

	if weapon:getUsed() then
		local serial = weapon:getSerialNumber()
		local info = { weaponId = weaponId, serialNumber = serial }
		local key = string.format("GetEquippedWeaponData_%d", weapName)
		LocalPlayer.state:set(key, info, true)
	end
	TriggerServerEvent("vorpinventory:setUsedWeapon", weaponId, weapon:getUsed(), weapon:getUsed2())

	NUI_SERVICE.WEAPON.UPDATE_ICON(weapon:getId())
end

exports("useWeapon", useWeapon)

local function useItem(data)
	if ITEM_TIME_USE_SPAM == 0 then
		TriggerServerEvent("vorp_inventory:useItem", data)
		local timer = CONFIG.TIME_BETWEEN_ITEM_USE
		ITEM_TIME_USE_SPAM = 1
		SetTimeout(timer, function()
			ITEM_TIME_USE_SPAM = 0
		end)
	else
		CORE.NotifyRightTip(LANG.slow, 5000)
	end
end

exports("useItem", useItem)

local function getAmmoType(weapon)
	if not weapon then return end
	if not CACHE.Weapon then return end
	if CACHE.Weapon == `WEAPON_UNARMED` then return end

	if joaat(weapon:getName()) ~= CACHE.Weapon then
		return
	end

	local ammoTypeHash <const> = GetCurrentPedWeaponAmmoType(CACHE.Ped, GetPedWeaponObject(CACHE.Ped, true))
	return SHARED_DATA.AMMO_TYPE_HASH[ammoTypeHash]
end


local function getAttachmentSlotOrder(components)
	if not components then return end

	local order = {}
	for category, value in pairs(components) do
		order[#order + 1] = category
	end

	if #order == 0 then return end
	return order
end

local function getWeaponStats(weapon, used, used2)
	if not used and not used2 then return end
	local status <const> = weapon:getStatus()
	return {
		degradation = tonumber(status.degradation) or 0.0,
		damage = tonumber(status.damage) or 0.0,
		dirt = tonumber(status.dirt) or 0.0,
		soot = tonumber(status.soot) or 0.0,
	}
end




local nuiService = {

	INVENTORY = {

		LAYOUT_KVP_PREFIX = "vinv:mainlayout:",

		LAYOUT_KVP_KEY = function()
			if CHARID then
				return NUI_SERVICE.INVENTORY.LAYOUT_KVP_PREFIX .. CHARID
			end

			repeat Wait(100) until CHARID
			return NUI_SERVICE.INVENTORY.LAYOUT_KVP_PREFIX .. CHARID
		end,

		APPLY_SAVED_ORDER = function(items)
			local savedData <const> = GetResourceKvpString(NUI_SERVICE.INVENTORY.LAYOUT_KVP_KEY())
			if not savedData or savedData == "" then
				return items
			end

			local saved <const> = json.decode(savedData)
			if saved.slots then
				return items
			end

			local orderList <const> = saved.order or saved
			local map <const> = {}
			for _, item in ipairs(items) do
				local k <const> = tostring(item.type .. "_" .. item.id)
				map[k] = item
			end

			local used <const> = {}
			local out <const> = {}
			for _, row in ipairs(orderList) do
				local k <const> = tostring(row.type .. "_" .. row.id)
				local obj <const> = map[k]
				if obj and not used[k] then
					out[#out + 1] = obj
					used[k] = true
				end
			end

			for _, item in ipairs(items) do
				local k <const> = tostring(item.type .. "_" .. item.id)
				if not used[k] then
					out[#out + 1] = item
					used[k] = true
				end
			end

			return out
		end,

		GET_ITEMS = function()
			local items <const> = {}
			if not StoreSynMenu then
				for _, item in pairs(PLAYER_INVENTORY.ITEMS) do
					table.insert(items, item)
				end
			elseif StoreSynMenu then
				for _, item in pairs(PLAYER_INVENTORY.ITEMS) do
					if item.metadata ~= nil and item.metadata.orgdescription ~= nil then
						item.metadata.description = item.metadata.orgdescription
						item.metadata.orgdescription = nil
					end
				end

				local buyitems <const> = GenSynInfo.buyitems
				if buyitems and next(buyitems) then
					for _, item in pairs(PLAYER_INVENTORY.ITEMS) do
						for _, v in ipairs(buyitems) do
							if item.name == v.name then
								item.metadata = item.metadata or {}
								if item.metadata.orgdescription == nil then
									if item.metadata.description ~= nil then
										item.metadata.orgdescription = item.metadata.description
									else
										item.metadata.orgdescription = ""
									end
								end
								item.metadata.description = LANG.cansell .. "<span style=color:Green;>" .. v.price .. "</span>"
							end
						end
						table.insert(items, item)
					end
				else
					for _, item in pairs(PLAYER_INVENTORY.ITEMS) do
						table.insert(items, item)
					end
				end
			end
			return items
		end,

		GET_WEAPONS = function()
			local weapons <const> = {}
			for _, currentWeapon in pairs(PLAYER_INVENTORY.WEAPONS) do
				local weapon <const> = {}
				weapon.count = 1
				weapon.limit = -1
				weapon.label = currentWeapon:getLabel()
				weapon.name = currentWeapon:getName()
				weapon.ammo = currentWeapon:getAllAmmo()
				weapon.components = currentWeapon:getAllComponents()
				weapon.hash = GetHashKey(currentWeapon:getName())
				weapon.type = "item_weapon"
				weapon.canUse = true
				weapon.canRemove = true
				weapon.id = currentWeapon:getId()
				weapon.used = currentWeapon:getUsed()
				weapon.used2 = currentWeapon:getUsed2()
				weapon.desc = currentWeapon:getDesc()
				weapon.group = 5
				weapon.serial_number = currentWeapon:getSerialNumber()
				weapon.custom_label = currentWeapon:getCustomLabel()
				weapon.custom_desc = currentWeapon:getCustomDesc()
				weapon.weight = currentWeapon:getWeight()
				weapon.defaultClipSize = currentWeapon:getDefaultClipSize()
				weapon.current_ammo_type = getAmmoType(currentWeapon)
				weapon.componentCategoryCount = currentWeapon:getComponentCategoryCount()
				local weaponComps <const> = SHARED_DATA.WEAPONS[weapon.name]?.Components
				weapon.attachmentComponents = weaponComps
				weapon.attachmentSlotOrder = getAttachmentSlotOrder(weaponComps)
				weapon.canDegrade = currentWeapon.canDegrade
				weapon.weaponLiveStatus = getWeaponStats(currentWeapon, weapon.used, weapon.used2)
				weapon.ammoAllowed = AMMO_SERVICE.GET_ALLOWED_AMMO_TYPES(currentWeapon:getId())
				weapons[#weapons + 1] = weapon
			end
			return weapons
		end,

		GET_ITEMS_AND_WEAPONS = function()
			local itemsToSend <const> = {}
			local items <const> = NUI_SERVICE.INVENTORY.GET_ITEMS()
			local weapons <const> = NUI_SERVICE.INVENTORY.GET_WEAPONS()

			if CONFIG.INV_ORDER == "items" then
				for _, item in pairs(items) do
					table.insert(itemsToSend, item)
				end
				for _, weapon in pairs(weapons) do
					table.insert(itemsToSend, weapon)
				end
			else
				for _, weapon in pairs(weapons) do
					table.insert(itemsToSend, weapon)
				end
				for _, item in pairs(items) do
					table.insert(itemsToSend, item)
				end
			end

			return itemsToSend
		end,

		LOAD_ASYNC = function()
			SetTimeout(100, function()
				NUI_SERVICE.INVENTORY.GET_LOAD()
			end)
		end,

		OPEN = function()
			UTILS.APPLY_POSFX()
			DisplayRadar(false)
			local sound <const> = CONFIG.SFX.OPEN_INVENTORY
			if sound.ENABLE then
				PlaySoundFrontend(sound.NAME, sound.REF, true, 0)
			end

			SetNuiFocus(true, true)
			SendNUIMessage({
				action = "display",
				type = "main",
				search = CONFIG.INVENTORY_UI.SEARCH_BAR.ENABLE,
				autofocus = CONFIG.INVENTORY_UI.SEARCH_BAR.FOCUS,
				IsOnMount = GetMount(CACHE.Ped) > 0,
			})
			IS_INV_OPEN = true
			NUI_SERVICE.INVENTORY.GET_LOAD()
		end,
		RELOAD = function(inventory, packed)
			local payload = {}
			if packed then
				payload = msgpack.unpack(packed)
			else
				payload = json.decode(inventory)
			end

			if payload.itemList == '[]' then
				payload.itemList = {}
			end

			for _, item in pairs(payload.itemList) do
				if item.type == "item_weapon" then
					item.label = item.custom_label or UTILS.WEAPONS.GET_DEFAULT_LABEL(item.name)

					if item.desc and item.custom_desc then
						item.desc = item.custom_desc
					end

					if not item.desc then
						item.desc = UTILS.WEAPONS.GET_DEFAULT_DESC(item.name)
					end

					local weaponComps <const> = SHARED_DATA.WEAPONS[item.name]?.Components
					item.attachmentComponents = weaponComps
					item.attachmentSlotOrder = getAttachmentSlotOrder(weaponComps)
					local wid <const> = tonumber(item.id)
					local weapon = PLAYER_INVENTORY.WEAPONS[wid]
					if weapon then
						item.current_ammo_type = getAmmoType(weapon)
						item.componentCategoryCount = weapon:getComponentCategoryCount()
						item.canDegrade = weapon.canDegrade
						item.weaponLiveStatus = getWeaponStats(weapon, weapon:getUsed(), weapon:getUsed2())
					end
				else
					if not item.desc then
						if not CLIENT_ITEMS[item.name] then
							print("Item,", item.name, " no longer exist did you delete from database? or name was modified?")
						else
							item.desc = CLIENT_ITEMS[item.name].desc
						end
					end
				end
			end

			SendNUIMessage(payload)
			Wait(500)
			NUI_SERVICE.INVENTORY.GET_LOAD()
			SynPending = false
		end,

		OPEN_SECONDARY = function(name, id, capacity, weight)
			inCustomInventory = true
			UTILS.APPLY_POSFX()
			DisplayRadar(false)
			SetNuiFocus(true, true)
			SendNUIMessage({
				action = "display",
				type = "custom",
				title = tostring(name),
				id = tostring(id),
				capacity = capacity,
				weight = weight,
			})
			IS_INV_OPEN = true
		end,

		MOVE_TO_SECONDARY = function(obj)
			TriggerServerEvent("vorp_inventory:MoveToCustom", json.encode(obj))
		end,

		TAKE_FROM_SECONDARY = function(obj)
			TriggerServerEvent("vorp_inventory:TakeFromCustom", json.encode(obj))
		end,

		OPEN_PLAYER = function(name, id, type)
			UTILS.APPLY_POSFX()
			DisplayRadar(false)
			SetNuiFocus(true, true)
			SendNUIMessage({
				action = "display",
				type = type,
				title = name,
				id = id,
			})
			IS_INV_OPEN = true
		end,

		MOVE_TO_PLAYER = function(obj)
			TriggerServerEvent("vorp_inventory:MoveToPlayer", json.encode(obj))
		end,

		TAKE_FROM_PLAYER = function(obj)
			TriggerServerEvent("vorp_inventory:TakeFromPlayer", json.encode(obj))
		end,

		TRANSFER_EXCEEDED = function(maxValue)
			local message = string.format(LANG.MaxItemTransfer, maxValue.max)
			CORE.NotifyRightTip(message, 4000)
		end,

		CLOSE = function()
			local filter <const> = CONFIG.INVENTORY_UI.BACKGROUND_FILTER
			if filter.ENABLE then
				AnimpostfxStop(filter.FILTER)
			end
			if StoreSynMenu then
				StoreSynMenu = false
				GenSynInfo = {}
				for _, item in pairs(PLAYER_INVENTORY.ITEMS) do
					if item.metadata ~= nil and item.metadata.description ~= nil and (item.metadata.orgdescription ~= nil or item.metadata.orgdescription == "") then
						if item.metadata.orgdescription == "" then
							item.metadata.description = nil
						else
							item.metadata.description = item.metadata.orgdescription
						end
						item.metadata.orgdescription = nil
					end
				end
			end

			DisplayRadar(true)
			SetNuiFocus(false, false)
			SendNUIMessage({ action = "hide" })
			IS_INV_OPEN = false
			TriggerEvent("vorp_stables:setClosedInv", false)
			TriggerEvent("syn:closeinv")
			if inCustomInventory then
				inCustomInventory = false
				TriggerServerEvent("vorp_inventory:Server:CloseCustomInventory")
			end
		end,

		PROCESSING_PAYMENT = function()
			IS_PROCESSING_PAYMENT = false
		end,

		SAVE_LAYOUT = function(data, cb)
			cb("ok")

			if data.slots then
				local slotCount <const> = tonumber(data.slotCount) or #data.slots
				SetResourceKvp(NUI_SERVICE.INVENTORY.LAYOUT_KVP_KEY(), json.encode({ slots = data.slots, slotCount = slotCount }))
			else
				SetResourceKvp(NUI_SERVICE.INVENTORY.LAYOUT_KVP_KEY(), json.encode({ order = data.order }))
			end
		end,

		UPDATE_ITEM = function(id)
			local item <const> = PLAYER_INVENTORY.ITEMS[id]
			if not item then return end
			SendNUIMessage({ action = "mainItemUpdate", item = item })
			if CONFIG.HOTBAR.ENABLE then
				NUI_SERVICE.HOTBAR.SEND_UPDATE()
			end
		end,

		UPDATE_WEAPON = function(id)
			local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
			if not weapon then return end

			SendNUIMessage({
				action = "mainItemUpdate",
				item = {
					count                  = 1,
					limit                  = -1,
					label                  = weapon:getLabel(),
					name                   = weapon:getName(),
					hash                   = GetHashKey(weapon:getName()),
					ammo                   = weapon:getAllAmmo(),
					components             = weapon:getAllComponents(),
					type                   = "item_weapon",
					canUse                 = true,
					canRemove              = true,
					id                     = weapon:getId(),
					used                   = weapon:getUsed(),
					used2                  = weapon:getUsed2(),
					desc                   = weapon:getDesc(),
					group                  = 5,
					serial_number          = weapon:getSerialNumber(),
					custom_label           = weapon:getCustomLabel(),
					custom_desc            = weapon:getCustomDesc(),
					weight                 = weapon:getWeight(),
					defaultClipSize        = weapon:getDefaultClipSize(),
					current_ammo_type      = getAmmoType(weapon),
					componentCategoryCount = weapon:getComponentCategoryCount(),
					attachmentComponents   = SHARED_DATA.WEAPONS[weapon:getName()]?.Components,
					attachmentSlotOrder    = getAttachmentSlotOrder(SHARED_DATA.WEAPONS[weapon:getName()]?.Components),
					canDegrade             = weapon.canDegrade,
					weaponLiveStatus       = getWeaponStats(weapon, weapon:getUsed(), weapon:getUsed2()),
					ammoAllowed            = AMMO_SERVICE.GET_ALLOWED_AMMO_TYPES(weapon:getId()),
				}
			})
			if CONFIG.HOTBAR.ENABLE then
				NUI_SERVICE.HOTBAR.SEND_UPDATE()
			end
		end,

		GET_LOAD = function()
			local payload <const> = {}

			CORE.Callback.TriggerAsync("vorpinventory:get_slots", function(result)
				if not result then return end

				SendNUIMessage({ action = "changecheck", check = string.format("%.1f", (result.totalInvWeight or 0)), info = string.format("%.1f", (result.slots or 0)) })
				SendNUIMessage({
					action = "updateStatusHud",
					show   = not IsRadarHidden(),
					money  = result.money,
					gold   = result.gold,
					rol    = result.rol,
					id     = GetPlayerServerId(PlayerId()),
				})
			end)

			local itemsAndWeapons = NUI_SERVICE.INVENTORY.GET_ITEMS_AND_WEAPONS()
			local savedLayout <const> = GetResourceKvpString(NUI_SERVICE.INVENTORY.LAYOUT_KVP_KEY())
			local slotsPayload = nil
			if savedLayout and savedLayout ~= "" then
				local decoded <const> = json.decode(savedLayout)
				if decoded.slots then
					slotsPayload = {
						slots = decoded.slots,
						slotCount = tonumber(decoded.slotCount) or #decoded.slots,
					}
				end
			end

			if not slotsPayload then
				itemsAndWeapons = NUI_SERVICE.INVENTORY.APPLY_SAVED_ORDER(itemsAndWeapons)
			end

			payload.action = "setItems"
			payload.itemList = itemsAndWeapons
			payload.timenow = GlobalState.TimeNow
			if slotsPayload then
				payload.slotLayout = slotsPayload.slots
				payload.slotCount = slotsPayload.slotCount
			end

			if CONFIG.HOTBAR.ENABLE then
				payload.hotbarSlots = NUI_SERVICE.HOTBAR.BUILD_SLOTS()
			end

			SendNUIMessage(payload)
			if CONFIG.HOTBAR.ENABLE then
				NUI_SERVICE.HOTBAR.SEND_UPDATE()
			end
		end,

		DISABLE = function(param)
			INVENTORY_DISABLED = param
			if IS_INV_OPEN then
				NUI_SERVICE.INVENTORY.CLOSE()
			end
		end,

		GET_GROUPS = function(_, cb)
			cb(CONFIG.ITEM_GROUPS)
		end,

		CACHE_IMAGES = function(info)
			print("cache images")
			Wait(2000)
			local unpack = msgpack.unpack(info)
			SendNUIMessage({ action = "cacheImages", info = unpack })
		end,

		CONTEXT_MENU = function(data, cb)
			cb("ok")
			if not data then return end

			if data.close then
				NUI_SERVICE.INVENTORY.CLOSE()
			end

			if data.event?.client then
				TriggerEvent(data.event.client, data.event?.arguments, data.itemid)
			elseif data.event?.server then
				TriggerServerEvent("vorpinventory:validateContextMenuEvent", data)
			end
		end,

	},

	SHARED = {

		SECONDARY = {
			ITEM_ADDED = function(itemData)
				if itemData.type == "item_weapon" then
					-- static data get it from here instead of sending data through network
					local weapon <const> = SHARED_DATA.WEAPONS[itemData.name]
					if weapon then
						itemData.limit = 1
						itemData.weight = weapon.Weight
						itemData.group = 5
						itemData.count = 1
						itemData.defaultClipSize = weapon.DefaultClipSize
						itemData.componentCategoryCount = weapon.ComponentCategoryCount
					end
				end

				if itemData.type == "item_standard" then
					-- static data get it from here instead of sending data through network
					local item <const> = CLIENT_ITEMS[itemData.name]
					if item then
						itemData.label = item.label
						itemData.limit = item.limit
						itemData.canUse = item.canUse
						itemData.canRemove = item.canRemove
						itemData.desc = item.desc
						itemData.group = item.group
						itemData.weight = item.weight
						itemData.rarity = item.rarity
						itemData.instruction = item.instruction
						itemData.maxDegradation = item.maxDegradation
						itemData.useExpired = item.useExpired
					end
				end
				SendNUIMessage({ action = "secondaryItemAdded", item = itemData })
			end,

			ITEM_REMOVED = function(id, itemType)
				SendNUIMessage({ action = "secondaryItemRemoved", id = id, itemType = itemType })
			end,

			ITEM_UPDATED = function(id, count)
				SendNUIMessage({ action = "secondaryItemUpdated", id = id, count = count })
			end,
		},

		GIVE = function(obj)
			NUI_SERVICE.INVENTORY.CLOSE()
			if not CAN_USE_GIVE then
				return CORE.NotifyRightTip(LANG.cantgivehere, 5000)
			end

			local result <const> = exports.vorp_lib:Select({
				allow_self = false,
				amount_of_players = 4,
				distance = 8.0,
				allow_in_vehicle = false,
				allow_on_horse = false
			})

			if not result then
				return CORE.NotifyRightTip(LANG.noPlayersFound, 5000)
			end

			local target = result
			if target == GetPlayerServerId(CACHE.Player) then
				return CORE.NotifyRightTip(LANG.cantgiveyourself, 5000)
			end

			local data = obj
			local data2 = data.data
			local isvalid = Validator.IsValidNuiCallback(data.hsn)

			if isvalid then
				local itemId = data2.id

				if data2.type == "item_money" then
					if IS_PROCESSING_PAYMENT then return end
					IS_PROCESSING_PAYMENT = true
					TriggerServerEvent("vorpinventory:giveMoneyToPlayer", target, tonumber(data2.count))
				elseif CONFIG.INVENTORY_UI.ADD_GOLD_ITEM and data2.type == "item_gold" then
					if IS_PROCESSING_PAYMENT then return end
					IS_PROCESSING_PAYMENT = true
					TriggerServerEvent("vorpinventory:giveGoldToPlayer", target, tonumber(data2.count))
				elseif data2.type == "item_ammo" then
					if IS_PROCESSING_PAYMENT then return end
					IS_PROCESSING_PAYMENT = true
					local amount = tonumber(data2.count)
					local ammotype = data2.item
					local maxcount = SHARED_DATA.MAX_AMMO[ammotype]
					if amount > 0 and maxcount >= amount then
						TriggerServerEvent("vorpinventory:servergiveammo", ammotype, amount, target, maxcount)
					end
				elseif data2.type == "item_standard" then
					local amount = tonumber(data2.count)
					local item = PLAYER_INVENTORY.ITEMS[itemId]

					if amount > 0 and item ~= nil and item:getCount() >= amount then
						TriggerServerEvent("vorpinventory:serverGiveItem", itemId, amount, target)
					end
				else
					TriggerServerEvent("vorpinventory:serverGiveWeapon", tonumber(itemId), target)
				end
			end
		end,

		PLACE = function(obj)
			if not CAN_USE_DROP then
				return CORE.NotifyRightTip(LANG.cantdrophere, 5000)
			end

			local data = UTILS.EXPANDO_PROCESSING(obj)
			if not Validator.IsValidNuiCallback(data.hsn) then
				return print("Invalid data")
			end

			local function isInRoad(coords)
				---@diagnostic disable-next-line: param-type-mismatch, redundant-parameter
				local _, roadpoint <const> = GetClosestRoad(coords.x, coords.y, coords.z, 0.0, 1, vector3(0, 0, 0), vector3(0, 0, 0), 0, 0, 0.0, true)
				local distance <const> = #(coords - vector3(roadpoint.x, roadpoint.y, roadpoint.z))
				if distance < 8 then
					return true
				end
				return false
			end

			NUI_SERVICE.INVENTORY.CLOSE()

			local itemName <const> = data.item
			local itemType <const> = data.type

			if itemType == "item_standard" then
				local itemProp = CONFIG.PICKUPS.DROP_MODELS[itemName]
				if not itemProp then
					itemProp = CONFIG.PICKUPS.DROP_MODELS.default_box
				end

				if not UTILS.LOAD_MODEL(itemProp) then
					return print("Failed to load model", itemProp)
				end
				-- close inventory

				local offset <const> = GetOffsetFromEntityInWorldCoords(CACHE.Ped, 0, 1.0, 0)
				local object <const> = CreateObject(itemProp, offset.x, offset.y, offset.z, false, false, false)
				PlaceObjectOnGroundProperly(object, true)
				SetEntityAlpha(object, 200, true)
				local objectPositionData = exports.vorp_lib:StartGizmo(object, false, false, false, true)
				DeleteEntity(object)
				if not objectPositionData then return print("Failed to get object position data") end

				if isInRoad(objectPositionData.position) then
					return CORE.NotifyRightTip(LANG.cannotDropNearRoads, 5000)
				end

				data.advanced = objectPositionData
				NUI_SERVICE.ITEM.DROP(data, true)
			elseif itemType == "item_weapon" then
				local weaponName <const> = itemName
				if not SHARED_DATA.WEAPONS[weaponName] then
					print("Weapon not found in shared data, dropping weapon as standard item weapon:", weaponName)
					return NUI_SERVICE.WEAPON.DROP(data, true)
				end

				local objectPositionData = nil
				local offset <const> = GetOffsetFromEntityInWorldCoords(CACHE.Ped, 0, 1.0, 0)
				if not CONFIG.PICKUPS.USE_WEAPON_MODELS then
					local itemProp <const> = CONFIG.PICKUPS.DROP_MODELS.default_box
					if not UTILS.LOAD_MODEL(itemProp) then
						return print("Failed to load model")
					end
					local object <const> = CreateObject(itemProp, offset.x, offset.y, offset.z, false, false, false)
					PlaceObjectOnGroundProperly(object, true)
					SetEntityAlpha(object, 200, true)
					objectPositionData = exports.vorp_lib:StartGizmo(object, false, false, false, true)
					DeleteEntity(object)
					if not objectPositionData then return print("Failed to get object position data") end
				else
					if not Citizen.InvokeNative(0xFF07CF465F48B830, joaat(weaponName)) then
						Citizen.InvokeNative(0x72D4CB5DB927009C, joaat(weaponName), 1, true) -- request weapon asset
						repeat Wait(0) until Citizen.InvokeNative(0xFF07CF465F48B830, joaat(weaponName))
					end
					local object <const> = CreateWeaponObject(joaat(weaponName), 0, offset.x, offset.y, offset.z, true, 1.0)
					if object == 0 then return print("Failed to create weapon object object pool full?") end

					PlaceObjectOnGroundProperly(object, true)
					SetPickupLight(object, true)
					SetEntityVisible(object, true)
					if CONFIG.PICKUPS.WEAPON_ADJUSTMENTS[weaponName] then
						SetEntityRotation(object, CONFIG.PICKUPS.WEAPON_ADJUSTMENTS[weaponName], 0.0, 0.0, 0, true)
					end

					SetEntityCollision(object, false, false)
					SetEntityInvincible(object, true)
					SetEntityProofs(object, 1, true)
					FreezeEntityPosition(object, true)

					-- we need to use the same thing we use in pickup services
					objectPositionData = exports.vorp_lib:StartGizmo(object, false, false, false, true)
					DeleteEntity(object)
					if not objectPositionData then return end
				end


				if objectPositionData and isInRoad(objectPositionData.position) then
					return CORE.NotifyRightTip(LANG.cannotDropNearRoads, 5000)
				end

				data.advanced = objectPositionData
				NUI_SERVICE.WEAPON.DROP(data, true)
			elseif itemType == "item_money" or itemType == "item_gold" or itemType == "item_rol" then
				local quantity <const> = tonumber(data.number)
				if not quantity or quantity <= 0 then
					return
				end

				local modelKey <const> = itemType == "item_money" and "money_bag" or itemType == "item_gold" and "gold_bag" or "rol_bag"
				local model <const> = CONFIG.PICKUPS.DROP_MODELS[modelKey] or CONFIG.PICKUPS.DROP_MODELS.default_box

				if not UTILS.LOAD_MODEL(model) then
					return print("Failed to load pickup model", model)
				end

				local offset <const> = GetOffsetFromEntityInWorldCoords(CACHE.Ped, 0, 1.0, 0)
				local object <const> = CreateObject(model, offset.x, offset.y, offset.z, false, false, false, false)
				PlaceObjectOnGroundProperly(object, true)

				local objectPositionData <const> = exports.vorp_lib:StartGizmo(object, false, false, false, true)
				DeleteEntity(object)
				SetModelAsNoLongerNeeded(model)

				if not objectPositionData then
					return print("Failed to get object position data (currency)")
				end

				if isInRoad(objectPositionData.position) then
					return CORE.NotifyRightTip(LANG.cannotDropNearRoads, 5000)
				end

				data.advanced = objectPositionData
				if itemType == "item_money" then
					NUI_SERVICE.CURRENCY.DROP_MONEY(data, true)
				elseif itemType == "item_gold" then
					NUI_SERVICE.CURRENCY.DROP_GOLD(data, true)
				elseif itemType == "item_rol" then
					NUI_SERVICE.CURRENCY.DROP_ROLL(data, true)
				end
			end
		end,

		USE = function(obj)
			if obj.type == "item_standard" then
				useItem(obj)
			elseif obj.type == "item_weapon" then
				useWeapon(obj)
			end
		end,
		REMOVE = function(id, itemType)
			SendNUIMessage({ action = "mainItemRemoved", id = id, itemType = itemType })
			if CONFIG.HOTBAR.ENABLE then
				NUI_SERVICE.HOTBAR.SEND_UPDATE()
			end
		end,

		SEND_LANG = function()
			SendNUIMessage({
				action = "initiate",
				hotbarPos = CONFIG.HOTBAR.ENABLE and NUI_SERVICE.HOTBAR.LOAD_POSITION() or nil,
				language = {
					empty = LANG.emptyammo,
					prompttitle = LANG.prompttitle,
					prompttitle2 = LANG.prompttitle2,
					promptaccept = LANG.promptaccept,
					inventoryclose = LANG.inventoryclose,
					inventorysearch = LANG.inventorysearch,
					toplayerpromptitle = LANG.toplayerpromptitle,
					toplaterpromptaccept = LANG.toplaterpromptaccept,
					gunbeltlabel = LANG.gunbeltlabel,
					gunbeltdescription = LANG.gunbeltdescription,
					inventorymoneylabel = LANG.inventorymoneylabel,
					inventorymoneydescription = LANG.inventorymoneydescription,
					givemoney = LANG.givemoney,
					dropmoney = LANG.dropmoney,
					inventorygoldlabel = LANG.inventorygoldlabel,
					inventorygolddescription = LANG.inventorygolddescription,
					givegold = LANG.givegold,
					dropgold = LANG.dropgold,
					inventoryrolllabel = LANG.inventoryrolllabel,
					inventoryrolldescription = LANG.inventoryrolldescription,
					giveroll = LANG.giveroll,
					droproll = LANG.droproll,
					dropallroll = LANG.dropallroll,
					unequip = LANG.unequip,
					equip = LANG.equip,
					use = LANG.use,
					give = LANG.give,
					drop = LANG.drop,
					dropall = LANG.dropall,
					contextgiveamount = LANG.contextgiveamount,
					contextgiveall = LANG.contextgiveall,
					contextgivequick = LANG.contextgivequick,
					contextdropamount = LANG.contextdropamount,
					contextdropall = LANG.contextdropall,
					contextdropadvanced = LANG.contextdropadvanced,
					contextdropquick = LANG.contextdropquick,
					contextmenuactions = LANG.contextmenuactions,
					invdropzonehint = LANG.invdropzonehint,
					dropallmoney = LANG.dropallmoney,
					dropallgold = LANG.dropallgold,
					copyserial = LANG.copyserial,
					inspectweapon = LANG.inspectweapon,
					removebullets = LANG.removebullets,
					reloadweapon = LANG.reloadweapon,
					addweapontammotype = LANG.addweapontammotype,
					addweapontammotypeempty = LANG.addweapontammotypeempty,
					attachmentsPartsTitle = LANG.attachmentsPartsTitle,
					attachmentsTitle = LANG.attachmentsTitle,
					attachmentsFooterHint = LANG.attachmentsFooterHint,
					labels = LANG.labels,
				},
				config = {
					UseGoldItem = CONFIG.INVENTORY_UI.ADD_GOLD_ITEM,
					AddGoldItem = CONFIG.INVENTORY_UI.ADD_GOLD_ITEM,
					AddDollarItem = true,
					AddAmmoItem = true,
					UseRolItem = CONFIG.INVENTORY_UI.ADD_ROLL_ITEM,
					AddRollItem = CONFIG.INVENTORY_UI.ADD_ROLL_ITEM,
					WeightMeasure = CONFIG.INVENTORY_UI.WEIGHT_MEASURE,
					EnableHotbar = CONFIG.HOTBAR.ENABLE,
					HotbarAllow = CONFIG.HOTBAR.ALLOW,
					ItemRaritySlotStyle = CONFIG.INVENTORY_UI.ITEM_RARITY_SLOT_STYLE,
					TooltipPlacement = CONFIG.INVENTORY_UI.TOOLTIP_PLACEMENT,
					EnableHandCraftButton = CONFIG.INVENTORY_UI.HAND_CRAFT_BUTTON,
					EnableSaddleButton = CONFIG.INVENTORY_UI.SADDLE_BUTTON,
					MainInventoryFixedSlotCount = CONFIG.INVENTORY_UI.MAIN_INVENTORY_FIXED_SLOT_COUNT,
					EnableWeaponAttachments = CONFIG.INVENTORY_UI.USE_WEAPON_COMPONENTS,
				}
			})
		end,
	},

	WEAPON = {

		REMOVE_COMPONENT = function(data, cb)
			cb("ok")

			local result = CORE.Callback.TriggerAwait("vorp_inventory:callback:RemoveWeaponComponent", data)
			if not result then return print("Failed to remove weapon component") end

			local weapon <const> = PLAYER_INVENTORY.WEAPONS[tonumber(data.id)]
			if not weapon then return end
			weapon:removeComponent(data.component, data.slotCategory)
			NUI_SERVICE.INVENTORY.UPDATE_WEAPON(tonumber(data.id))
		end,

		ADD_COMPONENT = function(data, cb)
			cb("ok")
			local result = CORE.Callback.TriggerAwait("vorp_inventory:callback:AddWeaponComponent", data)
			if not result then return print("Failed to add weapon component") end

			local weapon <const> = PLAYER_INVENTORY.WEAPONS[tonumber(data.id)]
			if not weapon then return end

			weapon:addComponent(data.component, data.slotCategory)
			NUI_SERVICE.INVENTORY.UPDATE_WEAPON(tonumber(data.id))
		end,

		UPDATE_ICON = function(id)
			local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
			if not weapon then return end
			SendNUIMessage({
				action           = "weaponUsedUpdate",
				id               = weapon:getId(),
				type             = "item_weapon",
				used             = weapon:getUsed(),
				used2            = weapon:getUsed2(),
				weaponLiveStatus = getWeaponStats(weapon, weapon:getUsed(), weapon:getUsed2()),
			})
			if CONFIG.HOTBAR.ENABLE then
				NUI_SERVICE.HOTBAR.SEND_UPDATE()
			end
		end,
		UNEQUIP = function(obj)
			local data = obj
			local weapon <const> = PLAYER_INVENTORY.WEAPONS[tonumber(data.id)]
			if not weapon then return print("Weapon not found") end

			weapon:UnequipWeapon()
			NUI_SERVICE.WEAPON.UPDATE_ICON(weapon:getId())
		end,

		DROP = function(obj, skip)
			if not CAN_USE_DROP then
				return CORE.NotifyRightTip(LANG.cantdrophere, 5000)
			end

			local data = obj
			if not skip then
				data = UTILS.EXPANDO_PROCESSING(obj)
				if not Validator.IsValidNuiCallback(data.hsn) then
					return
				end
			end

			local weapon <const> = PLAYER_INVENTORY.WEAPONS[data.id]
			if not weapon then return print("Weapon not found") end
			local weaponName <const> = weapon:getName()
			local playerPed <const> = CACHE.Ped
			local dropData = {}
			local index <const> = PICKUP_SERVICE.GET_UNIQUE_ID()
			if not data.advanced then
				local coords <const>  = GetEntityCoords(playerPed, true, true)
				local forward <const> = GetEntityForwardVector(playerPed)
				local position        = vector3(coords.x + forward.x * 1.6, coords.y + forward.y * 1.6, coords.z + forward.z * 1.6)
				position              = UTILS.GET_RANDOM_POSITION_AROUND(position, 1)
				dropData              = { name = weaponName, obj = index, amount = 1, isItem = 0, position = position, id = data.id }
			else
				dropData = { name = weaponName, obj = index, amount = 1, isItem = 0, position = data.advanced.position, rotation = data.advanced.rotation, id = data.id }
			end

			local result <const> = CORE.Callback.TriggerAwait("vorp_inventory:callback:DropWeapon", dropData)
			if not result then return end

			if weapon:getUsed() then
				weapon:setUsed(false, true)
				weapon:UnequipWeapon()
			end

			PLAYER_INVENTORY.WEAPONS[dropData.id] = nil

			UTILS.PLAY_ANIM(CONFIG.PICKUPS.ANIMATIONS.DROP.Weapon)

			Wait(1000)
			local sound <const> = CONFIG.SFX.ITEM_DROP
			if sound.ENABLE then
				PlaySoundFrontend(sound.NAME, sound.REF, true, 0)
			end

			NUI_SERVICE.INVENTORY.LOAD_ASYNC()
		end,

		INSPECT = function(data, cb)
			cb("ok")

			if not CONFIG.USE_WEAPON_DEGRADATION then
				return
			end

			local weapon <const> = PLAYER_INVENTORY.WEAPONS[tonumber(data.id)]
			if not weapon then return print("Weapon not found") end
			local function getWeaponStatus(weaponHash)
				local emptyStruct = DataView.ArrayBuffer(256)

				local charStruct = DataView.ArrayBuffer(256)
				Citizen.InvokeNative(0x886DFD3E185C8A89, 1, emptyStruct:Buffer(), joaat('CHARACTER'), -1591664384, charStruct:Buffer())

				local unkStruct = DataView.ArrayBuffer(256)
				Citizen.InvokeNative(0x886DFD3E185C8A89, 1, charStruct:Buffer(), 923904168, -740156546, unkStruct:Buffer())

				local weaponStruct = DataView.ArrayBuffer(256)
				Citizen.InvokeNative(0x886DFD3E185C8A89, 1, unkStruct:Buffer(), weaponHash, -1591664384, weaponStruct:Buffer())
				return weaponStruct:Buffer()
			end

			local function getWeaponObjectLabel(weaponHash, weaponObject)
				local degradation = GetWeaponPermanentDegradation(weaponObject)
				local weaponName = weapon:getName()

				if degradation > 0.0 then
					weaponName = GetWeaponNameWithPermanentDegradation(weaponHash, degradation)
				end

				return GetHashKey(weaponName)
			end

			local function getWeaponObjectText(weaponObject)
				local degradation = GetWeaponDegradation(weaponObject)
				local permDegradation = GetWeaponPermanentDegradation(weaponObject)

				if degradation == 0.0 then
					return GetStringFromHashKey(1803343570)
				elseif permDegradation > 0.0 and degradation == permDegradation then
					return GetStringFromHashKey(-1933427003)
				end

				return GetStringFromHashKey(-54957657)
			end

			local function updateDataBinding(databind, weaponHash, weaponObject)
				local itemLabel = getWeaponObjectLabel(weaponHash, weaponObject)
				local tipText = getWeaponObjectText(weaponObject)
				Citizen.InvokeNative(0x951847CEF3D829FF, databind.status, getWeaponStatus(weaponHash), CACHE.Ped)
				DatabindingWriteDataHashString(databind.itemLabel, itemLabel)
				DatabindingWriteDataString(databind.tipText, tipText)
			end

			local function setUpDatabinding(weaponHash, weaponObject)
				local itemLabel = getWeaponObjectLabel(weaponHash, weaponObject)
				local tipText = getWeaponObjectText(weaponObject)

				local flowblock = UiflowblockRequest(`PM_FLOW_WEAPON_INSPECT`)
				local databind = {}
				databind.container = DatabindingAddDataContainerFromPath("", "ItemInspection")
				databind.visible = DatabindingAddDataBool(databind.container, "Visible", false)
				databind.status = Citizen.InvokeNative(0x46DB71883EE9D5AF, databind.container, 'stats', getWeaponStatus(weaponHash), CACHE.Ped)
				databind.itemLabel = DatabindingAddDataHash(databind.container, "itemLabel", itemLabel)
				databind.tipText = DatabindingAddDataString(databind.container, "tipText", tipText)

				EnableHudContext(-1847602092)
				repeat Wait(0) until UiflowblockIsLoaded(flowblock) == 1

				UiflowblockEnter(flowblock, 0)
				if UiStateMachineExists(-813354801) == 0 then
					UiStateMachineCreate(-813354801, flowblock)
				end

				return databind
			end

			NUI_SERVICE.INVENTORY.CLOSE()
			local startCleaning = false
			if not weapon:getUsed() then
				return CORE.NotifyRightTip(LANG.mustBeEquippedToInspect, 5000)
			end

			if CACHE.Weapon == `WEAPON_UNARMED` or CACHE.Weapon ~= joaat(weapon:getName()) then
				SetCurrentPedWeapon(CACHE.Ped, joaat(weapon:getName()), false, 0, false, false)
				Wait(1000)
			end

			local weaponHash <const> = joaat(weapon:getName())
			local weaponStatus = weapon:getStatus()

			local weaponObject <const> = GetPedWeaponObject(CACHE.Ped, true)
			if not DoesEntityExist(weaponObject) then
				return print("Weapon object not found")
			end

			local isAGun = IsWeaponAGun(weaponHash) == 1
			local isTwoHanded = IsWeaponTwoHanded(weaponHash) == 1

			local itemInteractionState = nil
			if isAGun and isTwoHanded then
				itemInteractionState = `LONGARM_HOLD_ENTER`
			end

			if isAGun and not isTwoHanded then
				itemInteractionState = `SHORTARM_HOLD_ENTER`
			end

			if not itemInteractionState then
				return print("Invalid weapon state")
			end

			TaskItemInteraction_2(CACHE.Ped, weaponHash, weaponObject, 0, itemInteractionState, 0, 0, 0.0)
			repeat Wait(0) until IsPedRunningInspectionTask(CACHE.Ped) ~= 0

			SetPedBlackboardBool(CACHE.Ped, 'GENERIC_WEAPON_CLEAN_PROMPT_AVAILABLE', false, -1)

			local databind <const> = setUpDatabinding(weaponHash, weaponObject)
			StartAudioSceneset("weapon", "Inspect_Item_Scenes")

			local hasItem, id = PLAYER_INVENTORY:HasItem(CONFIG.CLEAN_WEAPON_ITEM)
			if weaponStatus.degradation == 1.0 then
				if not hasItem then
					CORE.NotifyRightTip(LANG.notRequiredItemToClean, 5000)
				else
					if not CONFIG.RESTORE_WEAPON_DEGRADATION then
						CORE.NotifyRightTip(LANG.cannotCleanCauseNotDegraded, 5000)
					end
				end
				SetPedBlackboardBool(CACHE.Ped, 'GENERIC_WEAPON_CLEAN_PROMPT_AVAILABLE', false, -1)
			else
				if weaponStatus.degradation ~= 0.0 and weaponStatus.soot ~= 0.0 and weaponStatus.dirt ~= 0.0 then
					SetPedBlackboardBool(CACHE.Ped, 'GENERIC_WEAPON_CLEAN_PROMPT_AVAILABLE', true, -1)
				else
					SetPedBlackboardBool(CACHE.Ped, 'GENERIC_WEAPON_CLEAN_PROMPT_AVAILABLE', false, -1)
				end
			end

			local result = false
			while true do
				local state <const> = GetItemInteractionState(CACHE.Ped)

				if state ~= 0 then
					if DatabindingReadDataBool(databind.visible) == 0 then
						if state == `LONGARM_HOLD` or state == `SHORTARM_HOLD` then
							DatabindingWriteDataBool(databind.visible, true)
						end
						DisableControlAction(0, `INPUT_NEXT_CAMERA`, false)
					end

					if (state == `LONGARM_CLEAN_ENTER` or state == `SHORTARM_CLEAN_ENTER`) and not startCleaning then
						startCleaning = true

						result = CORE.Callback.TriggerAwait("vorp_inventory:callback:cleanWeapon", { id = weapon:getId(), itemId = id })
						if not result then
							SetPedBlackboardBool(CACHE.Ped, 'GENERIC_WEAPON_CLEAN_PROMPT_AVAILABLE', false, -1)
							ClearPedTasks(CACHE.Ped)
							CORE.NotifyRightTip("You do not have the required item to clean this weapon", 5000)
							break
						end
					end

					if result then
						if (state == `LONGARM_CLEAN_EXIT` or state == `SHORTARM_CLEAN_EXIT`) and startCleaning then
							startCleaning = false
							local degradation <const> = GetWeaponPermanentDegradation(weaponObject)

							if CONFIG.RESTORE_WEAPON_DEGRADATION then
								SetWeaponDegradation(weaponObject, degradation)
							end

							SetWeaponDirt(weaponObject, 0.0, false)
							SetWeaponSoot(weaponObject, 0.0, false)
							SetWeaponDamage(weaponObject, degradation, false)
							weapon:updateStatus()
							updateDataBinding(databind, weaponHash, weaponObject)
							SetPedBlackboardBool(CACHE.Ped, 'GENERIC_WEAPON_CLEAN_PROMPT_AVAILABLE', false, -1)
						else
							local promptProgress <const> = GetItemInteractionPromptProgress(CACHE.Ped, `INPUT_CONTEXT_X`)

							if promptProgress > 0.0 then
								local degradation <const> = GetWeaponPermanentDegradation(weaponObject)
								local newDegradation <const> = ((weaponStatus.degradation + degradation) - (promptProgress * weaponStatus.degradation))
								local newDamage <const> = ((weaponStatus.damage + degradation) - (promptProgress * weaponStatus.damage))
								local newDirt <const> = (weaponStatus.dirt - (promptProgress * weaponStatus.dirt))
								local newSoot <const> = (weaponStatus.soot - (promptProgress * weaponStatus.soot))

								SetWeaponDamage(weaponObject, math.max(newDamage, 0.0), false)
								SetWeaponDirt(weaponObject, math.max(newDirt, 0.0), false)
								SetWeaponSoot(weaponObject, math.max(newSoot, 0.0), false)
								if CONFIG.RESTORE_WEAPON_DEGRADATION then
									SetWeaponDegradation(weaponObject, math.max(newDegradation, 0.0))
								end

								updateDataBinding(databind, weaponHash, weaponObject)
							end
						end
					end


					if CACHE.IsDead or IsPedRunningInspectionTask(CACHE.Ped) == 0 then
						break
					end

					if state == `LONGARM_HOLD_EXIT` or state == `SHORTARM_HOLD_EXIT` then
						break
					end
				end

				Wait(0)
			end

			StopAudioSceneset("Inspect_Item_Scenes")
			UiStateMachineDestroy(-813354801)
			DatabindingRemoveDataEntry(databind.container)
			DisableHudContext(-1847602092)
		end,
	},

	ITEM = {

		DROP = function(obj, skip)
			if not CAN_USE_DROP then
				return CORE.NotifyRightTip(LANG.cantdrophere, 5000)
			end

			local data = obj
			if not skip then
				data = UTILS.EXPANDO_PROCESSING(obj)
				if not Validator.IsValidNuiCallback(data.hsn) then
					return
				end
			end

			local itemId = data.id
			local quantity = tonumber(data.number)
			if not quantity or quantity <= 0 then
				return
			end

			local item <const> = PLAYER_INVENTORY.ITEMS[itemId]
			if not item then return end

			if quantity > item:getCount() then
				return
			end

			local playerPed <const> = CACHE.Ped
			local itemName <const> = item:getName()
			local dropData = {}
			local index <const> = PICKUP_SERVICE.GET_UNIQUE_ID()
			if not data.advanced then
				local coords <const>  = GetEntityCoords(playerPed, true, true)
				local forward <const> = GetEntityForwardVector(playerPed)
				local position        = vector3(coords.x + forward.x * 1.6, coords.y + forward.y * 1.6, coords.z + forward.z * 1.6)
				position              = UTILS.GET_RANDOM_POSITION_AROUND(position, 1)
				dropData              = { name = itemName, obj = index, amount = quantity, isItem = 1, position = position, id = itemId }
			else
				dropData = { name = itemName, obj = index, amount = quantity, isItem = 1, position = data.advanced.position, rotation = data.advanced.rotation, id = itemId }
			end

			local result = CORE.Callback.TriggerAwait("vorp_inventory:callback:DropItem", dropData)
			if not result then return end
			NUI_SERVICE.INVENTORY.LOAD_ASYNC()

			UTILS.PLAY_ANIM(CONFIG.PICKUPS.ANIMATIONS.DROP.Item)

			Wait(1000)
			local sound <const> = CONFIG.SFX.ITEM_DROP
			if sound.ENABLE then
				PlaySoundFrontend(sound.NAME, sound.REF, true, 0)
			end
		end,
	},

	HOTBAR = {

		SLOT_COUNT = 5,

		KVP_PREFIX = "vinv:hotbar:",

		POS_KVP_PREFIX = "vinv:hotbarpos:",

		GET_POS_KVP_KEY = function()
			if CHARID then
				return NUI_SERVICE.HOTBAR.POS_KVP_PREFIX .. CHARID
			end

			repeat Wait(100) until CHARID
			return NUI_SERVICE.HOTBAR.POS_KVP_PREFIX .. CHARID
		end,

		GET_KVP_KEY = function()
			if CHARID then
				return NUI_SERVICE.HOTBAR.KVP_PREFIX .. CHARID
			end

			repeat Wait(100) until CHARID
			return NUI_SERVICE.HOTBAR.KVP_PREFIX .. CHARID
		end,

		READ_SLOTS_FROM_STORAGE = function(raw)
			local n <const> = NUI_SERVICE.HOTBAR.SLOT_COUNT
			local out <const> = {}
			for i = 1, n do
				out[i] = false
			end

			if not raw or raw == "" then
				return out
			end

			local decoded <const> = json.decode(raw)
			if not decoded then return out end

			for i = 1, n do
				local slotEntry <const> = decoded[i]
				if slotEntry then
					out[i] = {
						type = slotEntry.type,
						id = tonumber(slotEntry.id)
					}
				end
			end
			return out
		end,

		GET_ALLOW_MODE = function()
			local allow <const> = CONFIG.HOTBAR.ALLOW:lower()
			if allow == "weapons" or allow == "items" then
				return allow
			end
			return "all"
		end,

		IS_TYPE_ALLOWED = function(itemType)
			local allow <const> = NUI_SERVICE.HOTBAR.GET_ALLOW_MODE()
			if allow == "weapons" then
				return itemType == "item_weapon"
			end
			if allow == "items" then
				return itemType == "item_standard"
			end
			return itemType == "item_weapon" or itemType == "item_standard"
		end,

		SLOT_STILL_VALID = function(value)
			if not value then
				return false
			end

			local id <const> = tonumber(value.id)
			if not NUI_SERVICE.HOTBAR.IS_TYPE_ALLOWED(value.type) then
				return false
			end

			if value.type == "item_weapon" then
				return PLAYER_INVENTORY.WEAPONS[id]
			end

			if value.type == "item_standard" then
				return PLAYER_INVENTORY.ITEMS[id]
			end
			return false
		end,

		GET_SLOT = function(value)
			if type(value) ~= "table" then return nil end

			local id <const> = tonumber(value.id)
			local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
			if value.type == "item_weapon" and weapon then
				local wname <const> = weapon:getName()
				local customLabel <const> = weapon:getCustomLabel()
				local customDesc <const> = weapon:getCustomDesc()
				return {
					type                   = "item_weapon",
					id                     = id,
					name                   = wname,
					hash                   = GetHashKey(wname),
					group                  = 5,
					count                  = 1,
					limit                  = -1,
					label                  = customLabel or weapon:getLabel() or UTILS.WEAPONS.GET_DEFAULT_LABEL(wname),
					desc                   = customDesc or weapon:getDesc() or UTILS.WEAPONS.GET_DEFAULT_DESC(wname),
					weight                 = weapon:getWeight(),
					ammo                   = weapon:getAllAmmo(),
					components             = weapon:getAllComponents(),
					canUse                 = true,
					canRemove              = true,
					used                   = weapon:getUsed(),
					used2                  = weapon:getUsed2(),
					custom_label           = customLabel,
					custom_desc            = customDesc,
					serial_number          = weapon:getSerialNumber(),
					defaultClipSize        = weapon:getDefaultClipSize(),
					current_ammo_type      = getAmmoType(weapon),
					componentCategoryCount = weapon:getComponentCategoryCount(),
					attachmentComponents   = SHARED_DATA.WEAPONS[wname]?.Components,
					attachmentSlotOrder    = getAttachmentSlotOrder(SHARED_DATA.WEAPONS[wname]?.Components),
					canDegrade             = weapon.canDegrade,
					weaponLiveStatus       = getWeaponStats(weapon, weapon:getUsed(), weapon:getUsed2()),
					ammoAllowed            = AMMO_SERVICE.GET_ALLOWED_AMMO_TYPES(weapon:getId()),
				}
			end

			local item <const> = PLAYER_INVENTORY.ITEMS[id]
			if value.type == "item_standard" and item then
				return {
					type           = "item_standard",
					id             = id,
					name           = item:getName(),
					label          = item:getLabel(),
					desc           = item:getDesc(),
					metadata       = item:getMetadata() or {},
					group          = item:getGroup(),
					count          = item:getCount(),
					limit          = item:getLimit(),
					weight         = item:getWeight(),
					rarity         = item:getRarity() or 1,
					durability     = item:getDurability(),
					instruction    = item:getInstruction(),
					canUse         = item:getCanUse(),
					canRemove      = item:getCanRemove(),
					dropOnDeath    = item:getDropOnDeath(),
					degradation    = item:getDegradation(),
					maxDegradation = item:getMaxDegradation(),
					percentage     = item:getCurrentPercentage(),
					useExpired     = item:canUseExpiredItem(),
				}
			end
			return nil
		end,

		LOAD_POSITION = function()
			local raw <const> = GetResourceKvpString(NUI_SERVICE.HOTBAR.GET_POS_KVP_KEY())
			if not raw or raw == "" then return end

			local pos <const> = json.decode(raw)
			if pos and pos.left and pos.top then
				return pos
			end
		end,

		VALIDATE_PERSISTED_SLOTS = function()
			local raw <const> = GetResourceKvpString(NUI_SERVICE.HOTBAR.GET_KVP_KEY())
			local stored <const> = NUI_SERVICE.HOTBAR.READ_SLOTS_FROM_STORAGE(raw)
			local changed = false
			local out <const> = {}
			local n <const> = NUI_SERVICE.HOTBAR.SLOT_COUNT
			for i = 1, n do
				local value <const> = stored[i]
				if NUI_SERVICE.HOTBAR.SLOT_STILL_VALID(value) then
					out[i] = {
						type = value.type,
						id = tonumber(value.id),
					}
				else
					if value and type(value) == "table" then
						changed = true
					end
					out[i] = false
				end
			end

			if changed then
				SetResourceKvp(NUI_SERVICE.HOTBAR.GET_KVP_KEY(), json.encode(out))
			end

			return out
		end,

		BUILD_SLOTS = function()
			local slots <const> = NUI_SERVICE.HOTBAR.VALIDATE_PERSISTED_SLOTS()
			local array <const> = {}
			local n <const> = NUI_SERVICE.HOTBAR.SLOT_COUNT
			for i = 1, n do
				local value <const> = slots[i] and NUI_SERVICE.HOTBAR.GET_SLOT(slots[i])
				if value then
					local cell <const> = { occupied = true, index = i }
					for k, v in pairs(value) do
						cell[k] = v
					end
					array[i] = cell
				else
					array[i] = { occupied = false, index = i }
				end
			end
			return array
		end,

		SEND_UPDATE = function()
			local payload <const> = NUI_SERVICE.HOTBAR.BUILD_SLOTS()
			SendNUIMessage({ action = "hotbarSync", slots = payload })
		end,

		SAVE_POSITION = function(data, cb)
			cb("ok")
			if data and data.left and data.top then
				SetResourceKvp(NUI_SERVICE.HOTBAR.GET_POS_KVP_KEY(), json.encode({ left = data.left, top = data.top }))
			end
		end,

		SAVE_LAYOUT = function(data, cb)
			cb("ok")

			local incoming <const> = {}
			local n <const> = NUI_SERVICE.HOTBAR.SLOT_COUNT
			for i = 1, n do
				incoming[i] = false
			end

			for i = 1, n do
				local slotEntry <const> = data.slots[i]
				if slotEntry then
					local nid <const> = tonumber(slotEntry.id)
					local entry <const> = {
						type = slotEntry.type,
						id = nid,
					}
					incoming[i] = NUI_SERVICE.HOTBAR.SLOT_STILL_VALID(entry) and entry or false
				end
			end

			SetResourceKvp(NUI_SERVICE.HOTBAR.GET_KVP_KEY(), json.encode(incoming))
			NUI_SERVICE.HOTBAR.SEND_UPDATE()
		end,

		SET_VISIBLE = function(show)
			if CONFIG.HOTBAR.ENABLE and show then
				NUI_SERVICE.HOTBAR.SEND_UPDATE()
			end
			SendNUIMessage({ action = "hotbarGame", visible = show })
		end,

		USE_ITEM = function(index, isHotbar)
			index = tonumber(index)
			if not index or index < 1 or index > NUI_SERVICE.HOTBAR.SLOT_COUNT then
				print("UseHotbarSlot ignored (bad index)", index)
				return
			end

			if INVENTORY_DISABLED then
				print("UseHotbarSlot ignored (inventory blocked)", index)
				return
			end

			local slots <const> = NUI_SERVICE.HOTBAR.VALIDATE_PERSISTED_SLOTS()
			local entry <const> = slots[index]
			if not entry then
				print("UseHotbarSlot empty slot", index)
				return
			end
			local itemType <const> = entry.type
			local itemId <const> = tonumber(entry.id)

			if itemType == "item_standard" then
				local item <const> = PLAYER_INVENTORY.ITEMS[itemId]
				if not item then
					print("UseHotbarSlot standard item missing in PLAYER_INVENTORY.ITEMS", itemId)
					return
				end

				NUI_SERVICE.SHARED.USE({
					item = item:getName(),
					type = "item_standard",
					amount = item:getCount(),
					id = item:getId(),
				})
			elseif itemType == "item_weapon" then
				local weapon <const> = PLAYER_INVENTORY.WEAPONS[itemId]
				if not weapon then
					print("UseHotbarSlot weapon missing in PLAYER_INVENTORY.WEAPONS", itemId)
					return
				end

				if isHotbar and CONFIG.HOTBAR.HOSTER_WEAPONS_ON_UNEQUIP then
					--if not used set used
					if not weapon:getUsed() and not weapon:getUsed2() then
						useWeapon({
							item = weapon:getName(),
							type = "item_weapon",
							id = itemId,
							hash = GetHashKey(weapon:getName())
						})
						return
					else
						local weaponInHand = CACHE.Weapon
						if weaponInHand == `WEAPON_UNARMED` then
							SetCurrentPedWeapon(CACHE.Ped, joaat(weapon:getName()), false, 0, false, false);
							return
						end

						if weaponInHand == joaat(weapon:getName()) then
							HolsterPedWeapons(CACHE.Ped, true, false, true, false);
							Wait(1000)
							SetCurrentPedWeapon(CACHE.Ped, `WEAPON_UNARMED`, false, 0, false, false);
							return
						end

						if weaponInHand ~= joaat(weapon:getName()) then
							HolsterPedWeapons(CACHE.Ped, true, false, true, false);
							Wait(500)
							local function taskStatus(task)
								local time = GetGameTimer()
								repeat
									Wait(0)
								until (GetScriptTaskStatus(CACHE.Ped, task, true) == 8) or (GetGameTimer() - time) > 3000
							end
							taskStatus(`SCRIPT_TASK_SWAP_WEAPON`)
							SetCurrentPedWeapon(CACHE.Ped, joaat(weapon:getName()), false, 0, false, false);
							TaskSwapWeapon(CACHE.Ped, 1, 1, 0, 0); -- doesnt do anything?
							return
						end
					end
				end

				if weapon:getUsed() or weapon:getUsed2() then
					NUI_SERVICE.WEAPON.UNEQUIP({ item = weapon:getName(), id = itemId })
				else
					useWeapon({
						item = weapon:getName(),
						type = "item_weapon",
						id = itemId,
						hash = GetHashKey(weapon:getName())
					})
				end
			end
		end,
	},
	CURRENCY = {
		DROP_MONEY = function(obj, skip)
			if not CAN_USE_DROP then
				return CORE.NotifyRightTip(LANG.cantdrophere, 5000)
			end

			local data = obj
			if not skip then
				data = UTILS.EXPANDO_PROCESSING(obj)
				if not Validator.IsValidNuiCallback(data.hsn) then
					return
				end
			end

			local quantity = tonumber(data.number)
			if not quantity or quantity <= 0 then
				return
			end

			local dropData = {}
			local handle <const> = PICKUP_SERVICE.GET_UNIQUE_ID()
			if not data.advanced then
				local playerPed <const> = CACHE.Ped
				local coords <const>    = GetEntityCoords(playerPed, true, true)
				local forward <const>   = GetEntityForwardVector(playerPed)
				local position          = vector3(coords.x + forward.x * 1.6, coords.y + forward.y * 1.6, coords.z + forward.z * 1.6)
				position                = UTILS.GET_RANDOM_POSITION_AROUND(position, 1)
				dropData                = { handle = handle, amount = quantity, position = position }
			else
				dropData = { handle = handle, amount = quantity, position = data.advanced.position, rotation = data.advanced.rotation }
			end

			local result <const> = CORE.Callback.TriggerAwait("vorp_inventory:callback:DropMoney", dropData)
			if not result then return end

			UTILS.PLAY_ANIM(CONFIG.PICKUPS.ANIMATIONS.DROP.Money)
			Wait(1000)
			local sound <const> = CONFIG.SFX.MONEY_DROP
			if sound.ENABLE then
				PlaySoundFrontend(sound.NAME, sound.REF, true, 0)
			end

			NUI_SERVICE.INVENTORY.LOAD_ASYNC()
		end,
		DROP_GOLD = function(obj, skip)
			if not CAN_USE_DROP then
				return CORE.NotifyRightTip(LANG.cantdrophere, 5000)
			end

			if not CONFIG.INVENTORY_UI.ADD_GOLD_ITEM then
				return
			end

			local data = obj
			if not skip then
				data = UTILS.EXPANDO_PROCESSING(obj)
				if not Validator.IsValidNuiCallback(data.hsn) then
					return
				end
			end

			local quantity = tonumber(data.number)
			if not quantity or quantity <= 0 then
				return
			end

			local dropData       = {}
			local handle <const> = PICKUP_SERVICE.GET_UNIQUE_ID()
			if not data.advanced then
				local playerPed <const> = CACHE.Ped
				local coords <const>    = GetEntityCoords(playerPed, true, true)
				local forward <const>   = GetEntityForwardVector(playerPed)
				local position          = vector3(coords.x + forward.x * 1.6, coords.y + forward.y * 1.6, coords.z + forward.z * 1.6)
				position                = UTILS.GET_RANDOM_POSITION_AROUND(position, 1)

				dropData                = { handle = handle, amount = quantity, position = position }
			else
				dropData = { handle = handle, amount = quantity, position = data.advanced.position, rotation = data.advanced.rotation }
			end

			local result <const> = CORE.Callback.TriggerAwait("vorp_inventory:callback:DropGold", dropData)
			if not result then return end

			UTILS.PLAY_ANIM(CONFIG.PICKUPS.ANIMATIONS.DROP.Gold)
			Wait(1000)
			local sound <const> = CONFIG.SFX.GOLD_DROP
			if sound.ENABLE then
				PlaySoundFrontend(sound.NAME, sound.REF, true, 0)
			end

			NUI_SERVICE.INVENTORY.LOAD_ASYNC()
		end,
		DROP_ROLL = function(obj, skip)
			if not CAN_USE_DROP then
				return CORE.NotifyRightTip(LANG.cantdrophere, 5000)
			end

			local data = obj
			if not skip then
				data = UTILS.EXPANDO_PROCESSING(obj)
				if not Validator.IsValidNuiCallback(data.hsn) then
					return
				end
			end

			local quantity = tonumber(data.number)
			if not quantity or quantity <= 0 then
				return
			end

			local dropData = {}
			local handle <const> = PICKUP_SERVICE.GET_UNIQUE_ID()
			if not data.advanced then
				local playerPed <const> = CACHE.Ped
				local coords <const>    = GetEntityCoords(playerPed, true, true)
				local forward <const>   = GetEntityForwardVector(playerPed)
				local position          = vector3(coords.x + forward.x * 1.6, coords.y + forward.y * 1.6, coords.z + forward.z * 1.6)
				position                = UTILS.GET_RANDOM_POSITION_AROUND(position, 1)
				dropData                = { handle = handle, amount = quantity, position = position }
			else
				dropData = { handle = handle, amount = quantity, position = data.advanced.position, rotation = data.advanced.rotation }
			end

			local result <const> = CORE.Callback.TriggerAwait("vorp_inventory:callback:DropRoll", dropData)
			if not result then return end

			UTILS.PLAY_ANIM(CONFIG.PICKUPS.ANIMATIONS.DROP.Roll)
			Wait(1000)
			local sound <const> = CONFIG.SFX.ROLL_DROP
			if sound.ENABLE then
				PlaySoundFrontend(sound.NAME, sound.REF, true, 0)
			end

			NUI_SERVICE.INVENTORY.LOAD_ASYNC()
		end,
	},

	SOUND = {

		PLAY = function(sound)
			local sound <const> = CONFIG.SFX.ITEM_HOVER
			if sound.ENABLE then
				PlaySoundFrontend(sound.NAME, sound.REF, true, 0)
			end
		end,

	},

	FOCUS = {
		OFF = function()
			local filter <const> = CONFIG.INVENTORY_UI.BACKGROUND_FILTER
			if filter.ENABLE then
				AnimpostfxStop(filter.FILTER)
			end
			DisplayRadar(true)
			local sound <const> = CONFIG.SFX.CLOSE_INVENTORY
			if sound.ENABLE then
				PlaySoundFrontend(sound.NAME, sound.REF, true, 0)
			end
			NUI_SERVICE.INVENTORY.CLOSE()
		end,
	},
	CRAFTING = {
		REQUEST_RECIPES = function(_, cb)
			if not CONFIG.INVENTORY_UI.HAND_CRAFT_BUTTON then
				SendNUIMessage({ action = "handCraftingRecipes", recipes = {} })
				cb("ok")
				return
			end

			local list <const> = {}
			local src <const> = CONFIG.HAND_CRAFTING
			for i = 1, #src do
				local r = src[i]
				list[#list + 1] = {
					label = r.LABEL,
					desc = r.DESC,
					needed = r.NEEDED,
					reward = r.REWARD,
				}
			end
			SendNUIMessage({ action = "handCraftingRecipes", recipes = list })
			cb("ok")
		end,
		CRAFT_ITEM = function(data, cb)
			cb("ok")
			if not CONFIG.INVENTORY_UI.HAND_CRAFT_BUTTON then
				return
			end
			local idx <const> = tonumber(data and data.recipeIndex) + 1

			if CONFIG.HAND_CRAFTING[idx] then
				local result <const> = CORE.Callback.TriggerAwait("vorp_inventory:callback:HandCrafting", idx)
				if not result then
					return
				end

				CONFIG.HAND_CRAFTING[idx].ANIM()
			end
		end,
	},

	SADDLE = {
		OPEN = function(_, cb)
			cb("ok")
			if not CONFIG.INVENTORY_UI.SADDLE_BUTTON then return end
			local mount <const> = GetMount(CACHE.Ped)
			if mount > 0 then
				local netId <const> = NetworkGetNetworkIdFromEntity(mount)
				NUI_SERVICE.INVENTORY.CLOSE()
				TriggerServerEvent("vorp_inventory:Server:SaddleOpen", netId)
			else
				CORE.NotifyObjective("You are not on a horse", 5000)
			end
		end,
	},

}



NUI_SERVICE = nuiService
