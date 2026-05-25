-- holds all items from the server to be accessed by the client
CLIENT_ITEMS = {}
-- holds all items and weapons from the player from the server
PLAYER_INVENTORY = {
	ITEMS = {},
	WEAPONS = {},
	HasItem = function(_, itemName)
		for id, item in pairs(PLAYER_INVENTORY.ITEMS) do
			if item:getName() == itemName then
				return true, id
			end
		end
		return false
	end,
}

local inventory <const> = {
	RECEIVE_ITEM = function(name, id, amount, metadata, degradation, percentage, durability)
		if not name or not CLIENT_ITEMS[name] then
			return
		end

		local item <const> = PLAYER_INVENTORY.ITEMS[id]
		if item then
			item:addCount(amount)
		else
			local newItem <const> = ITEM:Register({
				id = id,
				count = amount,
				limit = CLIENT_ITEMS[name].limit,
				label = CLIENT_ITEMS[name].label,
				name = name,
				metadata = SHARED_UTILS.MERGE_TABLES(CLIENT_ITEMS[name].metadata, metadata),
				type = "item_standard",
				canUse = CLIENT_ITEMS[name].canUse,
				canRemove = CLIENT_ITEMS[name].canRemove,
				desc = CLIENT_ITEMS[name].desc,
				group = CLIENT_ITEMS[name].group or 1,
				rarity = CLIENT_ITEMS[name].rarity or 1,
				durability = durability or CLIENT_ITEMS[name].durability,
				instruction = CLIENT_ITEMS[name].instruction,
				weight = CLIENT_ITEMS[name].weight or 0.25,
				degradation = degradation,
				maxDegradation = CLIENT_ITEMS[name].maxDegradation,
				percentage = percentage
			})
			PLAYER_INVENTORY.ITEMS[id] = newItem
		end
		NUI_SERVICE.INVENTORY.UPDATE_ITEM(id)
	end,
	REMOVE_ITEM = function(id, count)
		local item <const> = PLAYER_INVENTORY.ITEMS[id]
		if not item then return end
		item:quitCount(count)

		if item:getCount() <= 0 then
			NUI_SERVICE.SHARED.REMOVE(id, item.type)
			PLAYER_INVENTORY.ITEMS[id] = nil
		else
			NUI_SERVICE.INVENTORY.UPDATE_ITEM(id)
		end
	end,
	RECEIVE_WEAPON = function(id, propietary, name, ammos, label, serial_number, custom_label, source, custom_desc, weight, components, status)
		local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
		if weapon then return print("Weapon already exists in inventory") end

		local newWeapon <const> = WEAPON:Register({
			id = id,
			propietary = propietary,
			name = name,
			label = custom_label or label,
			ammo = ammos,
			components = components or {},
			currInv = "default",
			dropped = 0,
			used = false,
			used2 = false,
			desc = custom_desc or UTILS.WEAPONS.GET_DEFAULT_DESC(name),
			group = 5,
			source = source,
			serial_number = serial_number,
			custom_label = custom_label,
			custom_desc = custom_desc,
			weight = weight,
			degradation = status?.degradation,
			damage = status?.damage,
			dirt = status?.dirt,
			soot = status?.soot,
		})


		local isPetrolCan = GetWeapontypeGroup(name) == joaat("GROUP_PETROLCAN")
		if isPetrolCan then
			local defaultClipSize <const> = SHARED_DATA.WEAPONS[name] and SHARED_DATA.WEAPONS[name].DefaultClipSize or 20
			newWeapon:addAmmo("AMMO_MOONSHINEJUG_MP", defaultClipSize)
		end

		local isGun = IsWeaponAGun(name) == 1
		if isGun then
			newWeapon:setDefaultAttachments()
			newWeapon:loadAmmo()
		end

		NUI_SERVICE.INVENTORY.UPDATE_WEAPON(id)
	end,
	SET_WEAPON_CUSTOM_LABEL = function(id, label)
		local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
		if not weapon then return end
		weapon:setCustomLabel(label)
	end,
	SET_WEAPON_CUSTOM_DESC = function(id, desc)
		local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
		if not weapon then return end
		weapon:setCustomDesc(desc)
	end,
	SET_WEAPON_SERIAL_NUMBER = function(id, serial_number)
		local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
		if not weapon then return end
		weapon:setSerialNumber(serial_number)
	end,
	ON_SELECTED_CHARACTER = function()
		SetNuiFocus(false, false)
		SendNUIMessage({ action = "hide" })
		TriggerServerEvent("vorpinventory:getItemsTable")
		Wait(300)
		TriggerServerEvent("vorpinventory:getInventory")
		TriggerServerEvent("vorpCore:LoadAllAmmo")
		print("Inventory loaded")
	end,
	PROCESS_ITEMS = function(items)
		CLIENT_ITEMS = {}
		local data = msgpack.unpack(items)
		for _, item in pairs(data) do
			local newItem <const> = ITEM:Register(item)
			CLIENT_ITEMS[item.item] = newItem
		end
	end,
	GET_LOADOUT = function(loadout)
		RemoveAllPedWeapons(CACHE.Ped, true, true)
		RemoveAllPedAmmo(CACHE.Ped)
		print("removed all weapons and ammo")
		Wait(1000)
		print("loaded out")

		for _, weapon in ipairs(loadout) do
			if weapon.currInv == "default" and (weapon.dropped == nil or weapon.dropped == 0) then
				local newWeapon <const> = WEAPON:Register({
					id = tonumber(weapon.id),
					identifier = weapon.identifier,
					label = weapon.custom_label or UTILS.WEAPONS.GET_DEFAULT_LABEL(weapon.name),
					name = weapon.name,
					ammo = weapon.ammo,
					components = weapon.components,
					used = weapon.used,
					used2 = weapon.used2,
					desc = weapon.custom_desc or UTILS.WEAPONS.GET_DEFAULT_DESC(weapon.name),
					currInv = weapon.curr_inv,
					dropped = 0,
					group = 5,
					custom_label = weapon.custom_label,
					serial_number = weapon.serial_number,
					custom_desc = weapon.custom_desc,
					weight = weapon.weight,
					degradation = weapon.degradation,
					damage = weapon.damage,
					dirt = weapon.dirt,
					soot = weapon.soot,
				})

				if CONFIG.AUTO_EQUIP_USED_WEAPONS then
					if newWeapon:getUsed() or newWeapon:getUsed2() then
						if INVENTORY_SERVICE.IS_WEAPON_EQUIP_BLOCKED_BY_LIMIT(newWeapon:getId(), newWeapon:getName()) then
							newWeapon:setUsed(false)
							newWeapon:setUsed2(false)
						else
							INVENTORY_SERVICE.SET_WEAPONS_ON_PLAYER(newWeapon:getId())
						end
					end
				end
			end
		end
		Wait(2000)
		-- need another loop because of get status method
		for _, weapon in pairs(PLAYER_INVENTORY.WEAPONS) do
			if CONFIG.USE_WEAPON_DEGRADATION and (weapon:getUsed() or weapon:getUsed2()) then
				local weaponStatus <const> = weapon:getStatus()
				local payload
				if weaponStatus and next(weaponStatus) then
					payload = {
						degradation = weaponStatus.degradation,
						damage = weaponStatus.damage,
						dirt = weaponStatus.dirt,
						soot = weaponStatus.soot,
					}
				else
					payload = {
						degradation = weapon.degradation,
						damage = weapon.damage,
						dirt = weapon.dirt,
						soot = weapon.soot,
					}
				end
				LAST_CLIENT_WEAPON_STATUS[weapon:getId()] = json.encode(payload)
			end
		end

		HidePedWeapons(CACHE.Ped, 2, true)
		NUI_SERVICE.INVENTORY.GET_LOAD()
	end,
	IS_WEAPON_EQUIP_BLOCKED_BY_LIMIT = function(weaponId, weaponName)
		local shared <const> = SHARED_DATA.WEAPONS[weaponName]
		if not shared then return end

		local cfg <const> = CONFIG.EQUIP_WEAPONS
		if not cfg then return end

		local function getCount(categoryKey)
			local count = 0
			for id, weapon in pairs(PLAYER_INVENTORY.WEAPONS) do
				if id ~= weaponId and (weapon:getUsed() or weapon:getUsed2()) then
					local _shared <const> = SHARED_DATA.WEAPONS[weapon:getName()]
					if _shared and _shared[categoryKey] then
						count = count + 1
					end
				end
			end
			return count
		end

		if shared.LongWeapon and cfg.LONG_WEAPONS and cfg.LONG_WEAPONS > 0 then
			if getCount("LongWeapon") >= cfg.LONG_WEAPONS then
				return true, "long", cfg.LONG_WEAPONS
			end
		end

		if shared.ShortWeapon and cfg.SHORT_WEAPONS and cfg.SHORT_WEAPONS > 0 then
			if getCount("ShortWeapon") >= cfg.SHORT_WEAPONS then
				return true, "short", cfg.SHORT_WEAPONS
			end
		end

		return false
	end,

	SET_WEAPON_USED = function(id, used)
		local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
		if not weapon then return end
		weapon:setUsed(used)
		NUI_SERVICE.INVENTORY.UPDATE_WEAPON(id)
		weapon:equipwep()
	end,
	SET_WEAPONS_ON_PLAYER = function(id)
		local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
		if not weapon then return print("Weapon not found 1") end

		local isMelee <const> = IsWeaponMeleeWeapon(weapon:getName()) == 1
		local isThrowable <const> = IsWeaponThrowable(weapon:getName()) == 1
		local isPetrolCan <const> = GetWeapontypeGroup(weapon:getName()) == joaat("GROUP_PETROLCAN")

		if isMelee or isThrowable or isPetrolCan then
			local ammoCount = 1
			if joaat(weapon:getName()) == `WEAPON_THROWN_THROWING_KNIVES` then
				ammoCount = weapon:getAmmo("AMMO_THROWING_KNIVES")
			end

			if isPetrolCan then
				local defaultClipSize <const> = SHARED_DATA.WEAPONS[weapon:getName()] and SHARED_DATA.WEAPONS[weapon:getName()].DefaultClipSize or 20
				weapon:addAmmo("AMMO_MOONSHINEJUG_MP", defaultClipSize)
				ammoCount = weapon:getAmmo("AMMO_MOONSHINEJUG_MP")
			end

			GiveWeaponToPed(CACHE.Ped, joaat(weapon:getName()), ammoCount, false, true, 0, false, 0.5, 1.0, 0, false, 0.0, false)
			local timer = GetGameTimer()
			repeat Wait(0) until HasPedGotWeapon(CACHE.Ped, joaat(weapon:getName()), 0, false) == 1 or GetGameTimer() - timer > 10000
			if GetGameTimer() - timer > 10000 then
				print("weapon not on ped after 10 seconds")
			end
		else
			GiveWeaponToPed( -- doesnt work with throwables?
				CACHE.Ped,
				joaat(weapon:getName()),
				0,
				false,
				true,
				0,
				false,
				0.5,
				1.0,
				0,
				false,
				0.0,
				false
			)

			if HasPedGotWeapon(CACHE.Ped, joaat(weapon:getName()), 0, false) ~= 1 then
				repeat
					Wait(500)
					GiveWeaponToPed(
						CACHE.Ped,
						joaat(weapon:getName()),
						0,
						false,
						true,
						0,
						false,
						0.5,
						1.0,
						0,
						false,
						0.0,
						false
					)
					print(HasPedGotWeapon(CACHE.Ped, joaat(weapon:getName()), 0, false))
				until HasPedGotWeapon(CACHE.Ped, joaat(weapon:getName()), 0, false) == 1
			end

			if not isMelee and not isThrowable then
				weapon:setDefaultAttachments()
				weapon:loadAmmo()
				weapon:loadComponents()
				SetTimeout(2000, function()
					weapon:setStatus()
				end)
			end
		end

		local serial = weapon:getSerialNumber()
		local info = { weaponId = id, serialNumber = serial }
		local weapName = joaat(weapon:getName())
		local key = string.format("GetEquippedWeaponData_%d", weapName)
		LocalPlayer.state:set(key, info, true)
	end,

	GET_INVENTORY = function(inventory)
		PLAYER_INVENTORY.ITEMS = {}
		local inventoryItems <const> = msgpack.unpack(inventory)

		for _, item in pairs(inventoryItems) do
			local newItem <const> = ITEM:Register({
				id = item.id,
				count = item.count,
				limit = item.limit,
				label = item.label,
				name = item.name,
				metadata = item.metadata,
				type = item.type,
				canUse = item.canUse,
				canRemove = item.canRemove,
				desc = item.desc,
				owner = item.owner,
				group = item.group,
				rarity = item.rarity,
				durability = item.durability,
				instruction = item.instruction,
				weight = item.weight,
				degradation = item.degradation,
				maxDegradation = item.maxDegradation,
				percentage = item.percentage
			})
			PLAYER_INVENTORY.ITEMS[item.id] = newItem
		end
	end,
	ASK_TO_GIVE_ITEMS = function(cb, data)
		local giveLabel
		if data.type == "item_money" then
			giveLabel = data.amount .. "$"
		elseif data.type == "item_gold" then
			giveLabel = data.amount .. " gold"
		elseif data.type == "item_ammo" then
			giveLabel = data.amount .. " ammo"
		elseif data.type == "item_standard" then
			local itemName <const> = data.itemName
			local itemCount <const> = data.itemCount
			local itemLabel <const> = CLIENT_ITEMS[itemName] and CLIENT_ITEMS[itemName].label or itemName
			giveLabel = itemCount .. " " .. itemLabel
		elseif data.type == "item_weapon" then
			local weaponName <const> = data.weaponName
			local weaponLabel <const> = SHARED_DATA.WEAPONS[weaponName] and SHARED_DATA.WEAPONS[weaponName].label or weaponName
			giveLabel = weaponLabel
		else
			giveLabel = "something"
		end
		CORE.NotifyObjective(LANG.someoneWantsToGiveYouSomething, 5000)

		local timeoutMs <const> = 5000
		local timer <const> = GetGameTimer()
		local group <const> = GetRandomIntInRange(0, 0xffffff)
		local function createPrompt(control, label)
			local prompt <const> = UiPromptRegisterBegin()
			UiPromptSetControlAction(prompt, control)
			UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', label))
			UiPromptSetEnabled(prompt, true)
			UiPromptSetVisible(prompt, true)
			UiPromptSetStandardMode(prompt, true)
			UiPromptSetGroup(prompt, group, 0)
			UiPromptRegisterEnd(prompt)
			return prompt
		end

		local acceptPrompt <const> = createPrompt(`INPUT_FRONTEND_ACCEPT`, "Accept")
		local cancelPrompt <const> = createPrompt(`INPUT_FRONTEND_CANCEL`, "Deny")
		local accepted = false

		repeat
			Wait(0)
			local remainingSec <const> = math.max(0, math.ceil((timeoutMs - (GetGameTimer() - timer)) / 1000))
			local label <const> = VarString(10, 'LITERAL_STRING', ("Receive %s (%ds)"):format(giveLabel, remainingSec))
			UiPromptSetActiveGroupThisFrame(group, label, 0, 0, 0, 0)

			if UiPromptHasStandardModeCompleted(acceptPrompt, 0) then
				accepted = true
				break
			end

			if UiPromptHasStandardModeCompleted(cancelPrompt, 0) then
				accepted = false
				break
			end
		until GetGameTimer() - timer > timeoutMs

		UiPromptDelete(cancelPrompt)
		UiPromptDelete(acceptPrompt)

		return cb(accepted)
	end
}

INVENTORY_SERVICE = inventory
