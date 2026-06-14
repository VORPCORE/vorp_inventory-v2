local PLAYER_AMMO_INFO  = {
    ammo = {}
}
local UPDATE_AMMO_CACHE = {}
local canUpdateAmmo     = true
local LIB <const>       = Import "events"
local EVENT <const>     = LIB.Events
local THROWABLE_AMMO_TYPES <const> = {
    [`WEAPON_THROWN_THROWING_KNIVES`] = "AMMO_THROWING_KNIVES",
    [`WEAPON_THROWN_BOLAS`] = "AMMO_BOLAS",
    [`WEAPON_THROWN_BOLAS_HAWKMOTH`] = "AMMO_BOLAS_HAWKMOTH",
    [`WEAPON_THROWN_BOLAS_INTERTWINED`] = "AMMO_BOLAS_INTERTWINED",
    [`WEAPON_THROWN_BOLAS_IRONSPIKED`] = "AMMO_BOLAS_IRONSPIKED",
    [`WEAPON_THROWN_TOMAHAWK`] = "AMMO_TOMAHAWK",
    [`WEAPON_THROWN_TOMAHAWK_ANCIENT`] = "AMMO_TOMAHAWK",
    [`WEAPON_THROWN_MOLOTOV`] = "AMMO_MOLOTOV",
    [`WEAPON_THROWN_POISONBOTTLE`] = "AMMO_POISONBOTTLE",
    [`WEAPON_THROWN_DYNAMITE`] = "AMMO_DYNAMITE",
}

local Ammo <const> = {
    ADD_AMMO_TO_PED = function(ammoData)
        if not ammoData then return end

        local playerPed <const> = PlayerPedId()
        for ammoType, ammo in pairs(ammoData) do
            SetPedAmmoByType(playerPed, joaat(ammoType), ammo)
        end
    end,
    RESTORE_PED_AMMO = function()
        if CONFIG.MANUAL_WEAPON_RELOAD then return end
        if not PLAYER_AMMO_INFO.ammo then return end

        AMMO_SERVICE.ADD_AMMO_TO_PED(PLAYER_AMMO_INFO.ammo)
    end,

    UPDATE_AMMO = function(ammoData, setAmmoToPed, isSource, removeAll)
        PLAYER_AMMO_INFO.ammo = ammoData.ammo
        if not CONFIG.MANUAL_WEAPON_RELOAD then return end

        SendNUIMessage({ action = "updateammo", ammo = ammoData.ammo })

        if setAmmoToPed then
            if not CONFIG.MANUAL_WEAPON_RELOAD then
                RemoveAllPedWeapons(CACHE.Ped, true, true)
                RemoveAllPedAmmo(CACHE.Ped)
                AMMO_SERVICE.ADD_AMMO_TO_PED(PLAYER_AMMO_INFO.ammo)
            end
            if not isSource then
                CORE.NotifyRightTip("you have received ammo for your weapons", 2000)
            else
                CORE.NotifyRightTip("you have transferred your ammo", 2000)
            end
        end

        if removeAll then
            RemoveAllPedWeapons(CACHE.Ped, true, true)
            RemoveAllPedAmmo(CACHE.Ped)
            for _, weapon in pairs(PLAYER_INVENTORY.WEAPONS) do
                weapon:cleanAllAmmoFromClip()
            end
        end
    end,
    UPDATE_UI_AMMO_COUNT = function(ammo)
        SendNUIMessage({ action = "updateammo", ammo = ammo })
        NUI_SERVICE.INVENTORY.GET_LOAD()
    end,
    SET_AMMO_TO_PED = function(ammoData)
        if CONFIG.MANUAL_WEAPON_RELOAD then return end

        RemoveAllPedWeapons(CACHE.Ped, true, true)
        RemoveAllPedAmmo(CACHE.Ped)
        AMMO_SERVICE.ADD_AMMO_TO_PED(ammoData)
    end,
    LOAD_AMMO = function(ammoData)
        SendNUIMessage({ action = "reclabels", labels = SHARED_DATA.AMMO_LABEL })
        PLAYER_AMMO_INFO = ammoData or {}

        AMMO_SERVICE.RESTORE_PED_AMMO()
        SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
    end,
    REMOVE_BULLETS_FROM_WEAPON = function(weaponId, ammoType)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        if weapon then
            weapon:cleanAmmoFromClip(ammoType)
            local bows = { [`WEAPON_BOW`] = true, [`WEAPON_BOW_IMPROVED`] = true }

            if CACHE.Weapon ~= `WEAPON_UNARMED` and joaat(weapon:getName()) == CACHE.Weapon then
                local _, ammo = GetAmmoInClip(CACHE.Ped, CACHE.Weapon)
                if bows[CACHE.Weapon] or IsWeaponThrowable(joaat(weapon:getName())) == 1 then
                    ammo = GetAmmoInPedWeapon(CACHE.Ped, CACHE.Weapon)
                end
                RemoveAmmoFromPedByType(CACHE.Ped, ammoType, ammo, `REMOVE_REASON_DROPPED`)
            end

            if not bows[CACHE.Weapon] then
                TaskReloadWeapon(CACHE.Ped, true)
            end

            NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
        end
    end,
    AMMO_TOGGLE = function(state)
        if not canUpdateAmmo and state then
            local result <const> = CORE.Callback.TriggerAwait("vorp_inventory:callback:GetAmmoInfo")
            if not result then return end

            PLAYER_AMMO_INFO = result or {}
            AMMO_SERVICE.ADD_AMMO_TO_PED(PLAYER_AMMO_INFO.ammo)
            SendNUIMessage({
                action = "updateammo",
                ammo   = PLAYER_AMMO_INFO.ammo
            })
        end
        canUpdateAmmo = state
    end,

    GET_ALLOWED_AMMO_TYPES = function(id)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
        if not weapon then return {} end

        local weaponName <const> = weapon:getName()
        local group <const> = GetWeapontypeGroup(joaat(weaponName))
        local ammoData <const> = SHARED_DATA.AMMO_TYPES[group] or {}

        local seen = {}
        local ammoAllowed = {}

        local function addType(ammoType)
            local weaponRestrictions = SHARED_DATA.AMMO_WEAPON_RESTRICTIONS and SHARED_DATA.AMMO_WEAPON_RESTRICTIONS[ammoType]
            if not ammoData[ammoType] or seen[ammoType] or (weaponRestrictions and not weaponRestrictions[weaponName]) then
                return
            end
            seen[ammoType] = true
            ammoAllowed[#ammoAllowed + 1] = ammoType
        end

        for ammoType, _ in pairs(ammoData) do
            local beltAmount = PLAYER_AMMO_INFO.ammo[ammoType]
            if beltAmount and beltAmount > 0 then
                addType(ammoType)
            end
        end

        for ammoType, _ in pairs(weapon:getAllAmmo()) do
            addType(ammoType)
        end

        return ammoAllowed
    end,
    GET_THROWABLE_AMMO_TYPE = function(weaponHash)
        return THROWABLE_AMMO_TYPES[weaponHash]
    end,
    GET_GUNBELT_AMMO = function(ammoType)
        if not PLAYER_AMMO_INFO.ammo then return nil end
        return PLAYER_AMMO_INFO.ammo[ammoType]
    end,
}

AMMO_SERVICE       = Ammo


if not CONFIG.MANUAL_WEAPON_RELOAD then
    local lastTrackedWeapon = `WEAPON_UNARMED`
    local skipAmmoReadUntil = 0

    --* AMMO SAVING THREAD
    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession

        while true do
            local sleep = 500
            -- this thread is to remove ammo one by one so we dont loose the ammo that is on the weapon if we diconnect
            if not IS_INV_OPEN and PLAYER_AMMO_INFO.ammo and not CACHE.IsDead then
                local playerPedId <const> = CACHE.Ped
                local isArmed <const> = IsPedArmed(playerPedId, 4) == 1
                local wephash <const> = GetPedCurrentHeldWeapon(playerPedId)
                local ismelee <const> = IsWeaponMeleeWeapon(wephash) == 1
                local wepgroup <const> = GetWeapontypeGroup(wephash)
                local ammotypes <const> = SHARED_DATA.AMMO_TYPES[wepgroup]
                -- if ammotypes then
                local isThrownGroup <const> = wepgroup == `GROUP_THROWN`
                local isBowGroup <const> = wepgroup == `GROUP_BOW`
                local isPetrol <const> = wepgroup == `GROUP_PETROLCAN`

                local weaponChanged <const> = wephash ~= lastTrackedWeapon
                if weaponChanged then
                    lastTrackedWeapon = wephash

                    if ammotypes and wephash ~= `WEAPON_UNARMED` then
                        local shouldRestoreAmmo = false
                        for ammo_type, _ in pairs(ammotypes) do
                            local beltAmmo <const> = PLAYER_AMMO_INFO.ammo[ammo_type]
                            if beltAmmo and beltAmmo > 0 then
                                local pedAmmo = GetPedAmmoByType(playerPedId, joaat(ammo_type))
                                if (isThrownGroup or isBowGroup or isPetrol) and pedAmmo == 1 then
                                    pedAmmo = 0
                                end

                                if pedAmmo <= 0 then
                                    shouldRestoreAmmo = true
                                    break
                                end
                            end
                        end

                        if shouldRestoreAmmo then
                            AMMO_SERVICE.ADD_AMMO_TO_PED(PLAYER_AMMO_INFO.ammo)
                            skipAmmoReadUntil = GetGameTimer() + 750
                        end
                    end
                end

                if ammotypes and (isArmed or isThrownGroup or isPetrol) and not ismelee and GetGameTimer() >= skipAmmoReadUntil then
                    local shouldUpdateUi = false

                    for ammo_type, _ in pairs(ammotypes) do
                        local value = PLAYER_AMMO_INFO.ammo[ammo_type]
                        if value ~= nil then
                            local ammoQty = GetPedAmmoByType(playerPedId, joaat(ammo_type))

                            if (isThrownGroup or isBowGroup or isPetrol) and ammoQty == 1 then
                                ammoQty = 0
                            end

                            if value ~= ammoQty then
                                PLAYER_AMMO_INFO.ammo[ammo_type] = ammoQty
                                UPDATE_AMMO_CACHE[ammo_type] = ammoQty
                                shouldUpdateUi = true
                            end
                        end
                    end

                    if shouldUpdateUi then
                        SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
                    end
                end
            end
            Wait(sleep)
        end
    end)


    CreateThread(function()
        repeat Wait(2000) until LocalPlayer.state.IsInSession

        while true do
            local sleep = 15000
            if not CACHE.IsDead then
                sleep = 10000
                if canUpdateAmmo then
                    if next(UPDATE_AMMO_CACHE) then
                        -- need in case of crash or disconnect to make sure its saved
                        TriggerServerEvent("vorpinventory:updateammo", PLAYER_AMMO_INFO)
                        UPDATE_AMMO_CACHE = {}
                    end
                end
            end
            Wait(sleep)
        end
    end)
