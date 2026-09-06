POLICE_NPCS = {
    {
        ped = "s_m_m_dispatchleaderpolice_01",
        x = -278.3875,
        y = 806.3165,
        z = 119.3921,
        heading = 243.3754,
        blip = -693644997
    }
}

Config = {
    InteractionDistance = 3.5,
    Key = 0x760A9C6F, -- Key 'G' (INPUT_CONTEXT)

    -- Handcuff Settings
    CuffKey = 0x805B4AEA, -- Key 'L'
    CuffDistance = 5.0,

    -- UI Duty Pill Settings
    EnableDutyPill = true,
    DutyPillText = "Sheriff On Duty",

    -- Permanently Locked Doors (Add door hashes here)
    LockedDoors = {
        295355979, -- Valentine Cell 1
        193903155  -- Valentine Cell 2
    },

    -- Jail Cell Locations (Teleport targets when using "Put in Jail")
    JailCells = {
        {
            id = 1,
            name = "Cell 1",
            coords = vector4(-271.5404, 807.2687, 119.3828, 80.5136)
        },
        {
            id = 2,
            name = "Cell 2",
            coords = vector4(-274.5190, 811.2169, 119.3842, 235.0658)
        }
    }
}
