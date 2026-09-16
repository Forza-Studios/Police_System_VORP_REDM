local spawnedPeds = {}
local spawnedBlips = {}
local spawnedDutyPeds = {}
local spawnedDutyBlips = {}
local updateDutyNPCs = nil
local clearDistressBlips = nil
local isPoliceOnDuty = false
local isHandcuffed = false

local isCarrying = false
local carriedPedHandle = nil
local carriedPlayerServerId = nil
local isBeingCarried = false
local carrierOfficerSrc = nil

local dutyPromptGroup = GetRandomIntInRange(0, 0xffffff)
local dutyPromptHandle = nil

local cuffPromptGroup = GetRandomIntInRange(0, 0xffffff)
local cuffPromptHandle = nil
local targetCuffStates = {} -- Cache for target player cuffed states
local cuffedNPCs = {}        -- Cache for NPC cuffed states

-- Reinforcement Vehicle Menu
local reinforcementPromptGroup = GetRandomIntInRange(0, 0xffffff)
local reinforcementPromptHandle = nil
local isReinforcementMenuOpen = false
local lastSpawnedReinforcement = nil

local function hasPoliceJob()
    local character = LocalPlayer.state.Character
    local job = character and (character.Job or character.job)
    return Config and Config.PoliceJobs and Config.PoliceJobs[job] == true
end

local function isAuthorizedOnDuty()
    return hasPoliceJob() and isPoliceOnDuty
end

local function notify(msg)
    TriggerEvent("vorp:TipRight", msg, 4000)
    TriggerEvent("vorp:Notify", "top-right", msg, 4000)
end

local function updateDutyUI(onDuty)
    if updateDutyNPCs then
        updateDutyNPCs(onDuty)
    end
    if not onDuty and clearDistressBlips then
        clearDistressBlips()
    end

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

-- Robust Target Ped Detection using GetGamePool('CPed') with FindFirstPed fallback
local function GetClosestTargetPed(maxDistance)
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local closestPed = -1
    local closestDist = maxDistance or 5.0
    local isPlayer = false
    local targetServerId = nil

    local peds = {}
    local successPool, pool = pcall(function() return GetGamePool('CPed') end)
    if successPool and type(pool) == "table" and #pool > 0 then
        peds = pool
    else
        local handle, ped = FindFirstPed()
        local success = true
        if handle and handle ~= -1 then
            repeat
                table.insert(peds, ped)
                success, ped = FindNextPed(handle)
            until not success
            EndFindPed(handle)
        end
    end

    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) and ped ~= myPed and not IsEntityDead(ped) then
            local isDutyNPC = false
            for _, sPed in ipairs(spawnedPeds) do
                if ped == sPed then
                    isDutyNPC = true
                    break
                end
            end

            if not isDutyNPC then
                local pedCoords = GetEntityCoords(ped)
                local dist = #(myCoords - pedCoords)
                if dist <= closestDist then
                    closestDist = dist
                    closestPed = ped
                    if IsPedAPlayer(ped) then
                        isPlayer = true
                        for _, player in ipairs(GetActivePlayers()) do
                            if GetPlayerPed(player) == ped then
                                targetServerId = GetPlayerServerId(player)
                                break
                            end
                        end
                    else
                        isPlayer = false
                        targetServerId = nil
                    end
                end
            end
        end
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
    local fallbackKeys = { keyHash, 0x805B4AEA, 0x26E9DAE4, 0x8FFC7572, 0xE30CD707 }
    for _, k in ipairs(fallbackKeys) do
        for group = 0, 2 do
            if IsControlJustPressed(group, k)
            or IsControlJustReleased(group, k)
            or IsDisabledControlJustPressed(group, k)
            or IsDisabledControlJustReleased(group, k) then
                return true
            end
        end
    end
    return false
end

local officerAnims = {
    { dict = "script_proc@robbing@cuffs", name = "cuff_cop" },
    { dict = "script_re@cuffs", name = "cuff_cop" },
    { dict = "mech_inventory@cuffs", name = "cuff_cop" },
    { dict = "cnv_camp@generic@cuffs", name = "cuff_cop" },
    { dict = "script_re@cuffs", name = "cuffed_loop" }
}

local targetAnims = {
    { dict = "script_proc@robbing@cuffs", name = "cuffed_loop" },
    { dict = "script_re@cuffs", name = "cuffed_loop" },
    { dict = "mech_inventory@cuffs", name = "cuffed_loop" },
    { dict = "script_story@sal1@ig@ig11_cuffedsimon", name = "cuffed_loop" },
    { dict = "script_proc@robberies@shop@rhodes@gunsmith@inside", name = "cuffed_loop" }
}

local function playAnimWithFallback(ped, animList, blendIn, blendOut, duration, flag)
    local targetPed = ped or PlayerPedId()
    for _, anim in ipairs(animList) do
        local dict = anim.dict
        local name = anim.name
        RequestAnimDict(dict)
        local timeout = 0
        while not HasAnimDictLoaded(dict) and timeout < 25 do
            Wait(10)
            timeout = timeout + 1
        end
        if HasAnimDictLoaded(dict) then
            TaskPlayAnim(targetPed, dict, name, blendIn or 8.0, blendOut or -8.0, duration or -1, flag or 31, 0.0, false, false, false)
            return dict, name
        end
    end
    return nil, nil
end

local function playOfficerCuffAnim()
    playAnimWithFallback(PlayerPedId(), officerAnims, 8.0, -8.0, 3000, 25)
end

local function cuffNPCPed(npcPed, cuffed)
    if not DoesEntityExist(npcPed) then return end

    if cuffed then
        SetEnableHandcuffs(npcPed, true)
        Citizen.InvokeNative(0x1913AE2D2FB18414, npcPed, 128, true) -- SetPedConfigFlag 128 (Handcuffed)
        SetBlockingOfNonTemporaryEvents(npcPed, true)
        FreezeEntityPosition(npcPed, true)

        playAnimWithFallback(npcPed, targetAnims, 8.0, -8.0, -1, 31)
        notify("You handcuffed the individual.")
    else
        SetEnableHandcuffs(npcPed, false)
        Citizen.InvokeNative(0x1913AE2D2FB18414, npcPed, 128, false) -- SetPedConfigFlag 128
        SetBlockingOfNonTemporaryEvents(npcPed, false)
        FreezeEntityPosition(npcPed, false)
        ClearPedTasks(npcPed)
        notify("You uncuffed the individual.")
    end
