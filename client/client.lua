local spawnedPeds = {}
local spawnedBlips = {}
local isPoliceOnDuty = false
local isHandcuffed = false

local dutyPromptGroup = GetRandomIntInRange(0, 0xffffff)
local dutyPromptHandle = nil

local cuffPromptGroup = GetRandomIntInRange(0, 0xffffff)
local cuffPromptHandle = nil
local targetCuffStates = {} -- Cache for target player cuffed states
local cuffedNPCs = {}        -- Cache for NPC cuffed states

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

-- Detect closest Target (Players OR NPC Peds)
local function GetClosestTargetPed(maxDistance)
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local closestPed = -1
    local closestDist = maxDistance or 2.5
    local isPlayer = false
    local targetServerId = nil

    -- 1. Check nearby players
    local players = GetActivePlayers()
    for _, player in ipairs(players) do
        local targetPed = GetPlayerPed(player)
        if targetPed ~= myPed and DoesEntityExist(targetPed) and not IsEntityDead(targetPed) then
            local dist = #(myCoords - GetEntityCoords(targetPed))
            if dist < closestDist then
                closestDist = dist
                closestPed = targetPed
                isPlayer = true
                targetServerId = GetPlayerServerId(player)
            end
        end
    end

    -- 2. If no player is closest, check nearby NPC Peds
    if closestPed == -1 then
        local pedHandle, ped = FindFirstPed()
        local success = true
        repeat
            if DoesEntityExist(ped) and ped ~= myPed and not IsEntityDead(ped) and not IsPedAPlayer(ped) then
                -- Make sure ped is not one of our duty station peds
                local isDutyNPC = false
                for _, sPed in ipairs(spawnedPeds) do
                    if ped == sPed then
                        isDutyNPC = true
                        break
                    end
                end

                if not isDutyNPC then
                    local dist = #(myCoords - GetEntityCoords(ped))
                    if dist < closestDist then
                        closestDist = dist
                        closestPed = ped
                        isPlayer = false
                        targetServerId = nil
                    end
                end
            end
            success, ped = FindNextPed(pedHandle)
        until not success
        EndFindPed(pedHandle)
    end

    return closestPed, closestDist, isPlayer, targetServerId
end

local function createDutyPrompt(actionText)
    local keyHash = (Config and Config.Key) or 0x760A9C6F
    local str = CreateVarString(10, 'LITERAL_STRING', actionText or "Go On Duty")
    if not dutyPromptHandle then
        dutyPromptHandle = PromptRegisterBegin()
        PromptSetControlAction(dutyPromptHandle, keyHash)
        PromptSetText(dutyPromptHandle, str)
        PromptSetEnabled(dutyPromptHandle, true)
        PromptSetVisible(dutyPromptHandle, true)
        PromptSetStandardMode(dutyPromptHandle, true)
        PromptSetGroup(dutyPromptHandle, dutyPromptGroup)
        PromptRegisterEnd(dutyPromptHandle)
    else
        PromptSetText(dutyPromptHandle, str)
    end
end

local function isDutyPromptPressed()
    if dutyPromptHandle then
        if PromptHasStandardModeCompleted(dutyPromptHandle)
        or PromptHasHoldModeCompleted(dutyPromptHandle)
        or PromptIsJustPressed(dutyPromptHandle)
        or PromptIsJustReleased(dutyPromptHandle) then
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

local function createCuffPrompt(actionText)
    local keyHash = (Config and Config.CuffKey) or 0x805B4AEA
    local str = CreateVarString(10, 'LITERAL_STRING', actionText or "Handcuff")
    if not cuffPromptHandle then
        cuffPromptHandle = PromptRegisterBegin()
        PromptSetControlAction(cuffPromptHandle, keyHash)
        PromptSetText(cuffPromptHandle, str)
        PromptSetEnabled(cuffPromptHandle, true)
        PromptSetVisible(cuffPromptHandle, true)
        PromptSetStandardMode(cuffPromptHandle, true)
        PromptSetGroup(cuffPromptHandle, cuffPromptGroup)
        PromptRegisterEnd(cuffPromptHandle)
    else
        PromptSetText(cuffPromptHandle, str)
    end
end

local function isCuffPromptPressed()
    if cuffPromptHandle then
        if PromptHasStandardModeCompleted(cuffPromptHandle)
        or PromptHasHoldModeCompleted(cuffPromptHandle)
        or PromptIsJustPressed(cuffPromptHandle)
        or PromptIsJustReleased(cuffPromptHandle) then
            return true
        end
    end

    local keyHash = (Config and Config.CuffKey) or 0x805B4AEA
    local fallbackKeys = { keyHash, 0x805B4AEA, 0x26E9DAE4 }
    for _, k in ipairs(fallbackKeys) do
        for group = 0, 2 do
            if IsControlJustPressed(group, k) or IsDisabledControlJustPressed(group, k) then
                return true
            end
        end
    end
    return false
end

local function playOfficerCuffAnim()
    local dict = "script_re@cuffs"
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    TaskPlayAnim(PlayerPedId(), dict, "cuff_cop", 8.0, -8.0, 2500, 25, 0, false, false, false)
end

local function cuffNPCPed(npcPed, cuffed)
    if not DoesEntityExist(npcPed) then return end

    if cuffed then
        SetEnableHandcuffs(npcPed, true)
        SetBlockingOfNonTemporaryEvents(npcPed, true)
        FreezeEntityPosition(npcPed, true)

        local dict = "script_re@cuffs"
        RequestAnimDict(dict)
        local timeout = 0
        while not HasAnimDictLoaded(dict) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end
        TaskPlayAnim(npcPed, dict, "cuffed_loop", 8.0, -8.0, -1, 31, 0, false, false, false)
        notify("You handcuffed the individual.")
    else
        SetEnableHandcuffs(npcPed, false)
        SetBlockingOfNonTemporaryEvents(npcPed, false)
        FreezeEntityPosition(npcPed, false)
        ClearPedTasks(npcPed)
        notify("You uncuffed the individual.")
    end
