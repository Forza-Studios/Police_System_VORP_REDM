local VORPcore = nil

local function DebugPrint(...)
    if Config and Config.Debug then
        print(...)
    end
end

Citizen.CreateThread(function()
    while VORPcore == nil do
        TriggerEvent("getCore", function(core) VORPcore = core end)
        if not VORPcore then
            pcall(function() VORPcore = exports.vorp_core:GetCore() end)
        end
        Citizen.Wait(200)
    end
    DebugPrint("^2[gw_policejob] Client: VORPcore Linked Successfully!^7")
end)

-- Shared States
local isMdtOpen = false
local onDuty = false
local isJailed = false
local isCuffed = false
local isPoliceMenuOpen = false
local isDutyMenuOpen = false
local isArmoryOpen = false
local isFineOpen = false
local currentOfficerName = ""
local currentJob = ""
local lastDutyToggle = 0 -- Added debounce timer to prevent double-click issues
local lastVehicle = 0 -- Shared state to track the last wagon for a cuffed suspect

-- [ Master Input Protection Thread (0ms) ] ---
Citizen.CreateThread(function()
    while true do
        if isMdtOpen or isPoliceMenuOpen or isDutyMenuOpen or isArmoryOpen or isFineOpen then
            -- 1. Aggressive Control Blocking (Fixed Perspective Logic)
            DisableAllControlActions(0) 

            Citizen.Wait(0)
        else
            Citizen.Wait(500)
        end
    end
end)

-- Diagnostic Bypass Command
RegisterCommand("testmdt", function()
    print("^3[gw_policejob] DIAGNOSTIC: Bypassing Job Checks. Opening MDT...^7")
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openMDT",
        isBoss = true,
        officerName = "DIAGNOSTIC UNIT",
        grade = "ADMIN",
        isDuty = true,
        serverId = GetPlayerServerId(PlayerId()),
        jails = Config.Jails or {}
    })
    isMdtOpen = true
end, false)

-- Open MDT Event
RegisterNetEvent("gw_policejob:client:openMDT")
AddEventHandler("gw_policejob:client:openMDT", function(isBoss, officerName, grade)
    DebugPrint("^2[gw_policejob] Client: Received openMDT request. Name: " .. tostring(officerName) .. "^7")
    
    local function isPolice(job)
        if not job then return false end
        local j = tostring(job):lower()
        return j:find("police") or j:find("sheriff")
    end

    local isDuty = isPolice(currentJob) and not tostring(currentJob or ""):find("off")
    
    DebugPrint("^3[gw_policejob] Client: MDT State -> Duty: " .. tostring(isDuty) .. " Job: " .. tostring(currentJob) .. "^7")
    
    local ped = PlayerPedId()
    DisplayHud(false) -- Hide HUD for immersion
    
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false) 
    isMdtOpen = true





    
    SendNUIMessage({ 
        action = "openMDT",
        isBoss = isBoss,
        officerName = officerName,
        grade = grade,
        isDuty = isDuty,
        serverId = GetPlayerServerId(PlayerId()),
        jails = Config.Jails,
        colors = Config.UIColors
    })
end)


-- Job Synchronization (VORP Core)
RegisterNetEvent("vorp:SelectedCharacter")
AddEventHandler("vorp:SelectedCharacter", function(char)
    currentJob = char.job
    DebugPrint("^2[gw_policejob] Client: Job Synchronized -> " .. tostring(currentJob) .. "^7")
end)

RegisterNetEvent("gw_policejob:client:setJob")
AddEventHandler("gw_policejob:client:setJob", function(job)
    currentJob = job
    DebugPrint("^2[gw_policejob] Client: Job Updated via Event -> " .. tostring(currentJob) .. "^7")
end)

-- NUI Callbacks
RegisterNUICallback("closeMDT", function(data, cb)
    isMdtOpen = false
    local ped = PlayerPedId()
    
    -- Safety Cleanup
    FreezeEntityPosition(ped, false)
    DisplayHud(true) 
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    cb('ok')
end)







RegisterNUICallback("closeMenu", function(data, cb)
    isPoliceMenuOpen = false
    isDutyMenuOpen = false
    isMdtOpen = false
    isArmoryOpen = false
    isFineOpen = false
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    -- Controls re-enable automatically when DisableAllControlActions stops being called
    cb('ok')
end)

RegisterNUICallback("closeArmoryCallback", function(data, cb)
    isArmoryOpen = false
    isFineOpen = false
    isPoliceMenuOpen = false
    isDutyMenuOpen = false
    isMdtOpen = false
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    -- Controls re-enable automatically when DisableAllControlActions stops being called
    cb('ok')
end)

RegisterNUICallback("focusMenu", function(data, cb)
    if data.state then
        -- Mode: Typing/Mouse Interaction
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false) -- STRICT: Game will NOT see the keyboard, fixing Backspace hanging!
        isFineOpen = true
    else
        -- Mode: Return to Interaction Menu (Arrows only) or Close
        if isPoliceMenuOpen then
            SetNuiFocus(true, false)
            SetNuiFocusKeepInput(true)
        else
            isPoliceMenuOpen = false
            isDutyMenuOpen = false
            isMdtOpen = false
            isArmoryOpen = false
            isFineOpen = false
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            local ped = PlayerPedId()
            FreezeEntityPosition(ped, false) -- UNFREEZE on final exit
            -- Controls re-enable automatically when DisableAllControlActions stops being called
        end
        isFineOpen = false
    end

    cb('ok')
end)


RegisterNUICallback("updatePhoto", function(data, cb)
    TriggerServerEvent("gw_policejob:server:updatePhoto", data.charid, data.url)
    cb('ok')
end)

RegisterNUICallback("searchPlayer", function(data, cb)
    TriggerServerEvent("gw_policejob:server:searchPlayer", data.query)
    cb('ok')
end)

-- --- NUI Data Bridge (Fixing Search & Data Hangs) ---
RegisterNetEvent("gw_policejob:client:receiveSearchResults")
AddEventHandler("gw_policejob:client:receiveSearchResults", function(results)
    SendNUIMessage({
        action = "searchResults",
        results = results
    })
end)

RegisterNetEvent("gw_policejob:client:receiveRecords")
AddEventHandler("gw_policejob:client:receiveRecords", function(records)
    SendNUIMessage({
        action = "recordsResults",
        records = records
    })
end)

RegisterNetEvent("gw_policejob:client:receiveWarrants")
AddEventHandler("gw_policejob:client:receiveWarrants", function(warrants)
    SendNUIMessage({
        action = "warrantsResults",
        warrants = warrants
    })
end)

RegisterNetEvent("gw_policejob:client:sendToNUI")
AddEventHandler("gw_policejob:client:sendToNUI", function(data)
    if data and data.action == "openArmory" then
        isArmoryOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        FreezeEntityPosition(PlayerPedId(), true)
    end
    SendNUIMessage(data)
end)
-- --------------------------------------------

RegisterNUICallback("getRecords", function(data, cb)
    TriggerServerEvent("gw_policejob:server:getRecords", data.charidentifier)
    cb('ok')
end)

RegisterNetEvent("gw_policejob:client:giveStandardKit")
AddEventHandler("gw_policejob:client:giveStandardKit", function()
    local ped = PlayerPedId()
    
    local kitWeapons = {
        { name = "WEAPON_LASSO", ammo = 1 },
        { name = "WEAPON_REVOLVER_SCHOFIELD", ammo = 200 },
        { name = "WEAPON_REVOLVER_CATTLEMAN", ammo = 200 },
        { name = "WEAPON_SNIPERRIFLE_CARCANO", ammo = 200 },
        { name = "WEAPON_SHOTGUN_SEMIAUTO", ammo = 100 }
    }
    
    for _, w in ipairs(kitWeapons) do
        local wHash = GetHashKey(w.name)
        GiveWeaponToPed(ped, wHash, w.ammo, true, true)
        SetAmmoInClip(ped, wHash, 6)
        AddAmmoToPed(ped, wHash, w.ammo)
    end

    -- Explicitly max out express & special ammo types for RedM ped
    local specialAmmo = {
        "AMMO_REVOLVER",
        "AMMO_REVOLVER_EXPRESS",
        "AMMO_REVOLVER_HIGH_VELOCITY",
        "AMMO_RIFLE",
        "AMMO_RIFLE_EXPRESS",
        "AMMO_RIFLE_HIGH_VELOCITY",
        "AMMO_SHOTGUN",
        "AMMO_SHOTGUN_SLUG"
    }

    for _, ammoName in ipairs(specialAmmo) do
        local aHash = GetHashKey(ammoName)
        pcall(function() SetPedAmmoByType(ped, aHash, 200) end)
        pcall(function() Citizen.InvokeNative(0x14E56BC5B5DBA471, ped, aHash, 200) end)
    end

    TaskStartScenarioInPlace(ped, GetHashKey("WORLD_HUMAN_INSPECT"), 1500, true, false, false, false)
    Citizen.CreateThread(function()
        Citizen.Wait(1500)
        ClearPedTasks(ped)
    end)

    TriggerEvent("gw_policejob:client:notify", _U('notify_kit_received'), "success", 5000)
end)

RegisterNUICallback("giveFine", function(data, cb)
    local targetId = tonumber(data.targetId)
    local reason = data.reason or _U('notify_general_infraction')
    local amount = tonumber(data.amount)

    if not targetId or targetId <= 0 then
        -- Find closest player
        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)
        local closestPlayer, closestDistance = VORPcore.getClosestPlayer()
        
        if closestPlayer ~= -1 and closestDistance <= 4.0 then
            targetId = GetPlayerServerId(closestPlayer)
        else
            TriggerEvent("gw_policejob:client:notify", _U('notify_no_nearby_player'), "error")
            cb('ok')
            return
        end
    end

    if targetId and amount and amount > 0 then
        TriggerServerEvent("gw_policejob:server:giveFine", targetId, amount, reason)
    end
    cb('ok')
end)

RegisterNUICallback("addRecord", function(data, cb)
    print("^3[gw_policejob] --- NUI CALLBACK: addRecord ---^7")
    print("^3[gw_policejob] ID: " .. tostring(data.charidentifier) .. " Time: " .. tostring(data.jail_time) .. "^7")
    
    TriggerServerEvent("gw_policejob:server:addRecord", data)
    cb('ok')
end)

