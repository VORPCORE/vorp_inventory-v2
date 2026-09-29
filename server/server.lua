--GLOBAL VARIABLES
LANG = CONFIG.LANG[CONFIG.LANGUAGE]
CORE = exports.vorp_core:GetCore()

if CONFIG.DEV_MODE then
    print("^1[DEV] ^7DEV MODE IS ENABLED, THIS IS NOT FOR PRODUCTION SERVERS")
end

RegisterServerEvent("syn:stopscene")
AddEventHandler("syn:stopscene", function(x)
    local _source <const> = source
    TriggerClientEvent("inv:dropstatus", _source, x)
end)

RegisterServerEvent("vorpinventory:netduplog", function()
    local _source <const> = source
    local playername <const> = GetPlayerName(_source)
    local description <const> = CONFIG.LOGS.NetDupWebHook.Language.descriptionstart .. playername .. CONFIG.LOGS.NetDupWebHook.Language.descriptionend

    if CONFIG.LOGS.NetDupWebHook.Active then
        local info <const> = {
            source = _source,
            title = CONFIG.LOGS.NetDupWebHook.Language.title,
            name = playername,
            description = description,
            webhook = CONFIG.LOGS.NetDupWebHook.webhook,
            color = CONFIG.LOGS.NetDupWebHook.color
        }
        SV_UTILS.DISCORD_LOG(info)
    else
        print('[' .. CONFIG.LOGS.NetDupWebHook.Language.title .. '] ', description)
    end
end)

AddEventHandler('playerDropped', function()
    local _source <const> = source
    if _source then
        local user <const>    = CORE.getUser(_source)

        local weapons <const> = USERS_WEAPONS.default

        if USERS_AMMO_DATA[_source] then
            INVENTORY_SERVICE.AMMO.SAVE(_source)
            USERS_AMMO_DATA[_source] = nil
        end

        local invId = INVENTORY_IN_USE[_source]

        if invId then
            INVENTORY_IN_USE[_source] = nil

            local customInv = CUSTOM_INVENTORIES[invId]

            if customInv and customInv:isInUse() then
                customInv:setInUse(false)
            end
        end

        if not user then return end

        local charid <const> = user.getUsedCharacter.charIdentifier
        for key, value in pairs(weapons) do
            if value.charId == charid then
                USERS_WEAPONS.default[key] = nil
                break
            end
        end
    end
end)

CORE.Callback.Register("vorpinventory:get_slots", function(source, cb, _)
    local user <const> = CORE.getUser(source)
    if not user then return cb(nil) end

    local character <const>      = user.getUsedCharacter
    local totalItems <const>     = INVENTORY_API.MAIN.GET_TOTAL_ITEMS_COUNT(character.identifier, character.charIdentifier)
    local totalWeapons <const>   = INVENTORY_API.MAIN.GET_TOTAL_WEAPONS_COUNT(character.identifier, character.charIdentifier, true)
    local totalInvWeight <const> = (totalItems + totalWeapons)
    return cb({
        totalInvWeight = totalInvWeight,
        slots = character.invCapacity,
        money = character.money,
        gold = character.gold,
        rol = character.rol
    })
end)

RegisterServerEvent("vorp_inventory:Server:SaddleOpen", function(netId)
    local _source <const> = source
    local user <const> = CORE.getUser(_source)
    if not user then return end
    local character <const> = user.getUsedCharacter
    local charId <const> = character.charIdentifier

    local entity <const> = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then return end

    local model <const> = GetEntityModel(entity)
    local horsePosition <const> = GetEntityCoords(entity)
    local playerPosition <const> = GetEntityCoords(GetPlayerPed(_source))

    local mindist = 5.0
    if #(horsePosition - playerPosition) > mindist then
        return CORE.NotifyObjective(_source, LANG.notCloseEnoughToHorse, 5000)
    end

    local id = CONFIG.OPEN_SADDLE(charId, model, entity, netId)
    INVENTORY_API.OPEN_INVENTORY(_source, id)
end)


RegisterServerEvent("vorp_inventory:Server:CloseCustomInventory", function()
    local _source <const> = source
    if not INVENTORY_IN_USE[_source] then
        return print("player:", GetPlayerName(_source), "did not open inventory through the server  but it closed it meaning it opened from the client", "possible Cheat!!")
    end
    local id <const> = INVENTORY_IN_USE[_source]
    if not CUSTOM_INVENTORIES[id] then
        return print("player:", GetPlayerName(_source), "tried to close inventory with id:", id, "but it was not found", "possible Cheat!!")
    end

    if not CUSTOM_INVENTORIES[id]:isInUse() then
        return print("player:", GetPlayerName(_source), "tried to close inventory with id:", id, "but it was not in use", "possible Cheat!!")
    end

    CUSTOM_INVENTORIES[id]:setInUse(false)
    INVENTORY_IN_USE[_source] = nil
end)

-- SERVER EVENTS ONLY
local ALLOWED_CONTEXT_MENU_EVENTS <const> = {}

