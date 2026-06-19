-- CONTAINS REGISTERED ITEMS
local REGISTERED_ITEMS <const> = {}
-- INVENTORY HANDLE USAGE
INVENTORY_IN_USE               = {}
-- CONTAINS USABLE ITEMS FUNCTIONS
USABLE_ITEMS                   = {}
-- CONTAINS PLAYER ITEMS LIMIT FOR openPlayerInventory
PLAYER_ITEMS_LIMIT             = {}
-- CONTAINS PLAYER INVENTORY COOLDOWN FOR openPlayerInventory
PLAYER_INV_COOL_DOWN           = {}
-- CONTAINS USERS AMMO DATA
USERS_AMMO_DATA                = {}
-- CONTAINS USERS ITEM DATA AND CUSTOM INVENTORY ITEM DATA
USERS_ITEMS                    = {
	default = {},

}

-- CONTAINS CUSTOM INVENTORIES CONFIGURATIONS
---@type table<string, table>
CUSTOM_INVENTORIES             = {
	default = {}
}

--used to sync time to the clients for degradation in items
CreateThread(function()
	while true do
		Wait(1000)
		GlobalState.TimeNow = os.time()
	end
end)

--- sync or async helper
local function respond(cb, result, message)
	if message then print(message) end
	if cb then cb(result) end
	return result
end

local function canContinue(id, jobName, grade, charid)
	if not CUSTOM_INVENTORIES[id] then
		return false
	end

	if not CUSTOM_INVENTORIES[id]:isPermEnabled() then
		return false
	end

	if charid then
		return true
	end

	if not jobName and not grade then
		return false
	end

	return true
end


CreateThread(function()
	SetTimeout(15000, function()
		print(">>>>>>>>>> ^1DEBUG: Starting item debug ^7 <<<<<<<<<<<<")
		for name, data in pairs(REGISTERED_ITEMS) do
			if not SERVER_ITEMS[name] then
				print("^3Warning^7: item ", name, " was added as usabled but ^1 does not exist in database ^7")
			end

			if SERVER_ITEMS[name] and not SERVER_ITEMS[name].canUse then
				print("^3Warning^7: item", name,
					" is not set as usable in database , ^1 you need to set usable to 1 in items database ^7")
			end

			if data.count > 1 then
				print("^3Warning^7: item ", name,
					" is being registered by multiple resources, ^1 can't register the same item multiple times only one.^7 resources: ",
					table.concat(data.resources, ", ") or "")
			end
		end
		table.wipe(REGISTERED_ITEMS)
		print(">>>>>>>>>> ^1DEBUG: Item debug finished ^7 <<<<<<<<<<<<")
	end)
end)

