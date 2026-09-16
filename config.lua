POLICE_NPCS = {
    {
        ped = "s_m_m_dispatchleaderpolice_01",
        x = -278.3875,
        y = 806.3165,
        z = 118.3921,
        heading = 243.3754,
        blip = -693644997,
        blipLabel = "Sheriff Office",
        dutyOnly = false -- Available at all times to go on/off duty
    },
    {
        ped = "cs_mrsadler", -- Police Lady / Reinforcement (Sadie Adler)
        x = -270.1339,
        y = 805.1387,
        z = 119.3438,
        heading = 197.9014,
        blip = -480291173,
        blipLabel = "Sheriff Reinforcement",
        dutyOnly = true -- Visible to on-duty sheriffs only
    }
}

Config = {
    -- Only characters with one of these VORP jobs can use police functions.
    PoliceJobs = {
        Police = true,
        Sheriff = true
    },

    InteractionDistance = 3.5,
    Key = 0x760A9C6F, -- Key 'G' (INPUT_CONTEXT)

    -- Handcuff Settings
    CuffKey = 0x805B4AEA, -- Key 'L'
    CuffDistance = 5.0,

    -- UI Duty Pill Settings
    EnableDutyPill = true,
    DutyPillText = "Sheriff On Duty",

    -- Cell Doors Array (On-Duty Sheriff toggles Lock/Unlock with Key 'K')
    LockedDoors = {
        { doorHash = 295355979, coords = vector3(-273.464, 809.966, 118.368), name = "Valentine Cell 1" },
        { doorHash = 193903155, coords = vector3(-272.052, 808.258, 118.369), name = "Valentine Cell 2" }
    },

    -- Jail Cell Locations (Teleport targets when using "Put in Jail")
    JailCells = {
        {
            id = 1,
            name = "Cell 1",
            coords = vector4(-271.5404, 807.2687, 118.3828, 80.5136)
        },
        {
            id = 2,
            name = "Cell 2",
            coords = vector4(-274.5190, 811.2169, 118.3842, 235.0658)
        }
    },

    -- Sheriff Stash / Locker Settings
    SheriffStash = {
        id = "coi_police_sheriff_locker",
        name = "Sheriff Locker",
        limit = 700,
        coords = vector3(-277.0092, 811.1743, 119.5367),
        heading = 100.2950,
        key = 0x760A9C6F -- Key 'G'
    }
}
