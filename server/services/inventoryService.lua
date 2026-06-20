local LIB <const>                  = Import "functions"
local LAST_SAVED_AMMO_DATA <const> = {}
LAST_SAVED_WEAPON_AMMO             = {} -- must be a global variable so we can access it from other files
LAST_SAVED_WEAPON_DATA             = {}
local BEING_ASKED <const>          = {}

--- CONTAINS THROWN WEAPONS DATA
---@type table<integer, {weaponName: string, weaponId: integer}>
local THROWN_WEAPONS <const>       = {}

--- LOCKS NEW PLAYERS FROM DOING ACTIONS
---@type table<integer, boolean>
local NEW_PLAYER <const>           = {}

--- CONTAINS PICKUPS DATA
---@type table<string, {ITEMS: table<string>, MONEY: table<string>, GOLD: table<string>, ROLL: table<string>}>
local PICKUPS <const>              = {
	ITEMS = {},
	MONEY = {},
	GOLD = {},
	ROLL = {},
}

math.randomseed(GetGameTimer())

--HELPERS
local function getCharacter(source)
	local user <const> = CORE.getUser(source)
	if not user then return end

	return user.getUsedCharacter
end

local function getSourceInfo(source)
	local character <const> = getCharacter(source)
	if not character then return end

	local charname <const> = character.firstname .. ' ' .. character.lastname
	local sourceIdentifier <const> = character.charIdentifier
	local steamname <const> = GetPlayerName(source) or ""
	return charname, sourceIdentifier, steamname
end

-- to update custom inv cache
local function updateItem(itemcrafted, value, item, charid, isExpired, id, identifier)
	local item_add <const> = ITEM:Register({
		id = itemcrafted.id,
		count = value.amount,
		limit = item:getLimit(),
		label = item:getLabel(),
		metadata = SHARED_UTILS.MERGE_TABLES(item.metadata, value.metadata or {}),
		name = value.name,
		type = "item_standard",
		canUse = item:getCanUse(),
		canRemove = item:getCanRemove(),
		owner = charid,
		desc = item:getDesc(),
		group = item:getGroup(),
		rarity = item:getRarity(),
		durability = item:getDurability(),
		instruction = item:getInstruction(),
		weight = item:getWeight(),
		maxDegradation = isExpired,
	})

	local isShared <const> = CUSTOM_INVENTORIES[id]:isShared()
	if isShared then
		local customInventory <const> = USERS_ITEMS[id]
		if not customInventory then
			return print("shared inventory does not exist with id update item " .. id)
		end

		customInventory[itemcrafted.id] = item_add
	else
		if not identifier then
			return print("inventory is not shared and you didnt pass identifier")
		end

		local customInventory <const> = USERS_ITEMS[id][identifier]
		if not customInventory then
			return print("non shared inventory does not exist for this identifier")
		end
		customInventory[itemcrafted.id] = item_add
	end
end

local function updateItemAmount(id, identifier, amount, itemcraftedid, metadata, name)
	local isShared <const> = CUSTOM_INVENTORIES[id]:isShared()
	if isShared then
		local customInventory <const> = USERS_ITEMS[id]

		if not customInventory[itemcraftedid] then
			return print("item crafted id does not exist")
		end

		customInventory[itemcraftedid].count = customInventory[itemcraftedid].count + amount
		if metadata then
			customInventory[itemcraftedid].metadata = metadata
		end
	else
		local customInventory <const> = USERS_ITEMS[id][identifier]

		if not customInventory[itemcraftedid] then
			return print("item crafted id does not exist 2")
		end

		customInventory[itemcraftedid].count = customInventory[itemcraftedid].count + amount
		if metadata then
			customInventory[itemcraftedid].metadata = metadata
		end
	end
	DB_SERVICE.ASYNC.UPDATE("UPDATE character_inventories SET amount = amount + @amount WHERE item_name = @itemname AND inventory_type = @inventory_type", { amount = amount, itemname = name, inventory_type = id })
end

local function updateItemInCustomInventory(id, identifier, itemCraftedId, _, metadata, value, item, charid, isExpired, name)
	local customInventory <const> = USERS_ITEMS[id]
	if not customInventory then
		return print("shared inventory does not exist with id " .. id)
	end


	local existingItem = nil
	if CUSTOM_INVENTORIES[id]:isShared() then
		existingItem = USERS_ITEMS[id][itemCraftedId]
	else
		if identifier then
			existingItem = USERS_ITEMS[id][identifier] and USERS_ITEMS[id][identifier][itemCraftedId]
		end
	end

	if existingItem then
		updateItemAmount(id, identifier, value.amount, itemCraftedId, metadata, name)
	else
		local dbCheck = DB_SERVICE.AWAIT.QUERY("SELECT ci.amount, ic.metadata, ic.durability FROM character_inventories ci LEFT JOIN items_crafted ic ON ic.id = ci.item_crafted_id WHERE ci.item_crafted_id = @id AND ci.inventory_type = @invType", { id = itemCraftedId, invType = id })
		if not dbCheck[1] then
			return print("[ERROR] updateItemInCustomInventory called but item doesn't exist in DB")
		end

		-- load item into cache with current amount
		local itemData = {
			name = value.name,
			amount = dbCheck[1].amount,
			metadata = json.decode(dbCheck[1].metadata) or {},
			durability = dbCheck[1].durability,
		}
		updateItem({ id = itemCraftedId }, itemData, item, charid, isExpired, id, identifier)
		updateItemAmount(id, identifier, value.amount, itemCraftedId, metadata, name)
	end
end

local function CanProceed(item, amount, sourceIdentifier, sourceName)
	if item.type == "item_weapon" then
		if not USERS_WEAPONS.default[item.id] then
			print("Player: " .. sourceName .. " is trying to add weapons to a custom inventory that he does not have, possible Cheat!!")
			return false
		end
		local weaponCount = 0
		for _, weapon in pairs(USERS_WEAPONS.default) do
			if weapon.name == item.name then
				weaponCount = weaponCount + 1
			end
		end
		if weaponCount < amount then
			print("Player: " .. sourceName .. " is trying to add ammount of weapons to a custom inventory that he does not have, possible Cheat!!")
			return false
		end
	else
		local inventory = USERS_ITEMS.default[sourceIdentifier]
		if not inventory or not inventory[item.id] then
			print("Player: " .. sourceName .. " is trying to add items to a custom inventory that he does not have, possible Cheat!!")
			return false
		end

		if inventory[item.id]:getCount() < amount then
			print("Player: " .. sourceName .. " is trying to add ammount of items to a custom inventory that he does not have, possible Cheat!!")
			return false
		end
	end

	return true
end

---@async
local function shareData(data)
	CreateThread(function()
		local uid = SV_UTILS.GENERATE_UNIQUE_ID()

		PICKUPS.ITEMS[uid] = {
			name = data.name,
			obj = data.obj,
			amount = data.amount,
			isItem = data.isItem,
			coords = data.position,
			id = data.id,
			degradation = data.degradation,
			durability = data.durability,
			metadata = data.metadata,
		}

		data.durability = nil
		data.degradation = nil
		data.uid = uid
		TriggerClientEvent("vorpInventory:sharePickupClient", -1, data, 1)

		if not CONFIG.PICKUPS.USE_TIMER then
			return
		end

		SetTimeout(CONFIG.PICKUPS.TIMER * 60000, function()
			if PICKUPS.ITEMS[uid] then
				TriggerClientEvent("vorpInventory:sharePickupClient", -1, data, 2)
				PICKUPS.ITEMS[uid] = nil
			end
		end)
	end)
end


local function HandleLimits(item, amount, target, _source, messages)
	local label = item.type == "item_weapon" and "weapons" or "items"
	if PLAYER_ITEMS_LIMIT[target] and PLAYER_ITEMS_LIMIT[target][item.type] then
		if PLAYER_ITEMS_LIMIT[target][item.type].limit >= amount then
			if PLAYER_ITEMS_LIMIT[target][item.type].limit - amount <= 0 then
				CORE.NotifyObjective(_source, LANG.limitWarning .. label .. ".", 2000)
				if PLAYER_ITEMS_LIMIT[target][item.type].timeout and not PLAYER_INV_COOL_DOWN[_source][item.type] then
					PLAYER_INV_COOL_DOWN[_source][item.type] = os.time() + PLAYER_ITEMS_LIMIT[target][item.type].timeout
				end
			end

			PLAYER_ITEMS_LIMIT[target][item.type].limit = PLAYER_ITEMS_LIMIT[target][item.type].limit - amount

			return true
		else
			CORE.NotifyObjective(_source, messages[label], 2000)
			return false
		end
	elseif PLAYER_INV_COOL_DOWN[_source] and PLAYER_INV_COOL_DOWN[_source][item.type] and os.time() < PLAYER_INV_COOL_DOWN[_source][item.type] then
		CORE.NotifyObjective(_source, messages.cooldown .. label, 2000)
		return false
	else
		return true
	end
end

local function IsItemExpired(degradation, maxDegradation)
	if not degradation or degradation <= 0 then
		return true
	end

	local maxDegradeSeconds = maxDegradation * 60
	local elapsedSeconds = os.time() - degradation

	return elapsedSeconds >= maxDegradeSeconds
end