local InventoryAPI = {
	MAIN = {
		--||||||||||| ITEMS |||||||||||--
		REMOVE_ALL_ITEMS = function(source, cb)
			local character <const> = CORE.getUser(source)?.getUsedCharacter
			if not character then return respond(cb, false) end

			local userInventory <const> = USERS_ITEMS.default[character.identifier]
			if not userInventory then return respond(cb, false) end

			for _, item in ipairs(userInventory) do
				INVENTORY_API.MAIN.SUB_ITEM_BY_ID(source, item:getId())
			end

			return respond(cb, true)
		end,

		---@deprecated used only internally for old api
		CAN_CARRY_ITEM_AMOUNT = function(source, _, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false) end

			local userInventory <const> = USERS_ITEMS.default[character.identifier]
			if not userInventory then return respond(cb, false) end

			local function cancarryammount()
				local totalAmount <const> = INVENTORY_API.MAIN.GET_TOTAL_ITEMS_COUNT(character.identifier,
					character.charIdentifier)
				local totalAmountWeapons <const> = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(character.identifier,
					character.charIdentifier, true)
				return character.invCapacity ~= -1 and totalAmount + totalAmountWeapons <= character.invCapacity
			end

			return respond(cb, cancarryammount())
		end,

		CAN_CARRY_ITEM = function(source, itemName, amount, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false) end

			local function exceedsItemLimit(identifier, limit)
				local items <const> = SV_UTILS.ITEMS.GET_ALL_BY_NAME("default", identifier, itemName)
				local count = 0
				for _, item in pairs(items) do
					count = count + item:getCount()
				end
				return count + amount > limit
			end

			local function exceedsInvLimit(identifier, charIdentifier, limit, itemWeight)
				local totalAmount <const> = INVENTORY_API.MAIN.GET_TOTAL_ITEMS_COUNT(identifier, charIdentifier)
				local totalAmountWeapons <const> = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(identifier, charIdentifier,
					true)
				itemWeight = itemWeight * amount
				return limit ~= -1 and totalAmount + totalAmountWeapons + itemWeight > limit
			end

			local canCarry = false
			local svItem <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(itemName, "canCarryItem")
			if not svItem then return respond(cb, false) end

			if svItem.limit ~= -1 and not exceedsItemLimit(character.identifier, svItem.limit) then
				canCarry = not exceedsInvLimit(character.identifier, character.charIdentifier, character.invCapacity,
					svItem.weight)
			elseif svItem.limit == -1 then
				canCarry = true
			end

			return respond(cb, canCarry)
		end,

		GET_TOTAL_ITEMS_COUNT = function(identifier, charid)
			local userTotalItemCount = 0
			local userInventory <const> = USERS_ITEMS.default[identifier]
			if not userInventory then return 0 end

			for _, item in pairs(userInventory or {}) do
				if item:getCount() == nil then
					userInventory[item:getId()] = nil
					DB_SERVICE.DELETE.ITEM(charid, item:getId())
				else
					local weight = item:getWeight() and (item:getWeight() * item:getCount()) or item:getCount()
					userTotalItemCount = userTotalItemCount + weight
				end
			end

			return userTotalItemCount
		end,


		REGISTER_ITEM = function(name, cb, resource)
			if not name then
				return print("registerUsableItem: name is required", resource)
			end

			if not REGISTERED_ITEMS[name] then
				REGISTERED_ITEMS[name] = { resources = { resource }, count = 1 }
			else
				REGISTERED_ITEMS[name].count = REGISTERED_ITEMS[name].count + 1
				REGISTERED_ITEMS[name].resources[#REGISTERED_ITEMS[name].resources + 1] = resource
			end

			USABLE_ITEMS[name] = cb
		end,

		UNREGISTER_ITEM = function(name)
			if USABLE_ITEMS[name] then
				USABLE_ITEMS[name] = nil
			end
		end,
		--- THIS EXPORT SHOULD ONLY BE USED FOR NORMAL ITEMS NOTHING ELSE for items with decay and metadata use the getUserInventoryItems they are unique items
		GET_ITEM_COUNT = function(source, cb, itemName, metadata, percentage)
			local _source <const> = source
			if not _source then
				error("getItemCount: specify a source")
				return respond(cb, 0)
			end

			local svItem <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(itemName, "getItemCount")
			if not svItem then return respond(cb, 0) end

			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then
				return respond(cb, 0)
			end

			local identifier <const> = character.identifier
			local userInventory <const> = USERS_ITEMS.default[identifier]
			if not userInventory then return respond(cb, 0) end

			if metadata then
				metadata = SHARED_UTILS.MERGE_TABLES(svItem.metadata, metadata or {})
				--if metadata then get only the item that matches the metadata we are looking for
				local item <const> = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA("default", identifier, itemName, metadata)
				if item then return respond(cb, item:getCount()) end
				return respond(cb, 0)
			end

			-- get count of all items but can choose to get expired items, by default will only get normal items
			-- it will also return items with metadata because people use this export to get them when it doesnt even make sense they are unique items
			local itemTotalCount <const> = SV_UTILS.ITEMS.GET_ITEM_COUNT("default", identifier, itemName, percentage)

			return respond(cb, itemTotalCount)
		end,

		GET_DEFAULT_ITEM = function(itemName, cb)
			local svItem <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(itemName, "getItemDB")
			return respond(cb, svItem)
		end,

		---@deprecated this cannot be used as there is items with metadata and decay system, which will return either one of these
		GET_ITEM_BY_NAME = function(source, itemName, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end


			local identifier <const> = character.identifier
			if not SV_UTILS.ITEMS.DOES_ITEM_EXIST(itemName, "getItemByName") then
				return respond(cb, nil)
			end

			local item <const> = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA("default", identifier, itemName, nil)
			return respond(cb, item)
		end,
		---@deprecated this does the same thing as getItem use getItem instead
		GET_ITEM_CONTAINING_METADATA = function(source, itemName, metadata, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end

			local identifier <const> = character.identifier

			if not SV_UTILS.ITEMS.DOES_ITEM_EXIST(itemName, "getItemContainingMetadata") then
				return respond(cb, nil)
			end

			local item <const> = SV_UTILS.ITEMS.GET_ITEM_MATCHING_METADATA("default", identifier, itemName, metadata)
			return respond(cb, item)
		end,

		---@deprecated this does the same thing as getItem use getItem instead
		GET_ITEM_MATCHING_METADATA = function(source, itemName, metadata, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end

			local identifier <const> = character.identifier
			local svItem <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(itemName, "getItemContainingMetadata")
			if not svItem then
				return respond(cb, nil)
			end

			metadata = SHARED_UTILS.MERGE_TABLES(svItem.metadata or {}, metadata or {})
			local item <const> = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA("default", identifier, itemName, metadata)

			return respond(cb, item)
		end,

		ADD_ITEM = function(source, name, amount, metadata, cb, allow, degradation, percentage)
			local _source <const> = source
			if not _source then
				error("InventoryAPI.addItem: specify a source")
				return respond(cb, false)
			end

			local svItem <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(name, "addItem")
			if not svItem then
				print("[]")
				return respond(cb, false)
			end

			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false) end

			local identifier <const> = character.identifier
			local charIdentifier <const> = character.charIdentifier

			local userInventory = USERS_ITEMS.default[identifier]
			if not userInventory then
				USERS_ITEMS.default[identifier] = {}
				userInventory = USERS_ITEMS.default[identifier]
			end

			if not userInventory or amount <= 0 then
				return respond(cb, false)
			end

			-- support metadata from default items table
			if not metadata then
				if svItem.metadata and next(svItem.metadata) then
					metadata = svItem.metadata
				end
			end

			--local metadata_merged = SharedUtils.MergeTables(svItem.metadata, metadata or {})
			local item <const> = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA("default", identifier, name, metadata or {}) -- get item
			-- items that cant degrade we add ammount and items that exist
			if item then
				local result <const> = SHARED_UTILS.TABLE_EQUALS(item:getMetadata(), metadata or {}) -- does metadata equals
				local doesMetadataExist <const> = metadata ~= nil                        -- was metadata passed
				local existingMetadata <const> = next(item:getMetadata()) ~= nil

				if item:getMaxDegradation() == 0 then
					-- if metadata equals and metadata was passed then add count to same stack
					if result and doesMetadataExist then
						item:addCount(amount)
						DB_SERVICE.SET.ITEM_AMOUNT(charIdentifier, item:getId(), item:getCount())
						TriggerClientEvent("vorpCoreClient:addItem", _source, item)
						return respond(cb, true)
					end

					-- if item does not contain metadata and metadata was not passed then add amount
					if not doesMetadataExist and not existingMetadata then
						-- item exists and does no t contain metdata or was passed as nil
						item:addCount(amount)
						DB_SERVICE.SET.ITEM_AMOUNT(charIdentifier, item:getId(), item:getCount())
						TriggerClientEvent("vorpCoreClient:addItem", _source, item)
						return respond(cb, true)
					end

					-- we need to get an item that does not have a metadata here other wise it will create a new one because the loop could return one with metadata that does not match
					local itemNoMetadata <const> = SV_UTILS.ITEMS.GET_ITEM_NO_METADATA("default", identifier, name)
					if itemNoMetadata then
						itemNoMetadata:addCount(amount)
						DB_SERVICE.SET.ITEM_AMOUNT(charIdentifier, itemNoMetadata:getId(), itemNoMetadata:getCount())
						TriggerClientEvent("vorpCoreClient:addItem", _source, itemNoMetadata)
						return respond(cb, true)
					end
				end
			end

			local isDegradable <const> = svItem:getMaxDegradation() ~= 0
			local isExpired = nil
			if degradation and isDegradable and degradation > 0 then
				isExpired = degradation >= os.time() and 0 or degradation
			end

			local promise = promise.new()
			DB_SERVICE.CREATE.ITEM(charIdentifier, svItem:getId(), amount, metadata or {}, name, isExpired,
				svItem:getDurability(), function(craftedItem)
					local newItem <const> = ITEM:Register({
						id = craftedItem.id,
						count = amount,
						limit = svItem:getLimit(),
						label = svItem:getLabel(),
						metadata = metadata or {},
						name = name,
						type = svItem:getType(),
						canUse = svItem:getCanUse(),
						canRemove = svItem:getCanRemove(),
						owner = charIdentifier,
						desc = svItem:getDesc(),
						group = svItem:getGroup(),
						rarity = svItem:getRarity(),
						durability = svItem:getDurability(),
						instruction = svItem:getInstruction(),
						weight = svItem:getWeight(),
						maxDegradation = svItem:getMaxDegradation()
					})

					if isDegradable and not degradation then
						newItem.degradation = os.time()
						newItem.percentage = 100
						DB_SERVICE.AWAIT.QUERY(
							'UPDATE character_inventories SET degradation = @degradation, percentage = @percentage WHERE item_crafted_id = @id',
							{ degradation = newItem.degradation, percentage = newItem.percentage, id = craftedItem.id })
					end

					if percentage then
						newItem.degradation = os.time() - newItem:getElapsedTime(svItem:getMaxDegradation(), percentage)
						newItem.percentage = newItem:getPercentage(svItem:getMaxDegradation(), degradation)
						DB_SERVICE.AWAIT.QUERY(
							'UPDATE character_inventories SET percentage = @percentage WHERE item_crafted_id = @id',
							{ percentage = newItem.percentage, id = craftedItem.id })
					end

					userInventory[craftedItem.id] = newItem
					TriggerClientEvent("vorpCoreClient:addItem", _source, newItem)


					if not allow then
						local data = { name = newItem:getName(), count = amount, metadata = newItem:getMetadata() }
						TriggerEvent("vorp_inventory:Server:OnItemCreated", data, _source)
					end
					promise:resolve(true)
				end, "default")

			Citizen.Await(promise)
			return respond(cb, true)
		end,

		GET_ITEM_BY_ID = function(source, id, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end

			local identifier <const> = character.identifier
			local userInventory <const> = USERS_ITEMS.default[identifier]
			if not userInventory then return respond(cb, nil) end


			local item <const> = userInventory[id]
			if not item then return respond(cb, nil) end

			local itemSv <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(item.name, "getItemById")
			if not itemSv then return respond(cb, nil) end

			local itemRequested <const> = {}
			itemRequested.id = item:getId()
			itemRequested.label = item.metadata?.label or item:getLabel()
			itemRequested.name = item:getName()
			itemRequested.metadata = item:getMetadata()
			itemRequested.type = item:getType()
			itemRequested.count = item:getCount()
			itemRequested.limit = item:getLimit()
			itemRequested.canUse = itemSv:getCanUse()
			itemRequested.group = item:getGroup()
			itemRequested.weight = item:getWeight()
			itemRequested.desc = item.metadata?.description or item:getDesc()
			itemRequested.percentage = item:getPercentage()
			itemRequested.isDegradable = item:getMaxDegradation() ~= 0
			itemRequested.durability = item:getDurability()
			itemRequested.hasDurability = itemSv:getDurability() ~= nil
			itemRequested.maxDurability = itemSv:getDurability()

			return respond(cb, itemRequested)
		end,

		SUB_ITEM_BY_ID = function(source, id, cb, allow, amount)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false) end
			local identifier <const> = character.identifier
			local charIdentifier <const> = character.charIdentifier

			local userInventory <const> = USERS_ITEMS.default[identifier]
			local item <const> = userInventory[id]
			if not userInventory or not item then
				return respond(cb, false)
			end

			amount = amount or 1
			item:quitCount(amount)
			local itemName <const> = item:getName()
			local itemMetadata <const> = item:getMetadata()

			if item:getCount() == 0 then
				DB_SERVICE.DELETE.ITEM(charIdentifier, item:getId())
				TriggerClientEvent("vorpCoreClient:subItem", _source, item:getId(), 0)
				userInventory[item:getId()] = nil
			else
				DB_SERVICE.SET.ITEM_AMOUNT(charIdentifier, item:getId(), item:getCount())
				TriggerClientEvent("vorpCoreClient:subItem", _source, item:getId(), item:getCount())
			end

			if not allow then
				local data = { name = itemName, count = amount, metadata = itemMetadata }
				TriggerEvent("vorp_inventory:Server:OnItemRemoved", data, _source)
			end
			return respond(cb, true)
		end,

		SUB_ITEM = function(source, name, amount, metadata, cb, allow, percentage)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false) end

			local svItem <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(name, "subItem")
			if not svItem then return respond(cb, false) end

			local identifier <const> = character.identifier
			local userInventory <const> = CUSTOM_INVENTORIES.default.shared and USERS_ITEMS.default or
				USERS_ITEMS.default[identifier]
			if not userInventory then return respond(cb, false) end

			--* for items with metadata only
			if metadata then
				local itemFound <const> = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA("default", identifier, name, metadata or {})
				if not itemFound then return respond(cb, false) end

				local itemName <const> = itemFound:getName()
				local itemMetadata <const> = itemFound:getMetadata()

				itemFound:quitCount(amount)
				TriggerClientEvent("vorpCoreClient:subItem", _source, itemFound:getId(), itemFound:getCount())
				if itemFound:getCount() == 0 then
					USERS_ITEMS.default[identifier][itemFound:getId()] = nil
					DB_SERVICE.DELETE.ITEM(character.charIdentifier, itemFound:getId())
				else
					DB_SERVICE.SET.ITEM_AMOUNT(character.charIdentifier, itemFound:getId(), itemFound:getCount())
				end

				if not allow then
					local data <const> = { name = itemName, count = amount, metadata = itemMetadata }
					TriggerEvent("vorp_inventory:Server:OnItemRemoved", data, _source)
				end
				return respond(cb, true)
			end

			--* items with no metadata
			local sortedItems <const> = {}
			for _, item in pairs(userInventory) do
				-- allow items with metadata so we dont break existing scripts because people are using this export to delete random items instead of specific items
				if name == item:getName() then
					-- decide which items to get
					if percentage then
						if percentage > 0 then
							-- only items with a percentage greater than or equal to the percentage requested
							if item:getPercentage() >= percentage then
								table.insert(sortedItems, item)
							end
						else
							-- only expired items
							if item:getPercentage() == 0 then
								table.insert(sortedItems, item)
							end
						end
					else
						-- only items with no decay should be added, currently there was no way to get normal items, if you want to use decay you must pass the argument since its new and optional
						--if item:getMaxDegradation() == 0 then -- canno use this because people are using this export to delete random items instead of specific items
						-- this works in conjunction with getItemCount that will only get items without decay, decay is optional
						table.insert(sortedItems, item)
						--end
					end
				end
			end

			-- if there is a stack with the same amount then remove that stack instead of removing from any stack
			local exactMatchItem = nil
			for _, item in ipairs(sortedItems) do
				-- do we look for items expired or not expired?
				if item:getCount() == amount then
					exactMatchItem = item
					break
				end
			end

			if exactMatchItem then
				-- if an exact match is found, use this instance
				local itemName <const> = exactMatchItem:getName()
				local itemMetadata <const> = exactMatchItem:getMetadata()
				exactMatchItem:quitCount(amount)
				TriggerClientEvent("vorpCoreClient:subItem", _source, exactMatchItem:getId(), exactMatchItem:getCount())
				if exactMatchItem:getCount() == 0 then
					USERS_ITEMS.default[identifier][exactMatchItem:getId()] = nil
					DB_SERVICE.DELETE.ITEM(character.charIdentifier, exactMatchItem:getId())
				else
					DB_SERVICE.SET.ITEM_AMOUNT(character.charIdentifier, exactMatchItem:getId(),
						exactMatchItem:getCount())
				end

				if not allow then
					local data <const> = { name = itemName, count = amount, metadata = itemMetadata }
					TriggerEvent("vorp_inventory:Server:OnItemRemoved", data, _source)
				end
			else
				-- sort items from lower to higher
				table.sort(sortedItems, function(a, b) return a:getCount() < b:getCount() end)

				-- combine stacks starting from the lowest to higher this allows to eliminate smaller stacks first
				local itemsToRemove <const> = {}
				local totalNeeded = amount
				for _, item in ipairs(sortedItems) do
					if totalNeeded <= 0 then break end

					-- in here we can add a condition to only get items expired or not expired? but this would cause issues if you get the amount of items and not selecting expired or not expired, because what if there is amount needed but not enough as expired or not expired.
					local countAvailable <const> = item:getCount()
					local removeCount <const> = math.min(countAvailable, totalNeeded)
					local itemMetadata <const> = item:getMetadata()

					table.insert(itemsToRemove, { item = item, count = removeCount, metadata = itemMetadata })
					totalNeeded = totalNeeded - removeCount
				end

				-- if there isnt enough items to remove then return false (you should be using the export getItemCount before using this export thats why we have it) either way you dont need to use it this check will secure it
				if #itemsToRemove == 0 or totalNeeded > 0 then
					return respond(cb, false)
				end

				-- remove the items
				for _, value in ipairs(itemsToRemove) do
					local item <const> = value.item
					local removeCount <const> = value.count
					local itemName <const> = item:getName()
					local itemMetadata <const> = item:getMetadata()

					item:quitCount(removeCount)
					TriggerClientEvent("vorpCoreClient:subItem", _source, item:getId(), item:getCount())
					if item:getCount() == 0 then
						USERS_ITEMS.default[identifier][item:getId()] = nil
						DB_SERVICE.DELETE.ITEM(character.charIdentifier, item:getId())
					else
						DB_SERVICE.SET.ITEM_AMOUNT(character.charIdentifier, item:getId(), item:getCount())
					end
					if not allow then
						-- allow other scripts to detect the item removal and its amount, (count) was added
						local data <const> = { name = itemName, count = removeCount, metadata = itemMetadata }
						TriggerEvent("vorp_inventory:Server:OnItemRemoved", data, _source)
					end
				end
			end
			return respond(cb, true)
		end,

		SET_ITEM_METADATA = function(source, itemId, metadata, amount, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false, "player not found") end

			if type(metadata) ~= "table" then
				return respond(cb, false, "metadata is not a table")
			end

			local identifier <const> = character.identifier
			local charId <const> = character.charIdentifier

			local userInventory <const> = USERS_ITEMS.default[identifier]
			if not userInventory then return respond(cb, false) end

			local item <const> = userInventory[itemId]
			if not item then return respond(cb, false, "item not found with id: " .. itemId) end

			local svItem <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(item.name, "setItemMetadata")
			if not svItem then return respond(cb, false, "item with name: " .. item.name .. " not found") end

			local function removeFromStack(amountToUpdate)
				item:quitCount(amountToUpdate)

				if item:getCount() == 0 then
					userInventory[item:getId()] = nil
					DB_SERVICE.DELETE.ITEM(charId, item:getId())
					return TriggerClientEvent("vorpCoreClient:subItem", _source, item:getId(), 0)
				end

				DB_SERVICE.SET.ITEM_AMOUNT(charId, item:getId(), item:getCount())
				TriggerClientEvent("vorpCoreClient:subItem", _source, item:getId(), item:getCount())
			end

			local function updateStack(dataItem, meta)
				DB_SERVICE.SET.ITEM_METADATA(charId, dataItem:getId(), meta)
				dataItem:setMetadata(meta)
				TriggerClientEvent("vorp_inventory:SetItemMetadata", _source, dataItem:getId(), meta)
			end

			local function moveToStack(itemFound, amountToUpdate)
				itemFound:addCount(amountToUpdate)
				DB_SERVICE.SET.ITEM_AMOUNT(charId, itemFound:getId(), itemFound:getCount())
				TriggerClientEvent("vorpCoreClient:addItem", _source, itemFound)
			end

			local function createNewStack(newMeta, amountToUpdate)
				local isExpired <const> = svItem:getMaxDegradation() ~= 0 and os.time() or nil

				DB_SERVICE.CREATE.ITEM(charId, SERVER_ITEMS[item.name].id, amountToUpdate, newMeta, item:getName(),
					isExpired, item:getDurability(), function(craftedItem)
						local newItem <const> = ITEM:Register({
							id = craftedItem.id,
							count = amountToUpdate,
							limit = item:getLimit(),
							label = item:getLabel(),
							metadata = newMeta,
							name = item:getName(),
							type = item:getType(),
							canUse = svItem:getCanUse(),
							canRemove = item:getCanRemove(),
							owner = charId,
							desc = item:getDesc(),
							group = item:getGroup(),
							rarity = item:getRarity(),
							durability = item:getDurability(),
							instruction = item:getInstruction(),
							weight = item:getWeight(),
							maxDegradation = svItem:getMaxDegradation()
						})

						if svItem:getMaxDegradation() ~= 0 then
							newItem.degradation = os.time()
							newItem.percentage = 100
							DB_SERVICE.AWAIT.QUERY(
								'UPDATE character_inventories SET degradation = @degradation, percentage = @percentage WHERE item_crafted_id = @id',
								{ degradation = newItem.degradation, percentage = newItem.percentage, id = craftedItem.id }
							)
						end

						userInventory[craftedItem.id] = newItem
						TriggerClientEvent("vorpCoreClient:addItem", _source, newItem)
					end)
			end

			local amountToUpdate = amount or 1
			local count <const> = item:getCount()
			if amountToUpdate > count then
				amountToUpdate = count
			end

			local itemFound <const> = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA("default", identifier, item.name, metadata)
			-- allows to keep entries that are not in the metadata we are passing. allowing to update only some entries and not all or all
			local newMeta <const> = SHARED_UTILS.MERGE_TABLES(item:getMetadata(), metadata)
			if amountToUpdate == count then
				if itemFound then
					if item:getId() ~= itemFound:getId() then
						moveToStack(itemFound, amountToUpdate)
						removeFromStack(amountToUpdate)
					else
						-- SAME ID AND SAME METADATA DO NOTHING  USER IS TRYING TO UPDATE THE SAME STACK WITH THE SAME METADATA.
					end
				else
					updateStack(item, newMeta)
				end
			else
				if not itemFound then
					removeFromStack(amountToUpdate)
					createNewStack(newMeta, amountToUpdate)
				else
					if item:getId() ~= itemFound:getId() then
						moveToStack(itemFound, amountToUpdate)
						removeFromStack(amountToUpdate)
					else
						-- SAME ID AND SAME METADATA DO NOTHING  USER IS TRYING TO UPDATE THE SAME STACK WITH THE SAME METADATA.
					end
				end
			end

			return respond(cb, true)
		end,

		SET_ITEM_DURABILITY = function(source, itemId, durability, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false) end

			local identifier <const> = character.identifier
			local charId <const> = character.charIdentifier
			local userInventory <const> = USERS_ITEMS.default[identifier]
			if not userInventory then return respond(cb, false) end

			local item <const> = userInventory[itemId]
			if not item then return respond(cb, false) end

			local hasDurability <const> = SERVER_ITEMS[item.name] and SERVER_ITEMS[item.name]:getDurability() ~= nil
			if not hasDurability then return respond(cb, false, "item does not have durability to set durability") end

			local dura <const> = math.max(0, durability)
			item:setDurability(dura)
			DB_SERVICE.SET.ITEM_DURABILITY(charId, itemId, dura)
			TriggerClientEvent("vorp_inventory:SetItemDurability", _source, itemId, dura)

			return respond(cb, true)
		end,

		GET_ITEM = function(source, itemName, cb, metadata, percentage)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end

			local identifier <const> = character.identifier
			local svItem <const> = SV_UTILS.ITEMS.DOES_ITEM_EXIST(itemName, "getItem")
			if not svItem then return respond(cb, nil) end

			local function updateItemValues(item)
				item.label = item.metadata.label or item:getLabel()
				item.desc = item.metadata.description or item:getDesc()
				item.weight = item:getWeight()
				item.percentage = item:getPercentage()
				item.isDegradable = item:getMaxDegradation() ~= 0
				item.durability = item:getDurability()
				return item
			end

			local function getItemExpired()
				percentage = percentage or 0
				local userInventory <const> = USERS_ITEMS.default[identifier]
				if not userInventory then return nil end
				for _, item in pairs(userInventory) do
					if item:getName() == itemName then
						local itemPercentage = item:getPercentage()
						if percentage > 0 then
							if itemPercentage >= percentage then
								return item
							end
						else
							if itemPercentage <= 0 then
								return item
							end
						end
					end
				end
				return false
			end

			-- if metadata is provided we check if it exists if not returns nil, and not any other items, only what we asked for
			if metadata then
				metadata = SHARED_UTILS.MERGE_TABLES(svItem.metadata or {}, metadata)
				local item <const> = SV_UTILS.ITEMS.GET_ITEM_BY_METADATA("default", identifier, itemName, metadata)
				if not item then return respond(cb, nil) end

				return respond(cb, updateItemValues(item))
			end

			-- return expired or not expired items when specified
			if percentage ~= nil then
				local item <const> = getItemExpired()
				if not item then
					return respond(cb, nil)
				end
				return respond(cb, updateItemValues(item))
			end

			-- no metadata was specified or getExpired was nil  we get a random item
			local item <const> = SV_UTILS.ITEMS.GET_ITEM("default", identifier, itemName)
			if not item then return respond(cb, nil) end
			return respond(cb, updateItemValues(item))
		end,

		--||||||||||| WEAPONS |||||||||||--

		REMOVE_ALL_WEAPONS = function(source, cb)
			local character <const> = CORE.getUser(source)?.getUsedCharacter
			if not character then return respond(cb, false) end
			local userWeapons <const> = USERS_WEAPONS.default

			for _, weapon in pairs(userWeapons) do
				if weapon:getPropietary() == character.identifier and weapon:getCharId() == character.charIdentifier then
					INVENTORY_API.MAIN.REMOVE_WEAPON(source, weapon:getId())
					INVENTORY_API.MAIN.DELETE_WEAPON(source, weapon:getId())
				end
			end

			return respond(cb, true)
		end,

		GET_WEAPON_BY_ID = function(source, cb, weaponId)
			local _source <const> = source
			local weapon <const> = {}

			local foundWeapon <const> = USERS_WEAPONS.default[weaponId]
			if not foundWeapon then
				return respond(cb, false)
			end

			weapon.name = foundWeapon:getName()
			weapon.id = foundWeapon:getId()
			weapon.propietary = foundWeapon:getPropietary()
			weapon.used = foundWeapon:getUsed()
			weapon.used2 = foundWeapon:getUsed2()
			weapon.ammo = foundWeapon:getAllAmmo()
			weapon.desc = foundWeapon:getDesc()
			weapon.group = 5
			weapon.source = foundWeapon:getSource()
			weapon.label = foundWeapon:getLabel()
			weapon.serial_number = foundWeapon:getSerialNumber()
			weapon.custom_label = foundWeapon:getCustomLabel()
			weapon.custom_desc = foundWeapon:getCustomDesc()
			weapon.weight = foundWeapon:getWeight()

			return respond(cb, weapon)
		end,

		GET_WEAPONS = function(source, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end
			local identifier <const> = character.identifier
			local charidentifier <const> = character.charIdentifier
			local userWeapons <const> = USERS_WEAPONS.default

			local userWeapons2 <const> = {}
			for _, currentWeapon in pairs(userWeapons) do
				if currentWeapon:getPropietary() == identifier and currentWeapon:getCharId() == charidentifier then
					local weapon <const> = {
						name = currentWeapon:getName(),
						id = currentWeapon:getId(),
						propietary = currentWeapon:getPropietary(),
						used = currentWeapon:getUsed(),
						used2 = currentWeapon:getUsed2(),
						ammo = currentWeapon:getAllAmmo(),
						desc = currentWeapon:getDesc(),
						group = 5,
						source = currentWeapon:getSource(),
						label = currentWeapon:getLabel(),
						serial_number = currentWeapon:getSerialNumber(),
						custom_label = currentWeapon:getCustomLabel(),
						custom_desc = currentWeapon:getCustomDesc(),
						weight = currentWeapon:getWeight()
					}
					table.insert(userWeapons2, weapon)
				end
			end

			return respond(cb, userWeapons2)
		end,

		GET_WEAPON_BULLETS = function(source, cb, weaponId)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, 0) end

			local identifier <const> = character.identifier
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, 0) end

			if userWeapons:getPropietary() == identifier then
				return respond(cb, userWeapons:getAllAmmo())
			end

			return respond(cb, 0)
		end,

		CLEAR_GUNBELT_AMMO = function(source, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end
			local identifier <const> = character.identifier
			local charId <const> = character.charIdentifier

			USERS_AMMO_DATA[_source].ammo = {}

			for _, weapon in pairs(USERS_WEAPONS.default) do
				if weapon:getPropietary() == identifier and weapon:getCharId() == charId and weapon.currInv == "default" then
					weapon:cleanAllAmmoFromClip()
				end
			end

			local wipeClientWeaponAmmo = true
			TriggerClientEvent("vorpinventory:recammo", _source, USERS_AMMO_DATA[_source], nil, nil, wipeClientWeaponAmmo)
			local params = { charId = charId, ammo = json.encode({}) }
			DB_SERVICE.ASYNC.UPDATE('UPDATE characters SET ammo = @ammo WHERE charidentifier = @charId', params)

			return respond(cb, true)
		end,

		GET_GUNBELT_AMMO = function(source, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end

			local ammo <const> = USERS_AMMO_DATA[_source]?.ammo
			return respond(cb, ammo)
		end,

		ADD_AMMO_TO_GUNBELT = function(source, ammoType, amount, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end

			local charidentifier <const> = character.charIdentifier
			local ammo <const> = USERS_AMMO_DATA[_source]?.ammo
			if not ammo then return respond(cb, nil) end

			-- we need to add check here to see if max ammo doesnt go above the max allowed
			local maxAmount <const> = SHARED_DATA.MAX_AMMO_BELT[ammoType]
			if not maxAmount then return respond(cb, false, "Invalid ammo type") end

			local currentAmount <const> = ammo[ammoType] or 0
			if currentAmount + amount > maxAmount then
				-- dont return because will break scripts im sure no one is listening for the return
				local amountAdded = maxAmount - currentAmount
				CORE.NotifyObjective(_source, "you can't hold that many added: " .. amountAdded .. " max is: " .. maxAmount)
				--return respond(cb, false)
			end

			if ammo[ammoType] then
				ammo[ammoType] = math.min(maxAmount, tonumber(ammo[ammoType]) + amount)
			else
				ammo[ammoType] = math.min(maxAmount, amount)
			end

			USERS_AMMO_DATA[_source].ammo = ammo

			TriggerClientEvent("vorpinventory:recammo", _source, USERS_AMMO_DATA[_source], not CONFIG.MANUAL_WEAPON_RELOAD)

			local query1 = 'UPDATE characters SET ammo = @ammo WHERE charidentifier = @charidentifier'
			local params1 <const> = { charidentifier = charidentifier, ammo = json.encode(ammo) }
			DB_SERVICE.ASYNC.UPDATE(query1, params1)

			return respond(cb, true)
		end,

		REMOVE_WEAPON_BULLETS = function(source, weaponId, bulletType, amount, cb)
			local _source <const> = source
			local character = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end

			local identifier <const> = character.identifier
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, false) end

			if userWeapons:getPropietary() == identifier then
				userWeapons:subAmmoFromClip(bulletType, amount)
				TriggerClientEvent("vorpCoreClient:subBullets", _source, bulletType, amount)
				return respond(cb, true)
			end

			return respond(cb, false)
		end,

		CAN_CARRY_WEAPON = function(source, amount, cb, weaponName)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false) end

			local function getWeaponNameFromHash()
				if weaponName and type(weaponName) == "number" then
					for _, value in pairs(SHARED_DATA.WEAPONS) do
						if joaat(value.HashName) == weaponName then
							return value.HashName
						end
					end
				end
				return SHARED_DATA.WEAPONS[weaponName] and weaponName or nil
			end

			weaponName = getWeaponNameFromHash()

			local function isInventoryFull(identifier, charId, invCapacity)
				local weaponWeight = SV_UTILS.WEAPONS.GET_WEAPON_WEIGHT(weaponName) * amount
				local itemsTotalWeight = INVENTORY_API.MAIN.GET_TOTAL_ITEMS_COUNT(identifier, charId)
				local weaponsTotalWeight = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(identifier, charId, true)

				if (itemsTotalWeight + weaponsTotalWeight + weaponWeight) > invCapacity then
					return true
				end
				return false
			end

			local identifier <const>  = character.identifier
			local charId <const>      = character.charIdentifier
			local invCapacity <const> = character.invCapacity
			local job <const>         = character.job
			local DefaultAmount       = CONFIG.MAX_WEAPONS.PLAYERS

			if weaponName and isInventoryFull(identifier, charId, invCapacity) then
				return respond(cb, false)
			end

			if weaponName and CONFIG.MAX_WEAPONS.WHITELIST[weaponName:upper()] then
				return respond(cb, true)
			end

			if CONFIG.MAX_WEAPONS.JOBS[job] then
				DefaultAmount = CONFIG.MAX_WEAPONS.JOBS[job]
			end

			if DefaultAmount ~= -1 then
				local sourceInventoryWeaponCount <const> = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(identifier, charId) +
					amount
				if sourceInventoryWeaponCount > DefaultAmount then return respond(cb, false) end
			end

			return respond(cb, true)
		end,

		ADD_WEAPON_COMPONENT = function(source, weaponId, component, category, cb)
			local _source <const> = source
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, false) end

			userWeapons:addComponent(component, category) -- updates database
			TriggerClientEvent("vorp_inventory:addComponent", _source, weaponId, component, category)

			return respond(cb, true)
		end,
		ADD_WEAPON_COMPONENTS = function(source, weaponId, components, cb)
			local _source <const> = source
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, false) end

			for category, component in pairs(components) do
				userWeapons:addComponent(component, category) -- updates database
			end

			TriggerClientEvent("vorp_inventory:addComponents", _source, weaponId, components)

			return respond(cb, true)
		end,

		REMOVE_WEAPON_COMPONENT = function(source, weaponId, component, category, cb)
			local _source <const> = source
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, false) end

			userWeapons:removeComponent(component, category) -- updates database
			TriggerClientEvent("vorp_inventory:subComponent", _source, weaponId, component, category)
			return respond(cb, true)
		end,

		REMOVE_WEAPON_COMPONENTS = function(source, weaponId, components, cb)
			local _source <const> = source
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, false) end

			for category, component in pairs(components) do
				userWeapons:removeComponent(component, category)
			end
			TriggerClientEvent("vorp_inventory:subComponents", _source, weaponId, components)
		end,

		SET_WEAPON_CUSTOM_LABEL = function(source, weaponId, label, cb)
			local _source <const> = source
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, false) end

			userWeapons:setCustomLabel(label)
			TriggerClientEvent("vorpInventory:setWeaponCustomLabel", _source, weaponId, label)
			DB_SERVICE.ASYNC.UPDATE('UPDATE loadout SET custom_label = @custom_label WHERE id = @id',
				{ id = weaponId, custom_label = label })

			return respond(cb, true)
		end,

		SET_WEAPON_CUSTOM_SERIAL_NUMBER = function(source, weaponId, serial, cb)
			local _source <const> = source
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, false) end

			userWeapons:setSerialNumber(serial)
			TriggerClientEvent("vorp_inventory:setWeaponSerialNumber", _source, weaponId, serial)
			DB_SERVICE.ASYNC.UPDATE('UPDATE loadout SET serial_number = @serial_number WHERE id = @id',
				{ id = weaponId, serial_number = serial })

			return respond(cb, true)
		end,

		SET_WEAPON_CUSTOM_DESCRIPTION = function(source, weaponId, description, cb)
			local _source <const> = source
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, false) end

			userWeapons:setCustomDesc(description)
			TriggerClientEvent("vorp_inventory:setWeaponCustomDesc", _source, weaponId, description)
			DB_SERVICE.ASYNC.UPDATE('UPDATE loadout SET custom_desc = @custom_desc WHERE id = @id',
				{ id = weaponId, custom_desc = description })

			return respond(cb, true)
		end,

		GET_WEAPON_COMPONENTS = function(source, weaponId, cb)
			local _source <const> = source
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, nil) end

			return respond(cb, userWeapons:getAllComponents())
		end,

		DELETE_WEAPON = function(source, weaponId, cb)
			local _source <const> = source
			local userWeapons <const> = USERS_WEAPONS.default
			if not userWeapons[weaponId] then
				return respond(cb, false)
			end

			userWeapons[weaponId] = nil
			DB_SERVICE.ASYNC.DELETE('DELETE FROM loadout WHERE id = @id', { id = weaponId })
			TriggerClientEvent("vorpCoreClient:subWeapon", _source, weaponId)

			LAST_SAVED_WEAPON_DATA[weaponId] = nil
			return respond(cb, true)
		end,

		ADD_WEAPON = function(source, wepname, ammos, _, comps, cb, wepId, customSerial, customLabel, customDesc, setUsed)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, nil) end

			if not SHARED_DATA.WEAPONS[wepname:upper()] then
				return respond(cb, nil)
			end

			local identifier <const> = character.identifier
			local charId <const> = character.charIdentifier
			local name = wepname:upper()
			local ammo = {}

			if not comps then
				comps = {}
			else
				if CONFIG.USE_WEAPON_COMPONENTS then
					local function isValidTable()
						-- only for weapons that has components
						local components <const> = SHARED_DATA.WEAPONS[wepname]?.Components
						if not components then return true end

						-- is comps an array ?
						if type(comps) == "table" then
							for key, _ in pairs(comps) do
								if type(key) ~= "string" then
									return false
								else
									-- is valid key ?
									if not SHARED_DATA.WEAPONS_COMPONENT_CATEGORIES[key] then
										print("the key is not a valid key see weapons.lua for allowed keys in loadout table under comps.")
										return false
									end
								end
							end

							return true
						end
						return false
					end

					if not isValidTable() then
						print("comps is not a table , this table needs to have keys as strings see weapons.lua in componets for the keys that need to be used.")
						return respond(cb, nil)
					end
				end
			end

			if ammos then
				for key, value in pairs(ammos) do
					ammo[key] = tonumber(value)
				end
			end

			local function hasSerialNumber()
				if wepId and USERS_WEAPONS.default[wepId] then
					local userWeps = USERS_WEAPONS.default
					local wep = userWeps[wepId]
					if wep:getSerialNumber() then
						return wep:getSerialNumber()
					end
				end
				return false
			end

			local function hasCustomLabel()
				if wepId and USERS_WEAPONS.default[wepId] then
					local userWeps = USERS_WEAPONS.default
					local wep = userWeps[wepId]
					if wep:getCustomLabel() then
						return wep:getCustomLabel()
					end
				end
				return nil
			end

			local function hasCustomDesc()
				if wepId and USERS_WEAPONS.default[wepId] then
					local userWeps = USERS_WEAPONS.default
					local wep = userWeps[wepId]
					if wep:getCustomDesc() then
						return wep:getCustomDesc()
					end
				end
				return nil
			end

			local function hasStatus()
				if wepId and USERS_WEAPONS.default[wepId] then
					local userWeps = USERS_WEAPONS.default
					local wep = userWeps[wepId]
					if wep:getStatus() then
						return wep:getStatus()
					end
				end
				return nil
			end

			local serialNumber = customSerial or hasSerialNumber() or SV_UTILS.WEAPONS.GENERATE_SERIAL_NUMBER(name)
			local label = customLabel or hasCustomLabel() or SV_UTILS.WEAPONS.GENERATE_WEAPON_LABEL(name)
			local desc = customDesc or hasCustomDesc()
			local status = hasStatus()
			local weight = SV_UTILS.WEAPONS.GET_WEAPON_WEIGHT(name)
			local query = 'INSERT INTO loadout (identifier, charidentifier, name, ammo,comps,label,serial_number,custom_label,custom_desc,degradation,damage,dirt,soot) VALUES (@identifier, @charid, @name, @ammo,@comps,@label,@serial_number,@custom_label,@custom_desc,@degradation,@damage,@dirt,@soot)'
			local params = {
				identifier = identifier,
				charid = charId,
				name = name,
				label = SV_UTILS.WEAPONS.GENERATE_WEAPON_LABEL(name),
				ammo = json.encode(ammo),
				comps = json.encode(comps),
				custom_label = label,
				serial_number = serialNumber,
				custom_desc = desc,
				degradation = status and status.degradation or 0.0,
				damage = status and status.damage or 0.0,
				dirt = status and status.dirt or 0.0,
				soot = status and status.soot or 0.0,
			}

			DB_SERVICE.ASYNC.INSERT(query, params, function(result)
				local weaponId = result
				local newWeapon <const> = WEAPON:Register({
					id = weaponId,
					propietary = identifier,
					name = name,
					ammo = ammo,
					used = false,
					used2 = false,
					charId = charId,
					currInv = "default",
					dropped = 0,
					source = _source,
					label = label,
					serial_number = serialNumber,
					custom_label = label,
					custom_desc = desc,
					group = 5,
					weight = weight,
					components = comps,
					degradation = status and status.degradation or 0.0,
					damage = status and status.damage or 0.0,
					dirt = status and status.dirt or 0.0,
					soot = status and status.soot or 0.0,
				})
				USERS_WEAPONS.default[weaponId] = newWeapon

				TriggerEvent("syn_weapons:registerWeapon", weaponId)
				TriggerClientEvent("vorpInventory:receiveWeapon", _source, weaponId, identifier, name, ammo, label, serialNumber, label, _source, desc, weight, comps, status)
				if setUsed then
					TriggerClientEvent("vorpInventory:setWeaponUsed", _source, weaponId, true)
				end
			end)

			return respond(cb, true)
		end,

		GIVE_WEAPON = function(source, weaponId, target, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false) end

			local sourceIdentifier <const> = character.identifier
			local sourceCharId <const> = character.charIdentifier
			local invCapacity <const> = character.invCapacity
			local job <const> = character.job
			local _target <const> = target
			local userWeapons <const> = USERS_WEAPONS.default
			local DefaultAmount = CONFIG.MAX_WEAPONS.PLAYERS

			local weapon <const> = userWeapons[weaponId]
			if not weapon then return respond(cb, false) end

			local weaponName = weapon:getName()
			local weight = weapon:getWeight()
			local weaponStatus = weapon:getStatus()
			local notListed = false

			if CONFIG.MAX_WEAPONS.JOBS[job] then
				DefaultAmount = CONFIG.MAX_WEAPONS.JOBS[job]
			end

			if DefaultAmount ~= 0 then
				if weaponName and CONFIG.MAX_WEAPONS.WHITELIST[weaponName:upper()] then
					notListed = true
				end

				if not notListed then
					local itemsToTalWeight <const> = INVENTORY_API.MAIN.GET_TOTAL_ITEMS_COUNT(sourceIdentifier,
						sourceCharId)
					local sourceTotalWeaponWeight <const> = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(sourceIdentifier,
						sourceCharId, true)

					if (weight + itemsToTalWeight + sourceTotalWeaponWeight) > invCapacity then
						CORE.NotifyRightTip(_source, LANG.fullInventory, 2000)
						return respond(cb, false)
					end

					local sourceTotalWeaponCount <const> = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(sourceIdentifier,
						sourceCharId) + 1
					if sourceTotalWeaponCount > DefaultAmount then
						CORE.NotifyRightTip(_source, LANG.cantweapons, 2000)
						return respond(cb, false)
					end
				end
			end


			weapon:setPropietary(sourceIdentifier)
			weapon:setCharId(sourceCharId)
			local weaponPropietary = weapon:getPropietary()
			local weaponAmmo = weapon:getAllAmmo()
			local label = weapon:getLabel()
			local serialNumber = weapon:getSerialNumber()
			local customLabel = weapon:getCustomLabel()
			local customDesc = weapon:getCustomDesc()
			local weaponComponents = weapon:getAllComponents()
			local query = "UPDATE loadout SET identifier = @identifier, charidentifier = @charid WHERE id = @id"
			local params = { identifier = sourceIdentifier, charid = sourceCharId, id = weaponId }

			DB_SERVICE.ASYNC.UPDATE(query, params, function()
				if _target and _target > 0 then
					if CORE.getUser(_target) then
						weapon:setSource(_target)
						TriggerClientEvent('vorp:ShowAdvancedRightNotification', _target, LANG.youGaveWeapon,
							"inventory_items", weaponName, "COLOR_PURE_WHITE", 4000)
						TriggerClientEvent("vorpCoreClient:subWeapon", _target, weaponId)
					end
				end
				TriggerClientEvent('vorp:ShowAdvancedRightNotification', _source, LANG.youReceivedWeapon,
					"inventory_items", weaponName, "COLOR_PURE_WHITE", 4000)
				TriggerClientEvent("vorpInventory:receiveWeapon", _source, weaponId, weaponPropietary, weaponName,
					weaponAmmo, label, serialNumber, customLabel, _source, customDesc, weight, weaponComponents,
					weaponStatus)
			end)

			return respond(cb, true)
		end,

		GET_INVENTORY = function(source, cb)
			local character <const> = CORE.getUser(source)?.getUsedCharacter
			if not character then return respond(cb, nil) end

			local identifier <const> = character.identifier
			local userInventory <const> = USERS_ITEMS.default[identifier]
			if not userInventory then return respond(cb, nil) end

			local playerItems <const> = {}

			for _, item in pairs(userInventory) do
				-- for existing scripts we need to check if labels and descriptions exist in metadata to avoid showing the default ones
				local newItem <const> = {
					id = item:getId(),
					label = item.metadata?.label or item:getLabel(),
					name = item:getName(),
					desc = item.metadata?.description or item:getDesc(),
					metadata = item:getMetadata(),
					type = item:getType(),
					count = item:getCount(),
					limit = item:getLimit(),
					canUse = item:getCanUse(),
					group = item:getGroup(),
					weight = item:getWeight(), -- metadata weight is in the method itself
					percentage = item:getPercentage(),
					isDegradable = item:getMaxDegradation() ~= 0,
					durability = item:getDurability(),
				}
				table.insert(playerItems, newItem)
			end
			return respond(cb, playerItems)
		end,

		REMOVE_WEAPON = function(source, weaponId, cb)
			local _source <const> = source
			local character <const> = CORE.getUser(_source)?.getUsedCharacter
			if not character then return respond(cb, false) end

			local charId <const> = character.charIdentifier
			local userWeapons <const> = USERS_WEAPONS.default[weaponId]
			if not userWeapons then return respond(cb, false) end

			userWeapons:setPropietary('')
			local query = "UPDATE loadout SET identifier = @identifier, charidentifier = @charid WHERE id = @id"
			local params = {
				identifier = '',
				charid = charId,
				id = weaponId
			}

			DB_SERVICE.ASYNC.UPDATE(query, params, function()
				TriggerClientEvent("vorpCoreClient:subWeapon", _source, weaponId)
			end)

			return respond(cb, true)
		end,

		GET_TOTAL_WEAPONS_COUNT = function(identifier, charId, checkWeight)
			local userTotalWeaponCount = 0

			for _, weapon in pairs(USERS_WEAPONS.default) do
				local owner_identifier <const> = weapon:getPropietary()
				local owner_charid <const> = weapon:getCharId()

				if owner_identifier == identifier and owner_charid == charId then
					local weaponName <const> = weapon:getName()
					if weaponName and not CONFIG.MAX_WEAPONS.WHITELIST[weaponName:upper()] or checkWeight then
						local count = 0
						if checkWeight then
							count = weapon:getWeight()
						else
							count = 1
						end
						userTotalWeaponCount = userTotalWeaponCount + count
					end
				end
			end
			return userTotalWeaponCount
		end,

	},
	SECONDARY = {

		REGISTER = function(data)
			if CUSTOM_INVENTORIES[data.id] then return end
			return SECONDARY_INVENTORY:Register(data)
		end,

		ADD_PERMISSION_MOVE_TO = function(id, jobName, grade)
			if not canContinue(id, jobName, grade) then
				return
			end
			local data = { name = jobName, grade = grade }
			CUSTOM_INVENTORIES[id]:addPermissionMoveTo(data)
		end,
		ADD_PERMISSION_TAKE_FROM = function(id, jobName, grade)
			if not canContinue(id, jobName, grade) then
				return
			end

			local data = { name = jobName, grade = grade }
			CUSTOM_INVENTORIES[id]:addPermissionTakeFrom(data)
		end,
		ADD_CHAR_ID_PERMISSION_MOVE_TO = function(id, charid, state)
			if canContinue(id, false, false, charid) then
				return
			end

			local data = { name = charid, state = state }
			CUSTOM_INVENTORIES[id]:addCharIdPermissionMoveTo(data)
		end,
		ADD_CHAR_ID_PERMISSION_TAKE_FROM = function(id, charid, state)
			if canContinue(id, false, false, charid) then
				return
			end

			local data = { charid = charid, state = state }
			CUSTOM_INVENTORIES[id]:addCharIdPermissionTakeFrom(data)
		end,
		BLACKLIST = function(id, name)
			if not CUSTOM_INVENTORIES[id] or not name then
				return
			end

			local data = { name = name }
			CUSTOM_INVENTORIES[id]:blackListItems(data)
		end,
		REMOVE = function(id)
			if not CUSTOM_INVENTORIES[id] then
				return
			end

			CUSTOM_INVENTORIES[id]:removeCustomInventory()
		end,
		UPDATE_SLOTS = function(id, slots)
			if not CUSTOM_INVENTORIES[id] or not slots then
				return
			end

			if type(slots) ~= "number" then
				print("InventoryAPI.updateCustomInventorySlots: slots is not a number")
				return
			end

			CUSTOM_INVENTORIES[id]:setCustomInventoryLimit(slots)
		end,
		GET_SLOTS = function(id, cb)
			if not CUSTOM_INVENTORIES[id] then
				return respond(cb, false)
			end

			local slots = CUSTOM_INVENTORIES[id]:getLimit()
			return respond(cb, slots)
		end,
		SET_ITEM_LIMIT = function(id, itemName, limit)
			if not CUSTOM_INVENTORIES[id] then
				return
			end

			if not itemName and not limit then
				return
			end

			if type(limit) ~= "number" then
				print("InventoryAPI.setCustomInventoryItemLimit: limit is not a number")
				return
			end

			local data = { name = itemName:lower(), limit = limit }

			CUSTOM_INVENTORIES[id]:setCustomItemLimit(data)
		end,
		SET_WEAPON_LIMIT = function(id, wepName, limit)
			if not CUSTOM_INVENTORIES[id] then
				return
			end

			if not wepName and not limit then
				return
			end

			if type(limit) ~= "number" then
				print("InventoryAPI.setCustomInventoryWeaponLimit: limit is not a number")
				return
			end

			local data = { name = wepName:lower(), limit = limit }

			CUSTOM_INVENTORIES[id]:setCustomWeaponLimit(data)
		end,
		IS_REGISTERED = function(id, callback)
			if CUSTOM_INVENTORIES[id] then
				return respond(callback, true)
			end

			return respond(callback, false)
		end,
		GET_DATA = function(id, callback)
			if CUSTOM_INVENTORIES[id] then
				return respond(callback, CUSTOM_INVENTORIES[id]:getCustomInvData())
			end
			return respond(callback, false)
		end,
		UPDATE_DATA = function(id, data, callback)
			if CUSTOM_INVENTORIES[id] then
				CUSTOM_INVENTORIES[id]:updateCustomInvData(data)
				return respond(callback, true)
			end
			return respond(callback, false)
		end,
		ADD_ITEMS = function(id, items, charid, callback, identifier)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, false)
			end

			if not charid or charid == 0 then
				print(("InventoryAPI.addItemsToCustomInventory: charid is not valid %s"):format(id))
				return respond(callback, false)
			end

			if type(items) ~= "table" then
				print("InventoryAPI.addItemsToCustomInventory: items must be a table")
				return respond(callback, false)
			end

			local totalAmount = 0
			for index, value in ipairs(items) do
				local item <const> = SERVER_ITEMS[value.name]
				if not item then
					print(("item %s dont exist, this request was cancelled make sure to add the items to database items table"):format(value.name))
					return respond(callback, false)
				end
				totalAmount = totalAmount + value.amount
			end

			local currentWeaponsAmount <const> = DB_SERVICE.SECONDARY.GET_TOTAL_WEAPONS(id)
			local currentItemsAmount <const> = DB_SERVICE.SECONDARY.GET_TOTAL_ITEMS(id)
			local total <const> = totalAmount + currentWeaponsAmount + currentItemsAmount
			if total > CUSTOM_INVENTORIES[id]:getLimit() then
				print("InventoryAPI.addItemsToCustomInventory: total amount is greater than inventory limit, cannot add items to this inv")
				return respond(callback, false)
			end

			INVENTORY_SERVICE.SECONDARY.ADD_ITEMS(id, items, charid, identifier)

			return respond(callback, true)
		end,
		ADD_WEAPONS = function(id, weapons, charid, callback)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, false)
			end

			if not CUSTOM_INVENTORIES[id]:doesAcceptWeapons() then
				print(
					"InventoryAPI.addWeaponsToCustomInventory: this inventory does not accept weapons, change the settings in the registerCustomInventory export")
				return respond(callback, false)
			end

			if not charid or charid == 0 then
				local msg = "InventoryAPI.addWeaponsToCustomInventory: charid is not valid %s"
				print((msg):format(id))
				return respond(callback, false)
			end

			if type(weapons) ~= "table" then
				print("InventoryAPI.addWeaponsToCustomInventory: weapons must be a table")
				return respond(callback, false)
			end

			local currentWeaponsAmount = DB_SERVICE.SECONDARY.GET_TOTAL_WEAPONS(id)
			local currentItemsAmount = DB_SERVICE.SECONDARY.GET_TOTAL_ITEMS(id)
			local total = #weapons + currentWeaponsAmount + currentItemsAmount
			if total > CUSTOM_INVENTORIES[id]:getLimit() then
				print(
					"InventoryAPI.addWeaponsToCustomInventory: total amount is greater than inventory limit, cannot add weapons to this inv")
				return respond(callback, false)
			end

			INVENTORY_SERVICE.SECONDARY.ADD_WEAPONS(id, weapons, charid)

			return respond(callback, true)
		end,
		GET_ITEM_COUNT = function(id, item_name, item_crafted_id, callback, metadata)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, 0)
			end

			local query     = "SELECT SUM(amount) as total_amount FROM character_inventories WHERE inventory_type = @invType AND item_name = @item_name;"
			local arguments = { invType = id, item_name = item_name }
			if item_crafted_id then
				query = "SELECT amount as total_amount FROM character_inventories WHERE inventory_type = @invType AND item_crafted_id = @item_crafted_id;"
				arguments = { invType = id, item_crafted_id = item_crafted_id }
			end

			if metadata then
				query = "SELECT ci.amount, ic.metadata FROM character_inventories ci LEFT JOIN items_crafted ic ON ic.id = ci.item_crafted_id WHERE ci.inventory_type = @invType AND ci.item_name = @item_name;"
				arguments = { invType = id, item_name = item_name }
				local result = DB_SERVICE.AWAIT.QUERY(query, arguments)

				local totalAmount = 0
				for _, row in ipairs(result) do
					if row.metadata then
						local itemMetadata = json.decode(row.metadata)
						local matches = SHARED_UTILS.TABLE_EQUALS(itemMetadata, metadata)
						if matches then
							totalAmount = totalAmount + row.amount
						end
					end
				end
				return respond(callback, totalAmount)
			end

			local result <const> = DB_SERVICE.AWAIT.QUERY(query, arguments)
			if result[1] and result[1].total_amount then
				return respond(callback, tonumber(result[1].total_amount))
			end

			return respond(callback, 0)
		end,
		GET_WEAPON_COUNT = function(id, weapon_name, callback)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, 0)
			end

			local result <const> = DB_SERVICE.AWAIT.QUERY("SELECT COUNT(*) as total_count FROM loadout WHERE curr_inv = @invType AND weapon = @weapon_name", { invType = id, weapon_name = weapon_name })
			if result[1] and result[1].total_count then
				return respond(callback, tonumber(result[1].total_count))
			end
			return respond(callback, 0)
		end,
		REMOVE_ITEM = function(id, item_name, amount, item_crafted_id, callback)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, false)
			end

			if INVENTORY_SERVICE.SECONDARY.REMOVE_ITEM(id, item_name, amount, item_crafted_id) then
				return respond(callback, true)
			end

			return respond(callback, false)
		end,
		REMOVE_WEAPON = function(id, weapon_name, callback)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, false)
			end

			if INVENTORY_SERVICE.SECONDARY.REMOVE_WEAPON(id, weapon_name) then
				return respond(callback, true)
			end

			return respond(callback, false)
		end,
		GET_ITEMS = function(id, callback)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, false)
			end

			local items = INVENTORY_SERVICE.SECONDARY.GET_ALL_ITEMS(id)
			return respond(callback, items)
		end,
		GET_WEAPONS = function(id, callback)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, false)
			end

			local weapons = INVENTORY_SERVICE.SECONDARY.GET_ALL_WEAPONS(id)
			return respond(callback, weapons)
		end,
		REMOVE_WEAPON_BY_ID = function(id, weapon_id, callback)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, false)
			end

			if INVENTORY_SERVICE.SECONDARY.REMOVE_WEAPON_BY_ID(id, weapon_id) then
				return respond(callback, true)
			end

			return respond(callback, false)
		end,
		UPDATE_ITEM = function(id, item_id, metadata, amount, callback, identifier)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, false)
			end

			if INVENTORY_SERVICE.SECONDARY.UPDATE_ITEM(id, item_id, metadata, amount, identifier) then
				return respond(callback, true)
			end

			return respond(callback, false)
		end,
		DELETE = function(id, callback)
			if not CUSTOM_INVENTORIES[id] then
				return respond(callback, false)
			end

			if INVENTORY_SERVICE.SECONDARY.DELETE(id) then
				return respond(callback, true)
			end
			CUSTOM_INVENTORIES[id]:removeCustomInventory()
			return respond(callback, false)
		end,

	},

	CLOSE_INVENTORY = function(source, id)
		local _source <const> = source
		if id and CUSTOM_INVENTORIES[id] then
			if CUSTOM_INVENTORIES[id]:isInUse(_source) then
				return print("InventoryAPI.closeInventory: inventory is not in use by: ", _source, " To close it ID: ", id)
			end
			CUSTOM_INVENTORIES[id]:setInUse(_source, nil)
			INVENTORY_IN_USE[_source] = nil
			return TriggerClientEvent("vorp_inventory:CloseCustomInv", _source)
		end

		TriggerClientEvent("vorp_inventory:CloseInv", _source)
	end,
	OPEN_INVENTORY = function(source, id)
		local _source <const> = source
		-- its main inventory
		if not id then
			TriggerClientEvent("vorp_inventory:OpenInv", _source)
			return
		end

		if not CUSTOM_INVENTORIES[id] or not USERS_ITEMS[id] then
			return print("InventoryAPI.openInventory: inventory not found with id: ", id)
		end

		local character <const> = CORE.getUser(_source)?.getUsedCharacter
		if not character then return print("InventoryAPI.openInventory: source found with id: ", _source) end

		-- is it being used by anyone else?
		if CUSTOM_INVENTORIES[id]:isInUse() then
			return CORE.NotifyObjective(_source, LANG.SomeoneUseing, 5000)
		end
		CUSTOM_INVENTORIES[id]:setInUse(true)
		-- for player dropp event or inventory client close so we dont have to use loops
		if INVENTORY_IN_USE[_source] then
			return CORE.NotifyObjective(_source, LANG.AlreadyInUse, 5000)
		end

		INVENTORY_IN_USE[_source] = id

		local identifier <const> = character.identifier
		local charid <const> = character.charIdentifier
		local capacity = CUSTOM_INVENTORIES[id]:getLimit() > 0 and tostring(CUSTOM_INVENTORIES[id]:getLimit()) or 'oo'
		local weight = nil
		if CUSTOM_INVENTORIES[id]:useWeight() then
			weight = CUSTOM_INVENTORIES[id]:getWeight() > 0 and tostring(CUSTOM_INVENTORIES[id]:getWeight())
		end

		local function createCharacterInventoryFromDB(inventory)
			local characterInventory <const> = {}
			for _, item in pairs(inventory) do
				local dbItem <const> = SERVER_ITEMS[item.item]
				if dbItem then
					-- Build character inventory
					local newItem <const> = ITEM:Register({
						count = tonumber(item.amount),
						id = item.id,
						limit = dbItem.limit,
						label = dbItem.label,
						metadata = SHARED_UTILS.MERGE_TABLES(dbItem.metadata, item.metadata),
						name = dbItem.item,
						type = dbItem.type,
						canUse = dbItem.canUse,
						canRemove = dbItem.canRemove,
						createdAt = item.created_at,
						owner = item.character_id,
						desc = dbItem.desc,
						group = dbItem.group,
						rarity = dbItem.rarity,
						durability = item.durability,
						instruction = dbItem.instruction,
						weight = dbItem.weight,
						degradation = item.degradation,
						maxDegradation = dbItem.maxDegradation,
						percentage = item.percentage
					})
					characterInventory[item.id] = newItem
				end
			end
			return characterInventory
		end


		local function triggerAndReloadInventory()
			TriggerClientEvent("vorp_inventory:OpenCustomInv", _source, CUSTOM_INVENTORIES[id]:getName(), id, capacity, weight)
			INVENTORY_SERVICE.INVENTORY.RELOAD(_source, id)
		end

		if CUSTOM_INVENTORIES[id]:isShared() then
			if USERS_ITEMS[id] and #USERS_ITEMS[id] > 0 then
				triggerAndReloadInventory()
			else
				DB_SERVICE.GET.SHARED_INVENTORY(id, function(inventory)
					USERS_ITEMS[id] = createCharacterInventoryFromDB(inventory)
					triggerAndReloadInventory()
				end)
			end
		else
			if USERS_ITEMS[id][identifier] then
				triggerAndReloadInventory()
			else
				DB_SERVICE.GET.INVENTORY(charid, id, function(inventory)
					USERS_ITEMS[id][identifier] = createCharacterInventoryFromDB(inventory)
					triggerAndReloadInventory()
				end)
			end
		end
	end,
	PLAYER = {

		OPEN_INVENTORY = function(data, callback)
			local title = data.title
			local target = data.target
			local source = data.source

			local targetCharacter <const> = CORE.getUser(target)?.getUsedCharacter
			if not targetCharacter then return respond(callback, false) end

			INVENTORY_API.CLOSE_INVENTORY(target)
			local charid <const> = targetCharacter.charIdentifier

			PlayerBlackListedItems = data.blacklist or {}

			if not PLAYER_INV_COOL_DOWN[source] then
				PLAYER_INV_COOL_DOWN[source] = {}
			end

			local function isInCooldown(itemType)
				return PLAYER_INV_COOL_DOWN[source][itemType] and os.time() < PLAYER_INV_COOL_DOWN[source][itemType]
			end

			local function HandleLimits(limitType)
				if not data.itemsLimit then return true, false end
				local itemType <const> = data.itemsLimit[limitType].itemType
				local limit <const> = data.itemsLimit[limitType].limit

				if not PLAYER_ITEMS_LIMIT[target] then
					PLAYER_ITEMS_LIMIT[target] = {}
				end

				if not PLAYER_ITEMS_LIMIT[target][itemType] then
					PLAYER_ITEMS_LIMIT[target][itemType] = { limit = limit, timeout = data.timeout or nil }
				end

				local cooldownActive <const> = isInCooldown(itemType)

				if PLAYER_ITEMS_LIMIT[target][itemType].limit <= 0 and cooldownActive then
					return false, true
				elseif not cooldownActive and data.timeout then
					PLAYER_ITEMS_LIMIT[target][itemType].limit = limit
				end

				return true, cooldownActive
			end

			local allowWeapons, cooldownWeapons = HandleLimits("weapons")
			local allowItems, cooldownItems = HandleLimits("items")

			if cooldownWeapons and cooldownItems then
				CORE.NotifyObjective(source, LANG.BothonCool, 5000)
				return respond(callback, false)
			end

			if allowWeapons or allowItems then
				INVENTORY_SERVICE.INVENTORY.RELOAD(target, "default", "player", source)
				TriggerClientEvent("vorp_inventory:OpenPlayerInventory", source, title, charid, "player")
			end

			return respond(callback, true)
		end,

	},
}