RegisterNUICallback("quickJail", function(data, cb)
    print("^3[gw_policejob] --- NUI QUICK JAIL ---^7 Target SID: " .. tostring(data.targetId) .. " Time: " .. tostring(data.jailTime) .. "^7")
    TriggerServerEvent("gw_policejob:server:quickJail", data.targetId, data.jailTime)
    cb('ok')
end)

RegisterNUICallback("getWarrants", function(data, cb)
    TriggerServerEvent("gw_policejob:server:getWarrants")
    cb('ok')
end)

RegisterNUICallback("addWarrant", function(data, cb)
    TriggerServerEvent("gw_policejob:server:addWarrant", data)
    cb('ok')
end)

RegisterNUICallback("deleteWarrant", function(data, cb)
    TriggerServerEvent("gw_policejob:server:deleteWarrant", data.id)
    cb('ok')
end)

RegisterNUICallback("manageRank", function(data, cb)
    -- Unified bridge: Pass all data (charid, action, currentGrade, targetSrc, etc.) to server
    TriggerServerEvent("gw_policejob:server:manageRank", data)
    cb('ok')
end)

-- Removed redundant/broken actionFine callback as NUI uses giveFine

RegisterNUICallback("getJailedPlayers", function(data, cb)
    TriggerServerEvent("gw_policejob:server:getJailedPlayers")
    cb('ok')
end)

RegisterNUICallback("unjailPlayer", function(data, cb)
    TriggerServerEvent("gw_policejob:server:adminUnjail", data.charid)
    cb('ok')
end)

RegisterNUICallback("spawnVehicle", function(data, cb)
    TriggerServerEvent("gw_policejob:server:spawnVehicle", data.model)
    cb('ok')
end)



RegisterNetEvent("gw_policejob:client:spawnVehicle")
AddEventHandler("gw_policejob:client:spawnVehicle", function(modelHash)
    local model = GetHashKey(modelHash)
    
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) and t < 100 do Citizen.Wait(100) t = t + 1 end
    
    if not HasModelLoaded(model) then
        TriggerEvent("gw_policejob:client:notify", _U('notify_veh_model_failed'), "error", 4000)
        return
    end

    -- موقع الظهور من الكونفق
    local spawnPos     = Config.Vehicles.vehicleSpawnPos
    local spawnHeading = Config.Vehicles.vehicleSpawnHeading or 180.0

    -- RedM environment may not expose ClearAreaOfVehicles.
    -- Keep it safe: just wait a bit and rely on spawn retries below if needed.
    Citizen.Wait(200)
    
    local vehicle = CreateVehicle(model, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, false)
    
    if DoesEntityExist(vehicle) then
        Citizen.InvokeNative(0x06FA3003, vehicle) -- SetVehicleOnGroundProperly
        SetEntityAsMissionEntity(vehicle, true, true)
        TriggerEvent("gw_policejob:client:notify", _U('notify_veh_spawned'), "success", 5000)
        print("^2[gw_policejob] Vehicle '" .. modelHash .. "' spawned at " .. tostring(spawnPos) .. "^7")
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_veh_create_failed'), "error", 5000)
        print("^1[gw_policejob] ERROR: CreateVehicle failed for: " .. modelHash .. "^7")
    end
    
    SetModelAsNoLongerNeeded(model)
end)

RegisterNetEvent("gw_policejob:client:forceWeaponAmmo")
AddEventHandler("gw_policejob:client:forceWeaponAmmo", function(weaponHash, ammoCount)
    local ped = PlayerPedId()
    local hash = GetHashKey(weaponHash)
    
    Citizen.CreateThread(function()
        local timeout = 0
        while not HasPedGotWeapon(ped, hash, false) and timeout < 100 do
            Citizen.Wait(100)
            timeout = timeout + 1
        end
        
        if HasPedGotWeapon(ped, hash, false) then
            print("^2[gw_policejob] Forcing Ammo for " .. weaponHash .. ": " .. ammoCount .. "^7")
            AddAmmoToPed(ped, hash, tonumber(ammoCount) or 100)
            -- Also set in clip if it's a revolver/repeater to be sure
            SetAmmoInClip(ped, hash, 6) 
        end
    end)
end)

RegisterNetEvent("gw_policejob:client:manualReload")
AddEventHandler("gw_policejob:client:manualReload", function(ammoId, count, allowedWeapons)
    local ped = PlayerPedId()
    local _, currentWeapon = GetCurrentPedWeapon(ped, true)
    
    if currentWeapon == GetHashKey("WEAPON_UNARMED") then
        TriggerEvent("gw_policejob:client:notify", _U('notify_hold_weapon'), "error", 4000)
        return
    end

    local isAllowed = false
    for _, wName in ipairs(allowedWeapons) do
        if currentWeapon == GetHashKey(wName) then
            isAllowed = true
            break
        end
    end
    
    if isAllowed then
        DebugPrint("^2[gw_policejob] Manual Reload: " .. ammoId .. " for weapon hash " .. currentWeapon .. "^7")
        local ammoCount = tonumber(count) or 100
        AddAmmoToPed(ped, currentWeapon, ammoCount)
        
        local ammoHash = GetHashKey(ammoId)
        pcall(function() SetPedAmmoByType(ped, ammoHash, ammoCount) end)
        pcall(function() Citizen.InvokeNative(0x14E56BC5B5DBA471, ped, ammoHash, ammoCount) end)
        
        -- Special handling for clip sizes
        local clipSize = 6
        if tostring(ammoId):lower():find("shotgun") then clipSize = 5 end
        if tostring(ammoId):lower():find("rifle") then clipSize = 5 end
        
        SetAmmoInClip(ped, currentWeapon, clipSize)
        
        -- Immersion: Play a sound
        PlaySoundFrontend("RELOAD_REVOLVER", "RDRO_Character_Sounds", true, 0)
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_wrong_ammo'), "error", 4000)
    end
end)

RegisterNUICallback("getBossOfficers", function(data, cb)
    TriggerServerEvent("gw_policejob:server:getBossOfficers")
    cb('ok')
end)

RegisterNetEvent("gw_policejob:client:forceUnjail")
AddEventHandler("gw_policejob:client:forceUnjail", function()
    print("^2[gw_policejob] Admin: Forced Unjail Triggered^7")
    isJailed = false
    isCuffed = false
    ApplyCuff(PlayerPedId(), false)
    
    -- Cleanup NUI
    SendNUIMessage({ action = "toggleJailTimer", display = false })
end)



RegisterNetEvent("gw_policejob:client:stripWeapons")
AddEventHandler("gw_policejob:client:stripWeapons", function()
    local ped = PlayerPedId()
    
    local serviceWeapons = {
        "WEAPON_LASSO",
        "WEAPON_REVOLVER_SCHOFIELD",
        "WEAPON_REVOLVER_CATTLEMAN",
        "WEAPON_SNIPERRIFLE_CARCANO",
        "WEAPON_SHOTGUN_SEMIAUTO"
    }

    for _, wName in ipairs(serviceWeapons) do
        local hash = GetHashKey(wName)
        RemoveWeaponFromPed(ped, hash)
    end
    
    -- Clear current weapon to be sure
    SetCurrentPedWeapon(ped, GetHashKey("WEAPON_UNARMED"), true)
    
    DebugPrint("^1[gw_policejob] Client: SERVICE WEAPONS STRIPPED^7")
    TriggerEvent("gw_policejob:client:notify", _U('notify_weapons_stripped'), "error", 4000)
end)

RegisterNUICallback("mdtMessage", function(data, cb)
    TriggerServerEvent("gw_policejob:server:sendMessage", data.targetId, data.message)
    cb('ok')
end)

RegisterNUICallback("getLocales", function(data, cb)
    DebugPrint("^3[gw_policejob] NUI CALLBACK: getLocales^7")
    if not _G.Locales then 
        DebugPrint("^1[gw_policejob] Locales not initialized!^7")
        cb({ lang = "ar", dict = {} }) 
        return 
    end
    local lang = Config.Language or "ar"
    local dict = _G.Locales[lang] or _G.Locales["ar"]
    cb({ lang = lang, dict = dict })
end)

RegisterNUICallback("sendMessage", function(data, cb)
    TriggerServerEvent("gw_policejob:server:sendMessage", data.targetId, data.message)
    cb('ok')
end)

RegisterNUICallback("claimStandardKit", function(data, cb)
    DebugPrint("^3[gw_policejob] NUI CALLBACK: claimStandardKit Triggered^7")
    TriggerServerEvent("gw_policejob:server:claimStandardKit")
    cb('ok')
end)

RegisterNUICallback("closeArmoryCallback", function(data, cb)
    isArmoryOpen = false
    FreezeEntityPosition(PlayerPedId(), false) -- إلغاء تجميد اللاعب
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    cb('ok')
end)

local lastPanic = 0
RegisterNUICallback("panicButton", function(data, cb)
    local curTime = GetGameTimer()
    if curTime - lastPanic < 120000 then
        local wait = math.ceil((120000 - (curTime - lastPanic)) / 1000)
        TriggerEvent("gw_policejob:client:notify", _U('notify_panic_cooldown', wait), "error", 5000)
        cb('ok')
        return
    end

    lastPanic = curTime
    DebugPrint("^3[gw_policejob] Panic Button Triggered from MDT^7")
    local coords = GetEntityCoords(PlayerPedId())
    -- Local feedback sound immediately
    PlaySoundFrontend("BASE_REWARD_SOUNDS", "GOLDFINGER_SOUNDSET", true, 0)
    TriggerServerEvent("gw_policejob:server:panicButton", coords)
    TriggerEvent("gw_policejob:client:notify", _U('notify_panic_sent_global'), "success", 5000)
    cb('ok')
end)

