CORE = exports.vorp_core:GetCore()
LANG = CONFIG.LANG[CONFIG.LANGUAGE]
local LIB = Import 'dataview'
DataView = LIB.DataView


if CONFIG.HOTBAR.ENABLE then
    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession
        local hotbarHudVisible = false
        local hotbarSuppressed = false
        local IsPauseMenuActive = IsPauseMenuActive
        local IsUiappActiveByHash = IsUiappActiveByHash
        local IsInCinematicMode = IsInCinematicMode
        local IsScreenFadedOut = IsScreenFadedOut
        local IsControlJustPressed = IsControlJustPressed

        while true do
            local sleep = 1000
            if not IS_INV_OPEN then
                sleep = 0

                if IsControlJustPressed(0, CONFIG.HOTBAR.TOGGLE_KEY) then
                    hotbarHudVisible = not hotbarHudVisible
                    hotbarSuppressed = false
                    NUI_SERVICE.HOTBAR.SET_VISIBLE(hotbarHudVisible)
                end

                for i = 1, 5 do
                    if IsControlPressed(0, CONFIG.HOTBAR.HOLD_KEY) then
                        if CONFIG.HOTBAR.SHOW_WHEN_HOLD and not hotbarHudVisible then
                            hotbarHudVisible = true
                            hotbarSuppressed = false
                            NUI_SERVICE.HOTBAR.SET_VISIBLE(hotbarHudVisible)
                            SetTimeout(3000, function()
                                hotbarHudVisible = false
                                hotbarSuppressed = true
                                NUI_SERVICE.HOTBAR.SET_VISIBLE(hotbarHudVisible)
                            end)
                        end

                        DisableControlAction(0, CONFIG.HOTBAR.SLOT_KEYS[i], true)
                        if IsDisabledControlJustPressed(0, CONFIG.HOTBAR.SLOT_KEYS[i]) then
                            NUI_SERVICE.HOTBAR.USE_ITEM(i, true)
                            break
                        end
                    end
                end
            end

            local isMenuOpen <const> = IsPauseMenuActive() == 1
            local isHudHidden <const> = IsHudHidden()
            local isCinematic <const> = IsInCinematicMode() == 1
            local isMapOpen <const> = IsUiappActiveByHash(joaat("MAP")) == 1
            local isScreenFaded <const> = IsScreenFadedOut()
            local shouldSuppress = isMenuOpen or isHudHidden or isCinematic or isMapOpen or isScreenFaded

            if shouldSuppress and hotbarHudVisible and not hotbarSuppressed then
                hotbarSuppressed = true
                NUI_SERVICE.HOTBAR.SET_VISIBLE(false)
            elseif not shouldSuppress and hotbarSuppressed then
                hotbarSuppressed = false
                NUI_SERVICE.HOTBAR.SET_VISIBLE(hotbarHudVisible)
            end

            Wait(sleep)
        end
    end)
end



AddEventHandler('onClientResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    if not CONFIG.DEV_MODE then return end

    SendNUIMessage({ action = "hide" })
    TriggerServerEvent("DEV:loadweapons")
    TriggerServerEvent("vorpinventory:getItemsTable")
    Wait(1000)
    TriggerServerEvent("vorpinventory:getInventory")
    Wait(1000)
    TriggerServerEvent("vorpCore:LoadAllAmmo")
end)



if CONFIG.USE_LANTERN_ON_BELT then
    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession

        local IsWeaponLantern = IsWeaponLantern
        local lastLantern = 0

        while true do
            local pedid = CACHE.Ped
            local weaponHeld <const> = CACHE.Weapon
            local isLantern <const> = IsWeaponLantern(weaponHeld) == 1 -- assuming it will return all lanterns to true
            if isLantern then
                lastLantern = weaponHeld
            end

            if lastLantern ~= 0 and not isLantern then
                SetCurrentPedWeapon(pedid, lastLantern, true, 12, false, false)
                lastLantern = 0
            end
            Wait(500)
        end
    end)
end



