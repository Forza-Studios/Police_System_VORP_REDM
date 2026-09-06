local doorStates = {}

-- Initialize door states on resource start
AddEventHandler("onResourceStart", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if Config and Config.DoorList then
            for _, door in ipairs(Config.DoorList) do
                doorStates[door.id] = (door.locked ~= false)
            end
        end
    end
end)

RegisterNetEvent("coi_police:server:requestDoorStates", function()
    local _source = source
    if Config and Config.DoorList then
        for _, door in ipairs(Config.DoorList) do
            if doorStates[door.id] == nil then
                doorStates[door.id] = (door.locked ~= false)
            end
        end
    end
    TriggerClientEvent("coi_police:client:syncDoorStates", _source, doorStates)
end)

RegisterNetEvent("coi_police:server:toggleDoorState", function(doorId)
    local _source = source
    if not doorId then return end

    if doorStates[doorId] == nil then
        doorStates[doorId] = true
    end

    doorStates[doorId] = not doorStates[doorId]
    TriggerClientEvent("coi_police:client:updateDoorState", -1, doorId, doorStates[doorId])
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
