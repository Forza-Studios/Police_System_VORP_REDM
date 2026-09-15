local doorStates = {} -- [doorHashNum] = isLocked (boolean)
local Core = exports.vorp_core:GetCore()

local function isPolice(source)
    local user = Core.getUser(source)
    local character = user and user.getUsedCharacter
    local allowedJobs = Config and Config.PoliceJobs
    return character and allowedJobs and allowedJobs[character.job] == true
end

local function ToPrimitiveNumber(val)
    if type(val) == "number" then return math.floor(val) end
    if type(val) == "string" then return math.floor(tonumber(val) or 0) end
    if type(val) == "boolean" then return val and 1 or 0 end
    return 0
end

local function initDoorStates()
    local doorsList = (Config and (Config.LockedDoors or Config.Doors)) or {}
    for _, entry in ipairs(doorsList) do
        local doorHash = ToPrimitiveNumber(type(entry) == "table" and (entry.doorHash or entry.hash) or entry)
        if doorHash ~= 0 and doorStates[doorHash] == nil then
            doorStates[doorHash] = true -- Default locked
        end
    end
end

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        initDoorStates()
    end
end)

RegisterNetEvent("coi_police:server:requestDoorStates", function()
    local _source = source
    initDoorStates()
    TriggerClientEvent("coi_police:client:syncDoorStates", _source, doorStates)
end)

RegisterNetEvent("coi_police:server:toggleDoorLock", function(hash)
    local _source = source
    if not isPolice(_source) then return end
    local doorHash = ToPrimitiveNumber(hash)
    if doorHash == 0 then return end

    if doorStates[doorHash] == nil then
        doorStates[doorHash] = true
    end

    doorStates[doorHash] = not doorStates[doorHash]
    TriggerClientEvent("coi_police:client:syncSingleDoor", -1, doorHash, doorStates[doorHash])
end)

-- Handcuff Target Event Forwarding
RegisterNetEvent("coi_police:server:toggleCuff", function(targetServerId)
    local _source = source
    if not isPolice(_source) then return end
    if not targetServerId or targetServerId == -1 then return end

    local officerPed = GetPlayerPed(_source)
    local targetPed = GetPlayerPed(targetServerId)

    if DoesEntityExist(officerPed) and DoesEntityExist(targetPed) then
        local officerCoords = GetEntityCoords(officerPed)
        local targetCoords = GetEntityCoords(targetPed)
        local dist = #(officerCoords - targetCoords)

        if dist <= 5.0 then
            TriggerClientEvent("coi_police:client:toggleCuffTarget", targetServerId, _source)
        end
    end
end)

-- Carry / Escort Target Event Forwarding
RegisterNetEvent("coi_police:server:toggleCarry", function(targetServerId)
    local _source = source
    if not isPolice(_source) then return end
    if not targetServerId or targetServerId == -1 then return end

    local officerPed = GetPlayerPed(_source)
    local targetPed = GetPlayerPed(targetServerId)

    if DoesEntityExist(officerPed) and DoesEntityExist(targetPed) then
        local officerCoords = GetEntityCoords(officerPed)
        local targetCoords = GetEntityCoords(targetPed)
        local dist = #(officerCoords - targetCoords)

        if dist <= 5.0 then
            TriggerClientEvent("coi_police:client:syncCarryTarget", targetServerId, _source)
        end
    end
end)

-- Put Target in Jail Cell Event
RegisterNetEvent("coi_police:server:putInJail", function(targetServerId, coords)
    local _source = source
    if not isPolice(_source) then return end
    if not targetServerId or not coords then return end

    local officerPed = GetPlayerPed(_source)
    local targetPed = GetPlayerPed(targetServerId)

    if DoesEntityExist(officerPed) and DoesEntityExist(targetPed) then
        local officerCoords = GetEntityCoords(officerPed)
        local targetCoords = GetEntityCoords(targetPed)
        local dist = #(officerCoords - targetCoords)

        if dist <= 5.0 then
            TriggerClientEvent("coi_police:client:teleportToCell", targetServerId, coords)
        end
    end
end)