end

-- CORE CUFF TRIGGER FUNCTION (Invoked by Menu Action)
local function tryCuffTarget()
    if not isAuthorizedOnDuty() then
        notify("You must be ON duty to handcuff!")
        return
    end

    local cuffDist = (Config and Config.CuffDistance) or 5.0
    local closestPed, closestDist, isPlayer, targetServerId = GetClosestTargetPed(cuffDist)

    if closestPed ~= -1 and DoesEntityExist(closestPed) then
        local isTargetCuffed = false
        if isPlayer and targetServerId then
            isTargetCuffed = targetCuffStates[targetServerId] or false
        else
            isTargetCuffed = cuffedNPCs[closestPed] or false
        end

        playOfficerCuffAnim()

        if isPlayer and targetServerId then
            targetCuffStates[targetServerId] = not isTargetCuffed
            TriggerServerEvent("coi_police:server:toggleCuff", targetServerId)
        else
            cuffedNPCs[closestPed] = not isTargetCuffed
            cuffNPCPed(closestPed, cuffedNPCs[closestPed])
        end
    else
        notify("No target nearby to handcuff!")
    end
end

-- NUI CALLBACKS FOR TARGET ACTION MENU
RegisterNUICallback("closeMenu", function(data, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("actionHandcuff", function(data, cb)
    SetNuiFocus(false, false)
    tryCuffTarget()
    cb("ok")
end)

local function tryCarryTarget()
    -- The key mapping exists client-side for every player, so silently ignore it
    -- unless this character is actually a police officer.
    if not hasPoliceJob() then
        return
    end

    if not isPoliceOnDuty then
        notify("You must be ON duty to carry or escort suspects!")
        return
    end

    local myPed = PlayerPedId()

    if isCarrying then
        if carriedPlayerServerId then
            TriggerServerEvent("coi_police:server:toggleCarry", carriedPlayerServerId)
            carriedPlayerServerId = nil
        elseif carriedPedHandle and DoesEntityExist(carriedPedHandle) then
            DetachEntity(carriedPedHandle, true, true)
            FreezeEntityPosition(carriedPedHandle, true)
            carriedPedHandle = nil
        end
        isCarrying = false
        notify("You stopped carrying the individual.")
        return
    end

    local cuffDist = (Config and Config.CuffDistance) or 5.0
    local closestPed, closestDist, isPlayer, targetServerId = GetClosestTargetPed(cuffDist)

    if closestPed ~= -1 and DoesEntityExist(closestPed) then
        local isTargetCuffed = false
        if isPlayer and targetServerId then
            isTargetCuffed = targetCuffStates[targetServerId] or false
        else
            isTargetCuffed = cuffedNPCs[closestPed] or false
        end

        if not isTargetCuffed then
            notify("Target must be handcuffed before carrying!")
            return
        end

        if isPlayer and targetServerId then
            TriggerServerEvent("coi_police:server:toggleCarry", targetServerId)
            isCarrying = true
            carriedPlayerServerId = targetServerId
            notify("You are carrying/escorting the player.")
        else
            isCarrying = true
            carriedPedHandle = closestPed
            FreezeEntityPosition(closestPed, false)
            AttachEntityToEntity(closestPed, myPed, 0, 0.2, 0.45, 0.0, 0.0, 0.0, 0.0, true, false, false, false, 2, true)
            notify("You are carrying/escorting the individual.")
        end
    else
        notify("No target nearby to carry!")
    end
end

RegisterNUICallback("actionCarry", function(data, cb)
    SetNuiFocus(false, false)
    tryCarryTarget()
    cb("ok")
end)

RegisterCommand("carry", function()
    tryCarryTarget()
end, false)

RegisterKeyMapping("carry", "Carry / Escort Handcuffed Suspect", "keyboard", "R")

RegisterNetEvent("coi_police:client:syncCarryTarget", function(officerSrc)
    isBeingCarried = not isBeingCarried
    local playerPed = PlayerPedId()

    if isBeingCarried then
        carrierOfficerSrc = officerSrc
        local officerPlayer = GetPlayerFromServerId(officerSrc)
        local officerPed = GetPlayerPed(officerPlayer)

        if DoesEntityExist(officerPed) then
            FreezeEntityPosition(playerPed, false)
            AttachEntityToEntity(playerPed, officerPed, 0, 0.2, 0.45, 0.0, 0.0, 0.0, 0.0, true, false, false, false, 2, true)
            notify("You are being carried / escorted by the Sheriff.")
        end
    else
        carrierOfficerSrc = nil
        DetachEntity(playerPed, true, true)
        if isHandcuffed then
            FreezeEntityPosition(playerPed, true)
        end
        notify("You were dropped.")
    end
end)

RegisterNUICallback("actionPutInJail", function(data, cb)
    SetNuiFocus(false, false)
    tryPutTargetInJail()
    cb("ok")
end)

-- REINFORCEMENT VEHICLE MENU NUI CALLBACKS
local function createReinforcementPrompt()
    local keyHash = (Config and Config.ReinforcementKey) or 0xF10FB3E4
    local str = CreateVarString(10, 'LITERAL_STRING', "Request Reinforcement")
    if not reinforcementPromptHandle then
        reinforcementPromptHandle = PromptRegisterBegin()
        PromptSetControlAction(reinforcementPromptHandle, keyHash)
        PromptSetText(reinforcementPromptHandle, str)
        PromptSetEnabled(reinforcementPromptHandle, true)
        PromptSetVisible(reinforcementPromptHandle, true)
        PromptSetStandardMode(reinforcementPromptHandle, true)
        PromptSetGroup(reinforcementPromptHandle, reinforcementPromptGroup)
        PromptRegisterEnd(reinforcementPromptHandle)
    else
        PromptSetText(reinforcementPromptHandle, str)
    end
end

local function isReinforcementPromptPressed()
    if reinforcementPromptHandle then
        if PromptHasStandardModeCompleted(reinforcementPromptHandle)
        or PromptHasHoldModeCompleted(reinforcementPromptHandle)
        or PromptIsJustPressed(reinforcementPromptHandle)
        or PromptIsJustReleased(reinforcementPromptHandle) then
            return true
        end
    end

    local keyHash = (Config and Config.ReinforcementKey) or 0xF10FB3E4
    for group = 0, 2 do
        if IsControlJustPressed(group, keyHash) or IsDisabledControlJustPressed(group, keyHash) then
            return true
        end
    end
    return false
end

local function openReinforcementMenu()
    if not isAuthorizedOnDuty() then
        notify("You must be ON duty to request reinforcements!")
        return
    end

    if not Config or not Config.ReinforcementVehicles or #Config.ReinforcementVehicles == 0 then
        notify("No reinforcement vehicles configured!")
        return
    end

    -- Build vehicle data for NUI
    local vehicleData = {}
    for _, v in ipairs(Config.ReinforcementVehicles) do
        table.insert(vehicleData, {
            label = v.label,
            model = v.model,
            image = v.image or "",
            desc = v.desc or ""
        })
    end

    -- Check if a reinforcement vehicle is currently active
    local hasActiveVehicle = lastSpawnedReinforcement ~= nil and DoesEntityExist(lastSpawnedReinforcement)
    local activeVehicleLabel = ""
    if hasActiveVehicle then
        -- Try to find the label from config
        local activeHash = GetEntityModel(lastSpawnedReinforcement)
        for _, v in ipairs(Config.ReinforcementVehicles) do
            if GetHashKey(v.model) == activeHash then
                activeVehicleLabel = v.label
                break
            end
        end
    end

    isReinforcementMenuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openReinforcementMenu",
        vehicles = vehicleData,
        hasActiveVehicle = hasActiveVehicle,
        activeVehicleLabel = activeVehicleLabel
    })