RegisterNUICallback("spawnHeavyVehicle", function(data, cb)
    local modelName = tostring(data.model)
    DebugPrint("^3[gw_policejob] Requesting vehicle: " .. modelName .. "^7")
    cb('ok')

    Citizen.CreateThread(function()
        local model = GetHashKey(modelName)
        
        RequestModel(model)
        local t = 0
        while not HasModelLoaded(model) and t < 200 do
            Citizen.Wait(100)
            t = t + 1
        end
        
        if not HasModelLoaded(model) then
            TriggerEvent("gw_policejob:client:notify", _U('notify_veh_model_invalid', modelName), "error", 5000)
            DebugPrint("^1[gw_policejob] MODEL NOT FOUND: " .. modelName .. " | Hash: " .. model .. "^7")
            return
        end

        local sp = Config.Vehicles.vehicleSpawnPos
        local sh = Config.Vehicles.vehicleSpawnHeading or 180.0

        -- Create networked vehicle (robust + persistent)
        -- Some environments don't expose ClearAreaOfVehicles; to avoid collisions we try nearby offsets.
        local spawnOffsets = {
            { 0.0,  0.0, 0.0 },
            { 2.0,  0.0, 0.0 },
            { -2.0, 0.0, 0.0 },
            { 0.0,  2.0, 0.0 },
            { 0.0, -2.0, 0.0 },
            { 4.0,  0.0, 0.0 },
            { -4.0, 0.0, 0.0 },
        }

        local spawned = false
        local vehicle = 0

        for _, off in ipairs(spawnOffsets) do
            local tryX = sp.x + off[1]
            local tryY = sp.y + off[2]
            local tryZ = sp.z + off[3]

            Citizen.Wait(150)
            vehicle = CreateVehicle(model, tryX, tryY, tryZ, sh, true, true, false, false)

            local existCheck = 0
            while not DoesEntityExist(vehicle) and existCheck < 25 do
                Citizen.Wait(20)
                existCheck = existCheck + 1
            end

            if DoesEntityExist(vehicle) and vehicle ~= 0 then
                Citizen.InvokeNative(0x06FA3003, vehicle) -- SetVehicleOnGroundProperly
                Citizen.InvokeNative(0x77FF8D35EEC6BBC4, vehicle, 1, 0) -- Mission persistence
                SetEntityAsMissionEntity(vehicle, true, true)
                SetEntityVisible(vehicle, true)

                local netId = NetworkGetNetworkIdFromEntity(vehicle)
                if netId and netId ~= 0 then
                    SetNetworkIdExistsOnAllMachines(netId, true)
                    spawnedPoliceVehicles[netId] = vehicle
                    DebugPrint("^2[gw_policejob] Strategic vehicle stored NetID=" .. tostring(netId) .. "^7")
                else
                    DebugPrint("^3[gw_policejob] Strategic vehicle created without valid NetID^7")
                end

                spawned = true
                break
            end
        end

        if spawned then
            TriggerEvent("gw_policejob:client:notify", _U('notify_veh_spawn_success'), "success", 5000)
            DebugPrint("^2[gw_policejob] Vehicle OK (strategic), model=" .. modelName .. " handle=" .. tostring(vehicle) .. "^7")
        else
            TriggerEvent("gw_policejob:client:notify", _U('notify_veh_spawn_failed'), "error", 5000)
            DebugPrint("^1[gw_policejob] CreateVehicle FAILED: model=" .. modelName .. " handle=" .. tostring(vehicle) .. "^7")
        end

        SetModelAsNoLongerNeeded(model)
    end)
end)

-- أمر تجريبي لاختبار أسماء الموديلز
RegisterCommand("testveh", function(src, args)
    local modelName = args[1] or "stagecoach"
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    DebugPrint("^3[gw_policejob] Testing model: " .. modelName .. "^7")

    Citizen.CreateThread(function()
        local model = GetHashKey(modelName)
        RequestModel(model)
        local t = 0
        while not HasModelLoaded(model) and t < 100 do Citizen.Wait(100) t = t + 1 end

        if not HasModelLoaded(model) then
            TriggerEvent("gw_policejob:client:notify", _U('notify_model_failed', modelName), "error", 4000)
            DebugPrint("^1[TESTVEH] Model NOT loaded: " .. modelName .. "^7")
            return
        end

        local v = CreateVehicle(model, pos.x + 3, pos.y, pos.z, 0.0, true, false, false)
        Citizen.Wait(300)

        if DoesEntityExist(v) and v ~= 0 then
            Citizen.InvokeNative(0x06FA3003, v)
            TriggerEvent("gw_policejob:client:notify", _U('notify_model_success', modelName), "success", 4000)
            DebugPrint("^2[TESTVEH] SUCCESS: " .. modelName .. " handle=" .. v .. "^7")
        else
            TriggerEvent("gw_policejob:client:notify", _U('notify_veh_spawn_failed'), "error", 4000)
            DebugPrint("^1[TESTVEH] FAILED: " .. modelName .. "^7")
        end
        SetModelAsNoLongerNeeded(model)
    end)
end, false)

-- [ End of NUI Callback Section (Unified) ]


-- Panic Button Alert (Danger Zone Implementation)
RegisterNetEvent("gw_policejob:client:panicAlert")
AddEventHandler("gw_policejob:client:panicAlert", function(coords, name)
    DebugPrint("^3[gw_policejob] Panic Alert Received from: " .. tostring(name) .. "^7")
    TriggerEvent("gw_policejob:client:notify", _U('notify_panic_received', name), "error", 10000)
    
    -- Sound Alert (Custom Mp3 via NUI)
    SendNUIMessage({ action = "playSound" })
    
    -- Quick Backend backup sound
    PlaySoundFrontend("BASE_REWARD_SOUNDS", "GOLDFINGER_SOUNDSET", true, 0)
    
    -- 1. Create a large visible Blip for all Cops (Using explicit Sheriff Star)
    -- AddBlipForCoord: 0x554D9D53F696D002
    local panicBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)
    Citizen.InvokeNative(0x74F74D3207ED525C, panicBlip, 1997361198, true) 
    Citizen.InvokeNative(0xD38744167B2FA257, panicBlip, 2.5) -- HUGE
    Citizen.InvokeNative(0x662D364ABF11DA25, panicBlip, GetHashKey("BLIP_STYLE_DEBUG_RED")) -- User's Red Color Hash
    Citizen.InvokeNative(0x9CB1A1623062F402, panicBlip, _U('blip_panic', name))

    -- 2. Native RDR3 Blip Radius (Territory Circle as provided in your working snippet)
    -- Using the exact native 0x45F13B7E0A15C880 and hash -1282792512 you sent!
    local territoryRadius = Citizen.InvokeNative(0x45F13B7E0A15C880, -1282792512, coords.x, coords.y, coords.z, 40.0)
    
    -- Color the radius using standard safe string hash translation
    if territoryRadius ~= 0 then
        Citizen.InvokeNative(0x662D364ABF11DA25, territoryRadius, GetHashKey("BLIP_STYLE_DEBUG_RED"))
    end

    -- Cleanup after 60 Seconds
    Citizen.CreateThread(function()
        Citizen.Wait(60000)
        
        if panicBlip and panicBlip ~= 0 then RemoveBlip(panicBlip) end
        if territoryRadius and territoryRadius ~= 0 then RemoveBlip(territoryRadius) end
    end)
end)

-- Prison System
local jailZone = vector3(-277.89, 804.81, 119.38) -- Valentine jail coords

RegisterNetEvent("gw_policejob:client:jailPlayer")
AddEventHandler("gw_policejob:client:jailPlayer", function(time, location)
    local ped = PlayerPedId()
    local timeMin = tonumber(time) or 0
    if timeMin <= 0 then return end

    DebugPrint("^3[gw_policejob] Jail Sequence Started: " .. timeMin .. " min at " .. tostring(location) .. "^7")
    
    local targetCoords = vector3(-272.59, 807.21, 119.37) -- Default Valentine cell
    local releasePos = vector3(-184.45, 626.04, 114.12) -- Default Valentine release
    
    function isPolice(job)
        if not job then return false end
        local j = tostring(job):lower()
        return j:find("police") or j:find("sheriff")
    end

    if Config.Jails then
        for _, jail in ipairs(Config.Jails) do
            if jail.value == location then
                targetCoords = jail.coords
                releasePos = jail.releaseCoords or releasePos
                break
            end
        end
    end

    jailZone = targetCoords
    isJailed = true
    
    DoScreenFadeOut(500)
    Citizen.Wait(600) -- Simple wait instead of blocking while
    
    -- Safety: Freeze and Invincible during teleport
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    
    -- Pre-load collision
    RequestCollisionAtCoord(jailZone.x, jailZone.y, jailZone.z)
    local timeout = 0
    while not HasCollisionLoadedAroundEntity(ped) and timeout < 50 do
        Citizen.Wait(10)
        timeout = timeout + 1
    end
    
    SetEntityCoords(ped, jailZone.x, jailZone.y, jailZone.z)
    Citizen.Wait(800) -- Give it time to settle
    
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    
    -- Apply Handcuffs (Teleport can break anims)
    isCuffed = true
    ApplyCuff(ped, true)
    
    DoScreenFadeIn(1000)
    print("^2[gw_policejob] Jail Sequence Completed Successfully.^7")
    TriggerEvent("gw_policejob:client:notify", _U('notify_jailed_time', timeMin), "error", 5000)

    -- ESCAPE & CUFF PROTECTION LOOP
    Citizen.CreateThread(function()
        local lastCuffCheck = 0
        while isJailed do
            Citizen.Wait(2000)
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            
            -- Escape check
            if #(pCoords - jailZone) > 20.0 then
                SetEntityCoords(ped, jailZone.x, jailZone.y, jailZone.z)
                TriggerEvent("gw_policejob:client:notify", _U('notify_escape_failed'), "error", 3000)
            end

            -- Cuff persistence check (re-apply every 10s if anim cleared)
            if GetGameTimer() - lastCuffCheck > 10000 then
                lastCuffCheck = GetGameTimer()
                if not IsEntityPlayingAnim(ped, "mp_amb_rest_handcuffed@loop", "handcuffed_loop_male", 3) then
                    ApplyCuff(ped, true)
                end
            end
        end
    end)

    -- TIMER & RELEASE LOOP
    local charName = _U('ui_prisoner_unknown')
    local Character = nil
    
    if VORPcore and VORPcore.instance then
        local Character = (type(VORPcore.instance.GetUsedCharacter) == 'function') and VORPcore.instance.GetUsedCharacter() or VORPcore.instance.GetUsedCharacter
    end

    if Character and Character.firstname then
        charName = Character.firstname .. " " .. Character.lastname
    else
        charName = _U('ui_prisoner_number', GetPlayerServerId(PlayerId()))
    end
    
    Citizen.CreateThread(function()
        Citizen.Wait(2000) -- Small delay to ensure NUI is fully ready
        
        local lengthMs = timeMin * 60000
        local endTime = GetGameTimer() + lengthMs
        local lastSync = GetGameTimer()
        
        -- Show Timer UI (ALWAYS CALL THIS)
        DebugPrint("^2[gw_policejob] Showing Jail Timer for: " .. charName .. "^7")
        SendNUIMessage({ 
            action = "toggleJailTimer", 
            display = true, 
            name = charName 
        })

        while isJailed do
            Citizen.Wait(1000) -- Update every second
            local now = GetGameTimer()
            local totalSecondsLeft = math.floor((endTime - now) / 1000)
            
            if totalSecondsLeft <= 0 then break end

            local mins = math.floor(totalSecondsLeft / 60)
            local secs = totalSecondsLeft % 60
            
            -- Update NUI
            SendNUIMessage({
                action = "updateJailTimer",
                minutes = mins,
                seconds = secs
            })

            -- Sync with server every 60s
            if (now - lastSync) >= 60000 then
                lastSync = now
                TriggerServerEvent("gw_policejob:server:updateJailTime", math.ceil(totalSecondsLeft / 60))
            end
        end
        
        -- RELEASE
        SendNUIMessage({ action = "toggleJailTimer", display = false })
        
        isJailed = false
        isCuffed = false
        DebugPrint("^2[gw_policejob] Sentence Finished: Releasing Player...^7")
        TriggerServerEvent("gw_policejob:server:updateJailTime", 0)
        
        DoScreenFadeOut(500)
        Citizen.Wait(1000)
        
        local relPed = PlayerPedId()
        SetEntityCoords(relPed, releasePos.x, releasePos.y, releasePos.z)
        Citizen.Wait(500)
        
        -- فك الكلبشة بشكل كامل بعد الانتقال
        isCuffed = false
        SetEnableHandcuffs(relPed, false, false)
        SetPedConfigFlag(relPed, 137, false)
        ClearPedTasks(relPed)
        ClearPedTasksImmediately(relPed)
        SetCurrentPedWeapon(relPed, GetHashKey("WEAPON_UNARMED"), true)
        
        -- تمكين جميع التحكمات من جديد
        EnableControlAction(0, 0x8FFC75D1, true)
        EnableControlAction(0, 0xD4A1F184, true)
        EnableControlAction(0, 0x8CC57157, true)
        EnableControlAction(0, 0x07CEABE4, true)
        EnableControlAction(0, 0xF84FA74F, true)
        EnableControlAction(0, 0xCEE124C2, true)
        EnableControlAction(0, 0x580C44CA, true)
        
        DoScreenFadeIn(1000)
        DebugPrint("^2[gw_policejob] Player Released & Uncuffed Successfully.^7")
        TriggerEvent("gw_policejob:client:notify", _U('notify_sentence_finished'), "success", 5000)
    end)
end)