INVENTORY_API      = InventoryAPI

-- ITEMS
---@deprecated
exports("canCarryItems", INVENTORY_API.MAIN.CAN_CARRY_ITEM_AMOUNT)
exports("getItemByName", INVENTORY_API.MAIN.GET_ITEM_BY_NAME)
exports("getItemContainingMetadata", INVENTORY_API.MAIN.GET_ITEM_CONTAINING_METADATA)
exports("getItemMatchingMetadata", INVENTORY_API.MAIN.GET_ITEM_MATCHING_METADATA)
---------------------------------------------------------------------------------?

-- ALIAS
exports("subItemID", INVENTORY_API.MAIN.SUB_ITEM_BY_ID)
exports("getItemByMainId", INVENTORY_API.MAIN.GET_ITEM_BY_ID)

exports("subAllItems", INVENTORY_API.MAIN.REMOVE_ALL_ITEMS)
exports("canCarryItem", INVENTORY_API.MAIN.CAN_CARRY_ITEM)
exports("getUserInventoryItems", INVENTORY_API.MAIN.GET_INVENTORY)
exports("registerUsableItem", INVENTORY_API.MAIN.REGISTER_ITEM)
exports("unRegisterUsableItem", INVENTORY_API.MAIN.UNREGISTER_ITEM)
exports("getItemCount", INVENTORY_API.MAIN.GET_ITEM_COUNT)
exports("getItemDB", INVENTORY_API.MAIN.GET_DEFAULT_ITEM)
exports("addItem", INVENTORY_API.MAIN.ADD_ITEM)
exports("subItemById", INVENTORY_API.MAIN.SUB_ITEM_BY_ID)
exports("getItemById", INVENTORY_API.MAIN.GET_ITEM_BY_ID)
exports("subItem", INVENTORY_API.MAIN.SUB_ITEM)
exports("setItemMetadata", INVENTORY_API.MAIN.SET_ITEM_METADATA)
exports("setItemDurability", INVENTORY_API.MAIN.SET_ITEM_DURABILITY)
exports("getItem", INVENTORY_API.MAIN.GET_ITEM)

