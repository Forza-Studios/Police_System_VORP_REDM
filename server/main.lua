local VORPcore = {}
local CuffedPlayers = {} -- Server-side cuff state {[targetServerId] = officerServerId}
local lastDutyRequest = {} -- Debounce tracker for duty toggles

local function DebugPrint(...)
    if Config and Config.Debug then
        print(...)
    end
end

DebugPrint("^2[gw_policejob] Server script is INITIALIZING...^7")
TriggerEvent("getCore", function(core) VORPcore = core DebugPrint("^2[gw_policejob] VORPcore Link Established!^7") end)

-- Automated Schema Initialization
Citizen.CreateThread(function()
    Citizen.Wait(1000) -- Small delay for DB connection
    DebugPrint("^3[gw_policejob] Initializing Database Schema...^7")
    
    -- 1. Main Job Tables
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `gw_jail` (
            `charidentifier` varchar(100) NOT NULL,
            `jail_time` int(11) DEFAULT 0,
            `jail_location` varchar(50) DEFAULT 'Valentine',
            PRIMARY KEY (`charidentifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function(success)
        if success then
            DebugPrint("^2[gw_policejob] DB: gw_jail table verified/created successfully.^7")
        end
    end)

    -- جدول السجلات الجنائية
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `gw_police_records` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `charidentifier` varchar(100) NOT NULL,
            `firstname` varchar(100) DEFAULT NULL,
            `lastname` varchar(100) DEFAULT NULL,
            `officer_name` varchar(200) DEFAULT NULL,
            `title` varchar(255) DEFAULT NULL,
            `description` text DEFAULT NULL,
            `charges` text DEFAULT NULL,
            `jail_time` int(11) DEFAULT 0,
            `jail_location` varchar(50) DEFAULT 'None',
            `date` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function(success)
        if success then
            DebugPrint("^2[gw_policejob] DB: gw_police_records table verified/created successfully.^7")
        end
    end)

    -- جدول المذكرات
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `gw_police_warrants` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `charidentifier` varchar(100) NOT NULL,
            `firstname` varchar(100) DEFAULT NULL,
            `lastname` varchar(100) DEFAULT NULL,
            `reason` text DEFAULT NULL,
            `issuer` varchar(200) DEFAULT NULL,
            `char_img` text DEFAULT NULL,
            `date` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function(success)
        if success then
            DebugPrint("^2[gw_policejob] DB: gw_police_warrants table verified/created successfully.^7")
        end
    end)
end)

local VorpInv = exports.vorp_inventory
-- Register Bullets as Usable Items for Manual Reload
Citizen.CreateThread(function()
    Citizen.Wait(2000)
    local ammoItems = {
        { id = 'ammorevolverexpress', count = 100, weapons = {"WEAPON_REVOLVER_CATTLEMAN", "WEAPON_REVOLVER_SCHOFIELD", "WEAPON_REVOLVER_LEMAT"} },
        { id = 'ammorifleexpress',    count = 100, weapons = {"WEAPON_SNIPERRIFLE_CARCANO", "WEAPON_REPEATER_LANCASTER", "WEAPON_REPEATER_LITCHFIELD", "WEAPON_RIFLE_BOLTACTION"} },
        { id = 'AMMO_SHOTGUN_SLUG',  count = 100, weapons = {"WEAPON_SHOTGUN_SEMIAUTO", "WEAPON_SHOTGUN_DOUBLEBARREL", "WEAPON_SHOTGUN_PUMP"} }
    }

    for _, data in ipairs(ammoItems) do
        TriggerEvent("vorpCore:registerUsableItem", data.id, function(data_src)
            local User = VORPcore.getUser(data_src)
            if not User then return end
            
            -- Trigger client to reload currently held weapon
            TriggerClientEvent("gw_policejob:client:manualReload", data_src, data.id, data.count, data.weapons)
            
            -- Consume 1 item
            VORPcore.subItem(data_src, data.id, 1)
            TriggerClientEvent("gw_policejob:client:notify", data_src, _U('notify_weapon_cocked'), "success", 3000)
        end)
    end
end)

-- Auto-Database Migration
Citizen.CreateThread(function()
    Citizen.Wait(1000) -- Wait for DB to be ready
    
    -- 1. Ensure 'jail_location' exists and 'charidentifier' is VARCHAR
    MySQL.query("ALTER TABLE `gw_jail` MODIFY COLUMN `charidentifier` VARCHAR(100) NOT NULL", {}, function() end)
    MySQL.query("ALTER TABLE `gw_police_records` ADD COLUMN IF NOT EXISTS `jail_location` varchar(50) DEFAULT 'None' AFTER `jail_time`", {}, function(success)
        if success then print("^2[gw_policejob] DB: 'jail_location' column verified/added.^7") end
    end)
    
    -- 2. Ensure 'char_img' exists in characters (for Citizen Photos)
    MySQL.query("ALTER TABLE `characters` ADD COLUMN IF NOT EXISTS `char_img` TEXT DEFAULT NULL", {}, function(success)
        if success then print("^2[gw_policejob] DB: 'char_img' column verified/added to characters.^7") end
    end)
    
    -- 3. Ensure 'char_img' exists in gw_police_warrants (for historical persistence)
    MySQL.query("ALTER TABLE `gw_police_warrants` ADD COLUMN IF NOT EXISTS `char_img` TEXT DEFAULT NULL", {}, function(success)
        if success then print("^2[gw_policejob] DB: 'char_img' column verified/added to warrants.^7") end
    end)
    
    -- 4. Ensure 'gw_jail' table exists
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `gw_jail` (
            `charidentifier` int(11) NOT NULL,
            `jail_time` int(11) DEFAULT 0,
            `jail_location` varchar(50) DEFAULT 'Valentine',
            PRIMARY KEY (`charidentifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function(success)
        if success then print("^2[gw_policejob] DB: 'gw_jail' table verified/ready.^7") end
    end)
end)

-- Helper Functions
function isPolice(job)
    if not job then return false end
    local j = tostring(job):lower()
    return j:find("police") or j:find("sheriff")
end

function getRankLabel(grade)
    local g = tonumber(grade) or 0
    if Config.Salaries and Config.Salaries[g] then
        return Config.Salaries[g].label
    end
    return "Officer " .. g
end

function getPlayerSrcByCharId(charid)
    if not charid then return nil end
    local queryId = tonumber(charid)
    
    local players = GetPlayers()
    for _, player in ipairs(players) do
        local sourceId = tonumber(player)
        local User = VORPcore.getUser(sourceId)
        if User then
            local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
            if Character then
                -- Try multiple possible identifier fields used by different VORP versions
                local p_cid = Character.charIdentifier or Character.charid or Character.id
                if not p_cid and Character.getCharIdentifier then p_cid = Character.getCharIdentifier() end
                
                if p_cid and (tonumber(p_cid) == queryId) then
                    return sourceId
                end
            end
        end
    end
    return nil
end

-- Admin Get Jailed List
RegisterNetEvent("gw_policejob:server:getJailedPlayers")
AddEventHandler("gw_policejob:server:getJailedPlayers", function()
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character or not isPolice(Character.job) then return end
    
    print("^3[gw_policejob] Jailed List Check: ID " .. src .. " (" .. Character.firstname .. ") is querying...^7")
    
    -- Diagnostics: Check what's actually in the jail table
    MySQL.query("SELECT * FROM gw_jail", {}, function(raw)
        if raw and #raw > 0 then
            print("^3[gw_policejob] --- JAILED TABLE DUMP ---^7")
            for _, r in ipairs(raw) do
                print("^3[gw_policejob] ID in DB: " .. tostring(r.charidentifier) .. " | Time: " .. tostring(r.jail_time) .. "^7")
            end
        else
            print("^1[gw_policejob] --- JAILED TABLE IS EMPTY ---^7")
        end
    end)

    -- Universal Query (Hyper-Safe Join on both charIdentifier and primary identifier)
    MySQL.query([[
        SELECT j.*, 
        COALESCE(c.firstname, 'Inmate') as firstname, 
        COALESCE(c.lastname, 'Unknown') as lastname,
        c.charIdentifier as realid
        FROM gw_jail j 
        LEFT JOIN characters c ON (CAST(j.charidentifier AS CHAR) = CAST(c.charIdentifier AS CHAR) OR CAST(j.charidentifier AS CHAR) = CAST(c.charidentifier AS CHAR) OR j.charidentifier = c.identifier)
        WHERE j.jail_time > 0
    ]], {}, function(result)
        if result then
            print("^2[gw_policejob] Jailed List Query: Success found " .. #result .. " citizens.^7")
            -- Map the correct ID for the NUI
            for i=1, #result do
                result[i].charIdentifier = result[i].charidentifier -- Normalize for NUI
                print("^3[gw_policejob] Row ["..i.."]: ID=" .. tostring(result[i].charidentifier) .. " Name=" .. tostring(result[i].firstname) .. " Time=" .. tostring(result[i].jail_time) .. "^7")
            end
            
            TriggerClientEvent("gw_policejob:client:sendToNUI", src, {
                action = "jailedPlayersResults",
                players = result
            })
        else
            print("^1[gw_policejob] Jailed List Query: ERROR or No results found in gw_jail.^7")
            TriggerClientEvent("gw_policejob:client:sendToNUI", src, {
                action = "jailedPlayersResults",
                players = {}
            })
        end
    end)
end)

-- Admin Force Unjail
RegisterNetEvent("gw_policejob:server:adminUnjail")
AddEventHandler("gw_policejob:server:adminUnjail", function(charid)
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character or not isPolice(Character.job) then return end

    print("^3[gw_policejob] Admin Release: " .. Character.firstname .. " is freeing CharID " .. charid .. "^7")
    
    -- Update DB
    MySQL.query("UPDATE gw_jail SET jail_time = 0 WHERE charidentifier = ?", {charid})
    
    -- Release online player
    local targetSrc = getPlayerSrcByCharId(charid)
    if targetSrc then
        TriggerClientEvent("gw_policejob:client:forceUnjail", targetSrc)
        TriggerClientEvent("gw_policejob:client:notify", targetSrc, _U('notify_released_admin'), "success", 5000)
    end
    
    TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_released_success'), "success", 4000)
end)
-- NUI Callbacks equivalent for the server
RegisterNetEvent("gw_policejob:server:searchPlayer")
AddEventHandler("gw_policejob:server:searchPlayer", function(query)
    local src = source
    local User = VORPcore.getUser(src)
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not isPolice(Character.job) then return end

    local function processResults(results)
        for i=1, #results do
            local foundSource = getPlayerSrcByCharId(results[i].charIdentifier)
            print("^3[gw_policejob] Search Result ["..i.."]: ID=" .. tostring(results[i].charIdentifier) .. " Name=" .. tostring(results[i].firstname) .. "^7")
            results[i].sourceId = foundSource or "Offline"
            
            -- Resolve rank label if they are police/sheriff
            if isPolice(results[i].job) then
                results[i].rankLabel = getRankLabel(results[i].jobgrade)
            else
                results[i].rankLabel = results[i].job
            end
        end
        TriggerClientEvent("gw_policejob:client:receiveSearchResults", src, results)
        -- Also send via unified bridge as backup
        TriggerClientEvent("gw_policejob:client:sendToNUI", src, { action = "searchResults", results = results })
    end


    if query == "" or query == nil then
        MySQL.query("SELECT charIdentifier, firstname, lastname, job, jobgrade, char_img FROM characters LIMIT 50", {}, function(result)
            processResults(result)
        end)
    else
        MySQL.query("SELECT charIdentifier, firstname, lastname, job, jobgrade, char_img FROM characters WHERE LOWER(firstname) LIKE LOWER(?) OR LOWER(lastname) LIKE LOWER(?) LIMIT 50", {'%'..query..'%', '%'..query..'%'}, function(result)
            processResults(result)
        end)
    end
end)

RegisterNetEvent("gw_policejob:server:updatePhoto")
AddEventHandler("gw_policejob:server:updatePhoto", function(charid, url)
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not isPolice(Character.job) then return end

    local charid = data.charIdentifier or data.charidentifier or charid
    print("^3[gw_policejob] Server Update Photo Request: CID " .. tostring(charid) .. " URL: " .. tostring(url) .. "^7")

    MySQL.update("UPDATE characters SET char_img = ? WHERE charIdentifier = ?", {url, charid}, function(affectedRows)
        if affectedRows then
            print("^2[gw_policejob] Successfully processed photo update for CID " .. tostring(charid) .. "^7")
            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_photo_success'), "success", 4000)
        else
            print("^1[gw_policejob] DATABASE ERROR during photo update for CID " .. tostring(charid) .. "^7")
            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_db_error'), "error", 4000)
        end
    end)
end)

RegisterNetEvent("gw_policejob:server:getRecords")
AddEventHandler("gw_policejob:server:getRecords", function(charid)
    local src = source
    MySQL.query("SELECT * FROM gw_police_records WHERE charidentifier = ? ORDER BY date DESC", {charid}, function(result)
        TriggerClientEvent("gw_policejob:client:receiveRecords", src, result)
    end)
end)

RegisterNetEvent("gw_policejob:server:addRecord")
AddEventHandler("gw_policejob:server:addRecord", function(data)
    local src = source
    local User = VORPcore.getUser(src)
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not isPolice(Character.job) then return end
    
    local officerName = Character.firstname .. " " .. Character.lastname
    local jailTime = tonumber(data.jail_time) or 0
    local jailLocation = (data.jail_location and data.jail_location ~= "None") and data.jail_location or "Valentine"
    local charid = tostring(data.charidentifier or data.charIdentifier or "")

    print("^3[gw_policejob] --- ADD RECORD ---^7")
    print("^3[gw_policejob] CID: " .. charid .. " | Time: " .. jailTime .. " | Loc: " .. jailLocation .. "^7")

    -- جلب اسم الشخص من قاعدة البيانات
    MySQL.query("SELECT firstname, lastname FROM characters WHERE charIdentifier = ? OR charidentifier = ?", {charid, charid}, function(charResult)
        local firstName = (charResult and charResult[1]) and charResult[1].firstname or _U('ui_unknown')
        local lastName = (charResult and charResult[1]) and charResult[1].lastname or ""

        if jailTime > 0 then
            local targetSrc = getPlayerSrcByCharId(charid)

            -- حفظ في جدول السجن
            MySQL.query("INSERT INTO gw_jail (charidentifier, jail_time, jail_location) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE jail_time = ?, jail_location = ?",
            {charid, jailTime, jailLocation, jailTime, jailLocation})

            if targetSrc and GetPlayerName(targetSrc) then
                print("^2[gw_policejob] Jailing player ID: " .. targetSrc .. "^7")
                TriggerClientEvent("gw_policejob:client:jailPlayer", targetSrc, jailTime, jailLocation)
                TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_jailed_success'), "success", 5000)
            else
                print("^3[gw_policejob] Target offline. Jail persisted in DB.^7")
                TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_jailed_pending'), "info", 5000)
            end
        end

        -- حفظ السجل الجنائي
        MySQL.insert(
            "INSERT INTO gw_police_records (charidentifier, firstname, lastname, officer_name, title, description, charges, jail_time, jail_location) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            {charid, firstName, lastName, officerName, data.title or "?", data.description or "", data.charges or "?", jailTime, jailLocation},
            function(id)
                if id then
                    print("^2[gw_policejob] Record saved. ID: " .. id .. "^7")
                    -- إرسال السجلات المحدثة للضابط تلقائياً
                    MySQL.query("SELECT * FROM gw_police_records WHERE charidentifier = ? ORDER BY date DESC", {charid}, function(records)
                        TriggerClientEvent("gw_policejob:client:receiveRecords", src, records or {})
                    end)
                    if jailTime <= 0 then
                        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_infraction_saved'), "success", 4000)
                    end
                else
                    print("^1[gw_policejob] ERROR: Could not save record!^7")
                    TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_infraction_error'), "error", 4000)
                end
            end
        )
    end)
end)

-- Auto-Jail on Login
AddEventHandler("vorp:SelectedCharacter", function(src, character)
    local charid = character.charIdentifier
    if not charid then return end
    
    MySQL.query("SELECT jail_time, jail_location FROM gw_jail WHERE charidentifier = ?", {charid}, function(result)
        if result and result[1] and result[1].jail_time > 0 then
            print("^3[gw_policejob] Citizen " .. character.firstname .. " is still in jail (Remaining: " .. result[1].jail_time .. " min). Sending to prison...^7")
            Citizen.Wait(5000) -- Wait for character to fully load
            TriggerClientEvent("gw_policejob:client:jailPlayer", src, result[1].jail_time, result[1].jail_location)
        end
    end)
end)

-- Decrement Jail Time
RegisterNetEvent("gw_policejob:server:updateJailTime")
AddEventHandler("gw_policejob:server:updateJailTime", function(remaining)
    local src = source
    local User = VORPcore.getUser(src)
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character then return end
    
    MySQL.query("UPDATE gw_jail SET jail_time = ? WHERE charidentifier = ?", {remaining, Character.charIdentifier})
    
    if remaining <= 0 then
        MySQL.query("DELETE FROM gw_jail WHERE charidentifier = ?", {Character.charIdentifier})
        print("^2[gw_policejob] Citizen " .. Character.firstname .. " has served their time.^7")
    end
end)

-- DEBUG COMMAND: /jailtest [ServerID] [Time] [Location]
RegisterCommand("jailtest", function(source, args)
    local targetId = tonumber(args[1])
    local time = tonumber(args[2]) or 1
    local location = args[3] or "Valentine"

    if not targetId then
        print("^1[gw_policejob] Usage: /jailtest [ServerID] [Time] [Location]^7")
        return
    end

    print("^3[gw_policejob] ADMIN: Manually jailing ID " .. targetId .. " for " .. time .. " mins in " .. location .. "^7")
    TriggerClientEvent("gw_policejob:client:jailPlayer", targetId, time, location)
end, false) -- Temporarily public for debug

RegisterNetEvent("gw_policejob:server:quickJail")
AddEventHandler("gw_policejob:server:quickJail", function(targetId, time, location)
    local src = source
    local User = VORPcore.getUser(src)
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not isPolice(Character.job) then return end

    local targetUser = VORPcore.getUser(targetId)
    local jailLoc = location or "Valentine"
    if targetUser then
        local targetChar = targetUser.getUsedCharacter
        local charid = targetChar.charIdentifier or targetChar.charid or targetChar.id

        print("^3[gw_policejob] --- QUICK JAIL TRIGGERED ---^7")
        print("^3[gw_policejob] Officer: " .. Character.firstname .. " jailed Player ID: " .. targetId .. " for " .. time .. " mins in " .. jailLoc .. ".^7")
        
        -- Persist to database for Quick Jail
        MySQL.query("INSERT INTO gw_jail (charidentifier, jail_time, jail_location) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE jail_time = ?, jail_location = ?", 
        {charid, time, jailLoc, time, jailLoc})

        TriggerClientEvent("gw_policejob:client:jailPlayer", targetId, time, jailLoc)
        TriggerClientEvent("gw_policejob:client:stopCarryCop", src)
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_jailed_instant', targetId), "success", 4000)
    else
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_no_player'), "error", 4000)
    end
end)

RegisterNetEvent("gw_policejob:server:getWarrants")
AddEventHandler("gw_policejob:server:getWarrants", function()
    local src = source
    -- COALESCE prioritization: Use warrant's historical image first, fallback to current character image
    local query = [[
        SELECT w.*, COALESCE(w.char_img, c.char_img) AS char_img 
        FROM gw_police_warrants w 
        LEFT JOIN characters c ON w.charidentifier = c.charidentifier 
        ORDER BY w.date DESC
    ]]
    MySQL.query(query, {}, function(result)
        TriggerClientEvent("gw_policejob:client:receiveWarrants", src, result)
    end)
end)

RegisterNetEvent("gw_policejob:server:addWarrant")
AddEventHandler("gw_policejob:server:addWarrant", function(data)
    local src = source
    local User = VORPcore.getUser(src)
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not isPolice(Character.job) then return end

    local issuerName = Character.firstname .. " " .. Character.lastname

    MySQL.insert("INSERT INTO gw_police_warrants (charidentifier, firstname, lastname, reason, issuer, char_img) VALUES (?, ?, ?, ?, ?, ?)", 
    {data.charidentifier, data.firstname, data.lastname, data.reason, issuerName, data.char_img}, function(id)
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_warrant_added'), "success", 4000)
    end)
end)

RegisterNetEvent("gw_policejob:server:deleteWarrant")
AddEventHandler("gw_policejob:server:deleteWarrant", function(warrantId)
    local src = source
    MySQL.query("DELETE FROM gw_police_warrants WHERE id = ?", {warrantId}, function()
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_warrant_deleted'), "success", 4000)
    end)
end)

RegisterNetEvent("gw_policejob:server:manageRank")
AddEventHandler("gw_policejob:server:manageRank", function(targetId, action, rankGrade)
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    
    print("^3[gw_policejob] Boss Manage Request from " .. src .. " | Target: " .. (targetId or "nil") .. " | Action: " .. (action or "nil") .. " | Grade: " .. (rankGrade or "nil") .. "^7")

    local myGrade = tonumber(Character.jobgrade or Character.jobGrade) or 0
    if not Config.BossGrades[myGrade] then
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_no_boss_rank'), "error", 4000)
        return
    end

    local TargetId = tonumber(targetId)
    if not TargetId then 
        print("^1[gw_policejob] Fail: Target ID is invalid!^7")
        return 
    end

    local TargetUser = VORPcore.getUser(TargetId)
    if TargetUser then
        local TargetChar = (type(TargetUser.getUsedCharacter) == 'function') and TargetUser.getUsedCharacter() or TargetUser.getUsedCharacter
        
        if action == "hire" or action == "promote" then
            local grade = tonumber(rankGrade) or 0
            if grade > 11 then grade = 11 end -- Cap at 11 per Config.Salaries
            
            -- Multi-method job setting for maximum compatibility
            pcall(function() TargetChar.setJob("police") end)
            pcall(function() TargetChar.setJobGrade(grade) end)
            pcall(function() TargetChar.setJob("police", grade) end) -- Modern VORP
            
            TriggerClientEvent("gw_policejob:client:notify", src, _U('rank_given'), "success", 4000)
            TriggerClientEvent("gw_policejob:client:notify", TargetId, _U('notify_rank_updated_target', grade), "success", 4000)
            print("^2[gw_policejob] Successfully promoted " .. TargetId .. " to grade " .. grade .. "^7")
            
        elseif action == "fire" then
            -- Multi-method job setting for firing
            pcall(function() TargetChar.setJob("none") end)
            pcall(function() TargetChar.setJobGrade(0) end)
            pcall(function() TargetChar.setJob("none", 0) end) -- Modern VORP
            
            TriggerClientEvent("gw_policejob:client:notify", src, _U('rank_removed'), "success", 4000)
            TriggerClientEvent("gw_policejob:client:notify", TargetId, _U('notify_fired_target'), "error", 4000)
            print("^1[gw_policejob] Successfully fired " .. TargetId .. "^7")
        end
    else
        TriggerClientEvent("gw_policejob:client:notify", src, _U('player_not_found'), "error", 4000)
        print("^1[gw_policejob] Manage failure: Target " .. TargetId .. " not found!^7")
    end
end)

-- ===== CUFF STATE MANAGEMENT =====
RegisterNetEvent("gw_policejob:server:setCuffed")
AddEventHandler("gw_policejob:server:setCuffed", function(targetId, isCuffed)
    local src = source
    local User = VORPcore.getUser(src)
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not isPolice(Character.job) then return end
    
    local targetId = tonumber(targetId)
    if not targetId then return end
    
    if isCuffed then
        CuffedPlayers[targetId] = src
        print("^3[gw_policejob] CUFF: Player " .. targetId .. " cuffed by officer " .. src .. "^7")
        TriggerClientEvent("gw_policejob:client:setCuffState", targetId, true)
        TriggerClientEvent("gw_policejob:client:notify", targetId, _U('notify_cuffed_target'), "error", 5000)
    else
        CuffedPlayers[targetId] = nil
        print("^3[gw_policejob] UNCUFF: Player " .. targetId .. " released by officer " .. src .. "^7")
        TriggerClientEvent("gw_policejob:client:setCuffState", targetId, false)
        TriggerClientEvent("gw_policejob:client:notify", targetId, _U('notify_uncuffed_target'), "success", 4000)
    end
end)

-- ===== SEARCH PLAYER INVENTORY =====
RegisterNetEvent("gw_policejob:server:searchPlayerInventory")
AddEventHandler("gw_policejob:server:searchPlayerInventory", function(targetId)
    local src = source
    local User = VORPcore.getUser(src)
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    
    if not isPolice(Character.job) then return end

    local targetId = tonumber(targetId)
    if not targetId then return end

    -- ===== CUFF CHECK: Only allow search if target is cuffed =====
    if not CuffedPlayers[targetId] then
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_must_be_cuffed'), "error", 5000)
        print("^1[gw_policejob] SEARCH DENIED: Target " .. targetId .. " is not cuffed!^7")
        return
    end

    print("^3[gw_policejob] SEARCH: Officer " .. src .. " searching cuffed Player " .. targetId .. "^7")

    -- Get target's character info
    local targetUser = VORPcore.getUser(targetId)
    if not targetUser then
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_target_offline'), "error", 4000)
        return
    end

    local targetChar = (type(targetUser.getUsedCharacter) == 'function') and targetUser.getUsedCharacter() or targetUser.getUsedCharacter
    if not targetChar then
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_data_error'), "error", 4000)
        return
    end
    
    local targetName = (targetChar.firstname or _U('ui_unknown')) .. " " .. (targetChar.lastname or "")
    local charId = tostring(targetChar.charIdentifier or targetChar.charidentifier or targetChar.id or "")
    
    print("^3[gw_policejob] SEARCH: Target CharID = " .. charId .. " | Name = " .. targetName .. "^7")

    -- Query the Boss VORP inventory table directly
    MySQL.query(
        "SELECT data FROM pos_inventory_players WHERE characterid = ? LIMIT 1",
        { charId },
        function(result)
            local items = {}
            
            if result and result[1] and result[1].data then
                -- DEBUG: Save raw JSON completely to analyze its structure
                SaveResourceFile(GetCurrentResourceName(), "dump_inv.json", result[1].data, -1)
                
                local ok, parsed = pcall(json.decode, result[1].data)
                if ok and type(parsed) == "table" then
                    -- Boss VORP stores data as: { mainInventory={items=[...]}, ammo={...}, thirdInventory={items=[...]} }
                    local searchMode = Config.SearchMode or "all"
                    
                    for sectionKey, sectionVal in pairs(parsed) do
                        if type(sectionVal) == "table" then
                            if sectionKey == "ammo" then
                                if searchMode == "all" or searchMode == "weapons" then
                                    -- Ammo is a key-value dictionary
                                    for ammoName, ammoQty in pairs(sectionVal) do
                                        if type(ammoQty) == "number" and ammoQty > 0 then
                                            table.insert(items, {
                                                name    = ammoName,
                                                label   = ammoName,
                                                amount  = ammoQty,
                                                type    = "item_ammo",
                                                slot    = ammoName,
                                                section = "ammo",
                                                uid     = ammoName,
                                                charId  = charId,
                                            })
                                        end
                                    end
                                end
                            elseif sectionVal.items and type(sectionVal.items) == "table" then
                                -- Core items (mainInventory, thirdInventory) are arrays inside the .items key
                                for _, itemObj in pairs(sectionVal.items) do
                                    if type(itemObj) == "table" then
                                        local name  = itemObj.item or itemObj.name or ""
                                        local label = itemObj.label or name
                                        local amount= tonumber(itemObj.quantity or itemObj.amount or itemObj.count or 1)
                                        local uid   = itemObj.id or itemObj.uid or itemObj.uniqueid or 0
                                        local slotKey = itemObj.slot or 0
                                        
                                        local itype = "item_standard"
                                        if string.find(name, "WEAPON_") then
                                            itype = "item_weapon"
                                        end
                                        
                                        local canAdd = false
                                        if searchMode == "all" then
                                            canAdd = true
                                        elseif searchMode == "weapons" and (itype == "item_weapon" or itype == "item_ammo") then
                                            canAdd = true
                                        elseif searchMode == "items" and itype == "item_standard" then
                                            canAdd = true
                                        end
                                        
                                        if name ~= "" and canAdd then
                                            table.insert(items, {
                                                name    = name,
                                                label   = label,
                                                amount  = amount,
                                                type    = itype,
                                                slot    = slotKey,
                                                section = sectionKey,
                                                uid     = uid,
                                                charId  = charId,
                                            })
                                        end
                                    end
                                end
                            end
                        end
                    end
                    print("^2[gw_policejob] SEARCH: Found " .. #items .. " items for " .. targetName .. "^7")
                else
                    print("^1[gw_policejob] SEARCH: JSON parse error for CharID " .. charId .. "^7")
                end
            else
                print("^3[gw_policejob] SEARCH: No row in pos_inventory_players for CharID=" .. charId .. "^7")
            end
            
            -- Send result to officer's NUI
            TriggerClientEvent("gw_policejob:client:openSearchResult", src, {
                targetName = targetName,
                targetId   = targetId,
                charId     = charId,
                items      = items,
                imagePath  = "nui://vorp_inventory/html/img/items/"
            })
        end
    )
    
    TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_searching', targetName), "success", 3000)
end)

-- DEBUG TOOL FOR INVENTORY JSON:
RegisterCommand("dumpinv", function(source, args)
    local src = source
    if src ~= 0 then return end -- Console only, or change it! Actually let's allow it for anyone so they can just type it in F8
    
    local targetId = tonumber(args[1])
    if not targetId then
        print("^1Syntax: /dumpinv [playerId]^7")
        return
    end
    
    local tUser = VORPcore.getUser(targetId)
    if not tUser then print("^1User not found^7") return end
    local tChar = (type(tUser.getUsedCharacter) == 'function') and tUser.getUsedCharacter() or tUser.getUsedCharacter
    local charId = tostring(tChar.charIdentifier or tChar.charidentifier or tChar.id or "")
    
    MySQL.query("SELECT data FROM pos_inventory_players WHERE characterid = ? LIMIT 1", {charId}, function(res)
        if res and res[1] then
            print("\n^3================ DUMP INV JSON FOR CHAR " .. charId .. " ================\n")
            print(res[1].data)
            print("\n========================================================================^7\n")
            
            -- Also save it just in case
            SaveResourceFile(GetCurrentResourceName(), "dump_inv_manual.json", res[1].data, -1)
        else
            print("^1NO ROW FOUND IN pos_inventory_players FOR CHAR " .. charId .. "^7")
        end
    end)
end, true)

-- ===== CONFISCATE ITEM FROM SEARCH =====
RegisterNetEvent("gw_policejob:server:confiscateItem")
AddEventHandler("gw_policejob:server:confiscateItem", function(targetId, itemData)
    local src = source
    local User = VORPcore.getUser(src)
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not isPolice(Character.job) then return end

    local targetId = tonumber(targetId)
    if not targetId or not itemData then return end

    -- Must still be cuffed
    if not CuffedPlayers[targetId] then
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_not_cuffed'), "error", 4000)
        return
    end

    local itemName   = itemData.name or ""
    local itemAmount = tonumber(itemData.takeAmount) or tonumber(itemData.amount) or 1
    local itemUid    = itemData.uid
    local isWeapon   = (itemData.type or ""):lower():find("weapon") ~= nil

    if itemName == "" then return end

    print("^3[gw_policejob] CONFISCATE: Officer " .. src .. " taking '" .. itemName .. "' x" .. itemAmount .. " from Player " .. targetId .. "^7")

    if isWeapon and itemUid and itemUid ~= 0 then
        -- Remove weapon by UID from target
        pcall(function() exports.vorp_inventory:subWeapon(targetId, itemUid) end)
        TriggerEvent("vorp:subWeapon", targetId, itemUid)
        -- Give weapon to officer (add new instance)
        pcall(function() exports.vorp_inventory:addWeapon(src, itemName, nil, nil) end)
        TriggerEvent("vorp:addWeapon", src, itemName)
        print("^2[gw_policejob] CONFISCATE: Weapon '" .. itemName .. "' transferred.^7")
    else
        -- Remove item from target
        pcall(function() exports.vorp_inventory:subItem(targetId, itemName, itemAmount) end)
        TriggerEvent("vorp:subItem", targetId, itemName, itemAmount)
        -- Give item to officer
        pcall(function() exports.vorp_inventory:addItem(src, itemName, itemAmount) end)
        TriggerEvent("vorp:addItem", src, itemName, itemAmount)
        print("^2[gw_policejob] CONFISCATE: Item '" .. itemName .. "' x" .. itemAmount .. " transferred.^7")
    end

    -- Notify both parties
    local officer = Character.firstname .. " " .. Character.lastname
    TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_confiscated') .. (itemData.label or itemName), "success", 4000)
    TriggerClientEvent("gw_policejob:client:notify", targetId, string.format(_U('notify_confiscated_from_you'), (itemData.label or itemName)), "error", 4000)

    -- Tell officer's NUI to remove or subtract the item from the panel
    TriggerClientEvent("gw_policejob:client:removeSearchItem", src, itemName, itemUid, itemAmount)
end)

local activePanics = {}

RegisterNetEvent("gw_policejob:server:panicButton")
AddEventHandler("gw_policejob:server:panicButton", function(coords)
    local src = source
    print("^3[gw_policejob] Server received panic from ID: " .. src .. "^7")
    local User = VORPcore.getUser(src)
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    local name = Character.firstname .. " " .. Character.lastname
    
    activePanics[src] = { coords = coords, time = os.time() }

    for _, player in ipairs(GetPlayers()) do
        local pUser = VORPcore.getUser(player)
        if pUser then
            local pChar = pUser.getUsedCharacter
            if isPolice(pChar.job) then
                print("^3[gw_policejob] Sending alert to officer: " .. player .. "^7")
                TriggerClientEvent("gw_policejob:client:panicAlert", player, coords, name)
            end
        end
    end

    -- Clear panic after 2 mins
    Citizen.SetTimeout(120000, function()
        activePanics[src] = nil
    end)
end)

-- Unified Duty Toggle Handler with Cooldown
RegisterNetEvent("gw_policejob:server:toggleDuty")
AddEventHandler("gw_policejob:server:toggleDuty", function(action)
    local src = source
    local currentTime = os.time()
    
    -- 2 Second Server-side cooldown per player
    if lastDutyRequest[src] and (currentTime - lastDutyRequest[src] < 2) then
        return 
    end
    lastDutyRequest[src] = currentTime

    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = User.getUsedCharacter
    if not Character then return end

    local currentJob = Character.job
    local currentGrade = Character.jobGrade or Character.jobgrade or 0
    local targetJob = ""
    local isGoingOnDuty = false

    -- Determine Logic based on action or current state
    if action == "on" then
        if currentJob:find("off") then
            targetJob = currentJob:gsub("off", "")
            isGoingOnDuty = true
        else
            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_already_on_duty'), "info", 3000)
            return
        end
    elseif action == "off" then
        if not currentJob:find("off") and (currentJob:find("police") or currentJob:find("sheriff")) then
            targetJob = "off" .. currentJob
            isGoingOnDuty = false
        else
            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_not_on_duty'), "info", 3000)
            return
        end
    else
        -- Toggle Logic (Fallback)
        if currentJob:find("off") then
            targetJob = currentJob:gsub("off", "")
            isGoingOnDuty = true
        else
            targetJob = "off" .. currentJob
            isGoingOnDuty = false
        end
    end

    if targetJob ~= "" then
        if not isGoingOnDuty then
            removeStandardKit(src)
            TriggerClientEvent("gw_policejob:client:stripWeapons", src)
            TriggerClientEvent("gw_policejob:client:removeDutyWeapons", src)
            TriggerClientEvent("gw_policejob:client:updateCopBlips", src, {})
            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_off_duty'), "error", 5000)
        else
            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_on_duty') .. targetJob, "success", 5000)
        end

        Character.setJob(targetJob)
        Character.setJobGrade(currentGrade)
        TriggerClientEvent("gw_policejob:client:setJob", src, targetJob)
        print("^2[gw_policejob] Duty Change: " .. Character.firstname .. " is now " .. targetJob .. "^7")
    end
end)

RegisterNetEvent("gw_policejob:server:requestDutyMenu")
AddEventHandler("gw_policejob:server:requestDutyMenu", function()
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = User.getUsedCharacter
    if not Character then return end

    local job = Character.job
    local allowedJobs = {"police", "sheriff", "offpolice", "offsheriff"}
    local isAllowed = false
    for _, v in ipairs(allowedJobs) do
        if v == job then isAllowed = true end
    end

    if isAllowed then
        TriggerClientEvent("gw_policejob:client:openDutyMenu", src, job)
    else
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_not_police'), "error", 4000)
    end
end)

-- Diagnostic Command to find weapon IDs (Use /checkinv in chat)
RegisterCommand("checkinv", function(source, args)
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character then return end
    
    print("^3[gw_policejob] --- DIAGNOSTIC SCAN START FOR ID: " .. src .. " ---^7")
    TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_frisk_watch_console'), "info", 5000)
    
    local chWeapons = {}
    pcall(function() chWeapons = (type(Character.getWeapons) == 'function') and Character.getWeapons() or (Character.getWeapons or {}) end)
    
    local invWeapons = nil
    pcall(function() invWeapons = exports.vorp_inventory:getUserWeapons(src) end)
    
    print("^2[gw_policejob] From Character Obj: " .. (chWeapons and type(chWeapons) == "table" and #chWeapons or "N/A") .. " items.^7")
    if chWeapons and type(chWeapons) == "table" then
        for i, w in pairs(chWeapons) do
             print("^5[Char] #" .. i .. " Model: " .. tostring(w.name or "N/A") .. " | UID: " .. tostring(w.id or w.weaponid or "N/A") .. " | Label: " .. tostring(w.label or "N/A") .. "^7")
        end
    end
    
    print("^2[gw_policejob] From Inventory Export: " .. (invWeapons and #invWeapons or 0) .. " items.^7")
    if invWeapons and type(invWeapons) == "table" then
        for i, w in pairs(invWeapons) do
             print("^5[Inv] #" .. i .. " Model: " .. tostring(w.name or "N/A") .. " | UID: " .. tostring(w.id or w.weaponid or "N/A") .. " | Label: " .. tostring(w.label or "N/A") .. "^7")
        end
    end
    print("^3[gw_policejob] --- DIAGNOSTIC SCAN END ---^7")
end, false)

-- Helper to remove all kit items/weapons (MASTER CLEANUP)
function removeStandardKit(src)
    -- We do NOT remove weapons from the inventory here anymore,
    -- because the Standard Kit is now delivered virtually to the ped.
    -- If we aggressively remove weapons from their DB here, they will lose
    -- any personal weapons they legally bought.
    -- The client handles physically removing the virtual weapons from the ped.
    print("^2[gw_policejob] Notice: removeStandardKit called, relying purely on client-side native strip.^7")
end

-- Armory Standard Kit Claim (One-Click Fulfillment)
RegisterNetEvent("gw_policejob:server:claimStandardKit")
AddEventHandler("gw_policejob:server:claimStandardKit", function()
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    
    if not isPolice(Character.job) then
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_not_police'), "error", 4000)
        return
    end

    -- Trigger client to give weapons directly (No physical items in inventory)
    TriggerClientEvent("gw_policejob:client:giveStandardKit", src)
    
    print("^2[gw_policejob] Virtual Kit Delivered to " .. src .. "^7")
    TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_kit_received'), "success", 5000)
end)


-- Command to open MDT
RegisterCommand("policemdt", function(source, args, rawCommand)
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character then return end
    
    local function isPoliceOnDuty(job)
        if not job then return false end
        local j = tostring(job):lower()
        if j:find("off") then return false end
        return j:find("police") or j:find("sheriff")
    end

    if isPoliceOnDuty(Character.job) then
        local myGrade = tonumber(Character.jobgrade or Character.jobGrade) or 0
        local isBoss = Config.BossGrades[myGrade] or false
        local gradeLabel = (Config.Salaries[myGrade] and Config.Salaries[myGrade].label) or _U('ui_job_prefix') .. myGrade
        
        -- Get Name
        local fullName = Character.firstname .. " " .. Character.lastname
        print("^2[gw_policejob] Server: Authorizing MDT for " .. fullName .. "^7")
        
        TriggerClientEvent("gw_policejob:client:openMDT", src, isBoss, fullName, gradeLabel)
    else
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_must_be_on_duty'), "error", 4000)
    end
end, false)

-- Police Blips Location Broadcaster
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(3000) -- Refresh every 3 seconds
        local cops = {}
        
        -- Gather all active police
        for _, player in ipairs(GetPlayers()) do
            local User = VORPcore.getUser(player)
            if User then
                local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
                if Character and isPolice(Character.job) then
                    local ped = GetPlayerPed(player)
                    if DoesEntityExist(ped) then
                        local gradeId = 0
                        if Character.jobgrade then gradeId = tonumber(Character.jobgrade)
                        elseif Character.jobGrade then gradeId = tonumber(Character.jobGrade)
                        elseif Character.grade then gradeId = tonumber(Character.grade)
                        elseif Character.getJobGrade then gradeId = tonumber(Character.getJobGrade()) end
                        gradeId = gradeId or 0
                        
                        local rankLabel = "Officer"
                        if Config.Salaries and Config.Salaries[gradeId] then
                            rankLabel = Config.Salaries[gradeId].label
                        else
                            rankLabel = "Officer " .. gradeId
                        end

                        table.insert(cops, {
                            src = tonumber(player),
                            coords = GetEntityCoords(ped),
                            name = Character.firstname .. " " .. Character.lastname,
                            rank = rankLabel,
                            isPanic = (activePanics[tonumber(player)] ~= nil)
                        })
                    end
                end
            end
        end

        -- Broadcast to all cops
        for _, cop in ipairs(cops) do
            TriggerClientEvent("gw_policejob:client:updateCopBlips", cop.src, cops)
        end
    end
end)

-- Police Interaction Menu Features
RegisterNetEvent("gw_policejob:server:putInVehicle")
AddEventHandler("gw_policejob:server:putInVehicle", function(targetId, netId)
    local src = source
    local User = VORPcore.getUser(src)
    if not User or not targetId then return end
    local Character = User.getUsedCharacter
    
    if isPolice(Character.job) then
        print("^2[gw_policejob] Server: Placing ID " .. targetId .. " into Vehicle NetID: " .. tostring(netId) .. "^7")
        TriggerClientEvent("gw_policejob:client:putInVehicle", targetId, netId)
        TriggerClientEvent("gw_policejob:client:stopCarryCop", src)
    end
end)

RegisterNetEvent("gw_policejob:server:takeOutVehicle")
AddEventHandler("gw_policejob:server:takeOutVehicle", function(targetId)
    local src = source
    local User = VORPcore.getUser(src)
    if not User or not targetId then return end
    local Character = User.getUsedCharacter
    
    if isPolice(Character.job) then
        TriggerClientEvent("gw_policejob:client:takeOutVehicle", targetId)
    end
end)
RegisterNetEvent("gw_policejob:server:requestArmory")
AddEventHandler("gw_policejob:server:requestArmory", function()
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character then return end

    if isPolice(Character.job) then
        if tostring(Character.job):find("off") then
            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_armory_on_duty'), "error", 4000)
            return
        end

        local grade = tonumber(Character.jobGrade or Character.jobgrade) or 0
        local rankLabel = (Config.Salaries[grade] and Config.Salaries[grade].label) or "Officer"
        
        TriggerClientEvent("gw_policejob:client:sendToNUI", src, {
            action = "openArmory",
            items = Config.Armory.items,
            imagePath = Config.Armory.imagePath,
            resourceName = GetCurrentResourceName(),
            officerRank = rankLabel,
            gradeId = grade,
            isVehicles = false,
            colors = Config.UIColors
        })
    end
end)

RegisterNetEvent("gw_policejob:server:requestVehicleMenu")
AddEventHandler("gw_policejob:server:requestVehicleMenu", function()
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character then return end

    if isPolice(Character.job) then
        if tostring(Character.job):find("off") then
            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_veh_on_duty'), "error", 4000)
            return
        end

        local grade = tonumber(Character.jobGrade or Character.jobgrade) or 0
        local rankLabel = (Config.Salaries[grade] and Config.Salaries[grade].label) or "Officer"
        
        TriggerClientEvent("gw_policejob:client:sendToNUI", src, {
            action = "openArmory", -- Reuse UI logic for vehicles
            heavyVehicles = Config.Vehicles,
            imagePath = Config.Armory.imagePath,
            resourceName = GetCurrentResourceName(),
            officerRank = rankLabel,
            gradeId = grade,
            isVehicles = true,
            colors = Config.UIColors
        })
    end
end)

RegisterNetEvent("gw_policejob:server:spawnVehicle")
AddEventHandler("gw_policejob:server:spawnVehicle", function(model)
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    
    local grade = tonumber(Character.jobGrade or Character.jobgrade) or 0
    if grade >= Config.Armory.HeavyVehicles.minRank then
        print("^2[gw_policejob] Server: Rank Verification PASSED. Deploying " .. model .. " for " .. Character.firstname .. "^7")
        TriggerClientEvent("gw_policejob:client:spawnVehicle", src, model)
    else
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_veh_rank_low'), "error", 4000)
    end
end)

RegisterNetEvent("gw_policejob:server:requestPoliceMenu")
AddEventHandler("gw_policejob:server:requestPoliceMenu", function()
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character then return end

    if isPolice(Character.job) then
        TriggerClientEvent("gw_policejob:client:openPoliceMenu", src)
    else
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_no_access'), "error", 4000)
    end
end)

RegisterNetEvent("gw_policejob:server:toggleCuff")
AddEventHandler("gw_policejob:server:toggleCuff", function(targetId)
    local src = source
    local TargetId = tonumber(targetId)
    if not TargetId or TargetId == 0 then return end

    -- Explicit State Tracking
    CuffedPlayers[TargetId] = not (CuffedPlayers[TargetId] or false)
    local isCuffing = CuffedPlayers[TargetId]

    print("^3[gw_policejob] SERVER: Force SET CUFF STATE to " .. tostring(isCuffing) .. " for Target ID: " .. TargetId .. "^7")
    
    -- 1. Targeted Event (Explicit State)
    TriggerClientEvent("gw_policejob:client:setCuffState", TargetId, isCuffing)
    
    -- 2. Redundant Global Pulse (Explicit State)
    TriggerClientEvent("gw_policejob:client:globalPulseCuff", -1, TargetId, isCuffing)
    
    -- 3. Notify Requestor
    local msg = isCuffing and _U('notify_cuff_sent', TargetId) or _U('notify_uncuff_sent', TargetId)
    TriggerClientEvent("gw_policejob:client:notify", src, msg, "success", 3000)
end)

RegisterNetEvent("gw_policejob:server:setCuffed")
AddEventHandler("gw_policejob:server:setCuffed", function(targetId, state)
    local src = source
    local TargetId = tonumber(targetId)
    if not TargetId or TargetId == 0 then return end

    -- Explicit State Tracking
    CuffedPlayers[TargetId] = state
    local isCuffing = state

    print("^3[gw_policejob] SERVER: Force SET CUFF STATE to " .. tostring(isCuffing) .. " for Target ID: " .. TargetId .. "^7")
    
    -- 1. Targeted Event (Explicit State)
    TriggerClientEvent("gw_policejob:client:setCuffState", TargetId, isCuffing)
    
    -- 2. Redundant Global Pulse (Explicit State)
    TriggerClientEvent("gw_policejob:client:globalPulseCuff", -1, TargetId, isCuffing)
    
    -- 3. Notify Requestor
    local msg = isCuffing and _U('notify_cuff_sent', TargetId) or _U('notify_uncuff_sent', TargetId)
    TriggerClientEvent("gw_policejob:client:notify", src, msg, "success", 3000)
end)

-- Admin Force Cuff Command (Server-side)
RegisterCommand("cuff", function(source, args)
    local src = source
    local User = VORPcore.getUser(src)
    local Character = User.getUsedCharacter
    
    if isPolice(Character.job) then
        local target = tonumber(args[1])
        if target then
            print("^3[gw_policejob] ADMIN CUFF: " .. src .. " is cuffing " .. target .. "^7")
            -- Use the server-side toggle logic to keep state in sync
            local TargetId = target
            CuffedPlayers[TargetId] = not (CuffedPlayers[TargetId] or false)
            local isCuffing = CuffedPlayers[TargetId]
            TriggerClientEvent("gw_policejob:client:setCuffState", TargetId, isCuffing)
        else
            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_id_required'), "error", 3000)
        end
    end
end, false)

RegisterNetEvent("gw_policejob:server:escortPlayer")
AddEventHandler("gw_policejob:server:escortPlayer", function(targetId)
    local src = source
    local TargetId = tonumber(targetId)
    if not TargetId then return end

    -- Realism: Only allow dragging if cuffed
    if not CuffedPlayers[TargetId] then
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_escort_cuff_required'), "error", 4000)
        return
    end

    TriggerClientEvent("gw_policejob:client:toggleEscort", TargetId, src)
    TriggerClientEvent("gw_policejob:client:toggleCarryCop", src, TargetId)
end)


RegisterNetEvent("gw_policejob:server:finePlayer")
AddEventHandler("gw_policejob:server:finePlayer", function(targetId, amount, reason)
    local src = source
    local User = VORPcore.getUser(src)
    local Target = VORPcore.getUser(targetId)
    if Target then
        local TargetChar = Target.getUsedCharacter
        local myChar = User.getUsedCharacter
        TargetChar.removeCurrency(0, tonumber(amount))
        
        TriggerClientEvent("gw_policejob:client:notify", targetId, _U('notify_fined_target', amount, reason), "error", 5000)
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_fined_success'), "success", 5000)
        
        -- Add record to DB
        local officerName = myChar.firstname .. " " .. myChar.lastname
        MySQL.insert("INSERT INTO gw_police_records (charidentifier, firstname, lastname, officer_name, title, description, charges, jail_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", 
        {TargetChar.charIdentifier, TargetChar.firstname, TargetChar.lastname, officerName, _U('ui_fine_instant_record'), reason, _U('ui_fine_instant_desc', amount), 0})
    end
end)

RegisterNetEvent("gw_policejob:server:checkWanted")
AddEventHandler("gw_policejob:server:checkWanted", function(targetId)
    local src = source
    local Target = VORPcore.getUser(targetId)
    if Target then
        local TargetChar = Target.getUsedCharacter
        MySQL.query("SELECT * FROM gw_police_warrants WHERE charidentifier = ?", {TargetChar.charIdentifier}, function(result)
            if #result > 0 then
                TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_wanted_warning'), "error", 8000)
                TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_wanted_details', result[1].reason), "error", 8000)
            else
                TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_clean_record'), "success", 5000)
            end
        end)
    end
end)

RegisterNetEvent("gw_policejob:server:sendMessage")
AddEventHandler("gw_policejob:server:sendMessage", function(targetId, message)
    local src = source
    local User = VORPcore.getUser(src)
    local Target = VORPcore.getUser(tonumber(targetId))
    
    if User and Target then
        local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
        local name = Character.firstname .. " " .. Character.lastname
        
        TriggerClientEvent("gw_policejob:client:notify", tonumber(targetId), _U('notify_msg_received', name, message), "info", 10000)
    end
end)

RegisterNetEvent("gw_policejob:server:giveFine")
AddEventHandler("gw_policejob:server:giveFine", function(targetId, amount, reason)
    local src = source
    local PoliceUser = VORPcore.getUser(src)
    local CitizenUser = VORPcore.getUser(tonumber(targetId))
    
    if PoliceUser and CitizenUser then
        local PoliceChar = (type(PoliceUser.getUsedCharacter) == 'function') and PoliceUser.getUsedCharacter() or PoliceUser.getUsedCharacter
        local CitizenChar = (type(CitizenUser.getUsedCharacter) == 'function') and CitizenUser.getUsedCharacter() or CitizenUser.getUsedCharacter
        
        amount = tonumber(amount)
        CitizenChar.removeCurrency(0, amount) -- 0 = Money/Cash
        
        local policeName = PoliceChar.firstname .. " " .. PoliceChar.lastname
        local citizenName = CitizenChar.firstname .. " " .. CitizenChar.lastname
        
        -- Notify Police
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_fine_issued_success', amount, citizenName), "success")
        
        -- Notify Citizen
        TriggerClientEvent("gw_policejob:client:notify", tonumber(targetId), _U('notify_fine_received', amount, reason, policeName), "warning", 8000)
        
        -- Link to Criminal Records (MDT)
        local citizenCID = CitizenChar.charIdentifier or CitizenChar.charid or CitizenChar.id
        if not citizenCID and CitizenChar.getCharIdentifier then citizenCID = CitizenChar.getCharIdentifier() end
        
        if citizenCID then
            print("^3[gw_policejob] DB DEBUG: Attempting to add fine record for CID: " .. tostring(citizenCID) .. "^7")
            MySQL.insert("INSERT INTO gw_police_records (charidentifier, firstname, lastname, officer_name, title, description, charges, jail_time, jail_location) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", 
                {tostring(citizenCID), CitizenChar.firstname, CitizenChar.lastname, policeName, _U('ui_fine_record_title'), reason, _U('ui_fine_record_desc', amount), 0, "None"},
                function(insertedId)
                    if insertedId then
                        print("^2[gw_policejob] DB SUCCESS: Fine record added for " .. citizenName .. " (Record ID: " .. insertedId .. ")^7")
                    else
                        print("^1[gw_policejob] DB ERROR: Failed to insert fine record for " .. citizenName .. "^7")
                    end
                end
            )
        else
            print("^1[gw_policejob] ERROR: Could not find CID for citizen " .. citizenName .. ". Record NOT added.^7")
        end
        
        print("^2[gw_policejob] Fine Issued: ^7" .. policeName .. " fined " .. citizenName .. " $" .. amount .. " for " .. reason)
    end
end)

-- Helper: Get Player Source by Character Identifier (charIdentifier)
local function getPlayerSrcByCharId(charid)
    local players = GetPlayers()
    for _, pSrc in ipairs(players) do
        local tSrc = tonumber(pSrc)
        local tUser = VORPcore.getUser(tSrc)
        if tUser then
            local tChar = (type(tUser.getUsedCharacter) == 'function') and tUser.getUsedCharacter() or tUser.getUsedCharacter
            if tChar then
                local cid = tChar.charIdentifier or tChar.charid or tChar.id
                if not cid and tChar.getCharIdentifier then cid = tChar.getCharIdentifier() end
                
                if cid and tostring(cid) == tostring(charid) then
                    return tSrc
                end
            end
        end
    end
    return nil
end

-- Boss Menu: Get ALL officers (Online & Offline) from Database
-- Boss Menu: Get ALL officers (Online & Offline) from Database
RegisterNetEvent("gw_policejob:server:getBossOfficers")
AddEventHandler("gw_policejob:server:getBossOfficers", function()
    local src = source
    TriggerEvent("gw_policejob:server:getBossOfficers_Internal", src)
end)

-- Internal handler to allow triggering from other server events
RegisterNetEvent("gw_policejob:server:getBossOfficers_Internal")
AddEventHandler("gw_policejob:server:getBossOfficers_Internal", function(targetSrc)
    local src = targetSrc
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character then return end
    
    -- Safety: Only allow police bosses
    local myGrade = tonumber(Character.jobgrade or Character.jobGrade) or 0
    
    if not isPolice(Character.job) or not Config.BossGrades[myGrade] then 
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_no_roster_access'), "error", 4000)
        return 
    end
    
    -- Query all police from DB
    local jobList = "('police', 'sheriff')"
    if Config.PoliceJobs and #Config.PoliceJobs > 0 then
        jobList = "("
        for i, v in ipairs(Config.PoliceJobs) do
            jobList = jobList .. "'" .. v .. "'" .. (i == #Config.PoliceJobs and "" or ", ")
        end
        jobList = jobList .. ")"
    end

    MySQL.query("SELECT charIdentifier, firstname, lastname, job, jobgrade FROM characters WHERE job IN " .. jobList .. " ORDER BY jobgrade DESC", {}, function(results)
        local officers = {}
        local onlinePlayers = GetPlayers()
        
        for _, row in ipairs(results or {}) do
            local status = "Offline"
            local currentSrc = 0
            local liveGrade = nil
            
            -- Check if online
            for _, pSrc in ipairs(onlinePlayers) do
                local tSrc = tonumber(pSrc)
                local tUser = VORPcore.getUser(tSrc)
                if tUser then
                    local tChar = (type(tUser.getUsedCharacter) == 'function') and tUser.getUsedCharacter() or tUser.getUsedCharacter
                    if tChar then
                        local cid = tChar.charIdentifier or tChar.charid or tChar.id
                        if not cid and tChar.getCharIdentifier then cid = tChar.getCharIdentifier() end
                        
                        -- Match using charIdentifier from DB
                        if cid and tostring(cid) == tostring(row.charIdentifier) then
                            status = "Online"
                            currentSrc = tSrc
                            -- Use live rank if online
                            liveGrade = tonumber(tChar.jobgrade or tChar.jobGrade)
                            if not liveGrade and tChar.getJobGrade then liveGrade = tChar.getJobGrade() end
                            break
                        end
                    end
                end
            end

            local gId = liveGrade or tonumber(row.jobgrade) or 0
            local gLabel = (Config.Salaries[gId] and Config.Salaries[gId].label) or _U('ui_job_prefix') .. gId

            table.insert(officers, {
                charid = row.charIdentifier,
                src = currentSrc,
                name = row.firstname .. " " .. row.lastname,
                job = row.job,
                grade = gLabel,
                gradeId = gId,
                status = status
            })
        end

        TriggerClientEvent("gw_policejob:client:sendToNUI", src, {
            action = "bossOfficersResults",
            players = officers
        })
    end)
end)

-- Promote / Fire Management
RegisterNetEvent("gw_policejob:server:manageRank")
AddEventHandler("gw_policejob:server:manageRank", function(data)
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    
    -- Check Boss Permission
    local myGrade = tonumber(Character.jobgrade or Character.jobGrade) or 0
    if not isPolice(Character.job) or not Config.BossGrades[myGrade] then return end

    local targetCharId = data.charid -- Keep as string for DB matching
    local action = data.action -- 'promote', 'fire', or 'hire'
    
    if action == 'hire' then
        local tSrc = tonumber(data.targetSrc)
        local tGrade = tonumber(data.rankGrade)
        if tSrc and tGrade then
            local tUser = VORPcore.getUser(tSrc)
            if tUser then
                local tChar = (type(tUser.getUsedCharacter) == 'function') and tUser.getUsedCharacter() or tUser.getUsedCharacter
                if tChar then
                    local primaryJob = "police"
                    if Config.PoliceJobs and #Config.PoliceJobs > 0 then primaryJob = Config.PoliceJobs[1] end
                    
                    tChar.setJob(primaryJob)
                    tChar.setJobGrade(tGrade)
                    
                    local tCID = tChar.charIdentifier or tChar.charid or tChar.id
                    if not tCID and tChar.getCharIdentifier then tCID = tChar.getCharIdentifier() end
                    
                    if tCID then
                        -- Direct SQL update to ensure immediate visibility in the roster
                        MySQL.update("UPDATE characters SET job = ?, jobgrade = ? WHERE charIdentifier = ?", {primaryJob, tGrade, tostring(tCID)}, function(affected)
                            print("^2[gw_policejob] DB: Hired " .. tChar.firstname .. " " .. tChar.lastname .. " - DB Sync'd.^7")
                            -- Refresh Boss UI after DB confirmation
                            TriggerEvent("gw_policejob:server:getBossOfficers_Internal", src)
                        end)
                    else
                        -- Fallback if CID not found (shouldn't happen with VORP)
                        Citizen.SetTimeout(500, function()
                            TriggerEvent("gw_policejob:server:getBossOfficers_Internal", src)
                        end)
                    end
                    
                    TriggerClientEvent("gw_policejob:client:notify", tSrc, _U('notify_hired_target', (Config.Salaries[tGrade] and Config.Salaries[tGrade].label or tGrade)), "success", 10000)
                    TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_hired_success', tChar.firstname, tChar.lastname), "success", 4000)
                end
            else
                TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_invalid_id'), "error", 4000)
            end
        end
        return
    end

    if not targetCharId then return end
    
    if action == 'promote' then
        local newGrade = math.min(11, tonumber(data.currentGrade or 0) + 1)
        -- Update DB
        MySQL.update("UPDATE characters SET jobgrade = ? WHERE charIdentifier = ?", {newGrade, targetCharId}, function(affected)
            if affected > 0 then
                TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_promoted_success'), "success", 4000)
                -- If online, update character object
                local tSrc = getPlayerSrcByCharId(targetCharId)
                if tSrc then
                    local TargetUser = VORPcore.getUser(tSrc)
                    local TargetChar = (type(TargetUser.getUsedCharacter) == 'function') and TargetUser.getUsedCharacter() or TargetUser.getUsedCharacter
                    if TargetChar then
                        TargetChar.setJobGrade(newGrade)
                        TriggerClientEvent("gw_policejob:client:notify", tSrc, _U('notify_promoted_target', (Config.Salaries[newGrade] and Config.Salaries[newGrade].label or newGrade)), "info", 8000)
                    end
                end
                -- Refresh Boss UI
                TriggerEvent("gw_policejob:server:getBossOfficers_Internal", src)
            end
        end)
    elseif action == 'fire' then
        -- Update DB
        MySQL.update("UPDATE characters SET job = 'unemployed', jobgrade = 0 WHERE charIdentifier = ?", {targetCharId}, function(affected)
            if affected > 0 then
                TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_fired_success'), "error", 4000)
                -- If online, update character object
                local tSrc = getPlayerSrcByCharId(targetCharId)
                if tSrc then
                    local TargetUser = VORPcore.getUser(tSrc)
                    local TargetChar = (type(TargetUser.getUsedCharacter) == 'function') and TargetUser.getUsedCharacter() or TargetUser.getUsedCharacter
                    if TargetChar then
                        TargetChar.setJob('unemployed')
                        TargetChar.setJobGrade(0)
                        TriggerClientEvent("gw_policejob:client:notify", tSrc, _U('notify_fired_target'), "error", 10000)
                    end
                end
                -- Refresh Boss UI
                TriggerEvent("gw_policejob:server:getBossOfficers_Internal", src)
            end
        end)
    end
end)

RegisterNetEvent("gw_policejob:server:syncInit")
AddEventHandler("gw_policejob:server:syncInit", function()
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    local Character = User.getUsedCharacter
    if Character then
        TriggerClientEvent("gw_policejob:client:setJob", src, Character.job)
    end
end)

-- ==========================================
-- POLICE SALARY SYSTEM (12 RANKS)
-- ==========================================
local playerSalaryTimers = {}

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000) -- Tick every 1 minute
        local players = GetPlayers()
        
        for _, playerId in ipairs(players) do
            local src = tonumber(playerId)
            local User = VORPcore.getUser(src)
            
            if User then
                local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
                
                if Character and isPolice(Character.job) then
                    local grade = tonumber(Character.jobGrade or Character.jobgrade) or 0
                    local salaryConfig = Config.Salaries[grade]
                    
                    if salaryConfig then
                        -- Initialize timer if not exists for this session
                        if not playerSalaryTimers[src] then
                            playerSalaryTimers[src] = salaryConfig.interval
                        end
                        
                        -- Decrement minutes remaining
                        playerSalaryTimers[src] = playerSalaryTimers[src] - 1
                        
                        if playerSalaryTimers[src] <= 0 then
                            -- PAYOUT TIME!
                            Character.addCurrency(0, salaryConfig.amount) -- 0: Cash/Bank dependent on VORP config
                            
                            -- Notify Player
                            TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_salary_received', salaryConfig.amount), "success", 5000)
                            
                            -- Reset Timer to full interval
                            playerSalaryTimers[src] = salaryConfig.interval
                            print("^2[gw_policejob] Salary Paid: $" .. salaryConfig.amount .. " to " .. Character.firstname .. " (Rank: " .. (salaryConfig.label or grade) .. ")^7")
                        end
                    end
                else
                    -- Cleanup if they are no longer police
                    playerSalaryTimers[src] = nil
                end
            end
        end
    end
end)

-- Cleanup when player leaves
AddEventHandler('playerDropped', function()
    local src = source
    playerSalaryTimers[src] = nil
end)

RegisterNetEvent("gw_policejob:server:spawnVehicle")
AddEventHandler("gw_policejob:server:spawnVehicle", function(model)
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    
    local Character = (type(User.getUsedCharacter) == 'function') and User.getUsedCharacter() or User.getUsedCharacter
    if not Character then return end
    
    -- التحقق من الرتبة
    local grade = tonumber(Character.jobgrade or Character.jobGrade) or 0
    local minRank = (Config.Vehicles and Config.Vehicles.minRank) or 4
    if grade < minRank then
        TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_veh_rank_required', minRank), "error", 4000)
        return
    end

    -- إرسال الأمر للكلاينت لإنشاء العربة
    TriggerClientEvent("gw_policejob:client:spawnVehicle", src, model)
    print("^2[gw_policejob] Strategic Support: Officer " .. Character.firstname .. " requested " .. model .. "^7")
    TriggerClientEvent("gw_policejob:client:notify", src, _U('notify_veh_en_route_server'), "success", 4000)
end)