-- Police Interaction Menu (Hotkey Z: 0x26E9DC00)
-- Police Interaction Menu (Hotkey Z: 0x26E9DC00)
RegisterCommand("gw_policemenu", function()
    if not currentJob then return end
    TriggerServerEvent("gw_policejob:server:requestPoliceMenu")
end, false)

local isPoliceMenuOpen = false

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        -- Native Z Key (Standard RedM Control)
        if IsControlJustPressed(0, 0x26E9DC00) then
            local function isPoliceOnDuty(job)
                if not job then return false end
                local j = tostring(job):lower()
                if j:find("off") then return false end
                return j:find("police") or j:find("sheriff")
            end
            
            if isPoliceOnDuty(currentJob) then
                DebugPrint("^3[gw_policejob] Z Pressed - Requesting Police Menu from Server...^7")
                TriggerServerEvent("gw_policejob:server:requestPoliceMenu")
            else
                -- Optional: Notify or just ignore
            end
        end
    end
end)

RegisterNetEvent("gw_policejob:client:openPoliceMenu")
AddEventHandler("gw_policejob:client:openPoliceMenu", function()
    isPoliceMenuOpen = not isPoliceMenuOpen
    if isPoliceMenuOpen then
        SetNuiFocus(true, false) -- Keyboard focus only
        SetNuiFocusKeepInput(true) -- السماح برصد الأزرار مع التعطيل بواسطة Master Thread

        SendNUIMessage({ action = "openPoliceMenu" })
        
        -- Individual Button Detection Thread
        Citizen.CreateThread(function()
            while isPoliceMenuOpen do
                 Citizen.Wait(0)
                 
                 -- ONLY process these if we are NOT in a sub-menu that requires typing (like the Fine menu)
                 if not isFineOpen then
                    -- نستخدم IsDisabledControl لأن Master Thread يقوم بتعطيل كل شيء
                    if IsDisabledControlJustPressed(0, 0x6319DB71) then -- UP
                        SendNUIMessage({ action = "menuUp" })
                    elseif IsDisabledControlJustPressed(0, 0x05CA7C52) then -- DOWN
                        SendNUIMessage({ action = "menuDown" })
                    elseif IsDisabledControlJustPressed(0, 0xC7B5340A) then -- ENTER
                        SendNUIMessage({ action = "menuEnter" })
                    elseif IsDisabledControlJustPressed(0, 0x156F7119) then -- ESC ONLY for keyboard close
                        isPoliceMenuOpen = false
                        FreezeEntityPosition(PlayerPedId(), false)
                        SetNuiFocus(false, false)
                        SetNuiFocusKeepInput(false)
                        SendNUIMessage({ action = "closePoliceMenu" })
                    end
                 end
            end
        end)

    else
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ action = "closePoliceMenu" })
    end

end)

-- [ Callbacks consolidated above ]


function getClosestPlayer()
    local players = GetActivePlayers()
    local closestDistance = -1
    local closestPlayer = -1
    local ply = PlayerPedId()
    local plyCoords = GetEntityCoords(ply)
    
    DebugPrint("^3[gw_policejob] Proximity Scan: Checking " .. #players .. " active players...^7")

    for _, player in ipairs(players) do
        local target = GetPlayerPed(player)
        if target ~= ply then
            local targetCoords = GetEntityCoords(target)
            local distance = #(targetCoords - plyCoords)
            
            -- Debug every player found for the officer
            DebugPrint("^3[gw_policejob] Found Player [" .. GetPlayerServerId(player) .. "] at dist: " .. string.format("%.2f", distance) .. "m^7")

            if closestDistance == -1 or closestDistance > distance then
                closestPlayer = player
                closestDistance = distance
            end
        end
    end
    
    if closestDistance ~= -1 and closestDistance <= 5.0 then -- Slightly more generous
        DebugPrint("^2[gw_policejob] Target SELECTED: ID " .. GetPlayerServerId(closestPlayer) .. " at dist " .. closestDistance .. "^7")
        return closestPlayer, GetPlayerServerId(closestPlayer)
    else
        DebugPrint("^1[gw_policejob] Fail: No player found within 5.0m range.^7")
        return nil, nil
    end
end

-- Diagnostic Tools
RegisterCommand("cufftest", function()
    DebugPrint("^3[gw_policejob] Testing Local Cuff Animation...^7")
    TriggerEvent("gw_policejob:client:toggleCuff")
end, false)

RegisterCommand("debugdist", function()
    local loop = true
    DebugPrint("^3[gw_policejob] Starting Distance Debugger (Type ESC to stop or wait 10s)^7")
    Citizen.CreateThread(function()
        local startTime = GetGameTimer()
        while loop and GetGameTimer() - startTime < 10000 do
            local _, tid = getClosestPlayer()
            Citizen.Wait(1000)
        end
        DebugPrint("^3[gw_policejob] Distance Debugger Stopped.^7")
    end)
end, false)

-- Direct Client Command for Admin/Officer
RegisterCommand("cuff", function(source, args)
    local target = tonumber(args[1])
    if target then
        DebugPrint("^3[gw_policejob] Client Command Cuff: Requesting ID " .. target .. "^7")
        TriggerServerEvent("gw_policejob:server:requestCuffTarget", target)
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_id_required'), "error", 3000)
    end
end, false)

-- Redundant Global Pulse Listener (Explicit State)
local lastCuffPulse = 0
RegisterNetEvent("gw_policejob:client:globalPulseCuff")
AddEventHandler("gw_policejob:client:globalPulseCuff", function(targetId, state)
    local myId = GetPlayerServerId(PlayerId())
    local now = GetGameTimer()
    
    if tonumber(targetId) == tonumber(myId) then
        if now - lastCuffPulse > 1500 then
            lastCuffPulse = now
            print("^2[gw_policejob] BACKUP SIGNAL Received: Setting state " .. tostring(state) .. "^7")
            TriggerEvent("gw_policejob:client:setCuffState", state)
        end
    end
end)

RegisterNUICallback("actionCuff", function(data, cb)
    print("^3[gw_policejob] NUI CALLBACK: actionCuff Clicked^7")
    local closestPlayer, targetId = getClosestPlayer()
    
    if closestPlayer and targetId then
        -- Play Cop Anim Locally
        local ped = PlayerPedId()
        
        -- Use Scenario instead of dict
        TaskStartScenarioInPlace(ped, GetHashKey("WORLD_HUMAN_INSPECT"), -1, true, false, false, false)
        
        Citizen.Wait(2500)
        ClearPedTasks(ped)
        print("^2[gw_policejob] Requesting Server to CUFF ID: " .. targetId .. "^7")
        TriggerServerEvent("gw_policejob:server:setCuffed", targetId, true)
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "closePoliceMenu" })
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_no_nearby_id'), "error", 3000)
    end
    cb('ok')
end)

RegisterNUICallback("actionUncuff", function(data, cb)
    print("^3[gw_policejob] NUI CALLBACK: actionUncuff Clicked^7")
    local closestPlayer, targetId = getClosestPlayer()
    
    if closestPlayer and targetId then
        print("^2[gw_policejob] Requesting Server to UNCUFF ID: " .. targetId .. "^7")
        TriggerServerEvent("gw_policejob:server:setCuffed", targetId, false)
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "closePoliceMenu" })
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_no_nearby_uncuff'), "error", 3000)
    end
    cb('ok')
end)

RegisterNUICallback("actionEscort", function(data, cb)
    local _, targetId = getClosestPlayer()
    if targetId then
        TriggerServerEvent("gw_policejob:server:escortPlayer", targetId)
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_no_nearby_generic'), "error", 3000)
    end
    cb('ok')
end)