-- Sheriff Locker / Stash Event
RegisterNetEvent("coi_police:server:openSheriffStash", function()
    local _source = source
    if not isPolice(_source) then return end
    local stashConfig = Config and Config.SheriffStash
    if not stashConfig then return end

    local ped = GetPlayerPed(_source)
    if DoesEntityExist(ped) then
        local pedCoords = GetEntityCoords(ped)
        local dist = #(pedCoords - vector3(stashConfig.coords.x, stashConfig.coords.y, stashConfig.coords.z))

        if dist <= 3.5 then
            if exports.vorp_inventory then
                local isRegistered = exports.vorp_inventory:isCustomInventoryRegistered(stashConfig.id)
                if not isRegistered then
                    exports.vorp_inventory:registerInventory({
                        id = stashConfig.id,
                        name = stashConfig.name or "Sheriff Locker",
                        limit = stashConfig.limit or 700,
                        acceptWeapons = true,
                        shared = true,
                        ignoreItemStackLimit = true,
                        whitelistItems = false,
                        UsePermissions = false,
                        UseBlackList = false,
                        whitelistWeapons = false
                    })
                end
                exports.vorp_inventory:openInventory(_source, stashConfig.id)
            end
        end
    end
end)

-- Active Distress Calls Storage
local activeCalls = {}
local callCounter = 0

-- Call Sheriff Alert (any player can call, stores active call with exact player coords and notifies sheriffs)
RegisterNetEvent("coi_police:server:callSheriff", function(clientCoords)
    local _source = source

    -- Get the caller's character name via VORP Core
    local callerName = "Unknown"
    local user = Core.getUser(_source)
    if user then
        local character = user.getUsedCharacter
        if character then
            local first = character.firstname or ""
            local last = character.lastname or ""
            callerName = (first .. " " .. last):gsub("^%s+", ""):gsub("%s+$", "")
            if callerName == "" then
                callerName = GetPlayerName(_source) or "Unknown"
            end
        end
    end

    -- Get caller ped exact position
    local coords = { x = 0.0, y = 0.0, z = 0.0 }
    if clientCoords and type(clientCoords) == "table" and clientCoords.x then
        coords = {
            x = tonumber(clientCoords.x) or 0.0,
            y = tonumber(clientCoords.y) or 0.0,
            z = tonumber(clientCoords.z) or 0.0
        }
    else
        local ped = GetPlayerPed(_source)
        if DoesEntityExist(ped) then
            local c = GetEntityCoords(ped)
            coords = { x = c.x, y = c.y, z = c.z }
        end
    end

    callCounter = callCounter + 1
    local callData = {
        id = callCounter,
        callerSrc = _source,
        callerName = callerName,
        coords = coords,
        timeStr = os.date("%H:%M"),
        status = "PENDING" -- PENDING, RESPONDED, RESOLVED
    }

    table.insert(activeCalls, 1, callData)
    if #activeCalls > 25 then
        table.remove(activeCalls, #activeCalls)
    end

    -- Sync active calls list to all clients
    TriggerClientEvent("coi_police:client:syncActiveCalls", -1, activeCalls)

    -- Broadcast notification alert to all on-duty sheriffs
    TriggerClientEvent("coi_police:client:sheriffCallAlert", -1, callerName, callData)
    print(("[coi_police] Distress Call #%d received from %s (ID: %d) at (%.1f, %.1f)"):format(callCounter, callerName, _source, coords.x, coords.y))
end)

-- Request active calls for dashboard sync
RegisterNetEvent("coi_police:server:requestActiveCalls", function()
    local _source = source
    if not isPolice(_source) then return end
    TriggerClientEvent("coi_police:client:syncActiveCalls", _source, activeCalls)
end)

-- Respond to Call
RegisterNetEvent("coi_police:server:respondCall", function(callId)
    local _source = source
    if not isPolice(_source) then return end

    for _, call in ipairs(activeCalls) do
        if call.id == callId then
            call.status = "RESPONDED"

            -- Notify the player who called that a Sheriff is on the way
            if call.callerSrc and GetPlayerName(call.callerSrc) then
                TriggerClientEvent("coi_police:client:notifyCallerResponding", call.callerSrc)
            end
            break
        end
    end
    TriggerClientEvent("coi_police:client:syncActiveCalls", -1, activeCalls)
end)

-- Resolve/Clear Call
RegisterNetEvent("coi_police:server:resolveCall", function(callId)
    local _source = source
    if not isPolice(_source) then return end
    for i, call in ipairs(activeCalls) do
        if call.id == callId then
            table.remove(activeCalls, i)
            break
        end
    end
    TriggerClientEvent("coi_police:client:syncActiveCalls", -1, activeCalls)
end)

