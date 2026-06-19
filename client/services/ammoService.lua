local PLAYER_AMMO_INFO  = {
    ammo = {}
}
local UPDATE_AMMO_CACHE = {}
local canUpdateAmmo     = true
local LIB <const>       = Import "events"
local EVENT <const>     = LIB.Events


local Ammo <const> = {
    ADD_AMMO_TO_PED = function(ammoData)
        Wait(2000)
        for ammoType, ammo in pairs(ammoData) do
            if ammo > 0 then
                SetPedAmmoByType(CACHE.Ped, joaat(ammoType), ammo)
            end
        end
    end,

    UPDATE_AMMO = function(ammoData, setAmmoToPed, isSource, removeAll)
        PLAYER_AMMO_INFO.ammo = ammoData.ammo
        SendNUIMessage({ action = "updateammo", ammo = ammoData.ammo })

        if setAmmoToPed then
            if not CONFIG.MANUAL_WEAPON_RELOAD then
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
    LOAD_AMMO = function(ammoData)
        SendNUIMessage({ action = "reclabels", labels = SHARED_DATA.AMMO_LABEL })
        PLAYER_AMMO_INFO = ammoData or {}

        if not CONFIG.MANUAL_WEAPON_RELOAD then
            AMMO_SERVICE.ADD_AMMO_TO_PED(PLAYER_AMMO_INFO.ammo)
        end
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
            if not ammoData[ammoType] or seen[ammoType] then
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
}

AMMO_SERVICE       = Ammo