RegisterNUICallback("actionCheckWanted", function(data, cb)
    local _, targetId = getClosestPlayer()
    if targetId then
        TriggerServerEvent("gw_policejob:server:checkWanted", targetId)
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_no_nearby_generic'), "error", 3000)
    end
    cb('ok')
end)

RegisterNUICallback("actionFine", function(data, cb)
    local targetId
    if data.targetId and tonumber(data.targetId) then
        targetId = tonumber(data.targetId)
    else
        local _, clId = getClosestPlayer()
        targetId = clId
    end

    if targetId then
        TriggerServerEvent("gw_policejob:server:finePlayer", targetId, data.amount, data.reason)
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_id_or_nearby_required'), "error", 3000)
    end
    cb('ok')
end)

RegisterNUICallback("actionPutInVehicle", function(data, cb)
    print("^3[gw_policejob] NUI CALLBACK: actionPutInVehicle Clicked^7")
    local closestPlayer, targetId = getClosestPlayer()
    if closestPlayer and targetId then
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        
        -- Detection Range: Reduced to 6.0m for precision
        local vehicle = 0
        local vehicles = GetGamePool('CVehicle')
        local closestDist = 6.0
        
        for _, v in ipairs(vehicles) do
            local vPos = GetEntityCoords(v)
            local dist = #(pos - vPos)
            if dist < closestDist then
                closestDist = dist
                vehicle = v
            end
        end

        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            local netId = VehToNet(vehicle)
            print("^2[gw_policejob] Officer: Wagon Detected (" .. vehicle .. "). NetID: " .. netId .. " | Placing ID: " .. targetId .. "^7")
            TriggerServerEvent("gw_policejob:server:putInVehicle", targetId, netId)
            TriggerEvent("gw_policejob:client:notify", _U('notify_entering_vehicle'), "info", 3000)
        else
            print("^1[gw_policejob] Officer: No vehicle/wagon found in 6.0m range.^7")
            TriggerEvent("gw_policejob:client:notify", _U('notify_no_veh_nearby'), "error", 4000)
        end

    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_no_player_nearby'), "error", 3000)
    end
    cb('ok')
end)

RegisterNUICallback("actionSearch", function(data, cb)
    print("^3[gw_policejob] NUI CALLBACK: actionSearch Clicked^7")
    
    local closestPlayer, targetId = getClosestPlayer()
    
    if not targetId then
        TriggerEvent("gw_policejob:client:notify", _U('notify_no_nearby_frisk'), "error", 3000)
        cb('ok')
        return
    end

    -- Closest player found, NOW we can close the menu and proceed
    FreezeEntityPosition(PlayerPedId(), false)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = "closePoliceMenu" })
    SendNUIMessage({ action = "closeMDT" })
    
    Citizen.CreateThread(function()
        Citizen.Wait(500) -- Wait for NUI to fade out
        
        -- Trigger search on server (Primary & cleanest method)
        TriggerServerEvent("gw_policejob:server:searchPlayerInventory", targetId)
    end)
    
    cb('ok')
end)

-- ===== SEARCH RESULT HANDLER =====
-- Receives inventory data from server and displays it in a custom NUI panel
RegisterNetEvent("gw_policejob:client:openSearchResult")
AddEventHandler("gw_policejob:client:openSearchResult", function(data)
    print("^3[gw_policejob] CLIENT: Received search result for " .. tostring(data.targetName) .. " (" .. #data.items .. " items)^7")
    
    -- Open NUI focus for the search panel
    SetNuiFocus(true, true)
    
    -- Send to NUI
    SendNUIMessage({
        action     = "openSearchPanel",
        targetName = data.targetName,
        targetId   = data.targetId,
        items      = data.items,
        imagePath  = data.imagePath or "nui://vorp_inventory/html/img/items/",
    })
end)

-- Close search panel NUI callback  
RegisterNUICallback("closeSearchPanel", function(data, cb)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    cb('ok')
end)

-- NUI callback: Officer clicks "مصادرة" on an item
RegisterNUICallback("confiscateItem", function(data, cb)
    if data and data.targetId and data.item then
        TriggerServerEvent("gw_policejob:server:confiscateItem", tonumber(data.targetId), data.item)
    end
    cb('ok')
end)

-- Remove item from NUI after confiscation
RegisterNetEvent("gw_policejob:client:removeSearchItem")
AddEventHandler("gw_policejob:client:removeSearchItem", function(itemName, itemUid, takenAmount)
    SendNUIMessage({ action = "removeSearchItem", name = itemName, uid = itemUid, taken = takenAmount })
end)

-- NUI callback: Officer clicks "كلبش/فكّ" from interaction menu

RegisterNUICallback("actionTakeOutVehicle", function(data, cb)
    print("^3[gw_policejob] NUI CALLBACK: actionTakeOutVehicle Clicked^7")
    local closestPlayer, targetId = getClosestPlayer()
    if closestPlayer and targetId then
        TriggerServerEvent("gw_policejob:server:takeOutVehicle", targetId)
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_no_player_nearby'), "error", 3000)
    end
    cb('ok')
end)

function ApplyCuff(ped, state)
    isCuffed = state
    if state then
        SendNUIMessage({ action = "showNotify", message = _U('notify_you_are_cuffed'), type = "error" })
        print("^2[gw_policejob] Target is now CUFFED (Native Tech).^7")
        SetEnableHandcuffs(ped, true, false)
        SetPedConfigFlag(ped, 137, true) -- RDR3 CUFFED FLAG Must be true to keep state stable in engine
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true) -- Force unarmed
        
        local animDict = "mp_amb_rest_handcuffed@loop"
        local animName = "handcuffed_loop_male"
        
        RequestAnimDict(animDict)
        Citizen.CreateThread(function()
            local timeout = 0
            while not HasAnimDictLoaded(animDict) and timeout < 30 do Citizen.Wait(10) timeout = timeout + 1 end
            if HasAnimDictLoaded(animDict) then
                TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0, false, false, false)
            end
        end)
    else
        isCuffed = false
        SetEnableHandcuffs(ped, false, false)
        SetPedConfigFlag(ped, 137, false)
        ClearPedTasks(ped)
        print("^3[gw_policejob] Target RELEASED.^7")
    end
end

-- Self Test Alias
RegisterCommand("cuffme", function()
    TriggerEvent("gw_policejob:client:toggleCuff")
end, false)