if CONFIG.PUSH_TO_TALK then
    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession
        local isNuiFocused = false
        local DisableAllControlActions = DisableAllControlActions
        local EnableControlAction = EnableControlAction

        while true do
            local sleep = 0
            if IS_INV_OPEN then
                if not isNuiFocused then
                    SetNuiFocusKeepInput(true)
                    isNuiFocused = true
                end

                DisableAllControlActions(0)
                EnableControlAction(0, `INPUT_PUSH_TO_TALK`, true)
            else
                sleep = 1000
                if isNuiFocused then
                    SetNuiFocusKeepInput(false)
                    isNuiFocused = false
                end
            end
            Wait(sleep)
        end
    end)
end

CreateThread(function()
    local controlVar = false -- best to use variable than to check statebag every frame
    local isWalking = false
    if CONFIG.DISABLE_WEAPON_WHELL_ITEMS then
        EnableHudContext(-2106452847)
    end
    if CONFIG.DISABLE_WEAPON_WHEEL_WEAPONS then
        EnableHudContext(-1249243147)
    end

    repeat Wait(5000) until LocalPlayer.state.IsInSession
    repeat Wait(1000) until LocalPlayer.state?.Character?.CharId
    CHARID = LocalPlayer.state.Character.CharId

    NUI_SERVICE.SHARED.SEND_LANG()

    if CONFIG.HOTBAR.ENABLE then
        RegisterCommand(CONFIG.HOTBAR.EDIT_COMMAND, function()
            if IS_INV_OPEN then return end
            SendNUIMessage({ action = "hotbarEditPos" })
            SetNuiFocus(true, true)
        end, false)
    end

    local IsControlJustReleased = IsControlJustReleased
    local IsControlPressed      = IsControlPressed
    local IsPedHogtied          = IsPedHogtied
    local IsPedCuffed           = IsPedCuffed

    while true do
        local sleep = 1000
        if not CACHE.IsDead then
            sleep = 0
            if IsControlJustReleased(1, CONFIG.OPEN_INVENTORY_KEY) then
                local player          = CACHE.Ped
                local hogtied <const> = IsPedHogtied(player) == 1
                local cuffed <const>  = IsPedCuffed(player)
                if not hogtied and not cuffed and not INVENTORY_DISABLED then
                    if CONFIG.WALK_WHILE_INV_OPEN then
                        if IsControlPressed(1, `INPUT_MOVE_UP_ONLY`) == 1 and not isWalking then
                            isWalking = true
                            local mount <const> = CACHE.Mount
                            local vehicle <const> = CACHE.Vehicle
                            player = mount > 0 and mount or vehicle > 0 and vehicle or player
                            local _isWalking <const> = IsPedWalking(player)
                            local isRunning <const> = IsPedRunning(player)
                            local isSprinting <const> = IsPedSprinting(player)
                            local speed <const> = _isWalking and 1.0 or isRunning and 2.0 or isSprinting and 3.0 or 0.0
                            local heading <const> = GetEntityHeading(player)
                            CreateThread(function()
                                repeat Wait(0) until IsNuiFocused()
                                SimulatePlayerInputGait(PlayerId(), speed, -1, heading, false, false)
                                repeat Wait(0) until not IsNuiFocused()
                                isWalking = false
                                if GetMount(player) > 0 or IsPedInAnyVehicle(player, false) then
                                    ResetPlayerInputGait(PlayerId()) -- needs to reset on vehcicles or mount or only works for the first time for walking no need pressing the W key will reset it it seems
                                end
                            end)
                        end
                    end
                    NUI_SERVICE.INVENTORY.OPEN()
                end
            end
        end

        if IS_INV_OPEN and CACHE.IsDead then
            NUI_SERVICE.INVENTORY.CLOSE()
        end

        if IS_INV_OPEN then
            if not controlVar then
                controlVar = true
                LocalPlayer.state:set("IsInvActive", true, true) -- can also listen for statebag change
                TriggerEvent("vorp_inventory:Client:OnInvStateChange", true)
            end
        else
            if controlVar then
                controlVar = false
                LocalPlayer.state:set("IsInvActive", false, true)
                TriggerEvent("vorp_inventory:Client:OnInvStateChange", false)
            end
        end

        Wait(sleep)
    end
end)


