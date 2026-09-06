local doorStates = {} -- [doorHashNum] = isLocked (boolean)

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