end

RegisterNUICallback("closeReinforcementMenu", function(data, cb)
    SetNuiFocus(false, false)
    isReinforcementMenuOpen = false
    cb("ok")
end)

RegisterNUICallback("returnReinforcement", function(data, cb)
    SetNuiFocus(false, false)
    isReinforcementMenuOpen = false

    if lastSpawnedReinforcement and DoesEntityExist(lastSpawnedReinforcement) then
        DeleteVehicle(lastSpawnedReinforcement)
        DeleteEntity(lastSpawnedReinforcement)
        lastSpawnedReinforcement = nil
        notify("Reinforcement vehicle returned to depot.")
    else
        lastSpawnedReinforcement = nil
        notify("No active reinforcement vehicle to return.")
    end

    cb("ok")
end)

RegisterNUICallback("spawnReinforcement", function(data, cb)
    SetNuiFocus(false, false)
    isReinforcementMenuOpen = false

    if not isAuthorizedOnDuty() then
        notify("You must be ON duty to request reinforcements!")
        cb("ok")
        return
    end

    local modelName = data and data.model
    if not modelName or modelName == "" then
        notify("Invalid vehicle model!")
        cb("ok")
        return
    end

    -- Delete previously spawned reinforcement vehicle
    if lastSpawnedReinforcement and DoesEntityExist(lastSpawnedReinforcement) then
        DeleteVehicle(lastSpawnedReinforcement)
        DeleteEntity(lastSpawnedReinforcement)
        lastSpawnedReinforcement = nil
    end

    local spawnCoords = Config.ReinforcementSpawn or vector4(-263.5977, 808.7073, 118.7609, 189.0707)
    local modelHash = GetHashKey(modelName)

    if not IsModelValid(modelHash) then
        notify("Vehicle model is not valid: " .. modelName)
        cb("ok")
        return
    end

    RequestModel(modelHash, false)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end

    if not HasModelLoaded(modelHash) then
        notify("Failed to load vehicle model: " .. modelName)
        cb("ok")
        return
    end

    local vehicle = Citizen.InvokeNative(0xAF35D0D2583051B0, modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w, true, false, false, false)
    if vehicle and DoesEntityExist(vehicle) then
        lastSpawnedReinforcement = vehicle
        SetModelAsNoLongerNeeded(modelHash)
        notify("Reinforcement vehicle delivered: " .. (data.label or modelName))
    else
        notify("Failed to spawn reinforcement vehicle!")
    end

    cb("ok")
end)

RegisterNUICallback("actionComingSoon", function(data, cb)
    notify(data.msg or "Feature coming soon!")
    cb("ok")
end)

-- SUSPECT SATCHEL SEARCH & CONFISCATE NUI CALLBACKS
RegisterNUICallback("actionSearchInventory", function(data, cb)
    if not isAuthorizedOnDuty() then
        SetNuiFocus(false, false)
        notify("You must be ON duty to search satchels!")
        cb("ok")
        return
    end

    local cuffDist = (Config and Config.CuffDistance) or 5.0
    local closestPed, closestDist, isPlayer, targetServerId = GetClosestTargetPed(cuffDist)

    if closestPed ~= -1 and DoesEntityExist(closestPed) then
        local isTargetCuffed = false
        if isPlayer and targetServerId then
            isTargetCuffed = targetCuffStates[targetServerId] or false
        else
            isTargetCuffed = cuffedNPCs[closestPed] or false
        end

        if not isTargetCuffed then
            SetNuiFocus(false, false)
            notify("The individual must be restrained or handcuffed to search their satchel!")
            cb("ok")
            return
        end

        -- Search animation
        TaskStartScenarioInPlace(PlayerPedId(), GetHashKey("WORLD_HUMAN_CROUCH_INSPECT"), 2500, true, false, false, false)

        if isPlayer and targetServerId then
            TriggerServerEvent("coi_police:server:searchInventory", targetServerId)
        else
            -- NPC satchel fallback with period items
            SetNuiFocus(true, true)
            local npcItems = {
                { name = "pocket_watch", label = "Silver Pocket Watch", count = 1 },
                { name = "whiskey", label = "Kentucky Bourbon", count = 1 },
                { name = "consumable_meat_cooked", label = "Salted Meat", count = 2 },
                { name = "lockpick", label = "Battered Lockpick", count = 1 }
            }
            SendNUIMessage({
                action = "openSuspectInventory",
                targetServerId = -1,
                targetName = "Civilian Traveler",
                money = 1.75,
                gold = 0.0,
                items = npcItems
            })
        end
    else
        SetNuiFocus(false, false)
        notify("No target nearby to search!")
    end
    cb("ok")
end)