-- WEAPONS
exports("subAllWeapons", INVENTORY_API.MAIN.REMOVE_ALL_WEAPONS)
exports("getUserWeapon", INVENTORY_API.MAIN.GET_WEAPON_BY_ID)
exports("getUserInventoryWeapons", INVENTORY_API.MAIN.GET_WEAPONS)
exports("getWeaponBullets", INVENTORY_API.MAIN.GET_WEAPON_BULLETS)
exports("removeAllUserAmmo", INVENTORY_API.MAIN.CLEAR_GUNBELT_AMMO)
exports("getUserAmmo", INVENTORY_API.MAIN.GET_GUNBELT_AMMO)
exports("addBullets", INVENTORY_API.MAIN.ADD_AMMO_TO_GUNBELT)
exports("subBullets", InventoryAPI.MAIN.REMOVE_WEAPON_BULLETS)
exports("canCarryWeapons", INVENTORY_API.MAIN.CAN_CARRY_WEAPON)
exports("addWeaponComponent", INVENTORY_API.MAIN.ADD_WEAPON_COMPONENT)
exports("addWeaponComponents", INVENTORY_API.MAIN.ADD_WEAPON_COMPONENTS)
exports("subWeaponComponent", INVENTORY_API.MAIN.REMOVE_WEAPON_COMPONENT)
exports("subWeaponComponents", INVENTORY_API.MAIN.REMOVE_WEAPON_COMPONENTS)
exports("setWeaponCustomLabel", INVENTORY_API.MAIN.SET_WEAPON_CUSTOM_LABEL)
exports("setWeaponSerialNumber", INVENTORY_API.MAIN.SET_WEAPON_CUSTOM_SERIAL_NUMBER)
exports("setWeaponCustomDesc", INVENTORY_API.MAIN.SET_WEAPON_CUSTOM_DESCRIPTION)
exports("getWeaponComponents", INVENTORY_API.MAIN.GET_WEAPON_COMPONENTS)
exports("deleteWeapon", INVENTORY_API.MAIN.DELETE_WEAPON)
exports("createWeapon", INVENTORY_API.MAIN.ADD_WEAPON)
exports("giveWeapon", INVENTORY_API.MAIN.GIVE_WEAPON)
exports("subWeapon", INVENTORY_API.MAIN.REMOVE_WEAPON)