else
    local WEAPONS_UPDATE              = {}
    local isReloading                 = false
    local IsPedArmed                  = IsPedArmed
    local GetAmmoInPedWeapon          = GetAmmoInPedWeapon
    local GetPedWeaponObject          = GetPedWeaponObject
    local GetCurrentPedWeaponAmmoType = GetCurrentPedWeaponAmmoType
    local IsPedShooting               = IsPedShooting
    local IsWeaponMeleeWeapon         = IsWeaponMeleeWeapon
    local IsPedReloading              = IsPedReloading
    local GetMaxAmmoInClip            = GetMaxAmmoInClip

    local BOWS <const>                = {
        [`WEAPON_BOW`] = true,
        [`WEAPON_BOW_IMPROVED`] = true,
    }
    local SELECTED_AMMO_TYPES         = {}

    local function getAmmoFromGunbelt(ammoTypeName)
        local ammoInBelt <const> = PLAYER_AMMO_INFO.ammo[ammoTypeName]
        if ammoInBelt and ammoInBelt > 0 then
            return ammoInBelt
        end
        return 0
    end

    local function getOtherLoadedAmmoType(weapon, ammoTypeName)
        if not weapon then return end

        for loadedAmmoType, amount in pairs(weapon:getAllAmmo()) do
            amount = tonumber(amount) or 0
            if loadedAmmoType ~= ammoTypeName and amount > 0 then
                return loadedAmmoType
            end
        end
    end

    local function getCurrentAmmoTypeName(playerPedId)
        local ammoHash <const> = GetCurrentPedWeaponAmmoType(playerPedId, GetPedWeaponObject(playerPedId, true))
        return SHARED_DATA.AMMO_TYPE_HASH[ammoHash]
    end

    local function clearPedAmmoType(playerPedId, ammoTypeName)
        local ammoHash <const> = joaat(ammoTypeName)
        local ammoAmount <const> = GetPedAmmoByType(playerPedId, ammoHash)
        if ammoAmount > 0 then
            RemoveAmmoFromPedByType(playerPedId, ammoHash, ammoAmount, `REMOVE_REASON_DROPPED`)
        end
        SetPedAmmoByType(playerPedId, ammoHash, 0)
    end

    local function enforceSelectedAmmoType(playerPedId, weaponHash, weaponId)
        if not weaponId or weaponId <= 0 then return end

        local currentAmmoType <const> = getCurrentAmmoTypeName(playerPedId)
        local ammoTypes <const> = SHARED_DATA.AMMO_TYPES[GetWeapontypeGroup(weaponHash)]
        local userWeapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        local selectedAmmoType = SELECTED_AMMO_TYPES[weaponId]
        if not selectedAmmoType then
            if userWeapon then
                if currentAmmoType and userWeapon:getAmmo(currentAmmoType) > 0 then
                    selectedAmmoType = currentAmmoType
                else
                    local emptyAmmoType = nil
                    for ammoTypeName, amount in pairs(userWeapon:getAllAmmo()) do
                        if tonumber(amount) and tonumber(amount) > 0 then
                            selectedAmmoType = ammoTypeName
                            break
                        end
                        emptyAmmoType = emptyAmmoType or ammoTypeName
                    end
                    selectedAmmoType = selectedAmmoType or emptyAmmoType
                end
            else
                selectedAmmoType = currentAmmoType
            end
            SELECTED_AMMO_TYPES[weaponId] = selectedAmmoType
        end
        if not selectedAmmoType then
            if ammoTypes then
                SetPedAmmo(playerPedId, weaponHash, 0)
                for ammoTypeName, _ in pairs(ammoTypes) do
                    clearPedAmmoType(playerPedId, ammoTypeName)
                end
            end
            return false
        end

        if ammoTypes then
            for ammoTypeName, _ in pairs(ammoTypes) do
                if ammoTypeName ~= selectedAmmoType then
                    clearPedAmmoType(playerPedId, ammoTypeName)
                end
            end
        end

        if currentAmmoType ~= selectedAmmoType then
            SetPedAmmo(playerPedId, weaponHash, 0)
            if currentAmmoType then
                clearPedAmmoType(playerPedId, currentAmmoType)
            end
            SetAmmoTypeForPedWeapon(playerPedId, weaponHash, joaat(selectedAmmoType))
        end

        local hasSelectedAmmo = true
        if userWeapon and userWeapon:getAmmo(selectedAmmoType) <= 0 then
            hasSelectedAmmo = false
            SetPedAmmo(playerPedId, weaponHash, 0)
            clearPedAmmoType(playerPedId, selectedAmmoType)
        end

        if not ammoTypes then return end

        return hasSelectedAmmo
    end

    local function reloadBow(id)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]

        local function getObjectIndexFromPed()
            for attachPoint = 0, 29 do
                local _, _weapon <const> = GetCurrentPedWeapon(CACHE.Ped, true, attachPoint, false)
                if BOWS[_weapon] then
                    return GetObjectIndexFromEntityIndex(GetCurrentPedWeaponEntityIndex(CACHE.Ped, attachPoint)), _weapon
                end
            end

            return 0
        end

        local object <const>, weaponHash <const> = getObjectIndexFromPed()
        if object == 0 then return print("object not found") end

        local ammoType <const> = GetCurrentPedWeaponAmmoType(CACHE.Ped, object)
        if not ammoType then return print("ammo type not found") end

        local ammoTypeName <const> = SHARED_DATA.AMMO_TYPE_HASH[ammoType]
        if not ammoTypeName then return print("ammo type not found") end

        local ammoInBelt <const> = getAmmoFromGunbelt(ammoTypeName)

        if ammoInBelt > 0 and weapon then
            local maxAmmoInClip <const> = weapon:getDefaultClipSize()
            local ammoInWeapon <const> = GetAmmoInPedWeapon(CACHE.Ped, weaponHash)
            if ammoInWeapon >= weapon:getDefaultClipSize() then
                return CORE.NotifyRightTip("max arrows in weapon reached", 2000)
            end

            if ammoInBelt < maxAmmoInClip then
                local roundsNeeded <const> = math.max(0, maxAmmoInClip - ammoInWeapon)
                local amountToLoad <const> = math.min(roundsNeeded, ammoInBelt)

                if amountToLoad > 0 then
                    SetPedAmmo(CACHE.Ped, weaponHash, amountToLoad)
                    weapon:addAmmoToClip(ammoTypeName, amountToLoad)
                    PLAYER_AMMO_INFO.ammo[ammoTypeName] = math.max(0, PLAYER_AMMO_INFO.ammo[ammoTypeName] - amountToLoad)
                end
            else
                -- if weapon has ammo we only need to add the rest to complete the clip
                local roundsNeeded <const> = math.max(0, maxAmmoInClip - ammoInWeapon)
                local amountToLoad <const> = math.min(roundsNeeded, ammoInBelt)

                if amountToLoad > 0 then
                    SetPedAmmo(CACHE.Ped, weaponHash, amountToLoad)
                    weapon:addAmmoToClip(ammoTypeName, amountToLoad)
                    PLAYER_AMMO_INFO.ammo[ammoTypeName] = math.max(0, PLAYER_AMMO_INFO.ammo[ammoTypeName] - amountToLoad)
                end
            end

            NUI_SERVICE.INVENTORY.UPDATE_WEAPON(id)
            SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
        else
            CORE.NotifyRightTip("you do not have anymore arrows", 2000)
        end
    end

    local function reloadKnives(id)
        local weapon <const> = PLAYER_INVENTORY.WEAPONS[id]
        if weapon then
            -- get ammo from gun belt
            local ammoTypeName <const> = "AMMO_THROWING_KNIVES"

            local ammoInBelt <const> = getAmmoFromGunbelt(ammoTypeName)
            if ammoInBelt > 0 then
                local maxAmmoInClip <const> = weapon:getDefaultClipSize()
                local ammoInWeapon <const> = GetAmmoInPedWeapon(CACHE.Ped, joaat(weapon:getName())) -- if is more than 0 has weapon in hand and is more than 0
                if ammoInWeapon > 0 then
                    if ammoInWeapon >= weapon:getDefaultClipSize() then
                        return CORE.NotifyRightTip("max knives in weapon reached", 2000)
                    end
                end

                if ammoInBelt < maxAmmoInClip then
                    local roundsNeeded = math.max(0, maxAmmoInClip - ammoInWeapon)
                    local amountToLoad = math.min(roundsNeeded, ammoInBelt)

                    if ammoInWeapon > 0 then
                        SetPedAmmo(CACHE.Ped, joaat(weapon:getName()), amountToLoad)
                    else
                        SetPedAmmo(CACHE.Ped, joaat(weapon:getName()), amountToLoad)
                        GiveDelayedWeaponToPed(CACHE.Ped, joaat(weapon:getName()), amountToLoad, true, 0)
                    end
                    weapon:addAmmoToClip(ammoTypeName, amountToLoad)
                    PLAYER_AMMO_INFO.ammo[ammoTypeName] = math.max(0, PLAYER_AMMO_INFO.ammo[ammoTypeName] - amountToLoad)
                else
                    local roundsNeeded = math.max(0, maxAmmoInClip - ammoInWeapon)
                    local amountToLoad = math.min(roundsNeeded, ammoInBelt)

                    if ammoInWeapon > 0 then
                        SetPedAmmo(CACHE.Ped, joaat(weapon:getName()), amountToLoad)
                    else
                        SetPedAmmo(CACHE.Ped, joaat(weapon:getName()), amountToLoad)
                        GiveDelayedWeaponToPed(CACHE.Ped, joaat(weapon:getName()), amountToLoad, true, 0)
                    end

                    weapon:addAmmoToClip(ammoTypeName, amountToLoad)
                    PLAYER_AMMO_INFO.ammo[ammoTypeName] = math.max(0, PLAYER_AMMO_INFO.ammo[ammoTypeName] - amountToLoad)
                end

                NUI_SERVICE.INVENTORY.UPDATE_WEAPON(id)
                SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
            end
        end
    end


    local function reloadWeapon()
        local retval = IsPlayerFreeAiming(CACHE.Player)
        if not retval then
            local currentAmmoTypeHash <const> = GetCurrentPedWeaponAmmoType(CACHE.Ped, GetPedWeaponObject(CACHE.Ped, true))
            local ammoTypeName <const> = SHARED_DATA.AMMO_TYPE_HASH[currentAmmoTypeHash]

            local serverAmmoInfo <const> = CORE.Callback.TriggerAwait("vorp_inventory:callback:GetAmmoInfo")
            if serverAmmoInfo and serverAmmoInfo.ammo then
                PLAYER_AMMO_INFO = serverAmmoInfo
                SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
            end

            local ammoInBelt <const> = getAmmoFromGunbelt(ammoTypeName)
            if ammoInBelt > 0 then
                local weapon = CACHE.Weapon
                local _, ammoInClip = GetAmmoInClip(CACHE.Ped, weapon)
                local maxAmmoInClip = GetMaxAmmoInClip(CACHE.Ped, weapon, true)
                local roundsNeeded = math.max(0, maxAmmoInClip - ammoInClip)
                local amountToLoad = math.min(roundsNeeded, ammoInBelt)
                local finalAmmoInWeapon = math.min(maxAmmoInClip, ammoInClip + amountToLoad)

                if amountToLoad > 0 then
                    -- could possibly add minigame if they fail it adds half ammo

                    -- contains the weapon id
                    local key = string.format("GetEquippedWeaponData_%d", weapon)
                    local weaponData = LocalPlayer.state[key]
                    if weaponData then
                        local userWeapon <const> = PLAYER_INVENTORY.WEAPONS[weaponData.weaponId]
                        local otherAmmoType <const> = getOtherLoadedAmmoType(userWeapon, ammoTypeName)
                        if otherAmmoType then
                            local ammoLabel <const> = SHARED_DATA.AMMO_LABEL[otherAmmoType] or otherAmmoType
                            return CORE.NotifyRightTip("Unload " .. ammoLabel .. " first", 4000)
                        end

                        SELECTED_AMMO_TYPES[weaponData.weaponId] = ammoTypeName
                        enforceSelectedAmmoType(CACHE.Ped, weapon, weaponData.weaponId)
                    end
                    if weaponData and WEAPONS_UPDATE[weaponData.weaponId] then
                        TriggerServerEvent("vorpinventory:updateweapons", { [weaponData.weaponId] = WEAPONS_UPDATE[weaponData.weaponId] })
                        WEAPONS_UPDATE[weaponData.weaponId] = nil
                    end

                    isReloading = true

                    AddAmmoToPedByType(CACHE.Ped, GetHashKey(ammoTypeName), amountToLoad, 0)
                    SetAmmoTypeForPedWeapon(CACHE.Ped, weapon, GetHashKey(ammoTypeName))

                    MakePedReload(CACHE.Ped)
                    repeat Wait(0) until IsPedReloading(CACHE.Ped)
                    repeat
                        Wait(0)
                        DisableControlAction(0, `INPUT_ATTACK`, true)
                        DisableControlAction(0, `INPUT_MELEE_ATTACK`, true)
                    until not IsPedReloading(CACHE.Ped)

                    if ammoInBelt < maxAmmoInClip then
                        SetPedAmmo(CACHE.Ped, weapon, finalAmmoInWeapon)

                        if weaponData then
                            local userWeapon <const> = PLAYER_INVENTORY.WEAPONS[weaponData.weaponId]
                            if userWeapon then
                                userWeapon:addAmmoToClip(ammoTypeName, amountToLoad) -- updates server
                                NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponData.weaponId)
                            end
                        end

                        PLAYER_AMMO_INFO.ammo[ammoTypeName] = math.max(0, PLAYER_AMMO_INFO.ammo[ammoTypeName] - amountToLoad)
                        SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
                    else
                        SetPedAmmo(CACHE.Ped, weapon, finalAmmoInWeapon)
                        if weaponData then
                            local userWeapon <const> = PLAYER_INVENTORY.WEAPONS[weaponData.weaponId]
                            if userWeapon then
                                userWeapon:addAmmoToClip(ammoTypeName, amountToLoad) -- updates server
                                NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponData.weaponId)
                            end
                        end

                        PLAYER_AMMO_INFO.ammo[ammoTypeName] = math.max(0, PLAYER_AMMO_INFO.ammo[ammoTypeName] - amountToLoad)
                        SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
                    end

                    -- so we dont spam reload
                    SetTimeout(CONFIG.RELOAD_WAIT, function()
                        isReloading = false
                    end)
                end
            end
        else
            CORE.NotifyRightTip("you cannot reload while aiming", 2000)
        end
    end

    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession

        local DisableControlAction         = DisableControlAction
        local IsDisabledControlJustPressed = IsDisabledControlJustPressed


        while true do
            local sleep = 1000
            if not CACHE.IsDead and not IS_INV_OPEN then
                local weaponHash = CACHE.Weapon
                if weaponHash == `WEAPON_UNARMED` then
                    weaponHash = GetPedCurrentHeldWeapon(CACHE.Ped)
                end

                local isGun <const> = weaponHash and Citizen.InvokeNative(0x705BE297EEBDB95D, weaponHash)
                if isGun and weaponHash ~= 0 and weaponHash ~= `WEAPON_UNARMED` and not BOWS[weaponHash] then
                    local weaponId <const> = UTILS.INVENTORY.GET_WEAPON_ID(weaponHash)
                    if weaponId > 0 then
                        sleep = 0
                        local hasWeaponAmmo <const> = enforceSelectedAmmoType(CACHE.Ped, weaponHash, weaponId)
                        if hasWeaponAmmo == false then
                            DisablePlayerFiring(CACHE.Player, true)
                            DisableControlAction(0, `INPUT_ATTACK`, true)
                        end
                    end
                end

                if IsPedArmed(CACHE.Ped, 4) == 1 and CACHE.Weapon ~= `WEAPON_UNARMED` and not BOWS[CACHE.Weapon] then
                    sleep = 0
                    DisableControlAction(0, `INPUT_RELOAD`, true)
                    DisableControlAction(1, `INPUT_RELOAD`, true)
                    DisableControlAction(2, `INPUT_RELOAD`, true)
                    if (IsDisabledControlJustPressed(0, `INPUT_RELOAD`) or IsDisabledControlJustPressed(1, `INPUT_RELOAD`) or IsDisabledControlJustPressed(2, `INPUT_RELOAD`)) and not isReloading then
                        reloadWeapon()
                    end
                end
            end
            Wait(sleep)
        end
    end)


    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession


        while true do
            local sleep = 800

            if not IS_INV_OPEN and not CACHE.IsDead and CACHE.Weapon ~= `WEAPON_UNARMED` then
                local playerPedId <const> = CACHE.Ped
                local isArmed <const> = IsPedArmed(playerPedId, 4) == 1 -- only works for guns and bows check with other weapons too

                if isArmed then
                    sleep = 300
                    local wephash <const> = CACHE.Weapon
                    local ismelee <const> = IsWeaponMeleeWeapon(wephash) == 1
                    local isThrowable <const> = IsWeaponThrowable(wephash) == 1

                    if not isThrowable and not ismelee then
                        local isReloading <const> = IsPedReloading(playerPedId)
                        if not isReloading then
                            sleep = 0
                            local isShooting <const> = IsPedShooting(playerPedId) -- only works at 0 frames
                            if isShooting then
                                local ammoHash <const> = GetCurrentPedWeaponAmmoType(playerPedId, GetPedWeaponObject(playerPedId, true))
                                local ammoTypeName <const> = SHARED_DATA.AMMO_TYPE_HASH[ammoHash]
                                local beltAmmo <const> = PLAYER_AMMO_INFO.ammo[ammoTypeName]

                                if ammoTypeName and beltAmmo then
                                    local weaponId <const> = UTILS.INVENTORY.GET_WEAPON_ID(wephash)
                                    local userWeapon = nil
                                    if weaponId > 0 then
                                        userWeapon = PLAYER_INVENTORY.WEAPONS[weaponId]
                                        if userWeapon then
                                            userWeapon:subAmmoFromClip(ammoTypeName, 1)
                                            NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
                                        end

                                        local fired <const> = WEAPONS_UPDATE[weaponId] and WEAPONS_UPDATE[weaponId].fired or 0

                                        local maxAmmoInClip <const> = not BOWS[CACHE.Weapon] and GetMaxAmmoInClip(playerPedId, wephash, true) or userWeapon and userWeapon:getDefaultClipSize() or 0
                                        WEAPONS_UPDATE[weaponId] = { ammoTypeName = ammoTypeName, fired = math.min(fired + 1, maxAmmoInClip) }
                                    end
                                end
                            end
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end)

    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession

        while true do
            local sleep = 15000
            if not CACHE.IsDead then
                sleep = 10000
                if next(WEAPONS_UPDATE) then
                    TriggerServerEvent("vorpinventory:updateweapons", WEAPONS_UPDATE)
                    WEAPONS_UPDATE = {}
                end
            end
            Wait(sleep)
        end
    end)

    local function isWeaponAGun(weaponHash)
        return Citizen.InvokeNative(0x705BE297EEBDB95D, weaponHash)
    end

    RegisterNUICallback("setWeaponAmmoType", function(data, cb)
        cb("ok")
        if not CONFIG.MANUAL_WEAPON_RELOAD then return end

        local weaponId <const> = data.id
        local ammoTypeName <const> = data.ammoType
        local weaponName <const> = data.weaponName

        local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        if not weapon then return CORE.NotifyRightTip("Weapon not found", 2000) end
        if weapon:getName() ~= weaponName then return print("setWeaponAmmoType: weapon name mismatch") end

        local allowed <const> = AMMO_SERVICE.GET_ALLOWED_AMMO_TYPES(weaponId)
        local isAllowed = false
        for i = 1, #allowed do
            if allowed[i] == ammoTypeName then
                isAllowed = true
                break
            end
        end
        if not isAllowed then
            return CORE.NotifyRightTip("This ammo type does not fit this weapon", 4000)
        end

        if not weapon:getUsed() and not weapon:getUsed2() then
            return CORE.NotifyRightTip("Equip this weapon first", 2000)
        end

        local ammoTypeHash <const> = GetPedAmmoTypeFromWeapon(CACHE.Ped, joaat(weaponName)) -- cant set what is already set
        if ammoTypeHash == joaat(ammoTypeName) then
            return CORE.NotifyRightTip("This weapon already has this ammo type set, reload your weapon to add ammo", 2000)
        end

        local otherAmmoType <const> = getOtherLoadedAmmoType(weapon, ammoTypeName)
        if otherAmmoType then
            local ammoLabel <const> = SHARED_DATA.AMMO_LABEL[otherAmmoType] or otherAmmoType
            return CORE.NotifyRightTip("Unload " .. ammoLabel .. " first", 4000)
        end

        SetAmmoTypeForPedWeapon(CACHE.Ped, joaat(weaponName), joaat(ammoTypeName))
        SELECTED_AMMO_TYPES[weaponId] = ammoTypeName
        local amount <const> = weapon:getAmmo(ammoTypeName) -- if exists in ammo use this other wise player must reload
        if amount > 0 then
            SetPedAmmoByType(CACHE.Ped, joaat(ammoTypeName), amount)
        else
            SetPedAmmo(CACHE.Ped, joaat(weaponName), 0)
            SetPedAmmoByType(CACHE.Ped, joaat(ammoTypeName), 0)
            local ammoLabel <const> = SHARED_DATA.AMMO_LABEL[ammoTypeName] or ammoTypeName
            CORE.NotifyRightTip("Ammo type set to " .. ammoLabel .. " Reload your weapon to add ammo", 4000)
        end
    end)

    RegisterNUICallback("removeBullets", function(data, cb)
        cb("ok")
        if not CONFIG.MANUAL_WEAPON_RELOAD then return end

        local weaponId <const> = PLAYER_INVENTORY.WEAPONS[data.id]
        if not weaponId then return print("weapon not found") end
        local weaponName <const> = weaponId:getName()

        if CACHE.Weapon == `WEAPON_UNARMED` then
            SetCurrentPedWeapon(CACHE.Ped, joaat(weaponName), false, 0, false, false)
            Wait(1000)
        end

        local function canAddToGunbelt(ammoTypeName, amount)
            local maxAmmoInBelt <const> = SHARED_DATA.MAX_AMMO_BELT[ammoTypeName]
            if amount > maxAmmoInBelt then
                CORE.NotifyRightTip("Gunbelt cant hold this much ammo, max is : " .. maxAmmoInBelt, 2000)
                return false
            end
            return true
        end

        local isThrowable = IsWeaponThrowable(joaat(weaponName)) == 1
        if isThrowable then
            -- only knives since we can store more than one
            if joaat(weaponName) == `WEAPON_THROWN_THROWING_KNIVES` then
                local ammoInWeapon = GetAmmoInPedWeapon(CACHE.Ped, joaat(weaponName))
                if ammoInWeapon > 0 then
                    if not canAddToGunbelt("AMMO_THROWING_KNIVES", ammoInWeapon) then
                        return
                    end
                    TriggerServerEvent("vorpinventory:AddBulletFromWeapon", "AMMO_THROWING_KNIVES", ammoInWeapon, weaponId:getId())
                else
                    CORE.NotifyRightTip("You cannot unload to gunbelt as it has no ammo", 2000)
                end
            end
            return
        end


        if not isWeaponAGun(joaat(weaponName)) then
            return CORE.NotifyRightTip("You cannot remove bullets from a non-gun weapon", 2000)
        end

        if not CACHE.IsDead and CACHE.Weapon ~= `WEAPON_UNARMED` and IS_INV_OPEN then
            local isEquipped <const> = weaponId:getUsed() or weaponId:getUsed2()
            if not isEquipped then return print("weapon is not equipped") end

            local currentWeapon <const> = CACHE.Weapon
            if currentWeapon ~= joaat(weaponId:getName()) then return print("weapon is not in hands") end

            local ammoType <const> = GetCurrentPedWeaponAmmoType(CACHE.Ped, GetPedWeaponObject(CACHE.Ped, true))
            local ammoTypeName <const> = SHARED_DATA.AMMO_TYPE_HASH[ammoType]

            local _, amount = GetAmmoInClip(CACHE.Ped, joaat(weaponId:getName()))
            if BOWS[currentWeapon] then
                amount = GetAmmoInPedWeapon(CACHE.Ped, joaat(weaponId:getName()))
            end

            if amount == 0 then return CORE.NotifyRightTip("You cannot unload to gunbelt as it has no ammo", 2000) end
            -- can we add more than whatthe belt can hold?
            if not canAddToGunbelt(ammoTypeName, amount) then
                return
            end

            TriggerServerEvent("vorpinventory:AddBulletFromWeapon", ammoTypeName, amount, weaponId:getId())
        end
    end)

    RegisterNUICallback("reloadWeapon", function(data, cb)
        cb("ok")
        if not CONFIG.MANUAL_WEAPON_RELOAD then return end

        local weaponRow <const> = PLAYER_INVENTORY.WEAPONS[data.id]
        if not weaponRow then return print("weapon not found") end
        local weaponName <const> = weaponRow:getName()

        if BOWS[joaat(weaponName)] and (CACHE.Weapon == `WEAPON_UNARMED` or BOWS[CACHE.Weapon]) then
            return reloadBow(weaponRow:getId())
        end

        local isKnives = joaat(weaponName) == `WEAPON_THROWN_THROWING_KNIVES`
        if isKnives then
            return reloadKnives(weaponRow:getId())
        end

        if not isWeaponAGun(joaat(weaponName)) then
            return CORE.NotifyRightTip("You cannot reload a non-gun weapon", 2000)
        end

        if CACHE.Weapon == `WEAPON_UNARMED` then
            SetCurrentPedWeapon(CACHE.Ped, joaat(weaponName), false, 0, false, false)
            Wait(1000)
        end


        if not CACHE.IsDead and CACHE.Weapon ~= `WEAPON_UNARMED` and IS_INV_OPEN then
            local isEquipped <const> = weaponRow:getUsed() or weaponRow:getUsed2()
            if not isEquipped then return print("weapon is not equipped") end

            if CACHE.Weapon ~= joaat(weaponRow:getName()) then
                return print("held weapon is not the same as the weapon in the inventory")
            end

            reloadWeapon()
        end
    end)

    if CONFIG.REMOVE_THROWABLE_WEAPONS then
        local function getThrowableWeapon(lastWeapon, currentWeapon)
            if IsWeaponThrowable(lastWeapon) == 1 then
                return true, lastWeapon
            end
            if IsWeaponThrowable(currentWeapon) == 1 then
                return true, currentWeapon
            end
            return false, 0
        end

        EVENT:Register("EVENT_PLAYER_COLLECTED_AMBIENT_PICKUP", 0, function(data)
            local playerId <const> = data[3]
            local quantity <const> = data[7]
            local ammoType <const> = data[8] -- or weapon type

            if CACHE.Player == playerId then
                local ammoName <const> = SHARED_DATA.AMMO_TYPE_HASH[ammoType]
                if not ammoName then
                    local weaponType = ammoType
                    local weaponName <const> = GetWeaponName(weaponType)
                    local weaponLabel <const> = SHARED_DATA.WEAPONS[weaponName]?.Name or weaponName
                    SetPedAmmo(CACHE.Ped, weaponType, 0)
                    RemoveWeaponFromPed(CACHE.Ped, weaponType, true, 0)
                    TriggerServerEvent("vorpinventory:pickUpThrowableWeapon", weaponName)
                    CORE.NotifyRightTip("You picked up a " .. weaponLabel, 4000)
                    return
                else
                    local knivesAmmo = { [`AMMO_THROWING_KNIVES`] = true }
                    if knivesAmmo[ammoType] then
                        local currentWeapon <const> = CACHE.Weapon
                        local lastWeapon <const> = CACHE.LastWeapon
                        local isThrowable, weaponUsed <const> = getThrowableWeapon(lastWeapon, currentWeapon)
                        if isThrowable then
                            local weaponId <const> = UTILS.INVENTORY.GET_WEAPON_ID(weaponUsed)
                            if weaponId > 0 then
                                local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
                                if not weapon then return print("weapon not found") end

                                weapon:setUsed(true, true)

                                local ammoInWeapon <const> = GetAmmoInPedWeapon(CACHE.Ped, joaat(weapon:getName()))
                                if ammoInWeapon > weapon:getDefaultClipSize() then
                                    -- remove what we picked the game always adds the quantity we picked
                                    local amountToRemove = ammoInWeapon - weapon:getDefaultClipSize()
                                    RemoveAmmoFromPedByType(CACHE.Ped, ammoType, amountToRemove, `REMOVE_REASON_DROPPED`)
                                    return
                                end

                                weapon:addAmmoToClip(ammoName, quantity, true)
                                NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
                                -- to update server on cached ammo because these dont behave like bullets its done above already
                                WEAPONS_UPDATE[weaponId] = { ammoTypeName = ammoName, fired = quantity }
                                local ammoLabel <const> = SHARED_DATA.AMMO_LABEL[ammoName] or ammoName
                                CORE.NotifyRightTip("You picked up " .. ammoLabel, 4000)
                            else
                                -- must add the weapon to the inventory
                                TriggerServerEvent("vorpinventory:pickUpThrowableWeapon", GetWeaponName(weaponUsed))
                            end
                        end
                        -- these dont have physical holding weapons once thrown
                        return
                    end

                    local function getObjectIndexFromPed()
                        for attachPoint = 0, 29 do
                            local _, _weapon = GetCurrentPedWeapon(CACHE.Ped, true, attachPoint, false)
                            if BOWS[_weapon] then
                                return _weapon
                            end
                        end

                        return 0
                    end

                    local key <const> = string.format("GetEquippedWeaponData_%d", CACHE.Weapon)
                    local state <const> = LocalPlayer.state[key]
                    local weaponId = state and state.weaponId or 0
                    if not state then
                        local weapon <const> = getObjectIndexFromPed()
                        if weapon == 0 then return print("weapon object not found") end

                        weaponId = UTILS.INVENTORY.GET_WEAPON_ID(weapon)
                    end

                    local userWeapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
                    if not userWeapon then return print("weapon not found") end

                    local ammoInBow = GetAmmoInPedWeapon(CACHE.Ped, joaat(userWeapon:getName()))
                    -- bow is maxed
                    if ammoInBow > userWeapon:getDefaultClipSize() then
                        -- remove what we picked the game always adds the quantity we picked
                        local amountToRemove = ammoInBow - userWeapon:getDefaultClipSize()
                        RemoveAmmoFromPedByType(CACHE.Ped, ammoType, amountToRemove, `REMOVE_REASON_DROPPED`)
                        return
                    end

                    userWeapon:addAmmoToClip(ammoName, quantity, true)
                    NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
                    -- no need to update cache server bow arrows behave like bullets its done above already
                    local ammoLabel <const> = SHARED_DATA.AMMO_LABEL[ammoName] or ammoName
                    CORE.NotifyRightTip("You picked up " .. ammoLabel, 4000)
                end
            end
        end, true)

        SetAmbientPickupLifetime(179)
    end


    if CONFIG.REMOVE_LASSO then
        CreateThread(function()
            repeat Wait(5000) until LocalPlayer.state.IsInSession
            local lassos <const> = { [`WEAPON_LASSO`] = true, [`WEAPON_LASSO_REINFORCED`] = true }

            local function GetWhoHogtiedPed(ped)
                return Citizen.InvokeNative(0x3D9F958834AB9C30, ped)
            end

            local function removeLasso()
                local lastWeapon <const> = CACHE.LastWeapon
                local currentWeapon <const> = CACHE.Weapon
                local function getWeapon()
                    if lassos[lastWeapon] then
                        return lastWeapon
                    end
                    if lassos[currentWeapon] then
                        return currentWeapon
                    end
                    return 0
                end

                local weaponUsed <const> = getWeapon()
                if weaponUsed ~= 0 then
                    local weaponId <const> = UTILS.INVENTORY.GET_WEAPON_ID(weaponUsed)
                    if weaponId > 0 then
                        local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
                        if weapon then
                            weapon:setUsed(false, true)
                            TriggerServerEvent("vorpinventory:removeLasso", weaponId, weapon:getName())
                            CORE.NotifyRightTip("Lasso was removed from your inventory", 2000)
                            RemoveWeaponFromPed(CACHE.Ped, joaat(weapon:getName()), true, 0)
                        end
                    end
                end
            end
            while true do
                local sleep = 1000
                if not CACHE.IsDead and not IS_INV_OPEN and lassos[CACHE.Weapon] then
                    sleep = 500
                    local lassoTarget <const> = GetLassoTarget(CACHE.Ped)
                    if lassoTarget ~= 0 and (IsPedAPlayer(lassoTarget) == 1 or IsPedHuman(lassoTarget) == 1) then
                        local isLassoed <const> = IsPedLassoed(lassoTarget) == 1
                        if isLassoed then
                            repeat
                                Wait(100)
                                local isHogtying <const> = IsPedHogtying(CACHE.Ped) ~= 0
                                local isPedBeingHogtied <const> = IsPedBeingHogtied(lassoTarget) ~= 0
                                if isHogtying and isPedBeingHogtied then
                                    local isPedHogtied = false
                                    local timer <const> = GetGameTimer()
                                    repeat
                                        Wait(500)
                                        isPedHogtied = IsPedHogtied(lassoTarget) == 1
                                    until CACHE.IsDead or isPedHogtied or GetGameTimer() - timer > 20000

                                    if not CACHE.IsDead and isPedHogtied and GetGameTimer() - timer < 20000 then
                                        local ped <const> = GetWhoHogtiedPed(lassoTarget)
                                        if ped == CACHE.Ped then
                                            removeLasso()
                                        end
                                    end
                                    break
                                end
                            until CACHE.IsDead or lassoTarget == 0
                        end
                    else
                        local isFreeAiming <const> = IsPlayerFreeAiming(CACHE.Player)
                        if isFreeAiming then
                            sleep = 500
                            local retval <const>, entity <const> = GetEntityPlayerIsFreeAimingAt(CACHE.Player)
                            if retval and (IsPedHuman(entity) == 1 or IsPedAPlayer(entity) == 1) then
                                repeat
                                    Wait(0)
                                    local isHogtying <const> = IsPedBeingHogtied(entity) ~= 0
                                    if isHogtying then
                                        repeat Wait(0) until IsPedBeingHogtied(entity) == 0
                                    end
                                until not IsPlayerFreeAiming(CACHE.Player)
                                Wait(500)
                                local isPedHogtied <const> = IsPedHogtied(entity) == 1
                                if isPedHogtied then
                                    local ped <const> = GetWhoHogtiedPed(entity)
                                    if ped == CACHE.Ped then
                                        removeLasso()
                                    end
                                end
                            end
                        end
                    end
                end
                Wait(sleep)
            end
        end)
    end


    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession
        local lastAmmo = -1

        while true do
            local sleep = 500
            local weaponUsed <const> = CACHE.Weapon

            if not CACHE.IsDead and not IS_INV_OPEN and weaponUsed ~= `WEAPON_UNARMED` and not BOWS[weaponUsed] then
                local isThrowable = IsWeaponThrowable(weaponUsed) == 1
                if isThrowable then
                    sleep = 0

                    local ammo <const> = GetAmmoInPedWeapon(CACHE.Ped, weaponUsed)

                    if weaponUsed ~= `WEAPON_THROWN_THROWING_KNIVES` then
                        if lastAmmo >= 0 and ammo < lastAmmo then
                            local weaponId <const> = UTILS.INVENTORY.GET_WEAPON_ID(weaponUsed)
                            if weaponId > 0 then
                                local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
                                if weapon and weapon:getUsed() then
                                    weapon:setUsed(false, true)
                                    TriggerServerEvent("vorpinventory:dropThrowableWeapon", weaponId, weapon:getName())
                                    PLAYER_INVENTORY.WEAPONS[weaponId] = nil
                                end
                            end
                        end
                    else
                        if lastAmmo >= 0 and ammo < lastAmmo then
                            local weaponId <const> = UTILS.INVENTORY.GET_WEAPON_ID(weaponUsed)
                            if weaponId > 0 then
                                local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
                                if weapon and weapon:getUsed() then
                                    local thrown <const> = math.max(1, lastAmmo - ammo)
                                    local ammoType <const> = "AMMO_THROWING_KNIVES"
                                    weapon:subAmmoFromClip(ammoType, thrown)
                                    NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
                                    local prevFired <const> = WEAPONS_UPDATE[weaponId] and WEAPONS_UPDATE[weaponId].fired or 0
                                    WEAPONS_UPDATE[weaponId] = { ammoTypeName = ammoType, fired = prevFired + thrown }
                                end
                            end
                        end
                    end


                    lastAmmo = ammo
                end
            else
                lastAmmo = -1
            end
            Wait(sleep)
        end
    end)

    if CONFIG.ENABLE_PETROL_CAN then
        CreateThread(function()
            repeat Wait(5000) until LocalPlayer.state.IsInSession

            local IsControlPressed = IsControlPressed
            local lastAmmo = -1
            local ammoType <const> = "AMMO_MOONSHINEJUG_MP"

            while true do
                local sleep = 1000
                local weaponUsed <const> = CACHE.Weapon
                if not CACHE.IsDead and not IS_INV_OPEN and weaponUsed == `WEAPON_MOONSHINEJUG_MP` then
                    sleep = 0
                    if IsControlPressed(0, `INPUT_ATTACK`) then
                        local ammo <const> = GetAmmoInPedWeapon(CACHE.Ped, weaponUsed)
                        if lastAmmo >= 0 and ammo < lastAmmo then
                            local used <const> = lastAmmo - ammo
                            local weaponId <const> = UTILS.INVENTORY.GET_WEAPON_ID(weaponUsed)
                            if weaponId > 0 then
                                local weapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
                                if weapon and weapon:getUsed() then
                                    weapon:subAmmoFromClip(ammoType, used)

                                    if ammo == 0 then
                                        weapon:setUsed(false, true)
                                        TriggerServerEvent("vorpinventory:dropThrowableWeapon", weaponId, weapon:getName())
                                        PLAYER_INVENTORY.WEAPONS[weaponId] = nil

                                        MakePedDropWeapon(CACHE.Ped, false, 0, false, false)
                                        RemoveWeaponFromPed(CACHE.Ped, joaat("weapon_moonshinejug_mp"), true, -142743235)
                                        RemoveAmmoFromPedByType(CACHE.Ped, joaat("weapon_moonshinejug_mp"), 100, -142743235)
                                    else
                                        NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
                                    end
                                end
                            end
                        end

                        lastAmmo = ammo
                    end
                else
                    lastAmmo = -1
                end
                Wait(sleep)
            end
        end)
    end
end