RegisterNUICallback("closeInventory", function(data, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("actionConfiscateItem", function(data, cb)
    if not isAuthorizedOnDuty() then
        notify("You must be ON duty to confiscate evidence!")
        cb("ok")
        return
    end

    if not data or not data.itemName then
        cb("ok")
        return
    end

    local targetServerId = data.targetServerId
    if targetServerId and targetServerId ~= -1 then
        TriggerServerEvent("coi_police:server:confiscateItem", targetServerId, data.itemName, data.itemLabel or data.itemName, data.count or 1)
    else
        notify(("Confiscated %s x%d into county evidence."):format(data.itemLabel or data.itemName, data.count or 1))
    end
    cb("ok")
end)

-- SATCHEL INVENTORY CLIENT EVENTS
RegisterNetEvent("coi_police:client:receiveSuspectInventory", function(targetServerId, targetName, money, gold, items)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openSuspectInventory",
        targetServerId = targetServerId,
        targetName = targetName,
        money = money,
        gold = gold,
        items = items
    })
end)

RegisterNetEvent("coi_police:client:updateSuspectInventory", function(items, money, gold)
    SendNUIMessage({
        action = "updateSuspectInventory",
        items = items,
        money = money,
        gold = gold
    })
end)

-- PUBLIC /alert COMMAND (Available to ALL players)
local isAlertPanelOpen = false

RegisterCommand("alert", function()
    if isAlertPanelOpen then
        -- Close if already open
        SendNUIMessage({ action = "closeAlertPanel" })
        SetNuiFocus(false, false)
        isAlertPanelOpen = false
    else
        -- Open alert panel
        SetNuiFocus(true, true)
        SendNUIMessage({ action = "openAlertPanel" })
        isAlertPanelOpen = true
    end
end, false)

RegisterNUICallback("closeAlertPanel", function(data, cb)
    SetNuiFocus(false, false)
    isAlertPanelOpen = false
    cb("ok")
end)

-- NUI CALLBACK: Player clicked "Call Sheriff" in the alert panel
local lastCallSheriffTime = 0

RegisterNUICallback("actionCallSheriff", function(data, cb)
    SetNuiFocus(false, false)
    isAlertPanelOpen = false

    -- Cooldown check (30 seconds between calls)
    local now = GetGameTimer()
    if (now - lastCallSheriffTime) < 30000 then
        notify("You must wait before calling the Sheriff again!")
        cb("ok")
        return
    end

    lastCallSheriffTime = now
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    TriggerServerEvent("coi_police:server:callSheriff", { x = myCoords.x, y = myCoords.y, z = myCoords.z })
    notify("Your call has been sent to the Sheriff's office!")
    cb("ok")
end)

-- ACTIVE CALLS & SHERIFF DASHBOARD MANAGEMENT
local activeCallsList = {}
local isDashboardOpen = false

RegisterNetEvent("coi_police:client:syncActiveCalls", function(calls)
    if calls then
        activeCallsList = calls
        if isDashboardOpen then
            SendNUIMessage({
                action = "updateActiveCalls",
                activeCalls = activeCallsList
            })
        end
    end
end)

-- CLIENT EVENT: Received when someone calls the sheriff (sent to on-duty officers)
RegisterNetEvent("coi_police:client:sheriffCallAlert", function(callerName, callData)
    if not isPoliceOnDuty then return end

    -- Show the blue alert pill with caller name
    local alertText = (callerName or "Someone") .. " is calling a Sheriff"
    SendNUIMessage({
        action = "showCallAlert",
        text = alertText,
        duration = 10000
    })

    -- Also show a VORP notification toast
    notify(alertText)
end)

-- CLIENT EVENT: Triggered for the caller when Sheriff clicks Respond in dashboard
RegisterNetEvent("coi_police:client:notifyCallerResponding", function()
    notify("A Sheriff is on the way to your location!")
end)

-- OPEN SHERIFF DASHBOARD FUNCTION & /sheriff COMMAND
local function openSheriffDashboard()
    if not hasPoliceJob() then
        notify("Only Law Enforcement officers may access the Sheriff Ledger.")
        return
    end

    if not isPoliceOnDuty then
        notify("You must be ON DUTY to access the Sheriff Dashboard!")
        return
    end

    TriggerServerEvent("coi_police:server:requestActiveCalls")

    local character = LocalPlayer.state.Character
    local officerName = "Deputy Sheriff"
    if character then
        local first = character.firstname or ""
        local last = character.lastname or ""
        local full = (first .. " " .. last):gsub("^%s+", ""):gsub("%s+$", "")
        if full ~= "" then officerName = full end
    end

    isDashboardOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openSheriffDashboard",
        officerName = officerName,
        onDuty = isPoliceOnDuty,
        activeCalls = activeCallsList,
        doorStates = clientDoorStates
    })
end

RegisterCommand("sheriff", function()
    if isDashboardOpen then
        SendNUIMessage({ action = "closeSheriffDashboard" })
        SetNuiFocus(false, false)
        isDashboardOpen = false
    else
        openSheriffDashboard()
    end
end, false)

local currentCallBlip       = nil
local currentCallRadiusBlip = nil
local activeWaypointCoords  = nil
local activeWaypointCallId  = nil
local isTrackingArrival     = false

-- ---------------------------------------------------------------------------
-- setCallWaypoint  –  uses wagon_heist-verified RedM natives:
--   • BlipAddForCoords            = main map icon
--   • 0x45F13B7E0A15C880          = radius/zone circle blip (confirmed working)
--   • BlipAddModifier + MP_COLOR_2= red colour on both blips
--   • StartGpsMultiRoute          = live GPS path on minimap AND full map
-- ---------------------------------------------------------------------------

clearDistressBlips = function()
    activeWaypointCoords = nil
    activeWaypointCallId = nil

    if currentCallBlip then
        if DoesBlipExist(currentCallBlip) then
            RemoveBlip(currentCallBlip)
        end
        currentCallBlip = nil
    end

    if currentCallRadiusBlip then
        if DoesBlipExist(currentCallRadiusBlip) then
            RemoveBlip(currentCallRadiusBlip)
        end
        currentCallRadiusBlip = nil
    end

    ClearGpsMultiRoute()