if not CONFIG.MANUAL_WEAPON_RELOAD then
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
                local isThrownGroup <const> = wepgroup == `GROUP_THROWN`
                local isBowGroup <const> = wepgroup == `GROUP_BOW`
                local isPetrol <const> = wepgroup == `GROUP_PETROLCAN`

                if (isArmed or isThrownGroup or isPetrol) and not ismelee then
                    for ammo_type, value in pairs(PLAYER_AMMO_INFO.ammo) do
                        local ammoQty = GetPedAmmoByType(playerPedId, joaat(ammo_type))

                        if (isThrownGroup or isBowGroup or isPetrol) and ammoQty == 1 then
                            ammoQty = 0
                        end

                        if value ~= ammoQty then
                            UPDATE_AMMO_CACHE[ammo_type] = ammoQty
                            PLAYER_AMMO_INFO.ammo[ammo_type] = ammoQty
                            SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end)

    CreateThread(function()
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
    local isBeltsEmpty                = false
    local dualWieldLastClipAmmo       = {}
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

    local function getAmmoFromGunbelt(ammoTypeName)
        local ammoInBelt <const> = PLAYER_AMMO_INFO.ammo[ammoTypeName]
        if ammoInBelt and ammoInBelt > 0 then
            return ammoInBelt
        end
        return 0
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
                if not isBeltsEmpty then
                    isBeltsEmpty = true
                    SetPedAmmo(CACHE.Ped, weaponHash, ammoInBelt)
                    weapon:addAmmoToClip(ammoTypeName, ammoInBelt)
                    PLAYER_AMMO_INFO.ammo[ammoTypeName] = 0
                end
            else
                isBeltsEmpty = false
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

                    if not isBeltsEmpty then
                        isBeltsEmpty = true
                        if ammoInWeapon > 0 then
                            SetPedAmmo(CACHE.Ped, joaat(weapon:getName()), amountToLoad)
                        else
                            SetPedAmmo(CACHE.Ped, joaat(weapon:getName()), amountToLoad)
                            GiveDelayedWeaponToPed(CACHE.Ped, joaat(weapon:getName()), amountToLoad, true, 0)
                        end
                        weapon:addAmmoToClip(ammoTypeName, amountToLoad)
                        PLAYER_AMMO_INFO.ammo[ammoTypeName] = amountToLoad
                    end
                else
                    isBeltsEmpty = false
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

    local function isDualWielding()
        local weaponEntity <const> = GetCurrentPedWeaponEntityIndex(CACHE.Ped, 0)
        local weaponEntity2 <const> = GetCurrentPedWeaponEntityIndex(CACHE.Ped, 1)
        return weaponEntity ~= `WEAPON_UNARMED` and weaponEntity2 ~= `WEAPON_UNARMED`
    end

    local function getEquippedWeaponId(attachPoint, weaponHash)
        if weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then return 0 end

        for id, weapon in pairs(PLAYER_INVENTORY.WEAPONS) do
            if joaat(weapon:getName()) == weaponHash then
                if attachPoint == 1 then
                    if weapon:getUsed2() then return id end
                elseif weapon:getUsed() and not weapon:getUsed2() then
                    return id
                end
            end
        end

        for id, weapon in pairs(PLAYER_INVENTORY.WEAPONS) do
            if joaat(weapon:getName()) == weaponHash and (weapon:getUsed() or weapon:getUsed2()) then
                if attachPoint == 1 and weapon:getUsed2() then return id end
                if attachPoint == 0 and weapon:getUsed() then return id end
            end
        end

        local key <const> = string.format("GetEquippedWeaponData_%d", weaponHash)
        local weaponData = LocalPlayer.state[key]
        if weaponData then return weaponData.weaponId end

        return UTILS.INVENTORY.GET_WEAPON_ID(weaponHash)
    end

    local function processWeaponShot(playerPedId, attachPoint)
        local weaponEntity <const> = GetCurrentPedWeaponEntityIndex(playerPedId, attachPoint)
        if weaponEntity == 0 or weaponEntity == `WEAPON_UNARMED` then return end

        local _, weaponHash <const> = GetCurrentPedWeapon(playerPedId, attachPoint == 0, attachPoint, false)
        if weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then return end

        local ammoHash <const> = GetCurrentPedWeaponAmmoType(playerPedId, weaponEntity)
        local ammoTypeName <const> = SHARED_DATA.AMMO_TYPE_HASH[ammoHash]
        local beltAmmo <const> = ammoTypeName and PLAYER_AMMO_INFO.ammo[ammoTypeName]
        if not ammoTypeName or not beltAmmo then return end

        local weaponId <const> = getEquippedWeaponId(attachPoint, weaponHash)
        if weaponId <= 0 then return end

        local userWeapon <const> = PLAYER_INVENTORY.WEAPONS[weaponId]
        if userWeapon then
            userWeapon:subAmmoFromClip(ammoTypeName, 1)
            NUI_SERVICE.INVENTORY.UPDATE_WEAPON(weaponId)
        end

        local fired <const> = WEAPONS_UPDATE[weaponId] and WEAPONS_UPDATE[weaponId].fired or 0
        local maxAmmoInClip <const> = not BOWS[weaponHash] and GetMaxAmmoInClip(playerPedId, weaponHash, true) or userWeapon and userWeapon:getDefaultClipSize() or 0
        WEAPONS_UPDATE[weaponId] = { ammoTypeName = ammoTypeName, fired = math.min(fired + 1, maxAmmoInClip) }
    end

    local function getDualWieldFiredAttachPoint(playerPedId, lastClipAmmo)
        local _, weapon0 <const> = GetCurrentPedWeapon(playerPedId, false, 0, true)
        local _, weapon1 <const> = GetCurrentPedWeapon(playerPedId, true, 1, true)

        local _, clip0 = GetAmmoInClip(playerPedId, weapon0)
        local _, clip1 = GetAmmoInClip(playerPedId, weapon1)

        local prev0 = lastClipAmmo[0]
        local prev1 = lastClipAmmo[1]
        local fired0 = prev0 ~= nil and clip0 < prev0
        local fired1 = prev1 ~= nil and clip1 < prev1

        if fired0 and not fired1 then return 0 end
        if fired1 and not fired0 then return 1 end

        local heldWeapon <const> = GetPedCurrentHeldWeapon(playerPedId)
        if heldWeapon == weapon0 then return 0 end
        if heldWeapon == weapon1 then return 1 end

        if fired0 then return 0 end
        if fired1 then return 1 end

        return nil
    end

    local function updateDualWieldClipAmmo(playerPedId)
        local _, weapon0 <const> = GetCurrentPedWeapon(playerPedId, false, 0, true)
        local _, weapon1 <const> = GetCurrentPedWeapon(playerPedId, true, 1, true)
        local _, clip0 = GetAmmoInClip(playerPedId, weapon0)
        local _, clip1 = GetAmmoInClip(playerPedId, weapon1)

        dualWieldLastClipAmmo[0] = clip0
        dualWieldLastClipAmmo[1] = clip1
    end

    local function buildReloadEntry(attachPoint, beltRemaining)
        local weaponEntity <const> = GetCurrentPedWeaponEntityIndex(CACHE.Ped, attachPoint)
        if weaponEntity == 0 then return nil end

        local _, weaponHash <const> = GetCurrentPedWeapon(CACHE.Ped, attachPoint == 0, attachPoint, false)
        if weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then return nil end

        local currentAmmoTypeHash <const> = GetCurrentPedWeaponAmmoType(CACHE.Ped, weaponEntity)
        local ammoTypeName <const> = SHARED_DATA.AMMO_TYPE_HASH[currentAmmoTypeHash]
        if not ammoTypeName then return nil end

        local _, ammoInClip = GetAmmoInClip(CACHE.Ped, weaponHash)
        local maxAmmoInClip <const> = GetMaxAmmoInClip(CACHE.Ped, weaponHash, true)
        local roundsNeeded <const> = math.max(0, maxAmmoInClip - ammoInClip)
        if roundsNeeded == 0 then return nil end

        if beltRemaining[ammoTypeName] == nil then
            beltRemaining[ammoTypeName] = getAmmoFromGunbelt(ammoTypeName)
        end

        local ammoInBelt <const> = beltRemaining[ammoTypeName]
        if ammoInBelt <= 0 then return nil end

        local amountToLoad <const> = math.min(roundsNeeded, ammoInBelt)
        beltRemaining[ammoTypeName] = ammoInBelt - amountToLoad

        return {
            weaponHash = weaponHash,
            ammoTypeName = ammoTypeName,
            ammoInBelt = ammoInBelt,
            maxAmmoInClip = maxAmmoInClip,
            amountToLoad = amountToLoad,
            weaponId = getEquippedWeaponId(attachPoint, weaponHash),
        }
    end

    local function syncReloadedWeapon(entry, allowBeltEmptySync)
        if entry.amountToLoad <= 0 then return end

        if entry.ammoInBelt < entry.maxAmmoInClip then
            if allowBeltEmptySync then
                isBeltsEmpty = true
                SetPedAmmo(CACHE.Ped, entry.weaponHash, entry.ammoInBelt)

                if entry.weaponId > 0 then
                    local userWeapon <const> = PLAYER_INVENTORY.WEAPONS[entry.weaponId]
                    if userWeapon then
                        userWeapon:addAmmoToClip(entry.ammoTypeName, entry.ammoInBelt) -- updates server
                        NUI_SERVICE.INVENTORY.UPDATE_WEAPON(entry.weaponId)
                    end
                end

                PLAYER_AMMO_INFO.ammo[entry.ammoTypeName] = math.max(0, PLAYER_AMMO_INFO.ammo[entry.ammoTypeName] - entry.amountToLoad)
                SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
            end
        else
            isBeltsEmpty = false
            SetPedAmmo(CACHE.Ped, entry.weaponHash, GetMaxAmmoInClip(CACHE.Ped, entry.weaponHash, true))

            if entry.weaponId > 0 then
                local userWeapon <const> = PLAYER_INVENTORY.WEAPONS[entry.weaponId]
                if userWeapon then
                    userWeapon:addAmmoToClip(entry.ammoTypeName, entry.maxAmmoInClip) -- updates server
                    NUI_SERVICE.INVENTORY.UPDATE_WEAPON(entry.weaponId)
                end
            end

            PLAYER_AMMO_INFO.ammo[entry.ammoTypeName] = math.max(0, PLAYER_AMMO_INFO.ammo[entry.ammoTypeName] - entry.amountToLoad)
            SendNUIMessage({ action = "updateammo", ammo = PLAYER_AMMO_INFO.ammo })
        end
    end

    local function reloadWeapon()
        if IsPlayerFreeAiming(CACHE.Player) then
            return CORE.NotifyRightTip("you cannot reload while aiming", 2000)
        end

        local attachPoints = isDualWielding() and { 0, 1 } or { 0 }
        local beltRemaining = {}
        local reloadEntries = {}

        for _, attachPoint in ipairs(attachPoints) do
            local entry = buildReloadEntry(attachPoint, beltRemaining)
            if entry then
                reloadEntries[#reloadEntries + 1] = entry
            end
        end

        if #reloadEntries == 0 then return end

        isReloading = true

        -- could possibly add minigame if they fail it adds half ammo

        local ammoToAdd = {}

        for _, entry in ipairs(reloadEntries) do
            ammoToAdd[entry.ammoTypeName] = (ammoToAdd[entry.ammoTypeName] or 0) + entry.amountToLoad
            SetAmmoTypeForPedWeapon(CACHE.Ped, entry.weaponHash, GetHashKey(entry.ammoTypeName))
        end

        for ammoTypeName, amount in pairs(ammoToAdd) do
            AddAmmoToPedByType(CACHE.Ped, GetHashKey(ammoTypeName), amount, 0)
        end


        MakePedReload(CACHE.Ped)
        local startTime = GetGameTimer()
        repeat
            Wait(0)
        until IsPedReloading(CACHE.Ped) or GetGameTimer() - startTime > 2000
        if GetGameTimer() - startTime > 2000 then
            TaskReloadWeapon(CACHE.Ped, false)
            CORE.NotifyRightTip("Reload failed, reload again", 2000)
        end
        repeat
            Wait(0)
            DisableControlAction(0, `INPUT_ATTACK`, true)
            DisableControlAction(0, `INPUT_MELEE_ATTACK`, true)
        until not IsPedReloading(CACHE.Ped)

        local multiReload = #reloadEntries > 1
        for _, entry in ipairs(reloadEntries) do
            syncReloadedWeapon(entry, multiReload or not isBeltsEmpty)
        end

        SetTimeout(CONFIG.RELOAD_WAIT, function()
            isReloading = false
        end)
    end

    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession

        local DisableControlAction         = DisableControlAction
        local IsDisabledControlJustPressed = IsDisabledControlJustPressed


        while true do
            local sleep = 1000
            if not CACHE.IsDead and CACHE.Weapon ~= `WEAPON_UNARMED` and not IS_INV_OPEN then
                if IsPedArmed(CACHE.Ped, 4) == 1 and not BOWS[CACHE.Weapon] then
                    sleep = 0
                    DisableControlAction(0, `INPUT_RELOAD`, true)
                    if IsDisabledControlJustPressed(0, `INPUT_RELOAD`) and not isReloading then
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
                        if isReloading then
                            dualWieldLastClipAmmo = {}
                        end
                        if not isReloading then
                            sleep = 0
                            local dualWielding <const> = isDualWielding()
                            local isShooting <const> = IsPedShooting(playerPedId) -- only works at 0 frames
                            if isShooting then
                                if dualWielding then
                                    local firedAttachPoint <const> = getDualWieldFiredAttachPoint(playerPedId, dualWieldLastClipAmmo)
                                    if firedAttachPoint ~= nil then
                                        processWeaponShot(playerPedId, firedAttachPoint)
                                    end
                                else
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

                            if dualWielding then
                                updateDualWieldClipAmmo(playerPedId)
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

        SetAmmoTypeForPedWeapon(CACHE.Ped, joaat(weaponName), joaat(ammoTypeName))
        local amount <const> = weapon:getAmmo(ammoTypeName) -- if exists in ammo use this other wise player must reload
        if amount > 0 then
            SetPedAmmoByType(CACHE.Ped, joaat(ammoTypeName), amount)
        else
            CORE.NotifyRightTip("Ammo type set to " .. SHARED_DATA.AMMO_LABEL[ammoTypeName] or ammoTypeName .. " Reload your weapon to add ammo", 4000)
        end
    end)

    RegisterNUICallback("removeBullets", function(data, cb)
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