RegisterNetEvent("gw_policejob:client:setCuffState")
AddEventHandler("gw_policejob:client:setCuffState", function(state)
    local ped = PlayerPedId()
    print("^3[gw_policejob] FORCED STATE SYNC: isCuffed -> " .. tostring(state) .. "^7")
    ApplyCuff(ped, state)
    
    if state then
        -- Thread for Frame-Perfect Control Blocking (0ms)
        Citizen.CreateThread(function()
            while isCuffed do

                local myPed = PlayerPedId()
                local inVehicle = IsPedInAnyVehicle(myPed, false)
                
                -- Standard Action Blocking
                DisableControlAction(0, 0x8FFC75D1, true) -- Roll / Prompt 1
                DisableControlAction(0, 0xD4A1F184, true) -- Jump
                DisableControlAction(0, 0x8CC57157, true) -- Melee
                DisableControlAction(0, 0x07CEABE4, true) -- Shoot
                DisableControlAction(0, 0xF84FA74F, true) -- Sprint
                DisableControlAction(0, 0xCEE124C2, true) -- Vault
                DisableControlAction(0, 0x580C44CA, true) -- Weapon Wheel
                DisableControlAction(0, 0x018C47CF, true) -- Break out / Struggle
                DisableControlAction(0, 0xE8342FF2, true) -- Interact Break
                
                -- (Native Handcuff State is now only set ONCE during ApplyCuff to prevent animation resets)
                
                -- Realism: Prevent ANY form of Vehicle Exit or Seat Switching while cuffed
                if inVehicle then
                    -- Aggressive lock: Disable ALL controls when in wagon/vehicle
                    DisableAllControlActions(0)
                    
                    -- Re-enable essential controls (Camera & Chat)
                    EnableControlAction(0, 0x1E7DA606, true) -- T (Chat)
                    EnableControlAction(0, 0x0FDE73C3, true) -- Push to Talk
                    EnableControlAction(0, 0x72365F4B, true) -- Look L/R
                    EnableControlAction(0, 0xF5485987, true) -- Look U/D
                    EnableControlAction(0, 0x821E2E08, true) -- Frontend Menu (Esc/Settings)
                    
                    -- Update Memory ONLY if we aren't intentionally leaving (-1)
                    if lastVehicle ~= -1 then
                        lastVehicle = GetVehiclePedIsIn(myPed, false)
                    end
                    
                    SetPedConfigFlag(myPed, 32, false) -- Disable vehicle exit
                    
                    -- Physical Lock: Freeze suspect in seat to prevent ANY animation (even E prompts)
                    FreezeEntityPosition(myPed, true)
                else
                    -- Officially out: Reset -1 flag to 0 for next time
                    if lastVehicle == -1 then
                        lastVehicle = 0
                    end

                    -- Unfreeze if we were frozen during a failsafe or transition
                    FreezeEntityPosition(myPed, false)

                    -- Failsafe: If They Were Just In A Vehicle And Still Cuffed, Warp Back
                    if lastVehicle ~= 0 and lastVehicle ~= -1 and DoesEntityExist(lastVehicle) then

                        -- Check distance to wagon (Don't warp if wagon is gone)
                        local vPos = GetEntityCoords(lastVehicle)
                        local pPos = GetEntityCoords(myPed)
                        if #(pPos - vPos) < 10.0 then
                            -- High-priority re-seating
                            ClearPedTasksImmediately(myPed)
                            SetPedIntoVehicle(myPed, lastVehicle, -2)
                        else
                            lastVehicle = 0 -- Wagon is too far, stop warping
                        end
                    end
                    
                    -- Animation Protection: ONLY play standing animation if NOT in a vehicle and NOT escorted
                    if not IsEntityPlayingAnim(myPed, "mp_amb_rest_handcuffed@loop", "handcuffed_loop_male", 3) and not isEscorted then
                        TaskPlayAnim(myPed, "mp_amb_rest_handcuffed@loop", "handcuffed_loop_male", 8.0, -8.0, -1, 49, 0, false, false, false)
                    end
                end
                
                Citizen.Wait(0)
            end
            
            -- Ensure player is ALWAYS unfrozen when cuff state ends
            local finalPed = PlayerPedId()
            FreezeEntityPosition(finalPed, false)
            DetachEntity(finalPed, true, false) -- Safety for escorting
            SetEntityCollision(finalPed, true, true)
        end)
    end
end)




local isEscorted = false
local isCarrying = false
local escortedTarget = nil

RegisterNetEvent("gw_policejob:client:toggleCarryCop")
AddEventHandler("gw_policejob:client:toggleCarryCop", function(targetId)
    isCarrying = not isCarrying
    local myPed = PlayerPedId()
    print("DEBUG: toggleCarryCop called. isCarrying = " .. tostring(isCarrying) .. " | targetId = " .. tostring(targetId))
    if isCarrying then
        escortedTarget = targetId
        local animDict = "mech_carry_ped@shoulder@male"
        RequestAnimDict(animDict)
        Citizen.CreateThread(function()
            local timeout = 0
            while not HasAnimDictLoaded(animDict) and timeout < 30 do Citizen.Wait(10) timeout = timeout + 1 end
            if HasAnimDictLoaded(animDict) then
                print("DEBUG: Cop carrying animation loaded successfully.")
                TaskPlayAnim(myPed, animDict, "idle_carrier", 8.0, -8.0, -1, 49, 0, false, false, false)
            else
                print("DEBUG: Cop carrying animation FAILED to load.")
            end
        end)
    else
        escortedTarget = nil
        ClearPedTasks(myPed)
    end
end)

RegisterNetEvent("gw_policejob:client:stopCarryCop")
AddEventHandler("gw_policejob:client:stopCarryCop", function()
    print("DEBUG: stopCarryCop called. Clearing carrying tasks.")
    isCarrying = false
    escortedTarget = nil
    ClearPedTasks(PlayerPedId())
end)

RegisterNetEvent("gw_policejob:client:toggleEscort")
AddEventHandler("gw_policejob:client:toggleEscort", function(copSrc)
    isEscorted = not isEscorted
    local myPed = PlayerPedId()
    print("DEBUG: toggleEscort called. isEscorted = " .. tostring(isEscorted) .. " | copSrc = " .. tostring(copSrc))
    if isEscorted then
        -- Find cop ped (robust search)
        local copPed = 0
        local copPlayer = GetPlayerFromServerId(copSrc)
        if copPlayer ~= -1 then
            copPed = GetPlayerPed(copPlayer)
        else
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == copSrc then
                    copPed = GetPlayerPed(player)
                    break
                end
            end
        end

        print("DEBUG: resolved copPed = " .. tostring(copPed))
        if copPed and copPed ~= 0 then
            SetEntityCollision(myPed, false, true)
            AttachEntityToEntity(myPed, copPed, 0, 0.15, 0.15, 0.63, 0.0, 95.0, 0.0, false, false, false, true, 2, true)
            
            local animDict = "mech_carry_ped@shoulder@male"
            RequestAnimDict(animDict)
            Citizen.CreateThread(function()
                local timeout = 0
                while not HasAnimDictLoaded(animDict) and timeout < 30 do Citizen.Wait(10) timeout = timeout + 1 end
                if HasAnimDictLoaded(animDict) then
                    print("DEBUG: Target carried animation loaded successfully.")
                    TaskPlayAnim(myPed, animDict, "idle_target", 8.0, -8.0, -1, 3, 0, false, false, false)
                else
                    print("DEBUG: Target carried animation FAILED to load.")
                end
            end)
        else
            print("DEBUG: ERROR - resolved copPed is invalid!")
            isEscorted = false
        end
        
        TriggerEvent("gw_policejob:client:notify", _U('notify_being_dragged'), "error", 4000)
    else
        DetachEntity(myPed, true, false)
        SetEntityCollision(myPed, true, true)
        ClearPedTasks(myPed)
        TriggerEvent("gw_policejob:client:notify", _U('notify_drag_released'), "success", 4000)
    end
end)

RegisterNetEvent("gw_policejob:client:notify")
AddEventHandler("gw_policejob:client:notify", function(msg, type, time)
    SendNUIMessage({
        action = "showNotify",
        message = msg,
        type = type,
        time = time or 4000
    })
end)

-- --- VEHICLE INTERACTION HANDLERS (Missing Logic Restored) ---
RegisterNetEvent("gw_policejob:client:putInVehicle")
AddEventHandler("gw_policejob:client:putInVehicle", function(netId)
    local ped = PlayerPedId()
    local vehicle = NetToVeh(netId)
    
    if DoesEntityExist(vehicle) then
        DebugPrint("^2[gw_policejob] Target: Syncing entry to wagon handle " .. vehicle .. "^7")
        
        -- Detach and Reset
        isEscorted = false
        DetachEntity(ped, true, false)
        SetEntityCollision(ped, true, true)
        ClearPedTasksImmediately(ped)
        Citizen.Wait(250)

        -- Universal Seat Search (RDR2 Wagons vary in seat counts)
        local seat = -2 
        local testSeats = {1, 2, 3, 4, 5, 6, 0, -1}
        
        for _, s in ipairs(testSeats) do
            if IsVehicleSeatFree(vehicle, s) then
                seat = s
                break
            end
        end

        if seat ~= -2 then
            -- SetPedIntoVehicle is more absolute than TaskWarp
            SetPedIntoVehicle(ped, vehicle, seat)
            TriggerEvent("gw_policejob:client:notify", _U('notify_placed_in_veh'), "info", 5000)
        else
            DebugPrint("^1[gw_policejob] Fail: All seats occupied or wagon full.^7")
            TriggerEvent("gw_policejob:client:notify", _U('notify_veh_full'), "error", 4000)
        end
    else
        DebugPrint("^1[gw_policejob] Error: Vehicle handle not found on this client pool.^7")
    end
end)

RegisterNetEvent("gw_policejob:client:takeOutVehicle")
AddEventHandler("gw_policejob:client:takeOutVehicle", function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, true) then
        local veh = GetVehiclePedIsIn(ped, true)
        local coords = GetEntityCoords(veh)
        
        -- Immediate exit logic
        lastVehicle = -1 -- Marker: Intentionally leaving, ignore warp-back
        FreezeEntityPosition(ped, false) -- Unfreeze for exit task

        
        -- Temporary Cuff Release to facilitate stable teleport
        SetEnableHandcuffs(ped, false, false)
        SetPedConfigFlag(ped, 137, false)
        
        -- Use relative coordinates to exit to the REAR (Behind wagons)
        local safeOffset = GetOffsetFromEntityInWorldCoords(veh, 0.0, -3.5, 0.0)
        
        ClearPedTasksImmediately(ped)
        DetachEntity(ped, true, true)
        SetEntityCoords(ped, safeOffset.x, safeOffset.y, safeOffset.z, 1, 0, 0, 1)
        PlaceObjectOnGroundProperly(ped) -- Ensuring they are on the ground
        
        -- Settlement Delay
        Citizen.Wait(400)
        ClearPedTasksImmediately(ped)
        
        -- FORCED RE-CUFF (Standing Pose)
        if isCuffed then
            ApplyCuff(ped, true)
        end

        -- Re-apply cuffs if they were cuffed
        if isCuffed then
            ApplyCuff(ped, true)
        end
        TriggerEvent("gw_policejob:client:notify", _U('notify_removed_from_veh'), "success", 5000)
    else
        DebugPrint("^1[gw_policejob] Fail: takeOutVehicle requested but player not in any vehicle.^7")
    end
end)
-- -------------------------------------------------------------

-- Police Station Blip
local mdtCoords = vector3(-277.65, 808.29, 119.38)
Citizen.CreateThread(function()
    -- Create Map Blip
    local blipId = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, mdtCoords.x, mdtCoords.y, mdtCoords.z)
    Citizen.InvokeNative(0x74F74D3207ED525C, blipId, 1997361198, true) -- RDR2 Sheriff Star Blip Sprite
    Citizen.InvokeNative(0x9CB1A1623062F402, blipId, _U('blip_police_station')) -- Set Name
end)

RegisterNetEvent("gw_policejob:client:setJob")
AddEventHandler("gw_policejob:client:setJob", function(job)
    currentJob = job
    DebugPrint("^2[gw_policejob] Client: My Job is now -> " .. tostring(currentJob) .. "^7")
end)

-- Request initial job sync on startup
Citizen.CreateThread(function()
    Citizen.Wait(1000)
    TriggerServerEvent("gw_policejob:server:syncInit")
end)

function isAllowedDutyJob(job)
    if not job then return false end
    local j = tostring(job):lower()
    return j:find("police") or j:find("sheriff")
end

-- Duty Station NPC (Police Chief Lambert)
local dutyPed = nil
local dutyModel = GetHashKey("cs_mp_policechief_lambert")
local dutyCoords = vector3(-278.32, 803.47, 119.43)
local dutyHeading = 355.0

-- دالة لحذف كل البوتات من نفس الموديل قريبة من نقطة
local function deleteNearbyPedsByModel(modelHash, pos, radius)
    local peds = GetGamePool('CPed')
    for _, ped in ipairs(peds) do
        if GetEntityModel(ped) == modelHash and not IsPedAPlayer(ped) then
            local pedPos = GetEntityCoords(ped)
            if #(pedPos - pos) < radius then
                DeleteEntity(ped)
                DebugPrint("^3[gw_policejob] Deleted duplicate NPC near spawn point.^7")
            end
        end
    end
end

Citizen.CreateThread(function()
    Citizen.Wait(1000) -- انتظار تحميل العالم
    
    -- حذف البوتات المكررة من نفس الموديل (1.5م فقط)
    deleteNearbyPedsByModel(dutyModel, dutyCoords, 1.5)
    if dutyPed and DoesEntityExist(dutyPed) then
        DeleteEntity(dutyPed)
        dutyPed = nil
    end
    Citizen.Wait(500)

    -- تحميل الموديل
    RequestModel(dutyModel)
    local t = 0
    while not HasModelLoaded(dutyModel) and t < 100 do Citizen.Wait(10) t = t + 1 end
    
    dutyPed = CreatePed(dutyModel, dutyCoords.x, dutyCoords.y, dutyCoords.z - 1.0, dutyHeading, false, false, 0, 0)
    
    if DoesEntityExist(dutyPed) then
        SetEntityInvincible(dutyPed, true)
        FreezeEntityPosition(dutyPed, true)
        SetBlockingOfNonTemporaryEvents(dutyPed, true)
        Citizen.InvokeNative(0x283978A15512B2FE, dutyPed, true)
        DebugPrint("^2[gw_policejob] Duty NPC spawned OK.^7")
    else
        DebugPrint("^1[gw_policejob] ERROR: Duty NPC failed to spawn!^7")
    end
    
    SetModelAsNoLongerNeeded(dutyModel)
end)