end

local function startArrivalTracking()
    if isTrackingArrival then return end
    isTrackingArrival = true

    CreateThread(function()
        while activeWaypointCoords ~= nil do
            Wait(1000)

            if not isPoliceOnDuty then
                clearDistressBlips()
                break
            end

            if activeWaypointCoords then
                local playerPed = PlayerPedId()
                if DoesEntityExist(playerPed) and not IsEntityDead(playerPed) then
                    local pCoords = GetEntityCoords(playerPed)
                    local dist = #(pCoords - activeWaypointCoords)

                    -- When sheriff arrives within 25.0 meters of the alerted player location
                    if dist <= 25.0 then
                        clearDistressBlips()
                        notify("Arrived near the caller location. Distress route and radius cleared.")
                        break
                    end
                end
            end
        end
        isTrackingArrival = false
    end)
end

local function setCallWaypoint(x, y, z, callId)
    x = tonumber(x) or 0.0
    y = tonumber(y) or 0.0
    z = tonumber(z) or 0.0

    -- Clean up any previous call markers
    clearDistressBlips()

    activeWaypointCoords = vector3(x, y, z)
    activeWaypointCallId = callId

    local playerCoords = GetEntityCoords(PlayerPedId())

    -- 1. Red radius/zone circle blip (wagon_heist native – confirmed working in RedM)
    --    0x45F13B7E0A15C880 = BlipAddForRadius-style, args: style, x, y, z, radius
    local radiusBlip = Citizen.InvokeNative(0x45F13B7E0A15C880, -1282792512, x, y, z, 60.0)
    if radiusBlip and radiusBlip ~= 0 then
        BlipAddModifier(radiusBlip, joaat("BLIP_MODIFIER_MP_COLOR_2")) -- Red
        currentCallRadiusBlip = radiusBlip
    end

    -- 2. Main distress-call icon blip (BlipAddForCoords – confirmed working)
    local mainBlip = BlipAddForCoords(1664425300, x, y, z)
    if mainBlip and mainBlip ~= 0 then
        SetBlipSprite(mainBlip, -693644997, true)  -- Sheriff Star / Badge
        SetBlipScale(mainBlip, 1.2)
        SetBlipName(mainBlip, "Distress Call Location")
        BlipAddModifier(mainBlip, joaat("BLIP_MODIFIER_MP_COLOR_2")) -- Red
        currentCallBlip = mainBlip
    end

    -- 3. Realtime GPS route path on minimap AND full map
    ClearGpsMultiRoute()
    StartGpsMultiRoute(joaat("COLOR_RED"), true, true)
    AddPointToGpsMultiRoute(playerCoords.x, playerCoords.y, playerCoords.z, false)
    AddPointToGpsMultiRoute(x, y, z, false)
    SetGpsMultiRouteRender(true)

    -- 4. Start active distance check thread to auto-clean on arrival
    startArrivalTracking()
end

-- NUI DASHBOARD CALLBACKS
RegisterNUICallback("closeSheriffDashboard", function(data, cb)
    SetNuiFocus(false, false)
    isDashboardOpen = false
    cb("ok")
end)

RegisterNUICallback("setCallWaypoint", function(data, cb)
    if data and data.x and data.y then
        local x = tonumber(data.x) or 0.0
        local y = tonumber(data.y) or 0.0
        local z = tonumber(data.z) or 0.0
        local callId = data.callId

        -- Close dashboard UI so minimap & GPS route are immediately visible
        SendNUIMessage({ action = "closeSheriffDashboard" })
        SetNuiFocus(false, false)
        isDashboardOpen = false

        setCallWaypoint(x, y, z, callId)
        notify("GPS Waypoint & Route set to distress call location!")
    else
        notify("Could not set waypoint: location coordinates missing.")
    end
    cb("ok")
end)

RegisterNUICallback("respondCall", function(data, cb)
    if data and data.callId then
        TriggerServerEvent("coi_police:server:respondCall", data.callId)
        notify("Marked responding to Call #" .. tostring(data.callId))
    end
    cb("ok")
end)

RegisterNUICallback("resolveCall", function(data, cb)
    if data and data.callId then
        if activeWaypointCallId == data.callId then
            clearDistressBlips()
        end
        TriggerServerEvent("coi_police:server:resolveCall", data.callId)
        notify("Call #" .. tostring(data.callId) .. " resolved and cleared.")
    end
    cb("ok")
end)


-- FUNCTION TO PUT TARGET IN JAIL CELL
function tryPutTargetInJail()
    if not isAuthorizedOnDuty() then
        notify("You must be ON duty to put someone in jail!")
        return
    end

    if not Config or not Config.JailCells or #Config.JailCells == 0 then
        notify("No jail cells configured!")
        return
    end

    local cuffDist = (Config and Config.CuffDistance) or 5.0
    local closestPed, closestDist, isPlayer, targetServerId = GetClosestTargetPed(cuffDist)

    if closestPed ~= -1 and DoesEntityExist(closestPed) then
        -- Find closest cell location to officer
        local myCoords = GetEntityCoords(PlayerPedId())
        local selectedCell = Config.JailCells[1]
        local minCellDist = 9999.0

        for _, cell in ipairs(Config.JailCells) do
            local c = cell.coords
            local dist = #(myCoords - vector3(c.x, c.y, c.z))
            if dist < minCellDist then
                minCellDist = dist
                selectedCell = cell
            end
        end

        local c = selectedCell.coords
        local vecCoords = { x = c.x, y = c.y, z = c.z, heading = c.w or c.h or 80.0 }

        if isCarrying then
            isCarrying = false
            carriedPedHandle = nil
            carriedPlayerServerId = nil
        end

        if isPlayer and targetServerId then
            TriggerServerEvent("coi_police:server:putInJail", targetServerId, vecCoords)
            notify("You put the player in " .. (selectedCell.name or "Cell") .. ".")
        else
            SetEntityCoords(closestPed, vecCoords.x, vecCoords.y, vecCoords.z, false, false, false, false)
            if vecCoords.heading then
                SetEntityHeading(closestPed, vecCoords.heading)
            end
            notify("You put the individual in " .. (selectedCell.name or "Cell") .. ".")
        end
    else
        notify("No target nearby to put in jail!")
    end