--SECONDARY INVENTORY
exports("registerInventory", INVENTORY_API.SECONDARY.REGISTER)
exports("AddPermissionMoveToCustom", INVENTORY_API.SECONDARY.ADD_PERMISSION_MOVE_TO)
exports("AddPermissionTakeFromCustom", INVENTORY_API.SECONDARY.ADD_PERMISSION_TAKE_FROM)
exports("AddCharIdPermissionMoveToCustom", INVENTORY_API.SECONDARY.ADD_CHAR_ID_PERMISSION_MOVE_TO)
exports("AddCharIdPermissionTakeFromCustom", INVENTORY_API.SECONDARY.ADD_CHAR_ID_PERMISSION_TAKE_FROM)
exports("BlackListCustomAny", INVENTORY_API.SECONDARY.BLACKLIST)
exports("removeInventory", INVENTORY_API.SECONDARY.REMOVE)
exports("updateCustomInventorySlots", INVENTORY_API.SECONDARY.UPDATE_SLOTS)
exports("getCustomInventorySlots", INVENTORY_API.SECONDARY.GET_SLOTS)
exports("setCustomInventoryItemLimit", INVENTORY_API.SECONDARY.SET_ITEM_LIMIT)
exports("setCustomInventoryWeaponLimit", INVENTORY_API.SECONDARY.SET_WEAPON_LIMIT)
exports("openInventory", INVENTORY_API.OPEN_INVENTORY)
exports("closeInventory", INVENTORY_API.CLOSE_INVENTORY)
exports("isCustomInventoryRegistered", INVENTORY_API.SECONDARY.IS_REGISTERED)
exports("getCustomInventoryData", INVENTORY_API.SECONDARY.GET_DATA)
exports("updateCustomInventoryData", INVENTORY_API.SECONDARY.UPDATE_DATA)
exports("openPlayerInventory", INVENTORY_API.PLAYER.OPEN_INVENTORY)
exports("addItemsToCustomInventory", INVENTORY_API.SECONDARY.ADD_ITEMS)
exports("addWeaponsToCustomInventory", INVENTORY_API.SECONDARY.ADD_WEAPONS)
exports('getCustomInventoryItemCount', INVENTORY_API.SECONDARY.GET_ITEM_COUNT)
exports('getCustomInventoryWeaponCount', INVENTORY_API.SECONDARY.GET_WEAPON_COUNT)
exports("removeItemFromCustomInventory", INVENTORY_API.SECONDARY.REMOVE_ITEM)
exports("removeWeaponFromCustomInventory", INVENTORY_API.SECONDARY.REMOVE_WEAPON)
exports("getCustomInventoryItems", INVENTORY_API.SECONDARY.GET_ITEMS)
exports("getCustomInventoryWeapons", INVENTORY_API.SECONDARY.GET_WEAPONS)
exports("removeCustomInventoryWeaponById", INVENTORY_API.SECONDARY.REMOVE_WEAPON_BY_ID)
exports("updateCustomInventoryItem", INVENTORY_API.SECONDARY.UPDATE_ITEM)
exports("deleteCustomInventory", INVENTORY_API.SECONDARY.DELETE)