LAST_CLIENT_WEAPON_STATUS = LAST_CLIENT_WEAPON_STATUS or {}
if CONFIG.USE_WEAPON_DEGRADATION then
    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession
        local updateTimer = 10000 -- only updates if weapons are equipped and the values are changing

        local function weaponWearPayload(weapon)
            local weaponStatus <const> = weapon:getStatus()
            if weaponStatus and next(weaponStatus) then
                return {
                    degradation = weaponStatus.degradation,
                    damage = weaponStatus.damage,
                    dirt = weaponStatus.dirt,
                    soot = weaponStatus.soot,
                }
            end
            return { degradation = weapon.degradation, damage = weapon.damage, dirt = weapon.dirt, soot = weapon.soot }
        end

        while true do
            if not CACHE.IsDead then
                local batch = {}
                for _, weapon in pairs(PLAYER_INVENTORY.WEAPONS) do
                    if weapon.canDegrade then
                        local weaponId <const> = weapon:getId()
                        if weapon:getUsed() or weapon:getUsed2() then
                            local payload <const> = weaponWearPayload(weapon)
                            local encoded <const> = json.encode(payload)
                            if LAST_CLIENT_WEAPON_STATUS[weaponId] ~= encoded then
                                LAST_CLIENT_WEAPON_STATUS[weaponId] = encoded
                                batch[weaponId] = payload
                            end
                        else
                            LAST_CLIENT_WEAPON_STATUS[weaponId] = nil
                        end
                    end
                end

                if next(batch) then
                    -- send as a batch because of spam
                    TriggerServerEvent("vorpinventory:saveWeaponStatus", batch)
                end
            end
            Wait(updateTimer)
        end
    end)

    -- cant fire weapons that are degraded and damaged
    if CONFIG.DISABLE_WEAPON_FIRE_WHEN_DEGRADED then
        CreateThread(function()
            repeat Wait(5000) until LocalPlayer.state.IsInSession
            local DisablePlayerFiring = DisablePlayerFiring
            local IsDisabledControlJustPressed = IsDisabledControlJustPressed
            local IsPedArmed = IsPedArmed
            local GetPedWeaponObject = GetPedWeaponObject
            local GetWeaponDegradation = GetWeaponDegradation

            while true do
                local sleep = 1000
                if not CACHE.IsDead and not IS_INV_OPEN then
                    local weaponHeld = CACHE.Weapon
                    if weaponHeld ~= `WEAPON_UNARMED` then
                        local isArmed = IsPedArmed(CACHE.Ped, 4) == 1
                        if isArmed then
                            local weaponObject <const> = GetPedWeaponObject(CACHE.Ped, true)
                            local degradation <const> = GetWeaponDegradation(weaponObject)

                            if degradation >= 1.0 then
                                sleep = 0
                                DisablePlayerFiring(CACHE.Player, true)

                                if IsDisabledControlJustPressed(0, `INPUT_ATTACK`) then
                                    CORE.NotifyRightTip("Your weapon is degraded and cant be used", 5000)
                                end
                            end
                        end
                    end
                end
                Wait(sleep)
            end
        end)
    end
end


if CONFIG.DISABLE_HIP_FIRE then
    CreateThread(function()
        repeat Wait(5000) until LocalPlayer.state.IsInSession
        local DisablePlayerFiring = DisablePlayerFiring
        local IsPlayerFreeAiming = IsPlayerFreeAiming
        local IsPedArmed = IsPedArmed

        while true do
            local sleep = 500
            if not CACHE.IsDead and not IS_INV_OPEN then
                local weaponHeld <const> = CACHE.Weapon
                if weaponHeld ~= `WEAPON_UNARMED` then
                    sleep = 100
                    local isAiming <const> = IsPlayerFreeAiming(CACHE.Player)
                    local isArmed <const> = IsPedArmed(CACHE.Ped, 4) == 1
                    if not isAiming and isArmed then
                        sleep = 0
                        DisablePlayerFiring(CACHE.Player, true)
                    end
                end
            end
            Wait(sleep)
        end
    end)
end