end

-- TARGET PLAYER TELEPORT TO CELL EVENT
RegisterNetEvent("coi_police:client:teleportToCell", function(coords)
    if not coords then return end
    local ped = PlayerPedId()
    if isBeingCarried then
        isBeingCarried = false
        carrierOfficerSrc = nil
        DetachEntity(ped, true, true)
    end
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    if coords.heading then
        SetEntityHeading(ped, coords.heading)
    end
    if isHandcuffed then
        FreezeEntityPosition(ped, true)
    end
    notify("You have been locked in a jail cell.")
end)

-- FUNCTION TO OPEN TARGET ACTION MENU ON KEY 'L'
local function tryOpenTargetMenu()
    if not isAuthorizedOnDuty() then
        notify("You must be ON duty to perform police actions!")
        return
    end

    local cuffDist = (Config and Config.CuffDistance) or 5.0
    local closestPed, closestDist, isPlayer, targetServerId = GetClosestTargetPed(cuffDist)

    if closestPed ~= -1 and DoesEntityExist(closestPed) then
        local isTargetCuffed = false
        if isPlayer and targetServerId then
            isTargetCuffed = targetCuffStates[targetServerId] or false
        else
            isTargetCuffed = cuffedNPCs[closestPed] or false
        end

        local nameStr = isPlayer and ("Player [ID: " .. tostring(targetServerId) .. "]") or "Civilian / NPC"

        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "openTargetMenu",
            targetName = nameStr,
            targetServerId = targetServerId,
            isPlayer = isPlayer,
            isCuffed = isTargetCuffed,
            isCarrying = isCarrying
        })
    else
        notify("No target nearby to interact with!")
    end
end

-- KEY MAPPING AND COMMAND DEFINITION FOR PHYSICAL KEY 'L'
RegisterCommand("cuff", function()
    tryOpenTargetMenu()
end, false)

RegisterKeyMapping("cuff", "Open Police Target Menu", "keyboard", "L")

-- TARGET PLAYER CUFF / UNCUFF EVENT
RegisterNetEvent("coi_police:client:toggleCuffTarget", function(officerSrc)
    isHandcuffed = not isHandcuffed
    local playerPed = PlayerPedId()

    if isHandcuffed then
        notify("You have been handcuffed.")

        SetEnableHandcuffs(playerPed, true)
        Citizen.InvokeNative(0x1913AE2D2FB18414, playerPed, 128, true) -- SetPedConfigFlag 128
        SetCurrentPedWeapon(playerPed, `WEAPON_UNARMED`, true)
        if not isBeingCarried then
            FreezeEntityPosition(playerPed, true)
        end

        local usedDict, usedName = playAnimWithFallback(playerPed, targetAnims, 8.0, -8.0, -1, 31)

        CreateThread(function()
            while isHandcuffed do
                Wait(0)
                local ped = PlayerPedId()
                -- Disable Movement Controls
                DisableControlAction(0, 0x5966D52A, true) -- MOVE LEFT/RIGHT
                DisableControlAction(0, 0x4D8FA8B0, true) -- MOVE UP/DOWN
                DisableControlAction(0, 0x8FD015D8, true) -- SPRINT
                DisableControlAction(0, 0xD7FF1B00, true) -- JUMP
                DisableControlAction(0, 0x26E9DAE4, true) -- VAULT/COVER

                -- Disable Action Controls
                DisableControlAction(0, 0x07CE1E29, true) -- ATTACK
                DisableControlAction(0, 0x8FFC7572, true) -- AIM
                DisableControlAction(0, 0xD70350AF, true) -- SELECT WEAPON
                DisableControlAction(0, 0xD3B5E727, true) -- MELEE
                DisableControlAction(0, 0x8702B207, true) -- JOURNAL
                DisableControlAction(0, 0x41AC83D1, true) -- VEHICLE/MOUNT
                DisableControlAction(0, 0xCEFD9220, true) -- WHISTLE

                if usedDict and usedName then
                    if not IsEntityPlayingAnim(ped, usedDict, usedName, 3) and not IsPedRagdoll(ped) then
                        TaskPlayAnim(ped, usedDict, usedName, 8.0, -8.0, -1, 31, 0.0, false, false, false)
                    end
                end
            end
        end)
    else
        notify("You have been uncuffed.")
        if isBeingCarried then
            isBeingCarried = false
            carrierOfficerSrc = nil
            DetachEntity(playerPed, true, true)
        end
        SetEnableHandcuffs(playerPed, false)
        Citizen.InvokeNative(0x1913AE2D2FB18414, playerPed, 128, false)
        FreezeEntityPosition(playerPed, false)
        ClearPedTasks(playerPed)
    end
end)

-- CELL DOOR LOCKING SYSTEM (Key 'K' Toggle for On-Duty Sheriffs)
local clientDoorStates = {}

local function ToPrimitiveNumber(val)
    if type(val) == "number" then return math.floor(val) end
    if type(val) == "string" then return math.floor(tonumber(val) or 0) end
    if type(val) == "boolean" then return val and 1 or 0 end
    if type(val) == "userdata" then
        local str = tostring(val)
        local num = tonumber(str)
        if num then return math.floor(num) end
    end
    return 0
end

local function RegisterDoorHash(hash)
    if not hash or hash == 0 then return end
    if IsDoorRegisteredWithSystem and IsDoorRegisteredWithSystem(hash) then return end
    Citizen.InvokeNative(0xD99229FE93B46286, hash, 1, 1, 0, 0, 0, 0)
end