RegisterServerEvent("vorpinventory:validateContextMenuEvent", function(data)
    local _source <const> = source

    if not data or type(data) ~= "table" then return end

    if not data.event?.server then return end

    if next(ALLOWED_CONTEXT_MENU_EVENTS) == nil then
        return print("no events whitelisted", GetPlayerName(_source), " tried to call event:", data.event.server, "but no events were whitelisted", "possible Cheat!!")
    end

    if not ALLOWED_CONTEXT_MENU_EVENTS[joaat(data.event.server)] then
        return print("event not whitelisted", GetPlayerName(_source), " tried to call event:", data.event.server, "but it was not whitelisted", "possible Cheat!!")
    end

    TriggerEvent(data.event.server, _source, data.event?.arguments, data.itemid)
end)

---@param event string | table
---@param resourcename string
exports("addAllowedContextMenuEvent", function(event, resourcename)
    if not resourcename then return print("resourcename is required use GetCurrentResourceName() as argument") end

    if not event then return print("event name is required", resourcename) end

    if type(event) == "table" then
        for _, v in pairs(event) do
            ALLOWED_CONTEXT_MENU_EVENTS[joaat(v)] = true
        end
        return
    end

    if type(event) ~= "string" then return print("invalid eventname must be a string", resourcename) end
    ALLOWED_CONTEXT_MENU_EVENTS[joaat(event)] = true
end)

---@param event string | table
---@param resourcename string
exports("removeAllowedContextMenuEvent", function(event, resourcename)
    if not resourcename then return print("resourcename is required use GetCurrentResourceName() as argument") end

    if not event then return print("event name is required", resourcename) end

    if type(event) == "table" then
        for _, v in pairs(event) do
            ALLOWED_CONTEXT_MENU_EVENTS[joaat(v)] = nil
        end
        return
    end

    if type(event) ~= "string" then return print("invalid event name must be a string", resourcename) end
    ALLOWED_CONTEXT_MENU_EVENTS[joaat(event)] = nil
end)

if CONFIG.USE_RELOAD_SPEEDS then
    -- credits to xakra for reload speeds

    local function getCWeaponInfo(weaponName, params)
        local extraXml = ""
        if weaponName == "WEAPON_PISTOL_M1899" then
            extraXml = [[
           <ShortArmHolsterDOF value="3" />]]
        elseif weaponName == "WEAPON_PISTOL_MAUSER" then
            extraXml = [[
           <ShortArmHolsterDOF value="2" />]]
        elseif weaponName == "WEAPON_SNIPERRIFLE_CARCANO" or weaponName == "WEAPON_SNIPERRIFLE_ROLLINGBLOCK" then
            -- we remove a flag to allow toggle scope for carcano credits to mosquitoman
            extraXml = [[
            <WeaponFlags>
            CarriedInHand Gun CanFreeAim TwoHanded AnimReload UsableInCover
            UsableInVehicle UseSectionedReload UsableOnFoot HasLowCoverSwaps OnlyFireOneShot
            OnlyFireOneShotPerTriggerPress AllowCloseQuarterKills UseFPSAimIK UseFPSSecondaryMotion
            tGwmkMA_0xCE1E0473 CanHipFire cietEMA_0x1FCE1778 aONGdDA_0x081F0BDD nGjWRGA_0xC6550BE0 hNHcMQA_0x1FE95B8B ExclusivelyHolstered
            XrwawMA_0x7BA2F91C iZHoVCA_0x42D5F625 CanBeHorseHolstered CanBeOffhandCarried JxQEZJA_0xCC2A57A6 OwaLJJA_0x90882C1A xaYNfFA_0x40B6CD20 DropWhenLassoed
            kXLGCIB_0x08157808 oSZcNHA_0x3A829C54 HasIronSight SetLiTA_0x46B4F2E8 tPQYcQA_0x07982641 MfqZyCA_0x67B5DC71 GxuxzRA_0x87BD9548
            mCCDdGA_0x27895875 arChcAA_0xDB3819FA FTMdxOA_0x628A469E qpMyPBA_0x50CF49B4 MiiLNeA_0x323DB9E4 hnHIvQA_0xD62ED034 HnskfNA_0x4A113F84
            </WeaponFlags>
            ]]
        end

        return string.format([[
        <CWeaponInfo>
            <Name>%s</Name>
            <WeaponReload type="CWeaponReload">
                <AnimReloadRate value="%.2f" />
            </WeaponReload>%s
        </CWeaponInfo>
       ]], weaponName, params.AnimReloadRate, extraXml)
    end

    local filePath <const> = GetResourcePath(GetCurrentResourceName()) .. "/files/reloadspeeds.meta"
    local file <const>     = io.open(filePath, "w")

    local Content          = [[<?xml version="1.0" encoding="UTF-8"?>
    <Infos>
    ]]

    for weaponName, params in pairs(SHARED_DATA.WEAPONS) do
        if params.AnimReloadRate then
            Content = Content .. getCWeaponInfo(weaponName, params)
        end
    end
    Content = Content .. [[
    </Infos>
    ]]

    if file then
        file:write(Content)
        file:close()
    end
end