-- NPC Spawning (Armory & Vehicles)
local function spawnNPC(modelName, coords, heading, oldPed)
    -- حذف البوت القديم إذا وجد
    if oldPed and DoesEntityExist(oldPed) then
        DeleteEntity(oldPed)
    end
    
    -- حذف أي بوتات مكررة من نفس الموديل (نطاق صغير 1.5م لتجنب حذف البوتات المجاورة)
    local modelHash = GetHashKey(modelName)
    local peds = GetGamePool('CPed')
    for _, ped in ipairs(peds) do
        if GetEntityModel(ped) == modelHash and not IsPedAPlayer(ped) then
            local pedPos = GetEntityCoords(ped)
            if #(pedPos - coords) < 1.5 then
                DeleteEntity(ped)
                DebugPrint("^3[gw_policejob] Cleaned duplicate NPC.^7")
            end
        end
    end
    Citizen.Wait(400)
    
    RequestModel(modelHash)
    local t = 0
    while not HasModelLoaded(modelHash) and t < 100 do Citizen.Wait(10) t = t + 1 end
    
    local ped = CreatePed(modelHash, coords.x, coords.y, coords.z - 1.0, heading, false, false, 0, 0)
    if DoesEntityExist(ped) then
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
    end
    SetModelAsNoLongerNeeded(modelHash)
    return ped
end

Citizen.CreateThread(function()
    -- Spawn Armory NPC
    if Config.Armory and Config.Armory.enabled then
        armoryPed = spawnNPC(Config.Armory.npcModel, Config.Armory.coords, Config.Armory.npcHeading, armoryPed)
        DebugPrint("^2[gw_policejob] Armory NPC Spawned at: " .. tostring(Config.Armory.coords) .. "^7")
    end
    
    -- Spawn Vehicle NPC
    if Config.Vehicles and Config.Vehicles.enabled then
        vehiclePed = spawnNPC(Config.Vehicles.npcModel, Config.Vehicles.coords, Config.Vehicles.npcHeading, vehiclePed)
        DebugPrint("^2[gw_policejob] Vehicle NPC Spawned at: " .. tostring(Config.Vehicles.coords) .. "^7")
    end
end)

-- حذف البوتات عند إيقاف المورد
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if dutyPed and DoesEntityExist(dutyPed) then DeleteEntity(dutyPed) end
        if armoryPed and DoesEntityExist(armoryPed) then DeleteEntity(armoryPed) end
        if vehiclePed and DoesEntityExist(vehiclePed) then DeleteEntity(vehiclePed) end
        DebugPrint("^3[gw_policejob] NPCs cleaned up on resource stop.^7")
    end
end)

-- Armory Interaction Loop
-- Global Interaction Manager
local currentPromptType = nil -- 'armory' or 'duty'
local closestJailValue = nil

Citizen.CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local sleep = true
        
        local closestDist = 999.0
        local closestType = nil
        closestJailValue = nil

        -- Check Vehicles
        if Config.Vehicles and Config.Vehicles.coords then
            local dist = #(pos - Config.Vehicles.coords)
            if dist < 4.0 then
                sleep = false
                if dist < closestDist then
                    closestDist = dist
                    closestType = 'vehicles'
                end
            end
        end

        -- Check Duty Stations
        if Config.Stations then
            for name, data in pairs(Config.Stations) do
                if data.DutyToggle then
                    local dist = #(pos - data.DutyToggle)
                    if dist < 4.0 then
                        sleep = false
                        if dist < closestDist then
                            closestDist = dist
                            closestType = 'duty'
                        end
                    end
                end
            end
        end

        -- Check Weapon Armory (NPC)
        if Config.Armory and Config.Armory.coords then
            local dist = #(pos - Config.Armory.coords)
            if dist < 4.0 then
                sleep = false
                if dist < closestDist then
                    closestDist = dist
                    closestType = 'armory'
                end
            end
        end

        -- Check Jails (Only when carrying a suspect)
        if isCarrying and escortedTarget then
            if Config.Jails then
                for _, jail in ipairs(Config.Jails) do
                    local dist = #(pos - jail.coords)
                    if dist < 4.0 then
                        sleep = false
                        if dist < closestDist then
                            closestDist = dist
                            closestType = 'jail_cell'
                            closestJailValue = jail.value
                        end
                    end
                end
            end
        end

        -- Handle Closest Interaction Prompt
        if closestType and closestDist < 2.5 then
            sleep = false -- Keep thread fast (0ms) when close to point
            if not promptShowing or currentPromptType ~= closestType then
                promptShowing = true
                currentPromptType = closestType
                
                local pTitle = _U('ui_police_system')
                local pSub = _U('ui_press_interact')

                if closestType == 'duty' then
                    pTitle = _U('ui_duty_menu')
                    pSub = _U('ui_press_open_menu')
                elseif closestType == 'armory' then
                    pTitle = _U('ui_armory')
                    pSub = _U('ui_press_shop')
                elseif closestType == 'vehicles' then
                    pTitle = _U('ui_veh_mgmt')
                    pSub = _U('ui_press_request_veh')
                elseif closestType == 'jail_cell' then
                    pTitle = _U('ui_put_in_jail')
                    pSub = _U('ui_put_in_jail_sub')
                end
                
                SendNUIMessage({
                    action = "showPrompt",
                    title = pTitle,
                    subtitle = pSub,
                    key = "G"
                })
            end

            -- KEY PRESS DETECTION (MUST BE IN 0ms WAIT LOOP)
            if IsControlJustPressed(0, 0x760A9C6F) then -- [G]
                DebugPrint("^3[gw_policejob] Action Triggered: " .. tostring(closestType) .. "^7")
                SendNUIMessage({ action = "playPromptAnim" })
                
                if closestType == 'armory' then
                    openArmoryMenu()
                elseif closestType == 'vehicles' then
                    openVehicleMenu()
                elseif closestType == 'duty' then
                    openDutyMenuWithAnim()
                elseif closestType == 'jail_cell' then
                    if escortedTarget and closestJailValue then
                        local targetId = escortedTarget
                        local defaultJailTime = Config.DefaultJailTime or 10
                        TriggerServerEvent("gw_policejob:server:quickJail", targetId, defaultJailTime, closestJailValue)
                    end
                end
            end
        else
            if promptShowing then
                promptShowing = false
                currentPromptType = nil
                SendNUIMessage({ action = "hidePrompt" })
            end
        end

        if sleep then 
            Citizen.Wait(500) 
        else 
            Citizen.Wait(0) 
        end
    end
end)

function openVehicleMenu()
    if isArmoryOpen then return end
    
    local function isPolice(job)
        if not job then return false end
        local j = tostring(job):lower()
        if j:find("off") then return false end -- EXCLUDE OFF DUTY
        return j:find("police") or j:find("sheriff")
    end

    if isPolice(currentJob) then
        isArmoryOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false) 
        TriggerServerEvent("gw_policejob:server:requestVehicleMenu")

    else
        isArmoryOpen = false
        isFineOpen = false
        SetNuiFocus(false, false)
        TriggerEvent("gw_policejob:client:notify", _U('notify_off_duty_veh'), "error", 4000)
    end
end

function openArmoryMenu()
    if isArmoryOpen then
        isArmoryOpen = false
        FreezeEntityPosition(PlayerPedId(), false)
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "closeArmory" })
        return
    end

    local function isPolice(job)
        if not job then return false end
        local j = tostring(job):lower()
        if j:find("off") then return false end -- EXCLUDE OFF DUTY
        return j:find("police") or j:find("sheriff")
    end

    if isPolice(currentJob) then
        isArmoryOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        TriggerServerEvent("gw_policejob:server:requestArmory")

    else
        isArmoryOpen = false
        isFineOpen = false
        SetNuiFocus(false, false)
        TriggerEvent("gw_policejob:client:notify", _U('notify_off_duty_armory'), "error", 4000)
    end
end

function openDutyMenuWithAnim()
    local ped = PlayerPedId()
        -- Salute Animation
    local animDict = "amb_misc@world_human_salute@male_a@idle_a"
    RequestAnimDict(animDict)
    local t = 0
    while not HasAnimDictLoaded(animDict) and t < 50 do Citizen.Wait(10) t = t + 1 end
    
    if HasAnimDictLoaded(animDict) then
        TaskPlayAnim(ped, animDict, "idle_a", 8.0, -8.0, 1500, 0, 0, false, false, false)
        Citizen.Wait(1300)
    end
    
    TriggerServerEvent("gw_policejob:server:requestDutyMenu")
end




RegisterNetEvent("gw_policejob:client:openDutyMenu")
AddEventHandler("gw_policejob:client:openDutyMenu", function(isOnDuty)
    isDutyMenuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openDutyMenu",
        isOnDuty = isOnDuty,
        colors = Config.UIColors
    })
end)


RegisterNUICallback("dutyAction", function(data, cb)
    local currentTime = GetGameTimer()
    if currentTime - lastDutyToggle < 2000 then
        TriggerEvent("gw_policejob:client:notify", _U('notify_duty_cooldown'), "error", 3000)
        cb('ok')
        return
    end
    lastDutyToggle = currentTime

    isDutyMenuOpen = false
    isPoliceMenuOpen = false
    isMdtOpen = false
    isArmoryOpen = false
    isFineOpen = false
    FreezeEntityPosition(PlayerPedId(), false) -- UNFREEZE on action
    SetNuiFocus(false, false)
    TriggerServerEvent("gw_policejob:server:toggleDuty", data.action)
    cb('ok')
end)


-- Helper to draw 3D text (Legacy - DISABLED)
-- function DrawText3D(x, y, z, text) ... end

-- Live Map Blips for Police
local copBlips = {}