local function SetDoorLockState(hash, isLocked)
    local doorHash = ToPrimitiveNumber(hash)
    if not doorHash or doorHash == 0 then return end
    RegisterDoorHash(doorHash)
    if isLocked then
        if DoorSystemSetOpenRatio then
            DoorSystemSetOpenRatio(doorHash, 0.0, false, false)
        else
            Citizen.InvokeNative(0xB6E6FBA95C7324AC, doorHash, 0.0, true)
        end
        if DoorSystemSetDoorState then
            DoorSystemSetDoorState(doorHash, 1, false, false)
        else
            Citizen.InvokeNative(0x6BAB9442830C7F53, doorHash, 1)
        end
    else
        if DoorSystemSetDoorState then
            DoorSystemSetDoorState(doorHash, 0, false, false)
        else
            Citizen.InvokeNative(0x6BAB9442830C7F53, doorHash, 0)
        end
    end
end

RegisterNetEvent("coi_police:client:syncDoorStates", function(states)
    if states then
        clientDoorStates = states
    end
end)

RegisterNetEvent("coi_police:client:syncSingleDoor", function(doorHash, isLocked)
    clientDoorStates[doorHash] = isLocked
    SetDoorLockState(doorHash, isLocked)
    local actionText = isLocked and "Locked cell door." or "Unlocked cell door."
    notify(actionText)
end)

local function applyAllDoorStates()
    local doorsList = (Config and (Config.LockedDoors or Config.Doors)) or {}
    for _, entry in ipairs(doorsList) do
        local doorHash = ToPrimitiveNumber(type(entry) == "table" and (entry.doorHash or entry.hash) or entry)
        if doorHash ~= 0 then
            local isLocked = clientDoorStates[doorHash]
            if isLocked == nil then
                isLocked = true
            end
            SetDoorLockState(doorHash, isLocked)
        end
    end
end

CreateThread(function()
    while true do
        applyAllDoorStates()
        Wait(1000)
    end
end)

local function tryToggleClosestDoor()
    if not isAuthorizedOnDuty() then
        notify("You must be ON duty to lock or unlock cell doors!")
        return
    end

    local doorsList = (Config and (Config.LockedDoors or Config.Doors)) or {}
    if #doorsList == 0 then
        notify("No cell doors configured!")
        return
    end

    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local closestHash = nil
    local closestDist = 3.5

    -- 1. Direct coordinate proximity check
    for _, entry in ipairs(doorsList) do
        local doorHash = ToPrimitiveNumber(type(entry) == "table" and (entry.doorHash or entry.hash) or entry)
        if doorHash ~= 0 then
            local doorCoords = type(entry) == "table" and entry.coords
            if doorCoords then
                local dist = #(pedCoords - vector3(doorCoords.x, doorCoords.y, doorCoords.z))
                if dist <= closestDist then
                    closestDist = dist
                    closestHash = doorHash
                end
            end
        end
    end

    -- 2. Fallback scan object pool if not matched by coordinates
    if not closestHash then
        local objects = GetGamePool("CObject")
        for _, obj in ipairs(objects) do
            if DoesEntityExist(obj) then
                local objCoords = GetEntityCoords(obj)
                local dist = #(pedCoords - objCoords)
                if dist <= closestDist then
                    local modelHash = GetEntityModel(obj)
                    local doorHashPtr = Citizen.PointerValueIntInitialized(0)
                    local found = Citizen.InvokeNative(0x589F80B325CC82C5, objCoords.x, objCoords.y, objCoords.z, modelHash, doorHashPtr)
                    if found then
                        local doorHash = ToPrimitiveNumber(Citizen.PointerValueInt(doorHashPtr))
                        for _, entry in ipairs(doorsList) do
                            local configuredHash = ToPrimitiveNumber(type(entry) == "table" and (entry.doorHash or entry.hash) or entry)
                            if configuredHash == doorHash then
                                closestDist = dist
                                closestHash = doorHash
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    if closestHash then
        TriggerServerEvent("coi_police:server:toggleDoorLock", closestHash)
    else
        notify("No cell door nearby!")
    end
end

RegisterCommand("toggledoor", function()
    tryToggleClosestDoor()
end, false)

RegisterKeyMapping("toggledoor", "Lock or Unlock Cell Door", "keyboard", "K")

local function spawnSingleNPC(index, data)
    local pedHandle = nil
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

            pedHandle = ped
            SetModelAsNoLongerNeeded(modelHash)
        else
            print(("^1[coi_police] Error: Could not load model %s for NPC #%d^7"):format(tostring(data.ped), index))
        end
    else
        print(("^1[coi_police] Error: Invalid model %s for NPC #%d^7"):format(tostring(data.ped), index))
    end

    local blipHandle = nil
    if data.blip then
        local sprite = type(data.blip) == "number" and data.blip or GetHashKey(data.blip)
        local blipStyle = data.blipStyle or 1664425300
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, blipStyle, data.x, data.y, data.z)
        if blip and blip ~= 0 then
            SetBlipSprite(blip, sprite, true)
            local label = data.blipLabel or "Sheriff Office"
            local varString = CreateVarString(10, 'LITERAL_STRING', label)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, varString)
            blipHandle = blip
        end
    end

    return pedHandle, blipHandle
end

local function spawnPermanentNPCs()
    if not POLICE_NPCS or #POLICE_NPCS == 0 then return end
    for index, data in ipairs(POLICE_NPCS) do
        if not data.dutyOnly then
            local ped, blip = spawnSingleNPC(index, data)
            if ped then table.insert(spawnedPeds, ped) end
            if blip then table.insert(spawnedBlips, blip) end
        end
    end
end

local function spawnDutyOnlyNPCs()
    if not POLICE_NPCS or #POLICE_NPCS == 0 then return end
    if #spawnedDutyPeds > 0 or #spawnedDutyBlips > 0 then return end

    for index, data in ipairs(POLICE_NPCS) do
        if data.dutyOnly then
            local ped, blip = spawnSingleNPC(index, data)
            if ped then
                table.insert(spawnedDutyPeds, ped)
                table.insert(spawnedPeds, ped)
            end
            if blip then
                table.insert(spawnedDutyBlips, blip)
            end
        end
    end
end