end

-- TARGET PLAYER CUFF / UNCUFF EVENT
RegisterNetEvent("coi_police:client:toggleCuffTarget", function(officerSrc)
    isHandcuffed = not isHandcuffed
    local playerPed = PlayerPedId()

    if isHandcuffed then
        notify("You have been handcuffed.")

        -- Enable Handcuffs state
        SetEnableHandcuffs(playerPed, true)
        SetCurrentPedWeapon(playerPed, `WEAPON_UNARMED`, true)

        -- Load & Play Handcuff Loop Animation
        local dict = "script_re@cuffs"
        RequestAnimDict(dict)
        local timeout = 0
        while not HasAnimDictLoaded(dict) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end
        TaskPlayAnim(playerPed, dict, "cuffed_loop", 8.0, -8.0, -1, 31, 0, false, false, false)

        -- Disable actions loop while cuffed
        CreateThread(function()
            while isHandcuffed do
                Wait(0)
                local ped = PlayerPedId()
                DisableControlAction(0, 0x07CE1E29, true) -- ATTACK
                DisableControlAction(0, 0x8FFC7572, true) -- AIM
                DisableControlAction(0, 0xD70350AF, true) -- SELECT WEAPON
                DisableControlAction(0, 0xD3B5E727, true) -- MELEE
                DisableControlAction(0, 0x8702B207, true) -- JOURNAL
                DisableControlAction(0, 0x41AC83D1, true) -- VEHICLE/MOUNT
                DisableControlAction(0, 0xCEFD9220, true) -- WHISTLE
                DisableControlAction(0, 0x8FFC7572, true) -- INTERACT

                if not IsEntityPlayingAnim(ped, "script_re@cuffs", "cuffed_loop", 3) and not IsPedRagdoll(ped) then
                    TaskPlayAnim(ped, "script_re@cuffs", "cuffed_loop", 8.0, -8.0, -1, 31, 0, false, false, false)
                end
            end
        end)
    else
        notify("You have been uncuffed.")
        SetEnableHandcuffs(playerPed, false)
        ClearPedTasks(playerPed)
    end
end)

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

    if dutyPromptHandle then
        PromptDelete(dutyPromptHandle)
        dutyPromptHandle = nil
    end

    if cuffPromptHandle then
        PromptDelete(cuffPromptHandle)
        cuffPromptHandle = nil
    end

    updateDutyUI(false)
end

-- MAIN INTERACTION THREAD FOR DUTY NPC & TARGET HANDCUFFING
CreateThread(function()
    spawnPoliceNPCs()

    local groupTitle = CreateVarString(10, 'LITERAL_STRING', "Sheriff Office")
    local playerGroupTitle = CreateVarString(10, 'LITERAL_STRING', "Law Action")
    local npcInteractionDist = (Config and Config.InteractionDistance) or 3.5
    local cuffDist = (Config and Config.CuffDistance) or 2.5

    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()

        if not IsEntityDead(playerPed) then
            local playerCoords = GetEntityCoords(playerPed)

            -- 1. DUTY NPC INTERACTION
            if POLICE_NPCS and #POLICE_NPCS > 0 then
                for _, npcData in ipairs(POLICE_NPCS) do
                    local dist = #(playerCoords - vector3(npcData.x, npcData.y, npcData.z))
                    if dist <= npcInteractionDist then
                        sleep = 0

                        local actionText = isPoliceOnDuty and "Go Off Duty" or "Go On Duty"
                        createDutyPrompt(actionText)
                        PromptSetActiveGroupThisFrame(dutyPromptGroup, groupTitle, 0, 0, 0, 0)
                        DrawText3D(npcData.x, npcData.y, npcData.z + 1.1, "[G] " .. actionText)

                        if isDutyPromptPressed() then
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

            -- 2. ON-DUTY HANDCUFF INTERACTION (PLAYERS & NPC PEDS)
            if isPoliceOnDuty then
                local closestPed, closestDist, isPlayer, targetServerId = GetClosestTargetPed(cuffDist)
                if closestPed ~= -1 and DoesEntityExist(closestPed) then
                    sleep = 0

                    local isTargetCuffed = false
                    if isPlayer and targetServerId then
                        isTargetCuffed = targetCuffStates[targetServerId] or false
                    else
                        isTargetCuffed = cuffedNPCs[closestPed] or false
                    end

                    local cuffText = isTargetCuffed and "Uncuff Individual" or "Handcuff Individual"

                    createCuffPrompt(cuffText)
                    PromptSetActiveGroupThisFrame(cuffPromptGroup, playerGroupTitle, 0, 0, 0, 0)

                    local targetCoords = GetEntityCoords(closestPed)
                    DrawText3D(targetCoords.x, targetCoords.y, targetCoords.z + 1.0, "[L] " .. cuffText)

                    if isCuffPromptPressed() then
                        playOfficerCuffAnim()

                        if isPlayer and targetServerId then
                            targetCuffStates[targetServerId] = not isTargetCuffed
                            TriggerServerEvent("coi_police:server:toggleCuff", targetServerId)
                        else
                            cuffedNPCs[closestPed] = not isTargetCuffed
                            cuffNPCPed(closestPed, cuffedNPCs[closestPed])
                        end
                        Wait(1500)
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