RegisterNetEvent("gw_policejob:client:updateCopBlips")
AddEventHandler("gw_policejob:client:updateCopBlips", function(copsData)
    -- Remove old blips
    for src, blipId in pairs(copBlips) do
        RemoveBlip(blipId)
    end
    copBlips = {}

    local mySrc = GetPlayerServerId(PlayerId())

    -- Add current blips (INCLUDING LOCAL PLAYER for confirmation)
    for _, cop in ipairs(copsData) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, cop.coords.x, cop.coords.y, cop.coords.z)
            
            -- Set the sprite (Sheriff Star) & Force Visibility
            Citizen.InvokeNative(0x74F74D3207ED525C, blip, 1997361198, true)
            
            -- Set Blip Scale (Slightly larger for visibility)
            Citizen.InvokeNative(0xD38744167B2FA257, blip, 0.25)
            
            -- TACTICAL COLORING: Red/Pulse if Panic, Gold/Blue otherwise
            if cop.isPanic then
                Citizen.InvokeNative(0x662D364ABF11DA25, blip, 0xC62828FF) -- Deep Red
                Citizen.InvokeNative(0x1B86228308B9833D, blip, true) -- Start Blip Pulse
            else
                Citizen.InvokeNative(0x662D364ABF11DA25, blip, 0x00D2FFFF) -- Sheriff Blue
            end
            
            -- Set Blip Name / Tooltip
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, cop.name .. " [Officer]")
            
            copBlips[cop.src] = blip
        end

    -- Update NUI Dispatch Map if MDT is open
    if isMdtOpen then
        local myCoords = GetEntityCoords(PlayerPedId())
        local myName = currentOfficerName or "Officer"
        local mySrcInt = tonumber(mySrc)
        
        local combinedData = {}
        local myPanicStatus = false
        local myRank = "Officer"

        for _, cop in ipairs(copsData) do
            local copSrcInt = tonumber(cop.src)
            if copSrcInt == mySrcInt then
                myPanicStatus = cop.isPanic
                myRank = cop.rank or myRank
                -- Use the name from the server if we don't have one locally
                if not currentOfficerName or currentOfficerName == "" then
                    myName = cop.name
                end
            else
                table.insert(combinedData, {
                    src = cop.src,
                    name = cop.name,
                    coords = cop.coords,
                    rank = cop.rank,
                    isPanic = cop.isPanic
                })
            end
        end
        
        -- Add local player with precise current coordinates
        table.insert(combinedData, {
            src = mySrcInt,
            name = myName,
            coords = { x = myCoords.x, y = myCoords.y, z = myCoords.z },
            rank = myRank,
            isPanic = myPanicStatus,
            isMe = true -- Optional flag for special styling if needed later
        })

        SendNUIMessage({
            action = "updateDispatchMap",
            cops = combinedData
        })
    end
end)


local function RemoveDutyWeapons()
    local ped = PlayerPedId()
    local kitWeapons = {
        "WEAPON_LASSO",
        "WEAPON_REVOLVER_SCHOFIELD",
        "WEAPON_REVOLVER_CATTLEMAN",
        "WEAPON_SNIPERRIFLE_CARCANO",
        "WEAPON_SHOTGUN_SEMIAUTO"
    }
    for _, wName in ipairs(kitWeapons) do
        local wHash = GetHashKey(wName)
        if HasPedGotWeapon(ped, wHash, false) then
            RemoveWeaponFromPed(ped, wHash, true, 0)
        end
    end
end

RegisterNetEvent("gw_policejob:client:removeDutyWeapons")
AddEventHandler("gw_policejob:client:removeDutyWeapons", RemoveDutyWeapons)

RegisterNetEvent("gw_policejob:client:stripWeapons")
AddEventHandler("gw_policejob:client:stripWeapons", RemoveDutyWeapons)

-- Final Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        RemoveDutyWeapons()
        if (dutyPed and DoesEntityExist(dutyPed)) then DeleteEntity(dutyPed) end
        if (armoryPed and DoesEntityExist(armoryPed)) then DeleteEntity(armoryPed) end
        if promptShowing or playerPromptShowing then
            SendNUIMessage({ action = "hidePrompt" })
        end
    end
end)

-- NUI Bridge for Server-to-NUI Messaging
RegisterNetEvent("gw_policejob:client:sendToNUI")
AddEventHandler("gw_policejob:client:sendToNUI", function(data)
    DebugPrint("^3[gw_policejob] Receiving data from Server for NUI Action: " .. tostring(data.action) .. "^7")
    SendNUIMessage(data)
end)

-- Compatibility Event for External Scripts (vorp_admin, etc.)
RegisterNetEvent('vorp_admin:ClientHandcuffPlayerHandler')
AddEventHandler('vorp_admin:ClientHandcuffPlayerHandler', function()
    local player = PlayerPedId()
    -- Use native to check state for maximum precision
    if not IsPedCuffed(player) then
        ApplyCuff(player, true)
    else
        ApplyCuff(player, false)
    end
end)

-- Vehicle Interactions
RegisterNetEvent("gw_policejob:client:putInVehicle")
AddEventHandler("gw_policejob:client:putInVehicle", function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    -- Increase radius to 5.0m for wagons/horses
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 70)
    
    DebugPrint("^3[gw_policejob] Target: Received PutInVehicle command. Scanning for vehicles within 5.0m...^7")

    if vehicle ~= 0 then
        local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
        local freeSeat = -1
        
        DebugPrint("^3[gw_policejob] Vehicle found (ID: " .. vehicle .. "). Checking passenger seat priority...^7")

        -- Priority Seating for Suspects: 
        -- 1 (Back Left), 2 (Back Right), 3 (Wagon Back), 0 (Front Passenger)
        local prioritySeats = {1, 2, 3, 0}
        for _, seatId in ipairs(prioritySeats) do
            if IsVehicleSeatFree(vehicle, seatId) then
                freeSeat = seatId
                break
            end
        end

        -- Final fallback if priority seats are full/invalid
        if freeSeat == -1 then
            for i = 0, maxSeats - 1 do
                if IsVehicleSeatFree(vehicle, i) then
                    freeSeat = i
                    break
                end
            end
        end

        if freeSeat ~= -1 then
            TaskWarpPedIntoVehicle(ped, vehicle, freeSeat)
        end
    end
end)

RegisterNetEvent("gw_policejob:client:takeOutVehicle")
AddEventHandler("gw_policejob:client:takeOutVehicle", function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveAnyVehicle(ped, 0, 0)
    end
end)

spawnedPoliceVehicles = spawnedPoliceVehicles or {}

RegisterNetEvent("gw_policejob:client:spawnVehicleLocal")
AddEventHandler("gw_policejob:client:spawnVehicleLocal", function(modelStr, configCoords, configHeading)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local model = joaat(modelStr)
    
    -- STRICT POSITIONING: Use config coords exactly
    local spawnPos = configCoords
    local spawnHeading = configHeading or 0.0

    if not spawnPos then
        spawnPos = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 5.0, 0.0)
    end

    -- Only show spawn log
    DebugPrint("^3[gw_policejob] Attempting Spawn: " .. modelStr .. " at " .. tostring(spawnPos) .. "^7")

    Citizen.CreateThread(function()
        RequestModel(model)
        local timeout = 0
        while not HasModelLoaded(model) and timeout < 200 do
            Wait(10)
            timeout = timeout + 1
        end

        if not HasModelLoaded(model) then
            print("^1[gw_policejob] FATAL ERROR: Model " .. modelStr .. " failed to load!^7")
            TriggerEvent("gw_policejob:client:notify", _U('notify_veh_model_mem_fail'), "error", 5000)
            return
        end

        -- 2. Create Entity (gw_admin style)
        local vehicle = CreateVehicle(model, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true, false, false)
        
        local existCheck = 0
        while not DoesEntityExist(vehicle) and existCheck < 50 do
            Wait(10)
            existCheck = existCheck + 1
        end

        if DoesEntityExist(vehicle) then
            -- 3. Core Native Application
            Citizen.InvokeNative(0x77FF8D35EEC6BBC4, vehicle, 1, 0) -- Mission persistence
            SetVehicleOnGroundProperly(vehicle)
            SetEntityVisible(vehicle, true)
            SetModelAsNoLongerNeeded(model)
            
            -- Fixed networking for RedM
            local netId = NetworkGetNetworkIdFromEntity(vehicle)
            SetNetworkIdExistsOnAllMachines(netId, true)
            
            spawnedPoliceVehicles[netId] = vehicle
            
            DebugPrint("^2[gw_policejob] SUCCESS: Vehicle " .. modelStr .. " spawned with NetID: " .. netId .. "^7")
            TriggerEvent("gw_policejob:client:notify", _U('notify_strategic_veh_success'), "success", 5000)
        else
            DebugPrint("^1[gw_policejob] FATAL ERROR: CreateVehicle returned nil/invalid entity!^7")
            TriggerEvent("gw_policejob:client:notify", _U('notify_veh_entity_fail'), "error", 5000)
        end
    end)
end)

RegisterNUICallback("deleteStrategicVehicle", function(data, cb)
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    
    -- Build a lookup table of police vehicle models
    local policeModels = {}
    if Config.Vehicles and Config.Vehicles.list then
        for _, v in ipairs(Config.Vehicles.list) do
            policeModels[GetHashKey(v.model)] = true
        end
    end

    local closestVeh = nil
    local closestDist = 25.0 -- Search radius limit

    local handle, veh = FindFirstVehicle()
    local success
    if handle ~= -1 then
        repeat
            if DoesEntityExist(veh) then
                local model = GetEntityModel(veh)
                if policeModels[model] then
                    local vehCoords = GetEntityCoords(veh)
                    local dist = #(pCoords - vehCoords)
                    if dist < closestDist then
                        closestDist = dist
                        closestVeh = veh
                    end
                end
            end
            success, veh = FindNextVehicle(handle)
        until not success
        EndFindVehicle(handle)
    end

    if closestVeh then
        SetEntityAsMissionEntity(closestVeh, true, true)
        local netId = NetworkGetNetworkIdFromEntity(closestVeh)
        if netId and spawnedPoliceVehicles[netId] then
            spawnedPoliceVehicles[netId] = nil
        end
        DeleteVehicle(closestVeh)
        TriggerEvent("gw_policejob:client:notify", _U('notify_veh_withdrawn_success'), "success", 4000)
    else
        TriggerEvent("gw_policejob:client:notify", _U('notify_no_veh_to_withdraw'), "error", 4000)
    end

    cb('ok')
end)