local function removeDutyOnlyNPCs()
    for _, ped in ipairs(spawnedDutyPeds) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end
    spawnedDutyPeds = {}

    for _, blip in ipairs(spawnedDutyBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    spawnedDutyBlips = {}
end

updateDutyNPCs = function(onDuty)
    if onDuty and isAuthorizedOnDuty() then
        spawnDutyOnlyNPCs()
    else
        removeDutyOnlyNPCs()
    end
end

local function cleanup()
    removeDutyOnlyNPCs()
    clearDistressBlips()

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

    if reinforcementPromptHandle then
        PromptDelete(reinforcementPromptHandle)
        reinforcementPromptHandle = nil
    end

    if lastSpawnedReinforcement and DoesEntityExist(lastSpawnedReinforcement) then
        DeleteVehicle(lastSpawnedReinforcement)
        DeleteEntity(lastSpawnedReinforcement)
        lastSpawnedReinforcement = nil
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeTargetMenu" })
    SendNUIMessage({ action = "closeAlertPanel" })
    SendNUIMessage({ action = "hideCallAlert" })
    SendNUIMessage({ action = "closeSheriffDashboard" })
    SendNUIMessage({ action = "closeReinforcementMenu" })
    isAlertPanelOpen = false
    isDashboardOpen = false
    isReinforcementMenuOpen = false
    updateDutyUI(false)
end

-- MAIN INTERACTION THREAD FOR DUTY NPC & TARGET HANDCUFFING
CreateThread(function()
    spawnPermanentNPCs()
    if isPoliceOnDuty then
        spawnDutyOnlyNPCs()
    end
    TriggerServerEvent("coi_police:server:requestDoorStates")

    local groupTitle = CreateVarString(10, 'LITERAL_STRING', "Sheriff Office")
    local playerGroupTitle = CreateVarString(10, 'LITERAL_STRING', "Law Action")
    local npcInteractionDist = (Config and Config.InteractionDistance) or 3.5
    local cuffDist = (Config and Config.CuffDistance) or 5.0

    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()

        if not IsEntityDead(playerPed) then
            local playerCoords = GetEntityCoords(playerPed)

            -- 1. DUTY NPC INTERACTION
            if not hasPoliceJob() and isPoliceOnDuty then
                isPoliceOnDuty = false
                updateDutyUI(false)
            end

            if hasPoliceJob() and POLICE_NPCS and #POLICE_NPCS > 0 then
                for _, npcData in ipairs(POLICE_NPCS) do
                    if not npcData.dutyOnly or isPoliceOnDuty then
                        local dist = #(playerCoords - vector3(npcData.x, npcData.y, npcData.z))
                        if dist <= npcInteractionDist then
                            sleep = 0

                            if npcData.dutyOnly then
                                -- Reinforcement NPC: show K prompt
                                local reinforceTitle = CreateVarString(10, 'LITERAL_STRING', "Sheriff Reinforcement")
                                createReinforcementPrompt()
                                PromptSetActiveGroupThisFrame(reinforcementPromptGroup, reinforceTitle, 0, 0, 0, 0)
                                DrawText3D(npcData.x, npcData.y, npcData.z + 1.1, "Request Reinforcement")

                                if isReinforcementPromptPressed() then
                                    openReinforcementMenu()
                                    Wait(800)
                                end
                            else
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
                            end
                            break
                        end
                    end
                end
            end

            -- 2. ON-DUTY HANDCUFF & CARRY INTERACTION (PLAYERS & NPC PEDS)
            if isAuthorizedOnDuty() then
                if isCarrying then
                    sleep = 0
                    DrawText3D(playerCoords.x, playerCoords.y, playerCoords.z + 0.9, "[Hold R] Drop / Stop Carrying")
                else
                    local closestPed, closestDist, isPlayer, targetServerId = GetClosestTargetPed(cuffDist)
                    if closestPed ~= -1 and DoesEntityExist(closestPed) then
                        sleep = 0

                        local isTargetCuffed = false
                        if isPlayer and targetServerId then
                            isTargetCuffed = targetCuffStates[targetServerId] or false
                        else
                            isTargetCuffed = cuffedNPCs[closestPed] or false
                        end

                        if isTargetCuffed then
                            local targetCoords = GetEntityCoords(closestPed)
                            DrawText3D(targetCoords.x, targetCoords.y, targetCoords.z + 0.9, "[Hold R] Carry Suspect")
                        end

                        local cuffText = isTargetCuffed and "Uncuff Individual" or "Handcuff Individual"

                        createCuffPrompt(cuffText)
                        PromptSetActiveGroupThisFrame(cuffPromptGroup, playerGroupTitle, 0, 0, 0, 0)

                        if isCuffPromptPressed() then
                            tryOpenTargetMenu()
                            Wait(1000)
                        end
                    end
                end
            end

            -- 3. ON-DUTY CELL DOOR PROMPT
            if isAuthorizedOnDuty() then
                local doorsList = Config and (Config.LockedDoors or Config.Doors)
                if doorsList and #doorsList > 0 then
                    for _, entry in ipairs(doorsList) do
                        local doorHash = ToPrimitiveNumber(type(entry) == "table" and (entry.doorHash or entry.hash) or entry)
                        local doorCoords = type(entry) == "table" and entry.coords
                        if doorHash ~= 0 and doorCoords then
                            local dist = #(playerCoords - vector3(doorCoords.x, doorCoords.y, doorCoords.z))
                            if dist <= 2.5 then
                                sleep = 0
                                local isLocked = clientDoorStates[doorHash]
                                if isLocked == nil then isLocked = true end
                                local promptText = isLocked and "[K] Unlock Cell Door" or "[K] Lock Cell Door"
                                DrawText3D(doorCoords.x, doorCoords.y, doorCoords.z + 0.2, promptText)
                            end
                        end
                    end
                end
            end

            -- 4. ON-DUTY SHERIFF STASH / LOCKER PROMPT
            if isAuthorizedOnDuty() and Config and Config.SheriffStash then
                local stash = Config.SheriffStash
                local stashCoords = vector3(stash.coords.x, stash.coords.y, stash.coords.z)
                local dist = #(playerCoords - stashCoords)
                if dist <= 2.5 then
                    sleep = 0
                    DrawText3D(stashCoords.x, stashCoords.y, stashCoords.z + 0.3, "[G] Sheriff Locker")

                    local keyHash = stash.key or 0x760A9C6F
                    if IsControlJustPressed(0, keyHash) or IsDisabledControlJustPressed(0, keyHash) then
                        TriggerServerEvent("coi_police:server:openSheriffStash")
                        Wait(1000)
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