local InventoryService <const> = {
	GIVE = {

		ASK_TO_GIVE_ITEMS = function(source, target, data)
			if BEING_ASKED[target] or BEING_ASKED[source] then
				CORE.NotifyRightTip(source, LANG.playerAlreadyBeingAsked, 5000)
				return false
			end
			BEING_ASKED[target] = true
			BEING_ASKED[source] = true

			local result <const> = CORE.Callback.TriggerAwait("vorp_inventory:callback:wantToGiveItems", target, data)

			BEING_ASKED[target] = nil
			BEING_ASKED[source] = nil
			return result
		end,

		MONEY = function(target, amount)
			local _source <const> = source
			if target == _source then
				return CORE.NotifyRightTip(_source, LANG.cantgiveyourself, 5000)
			end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then return end
			SV_UTILS.PROCESS.ADD_USER(_source)

			local sourceCharacter = getCharacter(_source)
			local targetCharacter = getCharacter(target)
			if not targetCharacter or not sourceCharacter then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			local sourceMoney <const> = sourceCharacter.money
			local charid <const> = sourceCharacter.charIdentifier
			if not INVENTORY_SERVICE.IS_NEW_PLAYER(_source, charid) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if sourceMoney < amount then
				CORE.NotifyRightTip(_source, LANG.NotEnoughMoney, 3000)
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if BEING_ASKED[target] then
				CORE.NotifyRightTip(_source, LANG.playerAlreadyBeingAsked, 5000)
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if not INVENTORY_SERVICE.GIVE.ASK_TO_GIVE_ITEMS(_source, target, { type = "item_money", amount = amount }) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			sourceCharacter = getCharacter(_source)
			targetCharacter = getCharacter(target)
			if not targetCharacter or not sourceCharacter then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if sourceMoney < amount then
				CORE.NotifyRightTip(_source, LANG.NotEnoughMoney, 3000)
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end


			sourceCharacter.removeCurrency(0, amount)
			targetCharacter.addCurrency(0, amount)
			CORE.NotifyRightTip(_source, LANG.YouPaid .. amount .. " ID: " .. target, 3000)
			CORE.NotifyRightTip(target, LANG.YouReceived .. amount .. " ID: " .. _source, 3000)


			local charname <const>, _, steamname <const> = getSourceInfo(_source)
			local charname2 <const>, _, steamname2 <const> = getSourceInfo(target)
			local title <const> = LANG.givemoney
			local description <const> = "**" .. LANG.WebHookLang.amount .. "**: `" .. amount .. "`\n **" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "` \n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "` \n**" .. LANG.to .. "** `" .. charname2 .. "`\n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname2 .. "` \n"
			local info <const> = { source = _source, name = CONFIG.LOGS.webhookname, title = title, description = description, webhook = CONFIG.LOGS.webhook, color = CONFIG.LOGS.colorgiveMoney, }
			SV_UTILS.DISCORD_LOG(info)

			SV_UTILS.PROCESS.REMOVE_USER(_source)
		end,

		GOLD = function(target, amount)
			local _source <const> = source
			if target == _source then
				return CORE.NotifyRightTip(_source, LANG.cantgiveyourself, 5000)
			end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then return end
			SV_UTILS.PROCESS.ADD_USER(_source)

			local sourceCharacter = getCharacter(_source)
			local targetCharacter = getCharacter(target)
			if not sourceCharacter or not targetCharacter then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if not INVENTORY_SERVICE.IS_NEW_PLAYER(_source, sourceCharacter.charIdentifier) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if not INVENTORY_SERVICE.IS_NEW_PLAYER(target, targetCharacter.charIdentifier) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			local sourceGold = sourceCharacter.gold
			if sourceGold < amount then
				CORE.NotifyRightTip(_source, LANG.NotEnoughGold, 3000)
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if not INVENTORY_SERVICE.GIVE.ASK_TO_GIVE_ITEMS(_source, target, { type = "item_gold", amount = amount }) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			sourceCharacter = getCharacter(_source)
			targetCharacter = getCharacter(target)
			if not sourceCharacter or not targetCharacter then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			sourceGold = sourceCharacter.gold
			if sourceGold < amount then
				CORE.NotifyRightTip(_source, LANG.NotEnoughGold, 3000)
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			sourceCharacter.removeCurrency(1, amount)
			targetCharacter.addCurrency(1, amount)
			CORE.NotifyRightTip(_source, LANG.YouPaid .. amount .. "ID: " .. target, 3000)
			CORE.NotifyRightTip(target, LANG.YouReceived .. amount .. "ID: " .. _source, 3000)

			local charname <const>, _, steamname <const> = getSourceInfo(_source)
			local charname2 <const>, _, steamname2 <const> = getSourceInfo(target)
			local title <const> = LANG.givegold
			local description = "**" .. LANG.WebHookLang.amount .. "**: `" .. amount .. "`\n **" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "` \n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "` \n**" .. LANG.to .. "** `" .. charname2 .. "`\n**" .. LANG.WebHookLang.Steamname .. " `" .. steamname2 .. "` \n**"

			local info <const> = { source = _source, name = CONFIG.LOGS.webhookname, title = title, description = description, webhook = CONFIG.LOGS.webhook, color = CONFIG.LOGS.colorgiveGold, }
			SV_UTILS.DISCORD_LOG(info)

			SV_UTILS.PROCESS.REMOVE_USER(_source)
		end,

		WEAPON = function(weaponId, target)
			local _source = source
			if target == _source then
				return CORE.NotifyRightTip(_source, LANG.cantgiveyourself, 5000)
			end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then return end
			SV_UTILS.PROCESS.ADD_USER(_source)

			if not USERS_WEAPONS.default[weaponId] then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			local character <const> = getCharacter(_source)
			if not character then return SV_UTILS.PROCESS.REMOVE_USER(_source) end
			local targetCharacter <const> = getCharacter(target)
			if not targetCharacter then return SV_UTILS.PROCESS.REMOVE_USER(_source) end
			local charid <const> = character.charIdentifier
			local targetCharId <const> = targetCharacter.charIdentifier

			if not INVENTORY_SERVICE.IS_NEW_PLAYER(_source, charid) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if not INVENTORY_SERVICE.IS_NEW_PLAYER(target, targetCharId) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			INVENTORY_SERVICE.GIVE.WEAPON_TARGET(target, weaponId, _source)
		end,

		WEAPON_TARGET = function(target, weaponId, source)
			local weapon = USERS_WEAPONS.default[weaponId]
			if not weapon then return SV_UTILS.PROCESS.REMOVE_USER(source) end

			local targetCharacter <const> = getCharacter(target)
			if not targetCharacter then return SV_UTILS.PROCESS.REMOVE_USER(source) end

			local targetIdentifier <const>                 = targetCharacter.identifier
			local targetCharId <const>                     = targetCharacter.charIdentifier
			local invCapacity <const>                      = targetCharacter.invCapacity
			local job <const>                              = targetCharacter.job

			local DefaultAmount                            = CONFIG.MAX_WEAPONS.PLAYERS
			local weaponName <const>                       = weapon:getName()
			local serialNumber                             = weapon:getSerialNumber()
			local desc                                     = weapon:getCustomDesc()
			local newWeight <const>                        = weapon:getWeight()
			local charname <const>, _, steamname <const>   = getSourceInfo(target)
			local charname2 <const>, _, steamname2 <const> = getSourceInfo(source)
			local notListed                                = false

			if not desc then
				desc = weapon:getDesc()
			end

			if CONFIG.MAX_WEAPONS.JOBS[job] then
				DefaultAmount = CONFIG.MAX_WEAPONS.JOBS[job]
			end

			if DefaultAmount ~= 0 then
				if weaponName and CONFIG.MAX_WEAPONS.WHITELIST[weaponName:upper()] then
					notListed = true
				end

				if not notListed then
					local sourceTotalWeaponCount = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(targetIdentifier, targetCharId) + 1
					if sourceTotalWeaponCount > DefaultAmount then
						CORE.NotifyRightTip(target, LANG.cantweapons, 2000)
						return SV_UTILS.PROCESS.REMOVE_USER(source)
					end
				end
			end

			local function canCarryWeapons()
				local itemsTotalWeight = INVENTORY_API.MAIN.GET_TOTAL_ITEMS_COUNT(targetIdentifier, targetCharId)
				local sourceTotalWeaponsWeight = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(targetIdentifier, targetCharId, true)
				local totalInvWeight = itemsTotalWeight + sourceTotalWeaponsWeight + newWeight
				if totalInvWeight > invCapacity then
					return false
				end
				return true
			end

			if not canCarryWeapons() then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return CORE.NotifyRightTip(source, LANG.cancarryWeapons, 2000)
			end

			if not INVENTORY_SERVICE.GIVE.ASK_TO_GIVE_ITEMS(source, target, { type = "item_weapon", weaponName = weaponName }) then
				return SV_UTILS.PROCESS.REMOVE_USER(source)
			end

			weapon = USERS_WEAPONS.default[weaponId]
			if not weapon then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return print("Player", GetPlayerName(source), "tried to give a weapon that he no longer had it possible exploit!!")
			end

			local weaponcomps <const> = weapon:getAllComponents()
			weapon:setPropietary('')

			local ammo <const>       = weapon:getAllAmmo()
			local components <const> = {}

			INVENTORY_API.MAIN.ADD_WEAPON(target, weaponName, ammo, components, weaponcomps, nil, weaponId)
			INVENTORY_API.MAIN.DELETE_WEAPON(source, weaponId)
			TriggerClientEvent("vorpCoreClient:subWeapon", source, weaponId)


			if not serialNumber or serialNumber == "" then
				serialNumber = LANG.NoSerial
			end

			local description <const> = "**" .. LANG.WebHookLang.charname .. ":** `" .. charname2 .. "`\n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname2 .. "` \n**" .. LANG.WebHookLang.give .. "**  **" .. 1 .. "** \n**" .. LANG.WebHookLang.Weapontype .. ":** `" .. weaponName .. "` \n**" .. LANG.WebHookLang.Desc .. "** `" .. (desc or "") .. "`\n **" .. LANG.WebHookLang.serialnumber .. "** `" .. serialNumber .. "`\n **" .. LANG.to .. ":** ` " .. charname .. "` \n**" .. LANG.WebHookLang.Steamname .. "** ` " .. steamname .. "` "
			SV_UTILS.DISCORD_LOG({
				source = target,
				name = CONFIG.LOGS.webhookname,
				title = LANG.WebHookLang.gavewep,
				description = description,
				webhook = CONFIG.LOGS.webhook,
				color = CONFIG.LOGS.colorgiveWep
			})
			-- notify
			CORE.NotifyRightTip(source, LANG.youGaveWeapon, 2000)
			CORE.NotifyRightTip(target, LANG.youReceivedWeapon, 2000)
			SV_UTILS.PROCESS.REMOVE_USER(source)
		end,

		ITEM = function(itemId, amount, target)
			local _source = source
			if target == _source then
				return CORE.NotifyRightTip(_source, LANG.cantgiveyourself, 5000)
			end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then
				return
			end
			SV_UTILS.PROCESS.ADD_USER(_source)

			local character <const> = getCharacter(_source)
			local targetCharacter <const> = getCharacter(target)
			if not targetCharacter or not character then return SV_UTILS.PROCESS.REMOVE_USER(_source) end

			local charid <const> = character.charIdentifier
			local targetCharId <const> = targetCharacter.charIdentifier
			local sourceInventory <const> = USERS_ITEMS.default[character.identifier]
			local targetInventory <const> = USERS_ITEMS.default[targetCharacter.identifier]

			if not INVENTORY_SERVICE.IS_NEW_PLAYER(_source, charid) or not sourceInventory or not targetInventory or not sourceInventory[itemId] then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if not INVENTORY_SERVICE.IS_NEW_PLAYER(target, targetCharId) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			local item = sourceInventory[itemId]
			local itemName = item:getName()

			local canCarryItems <const> = INVENTORY_API.MAIN.CAN_CARRY_ITEM_AMOUNT(target, amount)
			local canCarryItem <const> = INVENTORY_API.MAIN.CAN_CARRY_ITEM(target, itemName, amount)
			if not canCarryItems or not canCarryItem then
				CORE.NotifyRightTip(_source, LANG.fullInventoryGive, 2000)
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if not INVENTORY_SERVICE.GIVE.ASK_TO_GIVE_ITEMS(_source, target, { type = "item_standard", itemName = itemName, itemCount = amount }) then
				CORE.NotifyRightTip(_source, LANG.playerRejectedRequest, 5000)
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			item = sourceInventory[itemId]
			if not item then
				SV_UTILS.PROCESS.REMOVE_USER(_source)
				return print("Player", GetPlayerName(_source), "tried to give an item that he no longer had it possible exploit!!")
			end

			local itemMetadata = item:getMetadata()
			local svItem = SERVER_ITEMS[itemName]
			if not svItem or not item then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if item:getCount() < amount then
				SV_UTILS.PROCESS.REMOVE_USER(_source)
				return print("tried to give more than you have possible cheat", GetPlayerName(_source))
			end


			local function updateClient(addedItem)
				TriggerClientEvent("vorpInventory:receiveItem", target, itemName, addedItem:getId(), amount, item:getMetadata(), item:getDegradation(), item:getPercentage(), item:getDurability())
				TriggerClientEvent("vorpInventory:removeItem", _source, item:getId(), amount)

				local data = { name = itemName, count = amount, metadata = itemMetadata }
				TriggerEvent("vorp_inventory:Server:OnItemRemoved", data, _source)

				if item:getCount() - amount <= 0 then
					DB_SERVICE.DELETE.ITEM(charid, item:getId())
					sourceInventory[item:getId()] = nil
				else
					item:quitCount(amount)
					DB_SERVICE.SET.ITEM_AMOUNT(charid, item:getId(), item:getCount())
				end

				local label = svItem:getMetadata()?.label or svItem:getLabel()
				CORE.NotifyRightTip(_source, LANG.yougive .. amount .. LANG.of .. label, 2000)
				CORE.NotifyRightTip(target, LANG.youreceive .. amount .. LANG.of .. label, 2000)
			end


			local function createItem()
				local isExpired <const> = svItem:getMaxDegradation() ~= 0 and item:getDegradation() or nil
				DB_SERVICE.CREATE.ITEM(targetCharId, svItem:getId(), amount, item:getMetadata(), itemName, isExpired, item:getDurability(), function(craftedItem)
					local targetItem <const> = ITEM:Register({
						id = craftedItem.id,
						count = amount,
						limit = svItem:getLimit(),
						label = svItem:getLabel(),
						name = itemName,
						type = "item_standard",
						metadata = item:getMetadata(),
						canUse = svItem:getCanUse(),
						canRemove = svItem:getCanRemove(),
						owner = targetCharId,
						desc = svItem:getDesc(),
						group = svItem:getGroup(),
						rarity = svItem:getRarity(),
						durability = item:getDurability(),
						instruction = svItem:getInstruction(),
						weight = svItem:getWeight(),
						degradation = item:getDegradation(),
						percentage = item:getPercentage(),
						maxDegradation = svItem:getMaxDegradation()
					})

					targetInventory[craftedItem.id] = targetItem

					updateClient(targetItem)
					local data <const> = { name = targetItem:getName(), count = amount, metadata = targetItem:getMetadata() }
					TriggerEvent("vorp_inventory:Server:OnItemCreated", data, target)
				end)
			end

			local targetItem <const> = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA("default", targetCharacter.identifier, itemName, item:getMetadata())
			if targetItem then
				if svItem:getMaxDegradation() == 0 then
					targetItem:addCount(amount)
					DB_SERVICE.SET.ITEM_AMOUNT(targetCharId, targetItem:getId(), targetItem:getCount())
					updateClient(targetItem)
				else
					-- needs check hereif they match
					if targetItem:getPercentage() == item:getPercentage() and targetItem:getDegradation() == item:getDegradation() then
						targetItem:addCount(amount)
						DB_SERVICE.SET.ITEM_AMOUNT(targetCharId, targetItem:getId(), targetItem:getCount())
						updateClient(targetItem)
					else
						createItem()
					end
				end
			else
				createItem()
			end
			local charname, _, steamname = character.firstname .. ' ' .. character.lastname, character.identifier, GetPlayerName(_source) or ""
			local charname2, _, steamname2 = targetCharacter.firstname .. ' ' .. targetCharacter.lastname, targetCharacter.identifier, GetPlayerName(target) or ""
			local description = "**" .. LANG.WebHookLang.amount .. "**: `" .. amount .. "`\n **" .. LANG.WebHookLang.item .. "** : `" .. itemName .. "`" .. "\n**" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "` \n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "` \n**" .. LANG.to .. "** `" .. charname2 .. "`\n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname2 .. "` \n"
			SV_UTILS.DISCORD_LOG({
				source = _source,
				name = CONFIG.LOGS.webhookname,
				title = LANG.WebHookLang.gaveitem,
				description = description,
				webhook = CONFIG.LOGS.webhook,
				color = CONFIG.LOGS.colorgiveitem
			})
			SV_UTILS.PROCESS.REMOVE_USER(_source)
		end,

		AMMO = function(ammotype, amount, target, maxcount)
			local _source = source
			if target == _source then
				return CORE.NotifyRightTip(_source, LANG.cantgiveyourself, 5000)
			end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then return end
			SV_UTILS.PROCESS.ADD_USER(_source)

			local sourceCharacter <const> = getCharacter(_source)
			local targetCharacter <const> = getCharacter(target)
			if not targetCharacter or not sourceCharacter then return SV_UTILS.PROCESS.REMOVE_USER(_source) end

			local sourceCharId <const> = sourceCharacter.charIdentifier
			local targetCharId <const> = targetCharacter.charIdentifier

			if not INVENTORY_SERVICE.IS_NEW_PLAYER(_source, sourceCharId) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end
			if not INVENTORY_SERVICE.IS_NEW_PLAYER(target, targetCharId) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if not SHARED_DATA.MAX_AMMO[ammotype] then
				SV_UTILS.PROCESS.REMOVE_USER(_source)
				return print("ammotype not found :", ammotype)
			end

			if maxcount ~= SHARED_DATA.MAX_AMMO[ammotype] then
				SV_UTILS.PROCESS.REMOVE_USER(_source)
				return -- max count was modified in client side
			end

			-- check if ammount is allowed
			if amount > SHARED_DATA.MAX_AMMO[ammotype] then
				SV_UTILS.PROCESS.REMOVE_USER(_source)
				return CORE.NotifyRightTip(_source, LANG.amountGreaterThanMaxAllowed, 2000)
			end

			local userAmmoData <const> = USERS_AMMO_DATA[_source]
			local targetAmmoData <const> = USERS_AMMO_DATA[target]
			if not userAmmoData or not targetAmmoData then return SV_UTILS.PROCESS.REMOVE_USER(_source) end

			local player1ammo <const> = userAmmoData.ammo[ammotype]
			if not player1ammo then
				SV_UTILS.PROCESS.REMOVE_USER(_source)
				return CORE.NotifyRightTip(_source, LANG.noAmmoOfThisType .. ammotype, 2000)
			end

			local player2ammo = targetAmmoData.ammo[ammotype]

			if not player2ammo then
				USERS_AMMO_DATA[target].ammo[ammotype] = 0
				player2ammo = 0
			end

			if amount > player1ammo then
				CORE.NotifyRightTip(_source, LANG.notenoughammo, 2000)
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if (player2ammo + amount) > SHARED_DATA.MAX_AMMO[ammotype] then
				CORE.NotifyRightTip(_source, LANG.fullammoyou, 2000)
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			if not INVENTORY_SERVICE.GIVE.ASK_TO_GIVE_ITEMS(source, target, { type = "item_ammo", ammotype = ammotype, amount = amount }) then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			userAmmoData.ammo[ammotype] = math.max(0, player1ammo - amount)
			targetAmmoData.ammo[ammotype] = math.max(0, player2ammo + amount)
			local charidentifier <const> = userAmmoData.charidentifier
			local charidentifier2 <const> = targetAmmoData.charidentifier

			local query <const> = "UPDATE characters Set ammo=@ammo WHERE charidentifier=@charidentifier"
			local params <const> = { charidentifier = charidentifier, ammo = json.encode(userAmmoData.ammo) }
			local params2 <const> = { charidentifier = charidentifier2, ammo = json.encode(targetAmmoData.ammo) }
			DB_SERVICE.ASYNC.UPDATE(query, params)
			DB_SERVICE.ASYNC.UPDATE(query, params2)


			local setAmmoToPed = true
			local isSource = true
			TriggerClientEvent("vorpinventory:recammo", _source, userAmmoData, setAmmoToPed, isSource)
			TriggerClientEvent("vorpinventory:recammo", target, targetAmmoData, setAmmoToPed)
			SV_UTILS.PROCESS.REMOVE_USER(_source)
		end,

	},

	PICKUP = {
		ITEM = function(data)
			local _source <const> = source

			local pickup <const> = PICKUPS.ITEMS[data.uid]
			if not pickup then return print("Pickup not found") end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then
				return
			end
			SV_UTILS.PROCESS.ADD_USER(_source)

			local character <const> = getCharacter(_source)
			if not character then return SV_UTILS.PROCESS.REMOVE_USER(_source) end

			local identifier = character.identifier
			local charId <const> = character.charIdentifier
			local invCapacity <const> = character.invCapacity
			local job <const> = character.job


			if pickup.isItem == 1 then
				local canCarryWeight <const> = INVENTORY_API.MAIN.CAN_CARRY_ITEM_AMOUNT(_source, pickup.amount)
				local canCarryLimit <const> = INVENTORY_API.MAIN.CAN_CARRY_ITEM(_source, pickup.name, pickup.amount)

				if not canCarryWeight or not canCarryLimit then
					CORE.NotifyRightTip(_source, LANG.fullInventory, 2000)
					return SV_UTILS.PROCESS.REMOVE_USER(_source)
				end

				local info = { degradation = pickup.degradation, isPickup = true, durability = pickup.durability }
				INVENTORY_SERVICE.ITEM.ADD(_source, "default", pickup.name, pickup.amount, pickup.metadata, info, function(_item)
					if _item and PICKUPS.ITEMS[data.uid] then
						PICKUPS.ITEMS[data.uid] = nil

						TriggerClientEvent("vorpInventory:sharePickupClient", -1, data, 2)
						TriggerClientEvent("vorpInventory:receiveItem", _source,
							_item:getName(),
							_item:getId(),
							pickup.amount,
							_item:getMetadata(),
							_item.getDegradation(),
							_item.getPercentage(),
							_item.getDurability()
						)
						TriggerClientEvent("vorpInventory:playerAnim", _source, data.uid)
						local charname <const>    = character.firstname .. ' ' .. character.lastname
						local steamname <const>   = GetPlayerName(_source) or ""
						local description <const> = "**" .. LANG.WebHookLang.amount .. "** `" .. pickup.amount .. "`\n **" .. LANG.WebHookLang.item .. "** `" .. pickup.name .. "` \n**" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "`\n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "`"
						SV_UTILS.DISCORD_LOG({
							source = _source,
							name = CONFIG.LOGS.webhookname,
							title = LANG.itempickup,
							description = description,
							webhook = CONFIG.LOGS.webhook,
							color = CONFIG.LOGS.coloritempickup,
						})
					end
				end)
			else
				local notListed = false
				local totalInvWeight = 0
				local sourceInventoryWeaponCount = 0
				local DefaultAmount = CONFIG.MAX_WEAPONS.PLAYERS
				local weaponId <const> = PICKUPS.ITEMS[data.uid].id

				local weapon <const> = USERS_WEAPONS.default[weaponId]
				if not weapon then
					return SV_UTILS.PROCESS.REMOVE_USER(_source)
				end

				local serialNumber     = weapon:getSerialNumber()
				local weaponCustomDesc = weapon:getCustomDesc()

				if CONFIG.MAX_WEAPONS.JOBS[job] then
					DefaultAmount = CONFIG.MAX_WEAPONS.JOBS[job]
				end

				if DefaultAmount ~= 0 then
					local weaponName <const> = weapon:getName()
					if weaponName and CONFIG.MAX_WEAPONS.WHITELIST[weaponName:upper()] then
						notListed = true
					end

					if not notListed then
						local itemsToTalWeight = INVENTORY_API.MAIN.GET_TOTAL_ITEMS_COUNT(identifier, charId)
						local sourceInventoryWeaponWeight = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(identifier, charId, true)
						totalInvWeight = (itemsToTalWeight + weapon:getWeight() + sourceInventoryWeaponWeight)
						sourceInventoryWeaponCount = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(identifier, charId) + 1
					end

					if totalInvWeight <= invCapacity or sourceInventoryWeaponCount <= DefaultAmount then
						local weaponObj <const> = PICKUPS.ITEMS[data.uid].obj

						weapon:setDropped(0)

						PICKUPS.ITEMS[data.uid] = nil
						if not weaponCustomDesc then
							weaponCustomDesc = "Custom Description not set"
						end
						if not serialNumber then
							serialNumber = "Serial Number not set"
						end

						TriggerClientEvent("vorpInventory:sharePickupClient", -1, { obj = weaponObj }, 2)
						TriggerClientEvent("vorpInventory:playerAnim", _source, data.uid)
						INVENTORY_SERVICE.WEAPON.ADD(_source, weaponId)

						local charname <const>    = character.firstname .. ' ' .. character.lastname
						local steamname <const>   = GetPlayerName(_source) or ""
						local description <const> = "**" .. LANG.WebHookLang.Weapontype .. ":** `" .. weaponName .. "`\n**" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "`\n**" .. LANG.WebHookLang.serialnumber .. "** `" .. serialNumber .. "`\n **" .. LANG.WebHookLang.Desc .. "** `" .. weaponCustomDesc .. "` \n **" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "`"
						SV_UTILS.DISCORD_LOG({
							source = _source,
							name = CONFIG.LOGS.webhookname,
							title = LANG.weppickup,
							description = description,
							webhook = CONFIG.LOGS.webhook,
							color = CONFIG.LOGS.colorweppickupd
						})
					end
				else
					CORE.NotifyRightTip(_source, LANG.fullInventoryWeapon, 2000)
				end
			end

			SV_UTILS.PROCESS.REMOVE_USER(_source)
		end,

		MONEY = function(data)
			local _source = source

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then
				return
			end
			SV_UTILS.PROCESS.ADD_USER(_source)

			local money <const> = PICKUPS.MONEY[data.uuid]
			if not money then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			local character <const> = getCharacter(_source)
			if not character then return SV_UTILS.PROCESS.REMOVE_USER(_source) end

			local charname          = character.firstname .. ' ' .. character.lastname
			local steamname <const> = GetPlayerName(_source) or ""
			local description       = "**" .. LANG.WebHookLang.money .. ":** `" .. money.amount .. "` `$` \n**" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "`\n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "`\n"
			SV_UTILS.DISCORD_LOG({
				source = _source,
				name = CONFIG.LOGS.webhookname,
				title = LANG.WebHookLang.moneypickup,
				description = description,
				webhook = CONFIG.LOGS.webhook,
				color = CONFIG.LOGS.colorDropGold
			})

			TriggerClientEvent("vorpInventory:shareMoneyPickupClient", -1, data.obj, nil, nil, nil, 2)
			TriggerClientEvent("vorpInventory:playerAnim", _source, data.obj)

			character.addCurrency(0, money.amount)
			PICKUPS.MONEY[data.uuid] = nil
			SV_UTILS.PROCESS.REMOVE_USER(_source)
		end,

		GOLD = function(data)
			local _source = source
			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then
				return
			end
			SV_UTILS.PROCESS.ADD_USER(_source)

			local picup <const> = PICKUPS.GOLD[data.uuid]
			if not picup then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			local character <const> = getCharacter(_source)
			if not character then return SV_UTILS.PROCESS.REMOVE_USER(_source) end



			TriggerClientEvent("vorpInventory:shareGoldPickupClient", -1, data.obj, nil, nil, nil, 2)
			TriggerClientEvent("vorpInventory:playerAnim", _source, data.obj)

			local charname          = character.firstname .. ' ' .. character.lastname
			local steamname <const> = GetPlayerName(_source) or ""
			local description       = "**" .. LANG.WebHookLang.gold .. ":** `" .. picup.amount .. "` \n**" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "`\n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "`\n"

			character.addCurrency(1, picup.amount)
			SV_UTILS.DISCORD_LOG({
				source = _source,
				name = CONFIG.LOGS.webhookname,
				title = LANG.WebHookLang.pickedgold,
				description = description,
				webhook = CONFIG.LOGS.webhook,
				color = CONFIG.LOGS.colorpickedgold
			})
			PICKUPS.GOLD[data.uuid] = nil
			SV_UTILS.PROCESS.REMOVE_USER(_source)
		end,

		ROLL = function(data)
			local _source = source

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then
				return
			end
			SV_UTILS.PROCESS.ADD_USER(_source)

			local roll <const> = PICKUPS.ROLL[data.uuid]
			if not roll then
				return SV_UTILS.PROCESS.REMOVE_USER(_source)
			end

			local character <const> = getCharacter(_source)
			if not character then return SV_UTILS.PROCESS.REMOVE_USER(_source) end

			TriggerClientEvent("vorpInventory:shareRollPickupClient", -1, data.obj, nil, nil, nil, 2)
			TriggerClientEvent("vorpInventory:playerAnim", _source, data.obj)

			local charname          = character.firstname .. ' ' .. character.lastname
			local steamname <const> = GetPlayerName(_source) or ""
			local rolLabel <const>  = (LANG.WebHookLang and LANG.WebHookLang.roll) or "Roll"
			local description       = "**" .. rolLabel .. ":** `" .. roll.amount .. "` \n**" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "`\n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "`\n"

			character.addCurrency(2, roll.amount)
			SV_UTILS.DISCORD_LOG({
				source = _source,
				name = CONFIG.LOGS.webhookname,
				title = (LANG.WebHookLang and LANG.WebHookLang.pickedroll) or "Picked up roll",
				description = description,
				webhook = CONFIG.LOGS.webhook,
				color = CONFIG.LOGS.colorpickedgold
			})
			PICKUPS.ROLL[data.uuid] = nil
			SV_UTILS.PROCESS.REMOVE_USER(_source)
		end,

	},

	DROP = {

		WEAPON = function(source, weaponId)
			local userWeapon <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapon then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return
			end

			local sourceCharacter <const> = getCharacter(source)
			if not sourceCharacter then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return
			end

			local charId <const> = sourceCharacter.charIdentifier
			local params <const> = { charId = charId, id = weaponId, }
			DB_SERVICE.ASYNC.UPDATE('UPDATE loadout SET identifier = "", dropped = 1, charidentifier = @charId WHERE id = @id', params)
			userWeapon:setPropietary('')
			userWeapon:setDropped(1)
			return true
		end,

		SHARE_WEAPON = function(source, callback, data)
			if SV_UTILS.PROCESS.USER_IN_PROCESSING(source) then
				return callback(false)
			end
			SV_UTILS.PROCESS.ADD_USER(source)

			if data.isItem == 1 then -- 1 is item 0 is weapon
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			local weapon <const> = USERS_WEAPONS.default[data.id]
			if not weapon then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			if CONFIG.PICKUPS.DELETE_ON_DROP then
				INVENTORY_API.MAIN.DELETE_WEAPON(source, data.id)
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(true)
			else
				local result <const> = INVENTORY_SERVICE.DROP.WEAPON(source, data.id)
				if not result then
					SV_UTILS.PROCESS.REMOVE_USER(source)
					return callback(false)
				end
			end

			local serialNumber = weapon:getSerialNumber()
			local desc = weapon:getCustomDesc()
			local charname <const>, _, steamname <const> = getSourceInfo(source)
			if not desc or desc == "" then
				desc = "Custom Description not set"
			end
			if not serialNumber or serialNumber == "" then
				serialNumber = "Serial Number not set"
			end

			local description <const> = "**" .. LANG.WebHookLang.Weapontype .. ":** `" .. weapon:getName() .. "`\n**" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "`\n**" .. LANG.WebHookLang.serialnumber .. "** ` " .. serialNumber .. " ` \n **" .. LANG.WebHookLang.Desc .. "** `" .. desc .. "` \n **" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "`"
			SV_UTILS.DISCORD_LOG({
				source = source,
				name = CONFIG.LOGS.webhookname,
				title = LANG.WebHookLang.dropedwep,
				description = description,
				webhook = CONFIG.LOGS.webhook,
				color = CONFIG.LOGS.colordropedwep,
			})

			data.type = "item_weapon"
			shareData(data)
			SV_UTILS.PROCESS.REMOVE_USER(source)
			return callback(true)
		end,

		SHARE_ITEM = function(source, callback, data)
			if SV_UTILS.PROCESS.USER_IN_PROCESSING(source) then
				return callback(false)
			end
			SV_UTILS.PROCESS.ADD_USER(source)

			local character <const> = getCharacter(source)
			if not character then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			local sourceInventory <const> = USERS_ITEMS.default[character.identifier]
			if not sourceInventory then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			local item <const> = sourceInventory[data.id]
			if not item then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			if data.isItem == 0 then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			if data.amount > item:getCount() then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			local result <const> = INVENTORY_SERVICE.ITEM.REMOVE(source, "default", data.id, data.amount)
			if not result then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			if CONFIG.PICKUPS.DELETE_ON_DROP then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(true)
			end

			local charname <const> = character.firstname .. ' ' .. character.lastname
			local steamname <const> = GetPlayerName(source) or ""
			local description = "**" .. LANG.WebHookLang.amount .. "** `" .. data.amount .. "`\n **" .. LANG.WebHookLang.itemDrop .. "**: `" .. data.name .. "`" .. "\n**" .. LANG.WebHookLang.charname .. ":** `" .. charname .. "`\n**" .. LANG.WebHookLang.Steamname .. "** `" .. steamname .. "`"

			SV_UTILS.DISCORD_LOG({
				source = source,
				name = CONFIG.LOGS.webhookname,
				title = LANG.WebHookLang.itemDrop,
				description = description,
				webhook = CONFIG.LOGS.webhook,
				color = CONFIG.LOGS.coloritemDrop,
			})
			data.type = "item_standard"
			data.metadata = item:getMetadata() -- for client label name
			data.degradation = item:getDegradation()
			data.durability = item:getDurability()
			shareData(data)
			SV_UTILS.PROCESS.REMOVE_USER(source)
			return callback(true)
		end,

		SHARE_MONEY = function(source, callback, data)
			if SV_UTILS.PROCESS.USER_IN_PROCESSING(source) then
				return callback(false)
			end
			SV_UTILS.PROCESS.ADD_USER(source)

			local character <const> = getCharacter(source)
			if not character then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			if data.amount > character.money then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			character.removeCurrency(0, data.amount)
			local uid <const> = SV_UTILS.GENERATE_UNIQUE_ID()
			TriggerClientEvent("vorpInventory:shareMoneyPickupClient", -1, data.handle, data.amount, data.position, uid, 1, data.rotation)

			PICKUPS.MONEY[uid] = {
				name = LANG.inventorymoneylabel,
				obj = data.handle,
				amount = data.amount,
				coords = data.position,
				uuid = uid
			}

			if not CONFIG.PICKUPS.USE_TIMER then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(true)
			end

			SetTimeout(CONFIG.PICKUPS.TIMER * 60000, function()
				if PICKUPS.MONEY[uid] then
					TriggerClientEvent("vorpInventory:shareMoneyPickupClient", -1, PICKUPS.MONEY[uid].obj, nil, nil, nil, 2)
					PICKUPS.MONEY[uid] = nil
				end
			end)
			SV_UTILS.PROCESS.REMOVE_USER(source)
			return callback(true)
		end,

		SHARE_GOLD = function(source, callback, data)
			if SV_UTILS.PROCESS.USER_IN_PROCESSING(source) then
				return callback(false)
			end
			SV_UTILS.PROCESS.ADD_USER(source)

			local character <const> = getCharacter(source)
			if not character then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			if data.amount > character.gold then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			character.removeCurrency(1, data.amount)
			local uid <const> = SV_UTILS.GENERATE_UNIQUE_ID()
			TriggerClientEvent("vorpInventory:shareGoldPickupClient", -1, data.handle, data.amount, data.position, uid, 1, data.rotation)

			PICKUPS.GOLD[uid] = {
				name = LANG.inventorygoldlabel,
				obj = data.handle,
				amount = data.amount,
				inRange = false,
				coords = data.position,
				uuid = uid
			}

			if not CONFIG.PICKUPS.USE_TIMER then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(true)
			end

			SetTimeout(CONFIG.PICKUPS.TIMER * 60000, function()
				if PICKUPS.GOLD[uid] then
					TriggerClientEvent("vorpInventory:shareGoldPickupClient", -1, PICKUPS.GOLD[uid].obj, nil, nil, nil, 2)
					PICKUPS.GOLD[uid] = nil
				end
			end)
			SV_UTILS.PROCESS.REMOVE_USER(source)
			return callback(true)
		end,

		SHARE_ROLL = function(source, callback, data)
			if SV_UTILS.PROCESS.USER_IN_PROCESSING(source) then
				return callback(false)
			end
			SV_UTILS.PROCESS.ADD_USER(source)

			local character <const> = getCharacter(source)
			if not character then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			if data.amount > character.rol then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(false)
			end

			character.removeCurrency(2, data.amount)
			local uid <const> = SV_UTILS.GENERATE_UNIQUE_ID()
			TriggerClientEvent("vorpInventory:shareRollPickupClient", -1, data.handle, data.amount, data.position, uid, 1, data.rotation)

			PICKUPS.ROLL[uid] = {
				name = LANG.inventoryrolllabel or "Roll",
				obj = data.handle,
				amount = data.amount,
				inRange = false,
				coords = data.position,
				uuid = uid
			}

			if not CONFIG.PICKUPS.USE_TIMER then
				SV_UTILS.PROCESS.REMOVE_USER(source)
				return callback(true)
			end

			SetTimeout(CONFIG.PICKUPS.TIMER * 60000, function()
				if PICKUPS.ROLL[uid] then
					TriggerClientEvent("vorpInventory:shareRollPickupClient", -1, PICKUPS.ROLL[uid].obj, nil, nil, nil, 2)
					PICKUPS.ROLL[uid] = nil
				end
			end)
			SV_UTILS.PROCESS.REMOVE_USER(source)
			return callback(true)
		end,

	},

	ITEM = {

		USE = function(data)
			local _source <const> = source
			local sourceCharacter <const> = getCharacter(_source)
			if not sourceCharacter then return end

			local itemId <const> = data.id
			local itemName <const> = data.item
			local identifier <const> = sourceCharacter.identifier
			local userInventory <const> = USERS_ITEMS.default[identifier]

			local svItem = SV_UTILS.ITEMS.DOES_ITEM_EXIST(itemName, "UseItem")
			if not svItem then return end

			local item = userInventory[itemId]
			if not item or not USABLE_ITEMS[itemName] then return end

			local arguments <const> = {
				source = _source,
				item = {
					---@deprecated -- same as item.id
					mainid = itemId,
					--------------------------------
					item = item:getName(), -- for backwards compatibility
					metadata = item:getMetadata(),
					percentage = item:getPercentage(),
					isDegradable = item:getMaxDegradation() ~= 0,
					id = item:getId(),
					count = item:getCount(),
					label = item.metadata?.label or item:getLabel(),
					name = item:getName(),
					desc = item.metadata?.description or item:getDesc(),
					type = item:getType(),
					limit = item:getLimit(),
					group = item:getGroup(),
					rarity = item:getRarity(),
					durability = item:getDurability(),
					instruction = item:getInstruction(),
					weight = item.metadata?.weight or item:getWeight()
				}
			}

			-- if its an item that can degrade then check if its expired
			if arguments.item.isDegradable then
				local isExpired = item:isItemExpired()
				if isExpired then
					local canUseExpired = arguments.item.metadata?.useExpired or SERVER_ITEMS[itemName]?.useExpired
					if not canUseExpired then
						local text = "Item is expired and can't be used"
						if CONFIG.DELETE_ITEM_EXPIRED then
							INVENTORY_API.MAIN.SUB_ITEM_BY_ID(_source, item:getId())
							text = "Item is expired and can't be used, item was removed from your inventory"
						end
						CORE.NotifyRightTip(_source, text, 3000)
						return
					end
				end
			end

			TriggerEvent("vorp_inventory:Server:OnItemUse", arguments)

			local success <const>, result <const> = pcall(USABLE_ITEMS[itemName], arguments)
			if not success then
				return print("Function call failed with error:", result, "a usable item :", itemName, " have an error in the callback function")
			end
		end,

		REMOVE = function(source, invId, itemId, amount)
			local _source <const> = source

			local sourceCharacter <const> = getCharacter(_source)
			if not sourceCharacter then return end

			local identifier <const> = sourceCharacter.identifier
			local userInventory <const> = CUSTOM_INVENTORIES[invId].shared and USERS_ITEMS[invId] or USERS_ITEMS[invId][identifier]
			if not userInventory then return false end

			local item <const> = userInventory[itemId]
			if not item then return false end

			if amount <= item:getCount() then
				item:quitCount(amount)
			end

			if item:getCount() == 0 then
				if invId == "default" then
					local data = { name = item:getName(), count = amount, metadata = item:getMetadata() }
					TriggerEvent("vorp_inventory:Server:OnItemRemoved", data, _source)
				end
				userInventory[itemId] = nil
				DB_SERVICE.DELETE.ITEM(item:getOwner(), itemId)
			else
				DB_SERVICE.SET.ITEM_AMOUNT(item:getOwner(), itemId, item:getCount())
			end

			return true
		end,

		ADD = function(source, invId, name, amount, metadata, data, cb)
			local _source <const> = source
			local sourceCharacter <const> = getCharacter(_source)
			if not sourceCharacter then return cb(nil) end

			local identifier <const> = sourceCharacter.identifier
			local charIdentifier <const> = sourceCharacter.charIdentifier
			local svItem <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(name, "addItem")
			if not svItem then return cb(nil) end

			metadata = SHARED_UTILS.MERGE_TABLES(svItem.metadata, metadata or {})
			local userInventory <const> = CUSTOM_INVENTORIES[invId].shared and USERS_ITEMS[invId] or USERS_ITEMS[invId][identifier]
			if not userInventory then return cb(nil) end

			local function createItem()
				local degrade <const> = svItem:getMaxDegradation()
				local isExpired <const> = degrade ~= 0 and os.time() or nil
				local promise <const> = promise.new()

				DB_SERVICE.CREATE.ITEM(charIdentifier, svItem:getId(), amount, metadata, name, isExpired, svItem:getDurability(), function(craftedItem)
					local item <const> = ITEM:Register({
						id = craftedItem.id,
						count = amount,
						limit = svItem:getLimit(),
						label = svItem:getLabel(),
						metadata = SHARED_UTILS.MERGE_TABLES(svItem.metadata, metadata),
						name = name,
						type = "item_standard",
						canUse = svItem:getCanUse(),
						canRemove = svItem:getCanRemove(),
						owner = charIdentifier,
						desc = svItem:getDesc(),
						group = svItem:getGroup(),
						rarity = svItem:getRarity(),
						durability = data.durability or svItem:getDurability(),
						instruction = svItem:getInstruction(),
						weight = svItem:getWeight(),
						maxDegradation = degrade,
					})

					if invId == "default" then
						if degrade ~= 0 then
							if data.degradation then
								if data.degradation > 0 then
									if data.isPickup then
										if not item:isItemExpired(data.degradation, degrade) then
											local elapsedTime <const> = os.time() - data.degradation
											item.degradation = os.time() - elapsedTime
											item.percentage = item:getPercentage(degrade, item.degradation)
										else
											item.degradation = 0
											item.percentage = 0
										end
									else
										item.degradation = os.time() - item:getElapsedTime(degrade, data.percentage)
										item.percentage = item:getPercentage(degrade, item.degradation)
									end
									DB_SERVICE.AWAIT.QUERY('UPDATE character_inventories SET degradation = @degradation, percentage = @percentage WHERE item_crafted_id = @id',
										{ degradation = item.degradation, percentage = item.percentage, id = craftedItem.id }
									)
								else
									item.degradation = 0
									item.percentage = 0
									DB_SERVICE.AWAIT.QUERY('UPDATE character_inventories SET degradation = @degradation, percentage = @percentage WHERE item_crafted_id = @id',
										{ degradation = 0, percentage = 0, id = craftedItem.id }
									)
								end
							else
								item.degradation = os.time()
								item.percentage = 100
								DB_SERVICE.AWAIT.QUERY('UPDATE character_inventories SET degradation = @degradation, percentage = @percentage WHERE item_crafted_id = @id',
									{ degradation = os.time(), percentage = 100, id = craftedItem.id }
								)
							end
						end
					else
						if data.degradation and degrade ~= 0 then
							if item:isItemExpired(data.degradation, degrade) then
								item.degradation = 0
								item.percentage = 0
							else
								item.percentage = item:getPercentage(degrade, data.degradation)
								item.degradation = os.time()
							end
							-- custom invs need to be updated everytime
							DB_SERVICE.AWAIT.QUERY('UPDATE character_inventories SET percentage = @percentage, degradation = @degradation WHERE item_crafted_id = @id',
								{ percentage = item.percentage, degradation = item.degradation, id = craftedItem.id }
							)
						end
					end
					promise:resolve(item)
				end, invId)

				local item = Citizen.Await(promise)
				if not item then
					return cb(nil)
				end

				userInventory[item:getId()] = item
				if invId == "default" then
					TriggerEvent("vorp_inventory:Server:OnItemCreated", { name = item:getName(), count = amount, metadata = item:getMetadata() }, _source)
				end
				return cb(item)
			end

			-- item exists in inventory by name and metadata?
			local item <const> = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA(invId, identifier, name, metadata)
			if item then
				-- items exists with the same name and metadata
				-- amount is greater than 0 for error
				if amount > 0 then
					-- if item is not a degradation item
					if svItem:getMaxDegradation() == 0 then
						local success = item:addCount(amount, CUSTOM_INVENTORIES[invId].ignoreItemStackLimit)
						if not success then
							return cb(false)
						end
						DB_SERVICE.SET.ITEM_AMOUNT(item:getOwner(), item:getId(), item:getCount())
						return cb(item)
					else
						-- if item is degradation item
						-- if is the correct item with the same values increase amount
						if item:getPercentage() == data.percentage then
							local success = item:addCount(amount, CUSTOM_INVENTORIES[invId].ignoreItemStackLimit)
							if not success then
								return cb(false)
							end
							DB_SERVICE.SET.ITEM_AMOUNT(item:getOwner(), item:getId(), item:getCount())
							return cb(item)
						end
					end
					-- create new item
					return createItem()
				end
				-- error
				return cb(nil)
			end
			-- item does not exist in inventory, or metadata is different create new item
			return createItem()
		end,

		GET_SERVER_ITEMS = function()
			local _source = source

			if SERVER_ITEMS then
				local data = msgpack.pack(SERVER_ITEMS)
				-- some people have thousands of items so use latent events.
				TriggerLatentClientEvent("vorpInventory:giveItemsTable", _source, 500000, data)
			end
		end,



	},

	WEAPON = {
		USED = function(id, used, used2)
			local userWeapons <const> = USERS_WEAPONS.default
			if not userWeapons[id] then return end

			if userWeapons[id]:getUsed() == used and userWeapons[id]:getUsed2() == used2 then
				return
			end

			local query <const> = 'UPDATE loadout SET used = @used, used2 = @used2 WHERE id = @id'
			local params <const> = { used = used and 1 or 0, used2 = used2 and 1 or 0, id = id }
			DB_SERVICE.ASYNC.UPDATE(query, params)

			userWeapons[id]:setUsed(used)
			userWeapons[id]:setUsed2(used2)
		end,

		ADD = function(source, weaponId, setUsed)
			local _source <const> = source
			local sourceCharacter <const> = getCharacter(_source)
			if not sourceCharacter then return end

			local userWeapon <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapon then return end

			local weaponcomps <const> = userWeapon:getAllComponents()
			local weaponname <const> = userWeapon:getName()

			local ammo <const> = userWeapon:getAllAmmo()
			local components <const> = {}

			local result <const> = INVENTORY_API.MAIN.ADD_WEAPON(_source, weaponname, ammo, components, weaponcomps, nil, weaponId, nil, nil, nil, setUsed)
			if not result then return end
			INVENTORY_API.MAIN.DELETE_WEAPON(_source, weaponId)
		end,

		UPDATE = function(weaponsUpdate)
			local _source = source

			local userAmmoData <const> = USERS_AMMO_DATA[_source]
			if not userAmmoData then return end

			for weaponId, value in pairs(weaponsUpdate) do
				if value.fired > 0 then
					if userAmmoData.ammo[value.ammoTypeName] then
						local weapon <const> = USERS_WEAPONS.default[weaponId]
						if weapon then
							weapon:subAmmoFromClip(value.ammoTypeName, value.fired)
						end
					end
				end
			end
		end,

		RELOADED = function(data)
			local _source <const> = source
			local weaponId <const> = data.weaponId
			local ammoType <const> = data.ammoType
			local amount <const> = data.amount
			local weapon <const> = USERS_WEAPONS.default[weaponId]
			if not weapon then return print("weapon not found :", weaponId) end

			local userAmmoData <const> = USERS_AMMO_DATA[_source]
			if not userAmmoData then return print("user ammo data not found :", _source) end

			if amount > weapon:getDefaultClipSize() then
				return print("cant take more than max clip size :", "for weapon :", weapon:getName())
			end

			weapon:addAmmoToClip(ammoType, amount)
			userAmmoData.ammo[ammoType] = math.max(0, userAmmoData.ammo[ammoType] - amount)
		end,

		ADD_BULLET = function(ammotype, amount, weaponid)
			local _source <const> = source

			local sourceCharacter <const> = getCharacter(_source)
			if not sourceCharacter then return print("source character not found :", _source) end

			local weapon <const> = USERS_WEAPONS.default[weaponid]
			if not weapon then return print("weapon not found :", weaponid) end
			local weaponName <const> = weapon:getName()

			local userAmmoData <const> = USERS_AMMO_DATA[_source]
			if not userAmmoData then return print("user ammo data not found :", _source) end

			if not userAmmoData.ammo[ammotype] then
				CORE.NotifyObjective(_source, "You can't unload your weapon because your gunbelt does not have the ammo type,to store ammo, your belt must have the ammotype", 2000);
				return
			end

			if weapon:getAmmo(ammotype) == 0 then
				return print("weapon does not have any ammo on server to remove from :", weaponName)
			end

			if amount > weapon:getAmmo(ammotype) then
				return print("weapon already has ammo maxed :", weaponName)
			end

			if amount > weapon:getDefaultClipSize() then
				return print("cant take more than max clip size :", "for weapon :", weaponName)
			end

			userAmmoData.ammo[ammotype] = math.min(userAmmoData.ammo[ammotype] + amount, SHARED_DATA.MAX_AMMO_BELT[ammotype])
			-- updates database each time we unload ammo from a weapon
			weapon:setAmmo(ammotype, 0)

			local query <const> = "UPDATE characters Set ammo=@ammo WHERE charidentifier=@charidentifier"
			local params <const> = { charidentifier = userAmmoData.charidentifier, ammo = json.encode(userAmmoData.ammo) }
			DB_SERVICE.ASYNC.UPDATE(query, params)

			TriggerClientEvent("vorpinventory:recammo", _source, userAmmoData)
			TriggerClientEvent("vorpinventory:weaponClipUnloaded", _source, weaponid, ammotype)
		end,

		ADD_COMPONENT = function(source, cb, args)
			if not CONFIG.USE_WEAPON_COMPONENTS then return cb(false) end
			local weaponId <const> = args.id
			local component <const> = args.component
			local category <const> = args.slotCategory
			-- weapon exists
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]

			if not userWeapons then
				print("Weapon not found")
				return cb(false)
			end

			-- does player have item?
			local itemId <const> = args.itemId
			local character = CORE.getUser(source)?.getUsedCharacter
			if not character then
				print("Character not found")
				return cb(false)
			end

			-- does weapon belong to user
			if userWeapons:getPropietary() ~= character.identifier then
				print("Weapon does not belong to user")
				return cb(false)
			end

			local userInventory <const> = USERS_ITEMS.default[character.identifier]
			if not userInventory then
				print("User inventory not found")
				return cb(false)
			end

			-- does player have item?
			local item <const> = userInventory[itemId]
			if not item then
				print("Item not found")
				return cb(false)
			end

			local comps <const> = userWeapons:getAllComponents()
			local existing <const> = comps[category]
			if existing then
				print("Weapon attachment slot already has a component; remove it before adding another")
				return cb(false)
			end

			-- remove item from inventory
			INVENTORY_API.MAIN.SUB_ITEM_BY_ID(source, itemId)
			userWeapons:addComponent(component, category)

			return cb(true)
		end,

		REMOVE_COMPONENT = function(source, cb, args)
			if not CONFIG.USE_WEAPON_COMPONENTS then return cb(false) end
			local weaponId <const> = args.id
			local component <const> = args.component -- item name
			local category <const> = args.slotCategory

			-- weapon exists
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then
				print("Weapon not found")
				return cb(false)
			end

			local character = CORE.getUser(source)?.getUsedCharacter
			if not character then
				print("Character not found")
				return cb(false)
			end

			-- does weapon belong to user
			if userWeapons:getPropietary() ~= character.identifier then
				print("Weapon does not belong to user")
				return cb(false)
			end

			-- remove item from inventory
			INVENTORY_API.MAIN.ADD_ITEM(source, component, 1, {})
			userWeapons:removeComponent(component, category)
			return cb(true)
		end,

		SAVE_STATUS = function(updates)
			local _source <const> = source
			if not CONFIG.USE_WEAPON_DEGRADATION then return end

			for id, data in pairs(updates) do
				local weaponId <const> = tonumber(id) or id
				local weapon <const> = USERS_WEAPONS.default[weaponId]

				if weapon and (weapon:getUsed() or weapon:getUsed2()) and weapon.canDegrade then
					weapon:updateStatus(data)
				end
			end
		end,

		CLEAN = function(source, cb, args)
			if not CONFIG.USE_WEAPON_DEGRADATION then
				return cb(false)
			end

			local weaponId <const> = args.id
			local itemId <const> = args.itemId
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return cb(false) end

			if not userWeapons.canDegrade then
				return cb(false)
			end

			if not CONFIG.RESTORE_WEAPON_DEGRADATION and userWeapons:getDegradation() == 1.0 then
				return cb(false)
			end

			local character = CORE.getUser(source)?.getUsedCharacter
			if not character then return cb(false) end

			if userWeapons:getPropietary() ~= character.identifier then
				return cb(false)
			end

			local userInventory <const> = USERS_ITEMS.default[character.identifier]
			if not userInventory then return cb(false) end

			local item <const> = userInventory[itemId]
			if not item then return cb(false) end

			INVENTORY_API.MAIN.SUB_ITEM_BY_ID(source, itemId)
			userWeapons:updateStatus({ degradation = 0.0, damage = 0.0, dirt = 0.0, soot = 0.0 })

			return cb(true)
		end,

	},

	AMMO = {
		UPDATE = function(ammoinfo)
			local _source = source

			local userAmmoData <const> = USERS_AMMO_DATA[_source]
			if not userAmmoData then return end

			for ammoType, amount in pairs(ammoinfo.ammo) do
				if not userAmmoData.ammo[ammoType] then
					return print("ammotype not found :", ammoType)
				end
				-- client can never have more than the server
				if amount > userAmmoData.ammo[ammoType] then
					return print("amount is greater than what we have :", amount, "we have :", userAmmoData.ammo[ammoType], "ammo type :", ammoType, "possible cheat!!", GetPlayerName(_source))
				end

				if amount <= 0 then
					userAmmoData.ammo[ammoType] = nil
				end

				userAmmoData.ammo[ammoType] = math.min(amount, SHARED_DATA.MAX_AMMO_BELT[ammoType])
			end
		end,

		SAVE = function(source)
			local userAmmoData <const> = USERS_AMMO_DATA[source]
			if not userAmmoData then return end

			local charId <const> = userAmmoData.charidentifier
			local encodedAmmo <const> = json.encode(userAmmoData.ammo)

			if LAST_SAVED_AMMO_DATA[charId] ~= encodedAmmo then
				LAST_SAVED_AMMO_DATA[charId] = encodedAmmo

				DB_SERVICE.ASYNC.UPDATE("UPDATE characters SET ammo=@ammo WHERE charidentifier=@charidentifier", {
					charidentifier = charId,
					ammo = encodedAmmo,
				})
			end
		end,

		LOAD_ALL = function()
			local _source = source
			local sourceCharacter = getCharacter(_source)
			if not sourceCharacter then return end

			local charidentifier <const> = sourceCharacter.charIdentifier
			local query <const> = "SELECT ammo FROM characters WHERE charidentifier=@charidentifier"
			local params <const> = { charidentifier = charidentifier }
			DB_SERVICE.ASYNC.QUERY(query, params, function(result)
				if result[1] and result[1].ammo then
					local ammo <const> = json.decode(result[1].ammo)
					USERS_AMMO_DATA[_source] = { charidentifier = charidentifier, ammo = ammo }
					LAST_SAVED_AMMO_DATA[charidentifier] = json.encode(ammo) -- so we dont update the database again.
					if next(ammo) then
						TriggerClientEvent("vorpinventory:loadammo", _source, USERS_AMMO_DATA[_source])
					end
				end
			end)
		end,

		GET_INFO = function(source, cb)
			if not USERS_AMMO_DATA[source] then
				return cb(false)
			end

			return cb(USERS_AMMO_DATA[source])
		end,

	},

	IS_NEW_PLAYER = function(_source, charid)
		if not CONFIG.NEW_PLAYER.ALLOW_ACTIONS.ENABLE then return true end

		if not NEW_PLAYER[charid] then return true end

		CORE.NotifyRightTip(_source, LANG.ToNew, 5000)
		SV_UTILS.PROCESS.REMOVE_USER(_source)
		return false
	end,

	INVENTORY = {

		GET = function()
			local _source = source
			local sourceCharacter <const> = getCharacter(_source)
			if not sourceCharacter then return end

			local sourceIdentifier <const> = sourceCharacter.identifier
			if not sourceIdentifier then return print("steam identifier not found for source :", _source) end
			local sourceCharId <const> = sourceCharacter.charIdentifier

			local characterInventory <const> = {}

			DB_SERVICE.GET.INVENTORY(sourceCharId, "default", function(inventory)
				for _, item in pairs(inventory) do
					local dbItem <const> = SERVER_ITEMS[item.item]
					if dbItem then
						local metadata <const> = SHARED_UTILS.MERGE_TABLES(dbItem.metadata, item.metadata)

						if dbItem.maxDegradation ~= 0 then
							if item.degradation == nil then
								-- existing items with no degradation
								item.degradation = os.time()
								item.percentage = 100
							else
								-- existing items with degradation
								if item.degradation > 0 then
									local isExpired <const> = IsItemExpired(item.degradation, dbItem.maxDegradation)
									if isExpired then
										item.degradation = 0
										item.percentage = 0
									else
										local elapsedTime = os.time() - item.degradation
										item.degradation = os.time() - elapsedTime
										item.percentage = dbItem:getPercentage(dbItem.maxDegradation, item.degradation)
									end
								end
							end
							-- need to update
							DB_SERVICE.AWAIT.QUERY("UPDATE character_inventories SET degradation = @degradation, percentage = @percentage WHERE item_crafted_id = @itemId", { degradation = item.degradation, percentage = item.percentage, itemId = item.id })
						end

						local itemObj <const> = ITEM:Register({
							count = item.amount,
							id = item.id,
							limit = dbItem.limit,
							label = dbItem.label,
							metadata = metadata,
							name = dbItem.item,
							type = dbItem.type,
							canUse = dbItem.canUse,
							canRemove = dbItem.canRemove,
							createdAt = item.created_at,
							owner = sourceCharId,
							desc = dbItem.desc,
							group = dbItem.group,
							rarity = dbItem.rarity,
							durability = item.durability or dbItem.durability, -- if items crafted is nill then use database if has any durability
							instruction = dbItem.instruction,
							weight = dbItem.weight,
							degradation = item.degradation,
							maxDegradation = dbItem.maxDegradation,
							percentage = item.percentage
						})
						characterInventory[item.id] = itemObj
					end
				end
				USERS_ITEMS.default[sourceIdentifier] = characterInventory
				local data <const> = msgpack.pack(characterInventory)
				TriggerClientEvent("vorpInventory:giveInventory", _source, data)
			end)


			local userWeapons <const> = {}
			for _, weapon in pairs(USERS_WEAPONS.default) do
				if weapon.propietary == sourceIdentifier and weapon.charId == sourceCharId and weapon.currInv == "default" and weapon.dropped == 0 then
					userWeapons[#userWeapons + 1] = weapon
				end
			end
			TriggerClientEvent("vorpInventory:giveLoadout", _source, userWeapons)

			for id, _ in pairs(CUSTOM_INVENTORIES) do
				if USERS_ITEMS[id][sourceIdentifier] then
					USERS_ITEMS[id][sourceIdentifier] = nil
				end
			end
		end,

		RELOAD = function(player, id, type, source)
			local invData <const> = CUSTOM_INVENTORIES[id]
			if not invData then return end

			local sourceCharacter <const> = getCharacter(player)
			if not sourceCharacter then return end

			local sourceIdentifier <const>     = sourceCharacter.identifier
			local sourceCharIdentifier <const> = sourceCharacter.charIdentifier
			type                               = type or "custom"
			local userInventory                = {}
			local itemList <const>             = {}

			if type == "custom" then
				if invData:isShared() then
					userInventory = USERS_ITEMS[id]
				else
					userInventory = USERS_ITEMS[id][sourceIdentifier]
				end

				for weaponId, weapon in pairs(USERS_WEAPONS[id]) do
					if invData:isShared() or weapon.charId == sourceCharIdentifier then
						itemList[#itemList + 1] = WEAPON:Register({
							id            = weaponId,
							count         = 1,
							name          = weapon.name,
							label         = weapon.name,
							limit         = 1,
							type          = "item_weapon",
							desc          = weapon.desc,
							group         = 5,
							serial_number = weapon.serial_number,
							custom_label  = weapon.custom_label,
							custom_desc   = weapon.custom_desc,
							ammo          = weapon:getAllAmmo(),
							components    = weapon:getAllComponents(),
							used          = weapon:getUsed(),
							used2         = weapon:getUsed2(),
							weight        = weapon:getWeight(),
						})
					end
				end
			elseif type == "player" then
				userInventory = USERS_ITEMS.default[sourceIdentifier]
				for weaponId, weapon in pairs(USERS_WEAPONS.default) do
					if weapon.charId == sourceCharIdentifier and weapon:getPropietary() == sourceIdentifier then
						itemList[#itemList + 1] = WEAPON:Register({
							id            = weaponId,
							count         = 1,
							name          = weapon.name,
							label         = weapon.name,
							limit         = 1,
							type          = "item_weapon",
							desc          = weapon.desc,
							group         = 5,
							serial_number = weapon.serial_number,
							custom_label  = weapon.custom_label,
							custom_desc   = weapon.custom_desc,
							weight        = weapon.weight,
							ammo          = weapon:getAllAmmo(),
							components    = weapon:getAllComponents(),
							used          = weapon:getUsed(),
							used2         = weapon:getUsed2(),
						})
					end
				end
			end

			for _, value in pairs(userInventory) do
				itemList[#itemList + 1] = value
			end

			local payload <const> = {
				itemList = itemList,
				action = "setSecondInventoryItems",
				info = {
					target = player,
					source = source,
				},
			}

			local msgpack <const> = msgpack.pack(payload)
			TriggerClientEvent("vorp_inventory:ReloadCustomInventory", source or player, false, msgpack)
		end,

	},

	ON_NEW_CHARACTER = function(source)
		SetTimeout(5000, function()
			local character <const> = getCharacter(source)
			if not character then return end

			for key, value in pairs(CONFIG.NEW_PLAYER.START_ITEMS) do
				INVENTORY_API.MAIN.ADD_ITEM(source, key, value, {})
			end

			for _, value in ipairs(CONFIG.NEW_PLAYER.START_WEAPONS) do
				INVENTORY_API.MAIN.ADD_WEAPON(source, value, {}, {}, {})
			end

			if not CONFIG.NEW_PLAYER.ALLOW_ACTIONS.ENABLE then
				return
			end

			local charid <const> = character.charIdentifier
			if NEW_PLAYER[charid] then return end

			NEW_PLAYER[charid] = source
			local timer <const> = CONFIG.NEW_PLAYER.ALLOW_ACTIONS.COOLDOWN
			SetTimeout(timer * 1000, function()
				NEW_PLAYER[charid] = nil
			end)
		end)
	end,

	FORCE_RESPAWN = function()
		local _source <const> = source

		local user <const> = CORE.getUser(_source)
		if not user then return end

		local character <const> = user.getUsedCharacter
		local job <const> = character.job
		local isdead <const> = character.isdead

		if not isdead then return end

		local function removeCurrency(currencyType, currencyAmount, percentage, jobLock)
			if not jobLock[job] then
				if percentage == 1.0 then
					character.removeCurrency(currencyType, currencyAmount)
				else
					character.removeCurrency(currencyType, currencyAmount * percentage)
				end
			end
		end

		local value <const> = CONFIG.PLAYER_RESPAWN

		if value.MONEY.ENABLE then
			removeCurrency(0, character.money, value.MONEY.PERCENTAGE, value.MONEY.JOB_LOCK)
		end

		if value.GOLD.ENABLE then
			removeCurrency(1, character.gold, value.GOLD.PERCENTAGE, value.GOLD.JOB_LOCK)
		end

		if value.ROLL.ENABLE then
			removeCurrency(2, character.rol, value.ROLL.PERCENTAGE, value.ROLL.JOB_LOCK)
		end

		if value.ITEMS.ENABLE then
			if not value.ITEMS.JOB_LOCK[job] then
				if value.ITEMS.ALL then
					INVENTORY_API.MAIN.REMOVE_ALL_ITEMS(_source)
				else
					INVENTORY_API.MAIN.GET_INVENTORY(_source, function(userInventory)
						for _, itemData in ipairs(userInventory) do
							if not value.ITEMS.WHITELIST[itemData.name] then
								INVENTORY_API.MAIN.SUB_ITEM_BY_ID(_source, itemData.id)
							end
						end
					end)
				end
			end
		end

		if value.WEAPONS.ENABLE then
			if not value.WEAPONS.JOB_LOCK[job] then
				if value.WEAPONS.ALL then
					INVENTORY_API.MAIN.REMOVE_ALL_WEAPONS(_source)
				else
					INVENTORY_API.MAIN.GET_WEAPONS(_source, function(userWeapons)
						for _, weaponData in ipairs(userWeapons) do
							if not value.WEAPONS.WHITELIST[weaponData.name] then
								INVENTORY_API.MAIN.REMOVE_WEAPON(_source, weaponData.id)
								INVENTORY_API.MAIN.DELETE_WEAPON(_source, weaponData.id)
							end
						end
					end)
				end
			end
		end

		if value.AMMO.ENABLE then
			if not value.AMMO.JOB_LOCK[job] then
				TriggerClientEvent('syn_weapons:removeallammo', _source) -- syn script
				INVENTORY_API.MAIN.CLEAR_GUNBELT_AMMO(_source)
			end
		end
	end,

	-- needs a list so we only allow throwables
	DROP_THROWABLE_WEAPON = function(weaponId, weaponName)
		local _source <const> = source

		if not CONFIG.REMOVE_THROWABLE_WEAPONS then return end

		if not SHARED_DATA.WEAPONS[weaponName]?.IsThrowable then return end

		local weapon <const> = USERS_WEAPONS.default[weaponId]
		if not weapon then return end

		if weapon:getName() ~= weaponName then return end

		if THROWN_WEAPONS[weaponId] then return end

		weapon:setUsed(false)
		weapon:setUsed2(false)


		local weaponsToDelete <const> = { -- only has one use cant be picked up
			[`WEAPON_THROWN_MOLOTOV`] = true,
			[`WEAPON_THROWN_POISONBOTTLE`] = true,
			[`WEAPON_THROWN_DYNAMITE`] = true,
			[`WEAPON_MOONSHINEJUG_MP`] = true,
		}

		if weaponsToDelete[joaat(weaponName)] then
			INVENTORY_API.MAIN.DELETE_WEAPON(_source, weaponId)
		else
			INVENTORY_SERVICE.DROP.WEAPON(_source, weaponId)
		end

		THROWN_WEAPONS[weaponId] = {
			weaponName = weaponName,
		}

		local minutes = 3 --minutes max
		SetTimeout(minutes * 60 * 1000, function()
			if THROWN_WEAPONS[weaponId] then
				-- no one picked it up delete it
				INVENTORY_API.MAIN.DELETE_WEAPON(_source, weaponId)
			end
			THROWN_WEAPONS[weaponId] = nil
		end)
	end,

	PICK_UP_THROWABLE_WEAPON = function(weaponName)
		local _source <const> = source
		if not CONFIG.REMOVE_THROWABLE_WEAPONS then return end

		if not SHARED_DATA.WEAPONS[weaponName]?.IsThrowable then return end

		for weaponId, thrownWeapon in pairs(THROWN_WEAPONS) do
			if thrownWeapon.weaponName == weaponName then
				-- check if weapon is dropped
				local weapon <const> = USERS_WEAPONS.default[weaponId]
				if not weapon then return end

				if weapon:getDropped() ~= 1 then return end

				THROWN_WEAPONS[weaponId] = nil
				-- set as used the game will add them to the wheel
				weapon:setUsed(true)
				INVENTORY_SERVICE.WEAPON.ADD(_source, weaponId, true)

				break
			end
		end
	end,

	REMOVE_LASSO = function(weaponId, weaponName)
		local _source <const> = source
		if not CONFIG.REMOVE_LASSO then return end
		local weapon <const> = USERS_WEAPONS.default[weaponId]
		if not weapon then return end

		if weapon:getName() ~= weaponName then return end

		INVENTORY_API.MAIN.DELETE_WEAPON(_source, weaponId)
	end,


	SECONDARY = {

		CAN_STORE_ITEM = function(identifier, charIdentifier, invId, name, amount, metadata)
			local invData <const> = CUSTOM_INVENTORIES[invId]
			if not invData then return false end

			if invData:getLimit() > 0 then
				local sourceInventoryItemCount = INVENTORY_SERVICE.SECONDARY.GET_TOTAL_COUNT(identifier, charIdentifier, invId)
				sourceInventoryItemCount       = sourceInventoryItemCount + amount
				if sourceInventoryItemCount > invData:getLimit() then
					return false, "Inventory limit reached"
				end
			end

			if invData:iswhitelistItemsEnabled() then
				if not invData:isItemInList(name) then
					return false, "Item not allowed"
				end

				local items <const> = SV_UTILS.ITEMS.GET_ALL_BY_NAME(invId, identifier, name)

				if #items > 0 then
					local itemCount = 0
					for _, item in pairs(items) do
						itemCount = itemCount + item:getCount()
					end
					local totalAmount = amount + itemCount

					if totalAmount > invData:getItemLimit(name) then
						return false, "Item limit reached"
					end
				else
					if amount > invData:getItemLimit(name) then
						return false, "Item limit reached"
					end
				end
			end

			if not invData:getIgnoreItemStack() then
				local item = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA(invId, identifier, name, metadata)
				if not item then
					local svItem = SERVER_ITEMS[name]
					if amount > svItem:getLimit() then
						return false, "Item limit reached"
					end
					return true
				end

				local totalCount = item:getCount() + amount -- count how many items there is in custom inv + what we want to allow
				if totalCount > item:getLimit() then -- check if stack is full
					return false, "Item limit reached"
				end
			end

			return true, ""
		end,


		CAN_STORE_WEAPON = function(identifier, charIdentifier, invId, name, amount)
			local invData <const> = CUSTOM_INVENTORIES[invId]
			if not invData then return false end


			if invData:getLimit() > 0 then
				local sourceInventoryItemCount = INVENTORY_SERVICE.SECONDARY.GET_TOTAL_COUNT(identifier, charIdentifier, invId)
				sourceInventoryItemCount = sourceInventoryItemCount + amount
				if sourceInventoryItemCount > invData:getLimit() then
					return false, "Inventory limit reached"
				end
			end

			if invData:iswhitelistWeaponsEnabled() then
				if not invData:isWeaponInList(name) then
					return false, "Weapon not allowed"
				end

				local weapons <const> = SV_UTILS.WEAPONS.GET_ALL_BY_NAME(invId, name)
				local weaponCount <const> = #weapons + amount
				if weaponCount > invData:getWeaponLimit(name) then
					return false, "Weapon limit reached"
				end
			end

			return true
		end,

		GET_TOTAL_COUNT = function(identifier, charIdentifier, invId)
			local userTotalItemCount = 0
			local userInventory      = {}

			if not CUSTOM_INVENTORIES[invId] then
				return 0
			end

			local userWeapons <const> = USERS_WEAPONS[invId]
			if not userWeapons then return 0 end

			if CUSTOM_INVENTORIES[invId]:isShared() then
				userInventory = USERS_ITEMS[invId]
			else
				userInventory = USERS_ITEMS[invId][identifier]
			end

			for _, item in pairs(userInventory) do
				userTotalItemCount = userTotalItemCount + item:getCount()
			end
			for _, weapon in pairs(userWeapons) do
				if CUSTOM_INVENTORIES[invId]:isShared() or weapon.charId == charIdentifier then
					userTotalItemCount = userTotalItemCount + 1
				end
			end
			return userTotalItemCount
		end,
		DOES_HAVE_PERMISSION = function(invId, jobPerm, charidPerm)
			if not CUSTOM_INVENTORIES[invId]:isPermEnabled() then
				return true
			end

			if not next(jobPerm.data) and not next(charidPerm.data) then
				return true
			end

			if next(jobPerm.data) then
				if jobPerm.data[jobPerm.job] and jobPerm.grade >= jobPerm.data[jobPerm.job] then
					return true
				end
			end

			if next(charidPerm.data) then
				if charidPerm.data[charidPerm.charid] then
					return true
				end
			end

			return false
		end,

		CHECK_IS_BLACK_LISTED = function(invId, ItemName)
			if not CUSTOM_INVENTORIES[invId]:isBlackListEnabled() then
				return true
			end

			local ItemsTable <const> = CUSTOM_INVENTORIES[invId]:getBlackList()

			if next(ItemsTable) then
				for item, _ in pairs(ItemsTable) do
					if item == ItemName then
						return false
					end
				end
			end
			return true
		end,

		MOVE_TO = function(obj)
			local _source = source
			local data = json.decode(obj)
			local invId <const> = tostring(data.id)
			if not CUSTOM_INVENTORIES[invId] then
				return print("InventoryService.MoveToCustom: inventory not found with id: ", invId)
			end

			-- can only move items if this inventory is in use meaning was opened by the server
			if not CUSTOM_INVENTORIES[invId]:isInUse() then
				return print("inventory was not opened from the server user:", GetPlayerName(_source), "Tried to move items to:", invId, "possible Cheat!!")
			end

			-- this user did not open inventory through the server
			if not INVENTORY_IN_USE[_source] then
				return print("player:", GetPlayerName(_source), "did not open inventory through the server:", invId, "possible Cheat!!")
			end

			-- is the id the same as the one in use?
			if INVENTORY_IN_USE[_source] ~= invId then
				return print("player:", GetPlayerName(_source), "tried to move items to:", invId, "when the inventory allowed id for this user is:" .. INVENTORY_IN_USE[_source] .. " possible Cheat!!")
			end


			local item = data.item
			local amount = tonumber(data.number)
			local sourceCharacter = CORE.getUser(_source).getUsedCharacter
			local sourceIdentifier = sourceCharacter.identifier
			local sourceName = sourceCharacter.firstname .. ' ' .. sourceCharacter.lastname
			local job = sourceCharacter.job
			local grade = sourceCharacter.jobGrade
			local sourceCharIdentifier = sourceCharacter.charIdentifier
			local tableJobs, tableCharIds = CUSTOM_INVENTORIES[invId]:getPermissionMoveTo()
			local jobPerm = { data = tableJobs, job = job, grade = grade }
			local charidPerm = { data = tableCharIds, charid = sourceCharIdentifier }
			local CanMove = INVENTORY_SERVICE.SECONDARY.DOES_HAVE_PERMISSION(invId, jobPerm, charidPerm)
			local IsBlackListed = INVENTORY_SERVICE.SECONDARY.CHECK_IS_BLACK_LISTED(invId, string.lower(item.name)) -- lower so we can checkitems and weapons


			if not CanProceed(item, amount, sourceIdentifier, sourceName) then
				return
			end

			if not IsBlackListed then
				return CORE.NotifyObjective(_source, LANG.itemBlackListed, 5000)
			end

			if not CanMove then
				return CORE.NotifyObjective(_source, LANG.noPermissionStorage, 5000)
			end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then
				return
			end

			SV_UTILS.PROCESS.ADD_USER(_source)

			if item.type == "item_weapon" then
				if not CUSTOM_INVENTORIES[invId]:doesAcceptWeapons() then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return CORE.NotifyRightTip(_source, LANG.storageNoWeapons, 2000)
				end

				local canStore, message = INVENTORY_SERVICE.SECONDARY.CAN_STORE_WEAPON(sourceIdentifier, sourceCharIdentifier, invId, item.name, amount)
				if not canStore then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return CORE.NotifyObjective(_source, message, 2000)
				end

				local query = "UPDATE loadout SET identifier = '',curr_inv = @invId WHERE charidentifier = @charid AND id = @weaponId"
				local params = { invId = invId, charid = sourceCharIdentifier, weaponId = item.id }
				DB_SERVICE.ASYNC.UPDATE(query, params)
				USERS_WEAPONS.default[item.id]:setCurrInv(invId)
				USERS_WEAPONS[invId][item.id] = USERS_WEAPONS.default[item.id]
				USERS_WEAPONS.default[item.id] = nil
				TriggerClientEvent("vorpCoreClient:subWeapon", _source, item.id)
				local weapon <const> = USERS_WEAPONS[invId][item.id]
				TriggerClientEvent("vorp_inventory:client:secondaryItemAdded", _source, {
					id            = item.id,
					name          = weapon:getName(),
					label         = weapon:getCustomLabel() or weapon:getLabel() or weapon:getName(),
					type          = "item_weapon",
					desc          = weapon:getCustomDesc() or weapon:getDesc(),
					serial_number = weapon:getSerialNumber(),
					custom_label  = weapon:getCustomLabel(),
					custom_desc   = weapon:getCustomDesc(),
					ammo          = weapon:getAllAmmo(),
					used          = weapon:getUsed(),
					used2         = weapon:getUsed2(),
				})
				INVENTORY_SERVICE.LOGS.DISCORD(invId, item.name, amount, sourceName, "Move")
				SV_UTILS.PROCESS.REMOVE_USER(_source)
			else
				local svItemCheck <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(item.name, "MoveToSecondary")
				if not svItemCheck then
					return SV_UTILS.PROCESS.REMOVE_USER(_source)
				end

				if item.count and amount and item.count < amount then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return
				end

				local result, message = INVENTORY_SERVICE.SECONDARY.CAN_STORE_ITEM(sourceIdentifier, sourceCharIdentifier, invId, item.name, amount, item.metadata)
				if not result then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return CORE.NotifyObjective(_source, message, 2000)
				end


				local info = { degradation = item.degradation, isPickup = false }
				INVENTORY_SERVICE.ITEM.ADD(_source, invId, item.name, amount, item.metadata, info, function(itemAdded)
					if not itemAdded then
						SV_UTILS.PROCESS.REMOVE_USER(_source)
						return
					end
					INVENTORY_SERVICE.ITEM.REMOVE(_source, "default", item.id, amount)
					TriggerEvent("vorp_inventory:Server:OnItemMovedToCustomInventory", { id = item.id, name = item.name, amount = amount, metadata = item.metadata }, invId, _source)
					TriggerClientEvent("vorpInventory:removeItem", _source, item.id, amount)

					if itemAdded:getCount() > amount then
						TriggerClientEvent("vorp_inventory:client:secondaryItemUpdated", _source, itemAdded:getId(), itemAdded:getCount())
					else
						TriggerClientEvent("vorp_inventory:client:secondaryItemAdded", _source, {
							id          = itemAdded:getId(),
							count       = amount,
							name        = itemAdded:getName(),
							type        = "item_standard",
							metadata    = itemAdded:getMetadata(),
							degradation = itemAdded:getDegradation(),
							percentage  = itemAdded:getPercentage(),
							durability  = itemAdded:getDurability(),
						})
					end
					INVENTORY_SERVICE.LOGS.DISCORD(invId, item.name, amount, sourceName, "Move")
					SV_UTILS.PROCESS.REMOVE_USER(_source)
				end)
			end
		end,

		TAKE_FROM = function(obj)
			local _source = source

			local data = json.decode(obj)
			local invId <const> = tostring(data.id)
			if not CUSTOM_INVENTORIES[invId] then
				return print("InventoryService.TakeFromCustom: inventory not found with id: ", invId)
			end

			-- can only take items if this user had opened the inventory through the server
			if not CUSTOM_INVENTORIES[invId]:isInUse() then
				return print("inventory was not opened from the server user:", GetPlayerName(_source), "Tried to take items from:", invId, "possible Cheat!!")
			end
			-- this user did not open inventory through the server
			if not INVENTORY_IN_USE[_source] then
				return print("player:", GetPlayerName(_source), "did not open inventory through the server:", invId, "possible Cheat!!")
			end

			-- is the id the same as the one in use?
			if INVENTORY_IN_USE[_source] ~= invId then
				return print("player:", GetPlayerName(_source), "tried to take items from:", invId, "when the inventory allowed id for this user is:" .. INVENTORY_IN_USE[_source] .. " possible Cheat!!")
			end

			local item = data.item
			local amount = tonumber(data.number)
			local sourceCharacter = CORE.getUser(_source).getUsedCharacter
			local sourceName = sourceCharacter.firstname .. ' ' .. sourceCharacter.lastname
			local sourceIdentifier = sourceCharacter.identifier
			local sourceCharIdentifier = sourceCharacter.charIdentifier
			local job = sourceCharacter.job
			local grade = sourceCharacter.jobGrade
			local tableJobs, tableCharIds = CUSTOM_INVENTORIES[invId]:getPermissionTakeFrom()
			local jobPerm = { data = tableJobs, job = job, grade = grade }
			local charidPerm = { data = tableCharIds, charid = sourceCharIdentifier }
			local CanMove = INVENTORY_SERVICE.SECONDARY.DOES_HAVE_PERMISSION(invId, jobPerm, charidPerm)

			if not CanMove then
				return CORE.NotifyObjective(_source, LANG.noPermissionTake, 5000)
			end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then
				return
			end
			SV_UTILS.PROCESS.ADD_USER(_source)

			if item.type == "item_weapon" then
				local canCarryWeapon = INVENTORY_API.MAIN.CAN_CARRY_WEAPON(_source, 1, nil, item.name)

				if not canCarryWeapon then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return CORE.NotifyObjective(_source, LANG.fullInventory, 2000)
				end

				local userWeapons <const> = USERS_WEAPONS.default
				local weapon              = userWeapons[item.id]
				if weapon then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return print(GetPlayerName(_source) .. " tried to take a weapon from:" .. invId .. ", but already has it on main inventory with the same ID:" .. item.id .. "Possible Cheat!!")
				end

				local _userWeapons = USERS_WEAPONS[invId]
				local _weapon = _userWeapons[item.id]
				if not _weapon then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return print(GetPlayerName(_source) .. " tried to take a weapon from:" .. invId .. ", but ID doesnt exist Possible Cheat!!")
				end

				local query = "UPDATE loadout SET curr_inv = 'default', charidentifier = @charid, identifier = @identifier WHERE id = @weaponId"
				local params = { identifier = sourceIdentifier, weaponId = item.id, charid = sourceCharIdentifier }
				DB_SERVICE.ASYNC.UPDATE(query, params)
				USERS_WEAPONS[invId][item.id]:setCurrInv("default")
				USERS_WEAPONS.default[item.id] = USERS_WEAPONS[invId][item.id]
				USERS_WEAPONS.default[item.id].propietary = sourceIdentifier
				USERS_WEAPONS.default[item.id].charId = sourceCharIdentifier
				USERS_WEAPONS[invId][item.id] = nil
				weapon = USERS_WEAPONS.default[item.id]
				local name = weapon:getName()
				local ammo = weapon:getAllAmmo()
				local label = weapon:getLabel()
				local serial = weapon:getSerialNumber()
				local custom = weapon:getCustomLabel()
				local customDesc = weapon:getCustomDesc()
				local weight = weapon:getWeight()
				local components = weapon:getAllComponents()
				local status = weapon:getStatus()

				TriggerClientEvent("vorpInventory:receiveWeapon", _source, item.id, sourceIdentifier, name, ammo, label, serial, custom, _source, customDesc, weight, components, status)
				TriggerClientEvent("vorp_inventory:client:secondaryItemRemoved", _source, item.id, "item_weapon")
				INVENTORY_SERVICE.LOGS.DISCORD(invId, item.name, amount, sourceName, "Take")
				SV_UTILS.PROCESS.REMOVE_USER(_source)
			else
				if item.count and amount > item.count then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return print(GetPlayerName(_source) .. " tried to take an item from:" .. invId .. ", but the item count is less than the amount requested:" .. amount .. "Possible Cheat!!")
				end

				local _userInventory = USERS_ITEMS.default
				local _item = _userInventory[sourceIdentifier]
				if _item and _item[item.id] then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return print(GetPlayerName(_source) .. " tried to take an item from:" .. invId .. ", but already has it on main inventory with the same ID:" .. item.id .. "Possible Cheat!!")
				end

				local canCarryItem = INVENTORY_API.MAIN.CAN_CARRY_ITEM(_source, item.name, amount)
				if not canCarryItem then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return CORE.NotifyObjective(_source, LANG.cantCarryItemStack, 2000)
				end

				local info = { degradation = item.degradation, isPickup = false, percentage = item.percentage }
				INVENTORY_SERVICE.ITEM.ADD(_source, "default", item.name, amount, item.metadata, info, function(itemAdded)
					if not itemAdded then
						SV_UTILS.PROCESS.REMOVE_USER(_source)
						return CORE.NotifyObjective(_source, LANG.cantAddItem, 2000)
					end

					local result = INVENTORY_SERVICE.ITEM.REMOVE(_source, invId, item.id, amount)
					if not result then
						print(GetPlayerName(_source) .. " tried to take an item from:" .. invId .. " tried to use nui dev tools to dupe items Possible Cheat!!")
						INVENTORY_SERVICE.ITEM.REMOVE(_source, "default", itemAdded:getId(), itemAdded:getCount())
						SV_UTILS.PROCESS.REMOVE_USER(_source)
						return
					end

					TriggerEvent("vorp_inventory:Server:OnItemTakenFromCustomInventory", { id = itemAdded:getId(), name = item.name, amount = amount, metadata = itemAdded:getMetadata() }, invId, _source)
					TriggerClientEvent("vorpInventory:receiveItem", _source,
						itemAdded:getName(),
						itemAdded:getId(),
						amount,
						itemAdded:getMetadata(),
						itemAdded:getDegradation(),
						itemAdded:getPercentage(),
						itemAdded:getDurability()
					)
					local remaining = (item.count or 0) - amount
					if remaining <= 0 then
						TriggerClientEvent("vorp_inventory:client:secondaryItemRemoved", _source, item.id, "item_standard")
					else
						TriggerClientEvent("vorp_inventory:client:secondaryItemUpdated", _source, item.id, remaining)
					end
					INVENTORY_SERVICE.LOGS.DISCORD(invId, item.name, amount, sourceName, "Take")

					SV_UTILS.PROCESS.REMOVE_USER(_source)
				end)
			end
		end,

		MOVE_TO_PLAYER = function(obj)
			local _source = source

			local data = json.decode(obj)
			local item = data.item
			local amount = tonumber(data.number)
			local sourceCharacter = CORE.getUser(_source).getUsedCharacter
			local sourceName = sourceCharacter.firstname .. ' ' .. sourceCharacter.lastname
			local invId = "default"
			local target = data.info.target
			local messages = {
				weapons = LANG.weaponsLimitExceeded,
				items = LANG.itemsLimitExceeded,
				cooldown = LANG.cooldownMessage
			}

			if not CanProceed(item, amount, sourceCharacter.identifier, sourceName) then
				return
			end

			local IsBlackListed = PlayerBlackListedItems[string.lower(item.name)]

			if IsBlackListed then
				CORE.NotifyObjective(_source, LANG.blackListedMessage, 5000)
				return
			end

			if not HandleLimits(item, amount, target, _source, messages) then
				return
			end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then
				return
			end
			SV_UTILS.PROCESS.ADD_USER(_source)

			if item.type == "item_weapon" then
				INVENTORY_API.MAIN.CAN_CARRY_WEAPON(target, 1, function(res)
					if res then
						INVENTORY_API.MAIN.GIVE_WEAPON(target, item.id, _source, function(result)
							if result then
								INVENTORY_SERVICE.INVENTORY.RELOAD(target, "default", "player", _source)
								INVENTORY_SERVICE.LOGS.DISCORD("default", item.name, amount, sourceName, "Move")
							end
							SV_UTILS.PROCESS.REMOVE_USER(_source)
						end)
					else
						SV_UTILS.PROCESS.REMOVE_USER(_source)
						return CORE.NotifyObjective(_source, LANG.cantweapons, 2000)
					end
				end, item.name)
			else
				if not item.count or not amount then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return
				end

				local res = INVENTORY_API.MAIN.CAN_CARRY_ITEM(target, item.name, amount)
				if not res then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return CORE.NotifyObjective(_source, LANG.cantCarryItemStack, 2000)
				end

				if amount > item.count then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return CORE.NotifyObjective(_source, LANG.notEnoughItems, 2000)
				end

				INVENTORY_API.MAIN.ADD_ITEM(target, item.name, amount, item.metadata, function(result)
					if result then
						INVENTORY_API.MAIN.SUB_ITEM(_source, item.name, amount, item.metadata, function(result2)
							if result2 then
								SetTimeout(400, function()
									INVENTORY_SERVICE.INVENTORY.RELOAD(target, "default", "player", _source)
									INVENTORY_SERVICE.LOGS.DISCORD(invId, item.name, amount, sourceName, "Move")
									local metadataLabel = item.metadata?.label or item.label
									CORE.NotifyRightTip(_source, LANG.movedToPlayer .. amount .. " " .. metadataLabel, 2000)
									CORE.NotifyRightTip(target, LANG.itemGivenToPlayer .. " " .. metadataLabel, 2000)
									SV_UTILS.PROCESS.REMOVE_USER(_source)
								end)
							else
								SV_UTILS.PROCESS.REMOVE_USER(_source)
							end
						end, true)
					else
						SV_UTILS.PROCESS.REMOVE_USER(_source)
					end
				end, true, item.degradation)
			end
		end,

		TAKE_FROM_PLAYER = function(obj)
			local _source = source
			local data = json.decode(obj)
			local item = data.item
			local amount = tonumber(data.number)
			local sourceCharacter = CORE.getUser(_source).getUsedCharacter
			local sourceName = sourceCharacter.firstname .. ' ' .. sourceCharacter.lastname
			local invId = "default"
			local target = data.info.target
			local IsBlackListed = PlayerBlackListedItems[string.lower(item.name)]
			local messages = {
				weapons = LANG.weaponsLimitExceeded,
				items = LANG.itemsLimitExceeded,
				cooldown = LANG.cooldownMessage
			}

			if IsBlackListed then
				CORE.NotifyObjective(_source, LANG.blackListedMessage, 5000)
				return
			end

			if not HandleLimits(item, amount, target, _source, messages) then
				return
			end

			if SV_UTILS.PROCESS.USER_IN_PROCESSING(_source) then
				return
			end
			SV_UTILS.PROCESS.ADD_USER(_source)

			if item.type == "item_weapon" then
				INVENTORY_API.MAIN.CAN_CARRY_WEAPON(_source, 1, function(res)
					if res then
						INVENTORY_API.MAIN.GIVE_WEAPON(_source, item.id, target, function(result)
							if result then
								INVENTORY_SERVICE.INVENTORY.RELOAD(target, "default", "player", _source)
								INVENTORY_SERVICE.LOGS.DISCORD("default", item.name, amount, sourceName, "Take")
							end
							SV_UTILS.PROCESS.REMOVE_USER(_source)
						end)
					else
						SV_UTILS.PROCESS.REMOVE_USER(_source)
						CORE.NotifyObjective(_source, LANG.cantweapons, 2000)
					end
				end, item.name)
			else
				local res = INVENTORY_API.MAIN.CAN_CARRY_ITEM(_source, item.name, amount)
				if not res then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return CORE.NotifyObjective(_source, LANG.cantCarryItemStack, 2000)
				end

				if amount > item.count then
					SV_UTILS.PROCESS.REMOVE_USER(_source)
					return CORE.NotifyObjective(_source, LANG.notEnoughItems, 2000)
				end

				INVENTORY_API.MAIN.ADD_ITEM(_source, item.name, amount, item.metadata, function(result)
					if result then
						INVENTORY_API.MAIN.SUB_ITEM(target, item.name, amount, item.metadata, function(result2)
							if result2 then
								INVENTORY_SERVICE.INVENTORY.RELOAD(target, "default", "player", _source)
								INVENTORY_SERVICE.LOGS.DISCORD(invId, item.name, amount, sourceName, "Take")
								local metadataLabel = item.metadata?.label or item.label
								CORE.NotifyRightTip(_source, LANG.takenFromPlayer .. " " .. amount .. " " .. metadataLabel, 2000)
								CORE.NotifyRightTip(target, LANG.itemsTakenFromPlayer .. " " .. metadataLabel, 2000)
							end
							SV_UTILS.PROCESS.REMOVE_USER(_source)
						end, true)
					else
						SV_UTILS.PROCESS.REMOVE_USER(_source)
					end
				end, true, item.degradation)
			end
		end,

		ADD_ITEMS = function(id, items, charid, identifier)
			local result <const> = DB_SERVICE.AWAIT.QUERY("SELECT inventory_type FROM character_inventories WHERE inventory_type = @id", { id = id })

			if not result[1] then
				for _, value in ipairs(items) do
					local item = SERVER_ITEMS[value.name]
					if item and value.amount > 0 then
						local isExpired = item:getMaxDegradation() ~= 0 and item:getDegradation() or nil
						DB_SERVICE.CREATE.ITEM(charid, item:getId(), value.amount, (value.metadata or {}), value.name, isExpired, item:getDurability(), function(itemcraftedid)
							updateItem(itemcraftedid, value, item, charid, isExpired, id, identifier)
						end, id)
					end
				end
			else
				for _, value in ipairs(items) do
					local item = SERVER_ITEMS[value.name]
					if item and value.amount > 0 then
						local itemMetadata = value.metadata or {}
						local result1 = DB_SERVICE.AWAIT.QUERY("SELECT amount, item_crafted_id FROM character_inventories WHERE item_name =@itemname AND inventory_type = @inventory_type", { itemname = value.name, inventory_type = id })

						local isExpired = item:getMaxDegradation() ~= 0 and item:getDegradation() or nil
						if not result1[1] then
							DB_SERVICE.CREATE.ITEM(charid, item:getId(), value.amount, itemMetadata, value.name, isExpired, item:getDurability(), function(itemcraftedid)
								updateItem(itemcraftedid, value, item, charid, isExpired, id, identifier)
							end, id)
						else
							local resulItems = {}
							for _, v in ipairs(result1) do -- if there is more than one apple we need to check which ones have metadata
								local result2 = DB_SERVICE.AWAIT.QUERY("SELECT metadata FROM items_crafted WHERE id =@id", { id = v.item_crafted_id })
								local hasMetadata = result2[1] and json.decode(result2[1].metadata) or {}
								if next(hasMetadata) then
									resulItems[#resulItems + 1] = v
								end
							end

							if #resulItems == 0 then
								if next(itemMetadata) then
									DB_SERVICE.CREATE.ITEM(charid, item:getId(), value.amount, itemMetadata, value.name, isExpired, item:getDurability(), function(itemcraftedid)
										updateItem(itemcraftedid, value, item, charid, isExpired, id, identifier)
									end, id)
								else
									local itemCraftedId = result1[1].item_crafted_id
									updateItemInCustomInventory(id, identifier, itemCraftedId, value.amount, itemMetadata, value, item, charid, isExpired, value.name)
								end
							else
								local newTable = {}
								for _, v in ipairs(resulItems) do
									local result2 = DB_SERVICE.AWAIT.QUERY("SELECT metadata FROM items_crafted WHERE id =@id", { id = v.item_crafted_id })
									local metadata = json.decode(result2[1].metadata)
									local result3 = SHARED_UTILS.TABLE_EQUALS(metadata, itemMetadata)
									if result3 then
										newTable[#newTable + 1] = v
									end
								end

								if #newTable == 0 then -- metadata of any of the items dont match new one so we create new one
									DB_SERVICE.CREATE.ITEM(charid, item:getId(), value.amount, itemMetadata, value.name, isExpired, item:getDurability(), function(itemcraftedid)
										updateItem(itemcraftedid, value, item, charid, isExpired, id, identifier)
									end, id)
								else
									local itemCraftedId = newTable[1].item_crafted_id
									updateItemInCustomInventory(id, identifier, itemCraftedId, value.amount, itemMetadata, value, item, charid, isExpired, value.name)
								end
							end
						end
					end
				end
			end
		end,

		ADD_WEAPONS = function(id, weapons, charid)
			for _, value in ipairs(weapons) do
				local label = SV_UTILS.WEAPONS.GENERATE_WEAPON_LABEL(value.name)
				local serial_number = value.serial_number or SV_UTILS.WEAPONS.GENERATE_SERIAL_NUMBER(value.name)
				local custom_label = value.custom_label or SV_UTILS.WEAPONS.GENERATE_WEAPON_LABEL(value.name)
				local weight = SV_UTILS.WEAPONS.GET_WEAPON_WEIGHT(value.name)
				local components = value.components and next(value.components) and value.components or {}
				local params = {
					curr_inv = id,
					charidentifier = charid,
					name = value.name,
					serial_number = serial_number,
					label = label,
					custom_label = custom_label,
					custom_desc = value.custom_desc or nil,
					comps = json.encode(components)
				}

				DB_SERVICE.ASYNC.INSERT("INSERT INTO loadout (identifier, curr_inv, charidentifier, name,serial_number,label,custom_label,custom_desc,comps) VALUES ('', @curr_inv, @charidentifier, @name, @serial_number, @label, @custom_label, @custom_desc, @comps)", params, function(result)
					local weaponId = result
					local newWeapon <const> = WEAPON:Register({
						id = weaponId,
						propietary = "",
						name = value.name,
						ammo = {},
						comps = components,
						used = false,
						used2 = false,
						charId = charid,
						currInv = id,
						dropped = 0,
						source = 0,
						label = label,
						serial_number = serial_number,
						custom_label = label,
						custom_desc = value.custom_desc or nil,
						group = 5,
						weight = weight
					})
					if not USERS_WEAPONS[id] then
						USERS_WEAPONS[id] = {}
					end
					USERS_WEAPONS[id][weaponId] = newWeapon
				end)
			end
		end,

		REMOVE_ITEM = function(invId, item_name, amount, item_crafted_id)
			local query = "SELECT amount, item_crafted_id FROM character_inventories WHERE item_name = @itemname AND inventory_type = @inventory_type ORDER BY amount DESC"
			local arguments = { itemname = item_name, inventory_type = invId }

			if item_crafted_id then
				query = "SELECT amount, item_crafted_id FROM character_inventories WHERE item_crafted_id = @item_crafted_id AND inventory_type = @inventory_type ORDER BY amount DESC"
				arguments = { item_crafted_id = item_crafted_id, inventory_type = invId }
			end

			local result = DB_SERVICE.AWAIT.QUERY(query, arguments)
			if not result[1] then
				return false
			end

			local remainingAmount = amount
			local totalAvailable = 0

			for _, item in ipairs(result) do
				totalAvailable = totalAvailable + item.amount
			end

			if totalAvailable < amount then
				return false
			end

			for _, item in ipairs(result) do
				if remainingAmount <= 0 then
					break
				end

				local amountToRemove = math.min(remainingAmount, item.amount)

				if amountToRemove >= item.amount then
					DB_SERVICE.AWAIT.QUERY("DELETE FROM character_inventories WHERE item_crafted_id = @id AND inventory_type = @inventory_type", { id = item.item_crafted_id, inventory_type = invId })
					DB_SERVICE.AWAIT.QUERY("DELETE FROM items_crafted WHERE id = @id", { id = item.item_crafted_id })
				else
					DB_SERVICE.AWAIT.QUERY("UPDATE character_inventories SET amount = amount - @amount WHERE item_crafted_id = @id AND inventory_type = @inventory_type", { amount = amountToRemove, id = item.item_crafted_id, inventory_type = invId })
				end

				remainingAmount = remainingAmount - amountToRemove
			end
			return true
		end,

		REMOVE_WEAPON = function(invId, weapon_name)
			local result = DB_SERVICE.AWAIT.QUERY("SELECT id FROM loadout WHERE curr_inv = @invId AND name = @name", { invId = invId, name = weapon_name })
			if not result[1] then
				return false
			end

			local weaponId = result[1].id
			DB_SERVICE.ASYNC.UPDATE("DELETE FROM loadout WHERE id = @id", { id = weaponId })
			if USERS_WEAPONS[invId] then
				USERS_WEAPONS[invId][weaponId] = nil
			end
			return true
		end,

		GET_ALL_ITEMS = function(invId)
			local result = DB_SERVICE.AWAIT.QUERY("SELECT item_name, amount, item_crafted_id, percentage FROM character_inventories WHERE inventory_type = @inventory_type", { inventory_type = invId })
			local items = {}
			local itemsMap = {}
			for _, value in ipairs(result) do
				local item = SERVER_ITEMS[value.item_name]
				if item then
					local itemMetadata = {}
					local result1 = DB_SERVICE.AWAIT.QUERY("SELECT metadata FROM items_crafted WHERE id =@id", { id = value.item_crafted_id })
					if result1[1] then
						itemMetadata = result1[1].metadata and json.decode(result1[1].metadata) or {}
					end

					if next(itemMetadata) then
						items[#items + 1] = {
							crafted_id = value.item_crafted_id,
							name = value.item_name,
							amount = value.amount,
							metadata = itemMetadata,
							percentage = value.percentage,
							charid = value.character_id,
							label = itemMetadata.label or item:getLabel(),
							desc = itemMetadata.description or item:getDesc(),
							weight = itemMetadata.weight or item:getWeight(),
						}
					else
						if itemsMap[value.item_name] then
							itemsMap[value.item_name].amount = itemsMap[value.item_name].amount + value.amount
						else
							itemsMap[value.item_name] = {
								crafted_id = value.item_crafted_id,
								name = value.item_name,
								amount = value.amount,
								metadata = itemMetadata,
								percentage = value.percentage,
								charid = value.character_id,
								label = itemMetadata.label or item:getLabel(),
								desc = itemMetadata.description or item:getDesc(),
								weight = itemMetadata.weight or item:getWeight(),
							}
							items[#items + 1] = itemsMap[value.item_name]
						end
					end
				end
			end
			return items
		end,

		GET_ALL_WEAPONS = function(invId)
			local result = DB_SERVICE.AWAIT.QUERY("SELECT id, name, serial_number, label, custom_label, custom_desc FROM loadout WHERE curr_inv = @invId", { invId = invId })
			local weapons = {}
			for _, value in ipairs(result) do
				weapons[#weapons + 1] = {
					name = value.name,
					serial_number = value.serial_number or "",
					label = value.label,
					custom_label = value.custom_label or "",
					custom_desc = value.custom_desc or "",
					id = value.id
				}
			end
			return weapons
		end,

		REMOVE_WEAPON_BY_ID = function(invId, weaponId)
			local result = DB_SERVICE.AWAIT.QUERY("SELECT id FROM loadout WHERE id = @id AND curr_inv = @invId", { id = weaponId, invId = invId })
			if not result[1] then
				return false
			end

			DB_SERVICE.ASYNC.UPDATE("DELETE FROM loadout WHERE id = @id", { id = weaponId })
			if USERS_WEAPONS[invId] then
				USERS_WEAPONS[invId][weaponId] = nil
			end
			return true
		end,

		UPDATE_ITEM = function(invId, item_crafted_id, metadata, amount, _)
			local result = DB_SERVICE.AWAIT.QUERY("SELECT amount FROM character_inventories WHERE item_crafted_id = @item_crafted_id AND inventory_type = @inventory_type", { item_crafted_id = item_crafted_id, inventory_type = invId })
			if not result[1] then
				return false
			end

			local item = result[1]
			local itemAmount = amount or item.amount
			if itemAmount <= 0 then
				return false
			end

			if metadata and type(metadata) == "table" then
				metadata = json.encode(metadata)
			end

			DB_SERVICE.ASYNC.UPDATE("UPDATE character_inventories SET amount = @amount WHERE item_crafted_id = @item_crafted_id AND inventory_type = @inventory_type", { amount = itemAmount, item_crafted_id = item_crafted_id, inventory_type = invId })

			if metadata then
				DB_SERVICE.ASYNC.UPDATE("UPDATE items_crafted SET metadata = @metadata WHERE id = @id", { metadata = metadata, id = item_crafted_id })
			end

			updateItemAmount(invId, nil, itemAmount, item_crafted_id, metadata)

			return true
		end,

		DELETE = function(invId)
			local result = DB_SERVICE.AWAIT.QUERY("SELECT item_crafted_id FROM character_inventories WHERE inventory_type = @inventory_type", { inventory_type = invId })
			if not result[1] then
				return false
			end

			for _, value in ipairs(result) do
				DB_SERVICE.ASYNC.UPDATE("DELETE FROM items_crafted WHERE id = @id", { id = value.item_crafted_id })
			end

			DB_SERVICE.ASYNC.UPDATE("DELETE FROM character_inventories WHERE inventory_type = @inventory_type", { inventory_type = invId })
			DB_SERVICE.ASYNC.UPDATE("DELETE FROM loadout WHERE curr_inv = @invId", { invId = invId })

			if USERS_WEAPONS[invId] then
				USERS_WEAPONS[invId] = nil
			end
		end,

	},

	LOGS = {
		DISCORD = function(inventory, itemName, amount, playerName, action)
			local title = CONFIG.LOGS.custitle
			local color = CONFIG.LOGS.cuscolor
			local logo = CONFIG.LOGS.cuslogo
			local footerlogo = CONFIG.LOGS.cusfooterlogo
			local avatar = CONFIG.LOGS.cusavatar
			local names = CONFIG.LOGS.cuswebhookname
			local webhook = CUSTOM_INVENTORIES[inventory]

			if webhook and inventory ~= "default" then
				local wh = webhook:getWebhook()
				---@diagnostic disable-next-line: cast-local-type
				webhook = (wh and wh ~= "") and wh or false
			end

			if action == "Move" then
				---@diagnostic disable-next-line: cast-local-type
				webhook = (type(webhook) == "string") and webhook or CONFIG.LOGS.CustomInventoryMoveTo
				local description = "**Player:**`" .. playerName .. "`\n **Moved to:** `" .. inventory .. "` \n**Weapon** `" .. itemName .. "`\n **Count:** `" .. amount .. "`"
				CORE.AddWebhook(title, webhook, description, color, names, logo, footerlogo, avatar)
			end


			if action == "Take" then
				---@diagnostic disable-next-line: cast-local-type
				webhook = (type(webhook) == "string") and webhook or CONFIG.LOGS.CustomInventoryTakeFrom
				local description = "**Player:**`" .. playerName .. "`\n **Took from:** `" .. inventory .. "`\n **item** `" .. itemName .. "`\n **amount:** `" .. amount .. "`"
				CORE.AddWebhook(title, webhook, description, color, names, logo, footerlogo, avatar)
			end
		end,

	},

	CRAFTING = {


		HAND_CRAFTING = function(source, cb, args)
			if not CONFIG.INVENTORY_UI.HAND_CRAFT_BUTTON then
				return cb(false)
			end
			local recipe <const> = CONFIG.HAND_CRAFTING[args]
			if not recipe then
				return cb(false)
			end

			local character <const> = CORE.getUser(source)?.getUsedCharacter
			if not character then
				return cb(false)
			end

			local userInventory <const> = USERS_ITEMS.default[character.identifier]
			if not userInventory then
				return cb(false)
			end

			local needed <const> = recipe.NEEDED
			local reward <const> = recipe.REWARD
			local idsToRemove <const> = {}
			local found <const> = {}

			for itemId, itemData in pairs(userInventory) do
				local itemName <const> = itemData:getName()
				local itemAmount <const> = itemData:getCount()
				local itemNeeded <const> = needed[itemName]

				if itemNeeded and itemAmount >= itemNeeded then
					found[itemName] = true
					table.insert(idsToRemove, itemId)
				end
			end

			if #idsToRemove == 0 then
				return cb(false)
			end

			for itemName in pairs(needed) do
				if not found[itemName] then
					return cb(false)
				end
			end

			local itemName <const> = next(reward)
			local amount <const> = reward[itemName]

			if not recipe.ISWEAPON then
				local result <const> = INVENTORY_API.MAIN.ADD_ITEM(source, itemName, amount, {})
				if not result then
					return cb(false)
				end
			else
				if itemName and not SHARED_DATA.WEAPONS[itemName:upper()] then
					return cb(false)
				end

				-- can player receive weapon ?
				local canReceiveWeapon <const> = INVENTORY_API.MAIN.CAN_CARRY_WEAPON(source, 1)
				if not canReceiveWeapon then
					return cb(false)
				end

				-- add weapon to player
				local result <const> = INVENTORY_API.MAIN.ADD_WEAPON(source, itemName, {}, {}, {})
				if not result then
					return cb(false)
				end
			end

			for _, itemId in ipairs(idsToRemove) do
				INVENTORY_API.MAIN.SUB_ITEM_BY_ID(source, itemId)
			end

			return cb(true)
		end,

	},

}

INVENTORY_SERVICE = InventoryService


CreateThread(function()
	--AMMO IS ONLY UPDATED WHEN DATA HAVE CHANGED (TO AVOID UNNECESSARY UPDATES)
	local updateTimer <const> = 10000 -- every 10 seconds

	LIB.SetInterval(function()
		local function updateAmmo()
			for source in pairs(USERS_AMMO_DATA) do
				InventoryService.AMMO.SAVE(source)
			end
		end

		if CONFIG.MANUAL_WEAPON_RELOAD then
			for weaponId, value in pairs(USERS_WEAPONS.default) do
				if value.currInv == "default" then
					local weapon <const> = USERS_WEAPONS.default[weaponId]

					if weapon then
						local ammo <const> = weapon:getAllAmmo()
						local encodedAmmo <const> = json.encode(ammo)
						local id <const> = weapon:getId()

						if LAST_SAVED_WEAPON_AMMO[id] ~= encodedAmmo then
							LAST_SAVED_WEAPON_AMMO[id] = encodedAmmo

							local query <const> = "UPDATE loadout SET ammo=@ammo WHERE id=@id"
							local params <const> = { ammo = encodedAmmo, id = id }

							DB_SERVICE.ASYNC.UPDATE(query, params)
						end
					end
				end
			end

			updateAmmo()
		else
			updateAmmo()
		end
	end, updateTimer, {}, true)
end)

if CONFIG.USE_WEAPON_DEGRADATION then
	CreateThread(function()
		local timeToSave <const> = 10000
		LIB.SetInterval(function()
			for _, weapon in pairs(USERS_WEAPONS.default) do
				if weapon.canDegrade then
					if weapon:getUsed() or weapon:getUsed2() then
						local id <const> = weapon:getId()
						local status <const> = weapon:getStatus()
						local encoded <const> = json.encode({
							degradation = status.degradation,
							damage = status.damage,
							dirt = status.dirt,
							soot = status.soot,
						})

						if LAST_SAVED_WEAPON_DATA[id] ~= encoded then
							LAST_SAVED_WEAPON_DATA[id] = encoded

							DB_SERVICE.ASYNC.UPDATE("UPDATE loadout SET degradation = @degradation, damage = @damage, dirt = @dirt, soot = @soot WHERE id = @id",
								{
									id = id,
									degradation = status.degradation,
									damage = status.damage,
									dirt = status.dirt,
									soot = status.soot,
								}
							)
						end
					end
				end
			end
		end, timeToSave, {}, true)
	end)
end
