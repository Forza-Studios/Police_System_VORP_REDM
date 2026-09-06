local spawnedPeds = {}
local spawnedBlips = {}

local function spawnPoliceNPCs()
    if not POLICE_NPCS or #POLICE_NPCS == 0 then return end

    for index, data in ipairs(POLICE_NPCS) do
        local modelHash = type(data.ped) == "number" and data.ped or GetHashKey(data.ped)

        if IsModelValid(modelHash) then
            if not HasModelLoaded(modelHash) then
                RequestModel(modelHash, false)
                local timeout = 0
                while not HasModelLoaded(modelHash) and timeout < 100 do
                    Wait(50)
                    timeout = timeout + 1
                end
            end

            if HasModelLoaded(modelHash) then
                local ped = CreatePed(modelHash, data.x, data.y, data.z, data.heading, false, false, false, false)
                repeat Wait(10) until DoesEntityExist(ped)

                SetRandomOutfitVariation(ped, true)
                PlaceEntityOnGroundProperly(ped)
                SetEntityCanBeDamaged(ped, false)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                FreezeEntityPosition(ped, true)

                table.insert(spawnedPeds, ped)
                SetModelAsNoLongerNeeded(modelHash)
            else
                print(("^1[coi_police] Error: Could not load model %s for NPC #%d^7"):format(data.ped, index))
            end
        else
            print(("^1[coi_police] Error: Invalid model %s for NPC #%d^7"):format(data.ped, index))
        end

        if data.blip then
            local sprite = type(data.blip) == "number" and data.blip or GetHashKey(data.blip)
            local blipStyle = data.blipStyle or 1664425300
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, blipStyle, data.x, data.y, data.z)
            if blip and blip ~= 0 then
                SetBlipSprite(blip, sprite, true)
                local varString = CreateVarString(10, 'LITERAL_STRING', "Sheriff Office")
                Citizen.InvokeNative(0x9CB1A1623062F402, blip, varString)
                table.insert(spawnedBlips, blip)
            end
        end
    end
end

local function cleanup()
    for _, ped in ipairs(spawnedPeds) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end
    spawnedPeds = {}

    for _, blip in ipairs(spawnedBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    spawnedBlips = {}
end

CreateThread(function()
    spawnPoliceNPCs()
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanup()
    end
end)
