local spawnedPeds = {}
local spawnedBlips = {}
local isPoliceOnDuty = false
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local promptHandle = nil

local function notify(msg)
    TriggerEvent("vorp:TipRight", msg, 4000)
    TriggerEvent("vorp:Notify", "top-right", msg, 4000)
end

local function updateDutyUI(onDuty)
    if Config and Config.EnableDutyPill then
        if onDuty then
            SendNUIMessage({
                action = "showDutyPill",
                text = (Config and Config.DutyPillText) or "Sheriff On Duty"
            })
        else
            SendNUIMessage({
                action = "hideDutyPill"
            })
        end
    end
end

local function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFontForCurrentCommand(1)
        SetTextColor(255, 255, 255, 215)
        SetTextCentre(1)
        local str = CreateVarString(10, "LITERAL_STRING", text)
        DisplayText(str, _x, _y)
    end
end

local function createDutyPrompt(actionText)
    local keyHash = (Config and Config.Key) or 0x760A9C6F
    local str = CreateVarString(10, 'LITERAL_STRING', actionText or "Go On Duty")
    if not promptHandle then
        promptHandle = PromptRegisterBegin()
        PromptSetControlAction(promptHandle, keyHash)
        PromptSetText(promptHandle, str)
        PromptSetEnabled(promptHandle, true)
        PromptSetVisible(promptHandle, true)
        PromptSetStandardMode(promptHandle, true)
        PromptSetGroup(promptHandle, promptGroup)
        PromptRegisterEnd(promptHandle)
    else
        PromptSetText(promptHandle, str)
    end
end

local function isPromptPressed()
    if promptHandle then
        if PromptHasStandardModeCompleted(promptHandle)
        or PromptHasHoldModeCompleted(promptHandle)
        or PromptIsJustPressed(promptHandle)
        or PromptIsJustReleased(promptHandle) then
            return true
        end
    end

    local keyHash = (Config and Config.Key) or 0x760A9C6F
    local fallbackKeys = { keyHash, 0x760A9C6F, 0x76037780, 0x44685E6B }
    for _, k in ipairs(fallbackKeys) do
        for group = 0, 2 do
            if IsControlJustPressed(group, k) or IsDisabledControlJustPressed(group, k) then
                return true
            end
        end
    end
    return false
end

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

    if promptHandle then
        PromptDelete(promptHandle)
        promptHandle = nil
    end

    updateDutyUI(false)
end

CreateThread(function()
    spawnPoliceNPCs()

    local groupTitle = CreateVarString(10, 'LITERAL_STRING', "Sheriff Office")
    local interactionDist = (Config and Config.InteractionDistance) or 3.5

    while true do
        local sleep = 1000
        if POLICE_NPCS and #POLICE_NPCS > 0 then
            local playerPed = PlayerPedId()
            if not IsEntityDead(playerPed) then
                local playerCoords = GetEntityCoords(playerPed)

                for _, npcData in ipairs(POLICE_NPCS) do
                    local dist = #(playerCoords - vector3(npcData.x, npcData.y, npcData.z))
                    if dist <= interactionDist then
                        sleep = 0

                        local actionText = isPoliceOnDuty and "Go Off Duty" or "Go On Duty"
                        createDutyPrompt(actionText)
                        PromptSetActiveGroupThisFrame(promptGroup, groupTitle, 0, 0, 0, 0)

                        -- 3D Text Floating above NPC for guaranteed interaction hint
                        DrawText3D(npcData.x, npcData.y, npcData.z + 1.1, "[G] " .. actionText)

                        if isPromptPressed() then
                            isPoliceOnDuty = not isPoliceOnDuty
                            if isPoliceOnDuty then
                                notify("You are now ON duty!")
                            else
                                notify("You are now OFF duty!")
                            end
                            updateDutyUI(isPoliceOnDuty)
                            Wait(800)
                        end
                        break
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanup()
    end
end)
