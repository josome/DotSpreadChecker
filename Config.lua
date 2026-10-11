local addonName, ns = ...

-- One profile per supported specialization, keyed by SpecializationID (not
-- the spec index). A square turns red only when every spell in `spells` is
-- present on the enemy, so list exactly the DoTs that should be spread.
ns.PROFILES = {
    [265] = { class = "WARLOCK",     spells = { 980 } },           -- Affliction: Agony
    [256] = { class = "PRIEST",      spells = { 589 } },           -- Discipline: Shadow Word: Pain
    [258] = { class = "PRIEST",      spells = { 34914, 589 } },    -- Shadow: Vampiric Touch + Shadow Word: Pain
    [63]  = { class = "MAGE",        spells = { 12654 } },         -- Fire: Ignite
    [252] = { class = "DEATHKNIGHT", spells = { 191587 } },        -- Unholy: Virulent Plague
    [259] = { class = "ROGUE",       spells = { 1943, 703 } },     -- Assassination: Rupture + Garrote
    [71]  = { class = "WARRIOR",     spells = { 388539 } },        -- Arms: Rend
    [263] = { class = "SHAMAN",      spells = { 188389 } },        -- Enhancement: Flame Shock
    [102] = { class = "DRUID",       spells = { 164812, 164815 } }, -- Balance: Moonfire + Sunfire
    [103] = { class = "DRUID",       spells = { 155722, 1079 } },  -- Feral: Rake + Rip
}

-- Set by Tracker to the profile of the current spec, or nil when none applies.
ns.TRACKED_SPELLS = nil

local defaults = {
    locked      = true,
    -- Top-left corner of the grid, in UIParent coordinates from the
    -- bottom-left of the screen. nil means "not placed yet"; Display.lua picks
    -- a default that suits the current resolution. The grid always grows right
    -- and then down from here, so the anchor never moves as enemies come and go.
    x           = nil,
    y           = nil,
    squareSize  = 16,
    squareGap   = 4,
    -- Squares per row; the grid wraps onto a new row below after this many.
    columns     = 8,
    -- Only enemies that are actually fighting get a square. Idle nameplates
    -- within range can never turn red, so they would only pad the grid.
    combatOnly  = true,
    -- Paint squares with an applied DoT in the player's class colour instead of red.
    classColor  = true,
    -- Opt-in: swipe on applied squares showing the DoT's remaining time.
    swipeOptIn = false,
    -- Opt-in: white inner frame while the DoT is in its pandemic (refresh) window.
    pandemicFrame = false,
    -- [specID] = { [spellID] = true } for DoTs the player opted out of.
    disabledSpells = {},
    dbVersion   = 0,
    minimap     = { hide = false },
    debug       = false,
}

-- Layout is saved per character (SavedVariablesPerCharacter), so each
-- character keeps its own grid position, square size and row width. A new
-- character starts from these defaults.
local CHAR_KEYS = { x = true, y = true, squareSize = true, columns = true }
local charDefaults = {
    x          = nil,
    y          = nil,
    squareSize = defaults.squareSize,
    columns    = defaults.columns,
}

local function applyDefaults(dst, src)
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            applyDefaults(dst[key], value)
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

function ns:InitializeDB()
    if type(DotSpreadCheckerDB) ~= "table" then DotSpreadCheckerDB = {} end
    applyDefaults(DotSpreadCheckerDB, defaults)
    -- v1 saves shipped with an 8px default; carry existing users over to 16px.
    if DotSpreadCheckerDB.dbVersion < 1 then
        if DotSpreadCheckerDB.squareSize == 8 then DotSpreadCheckerDB.squareSize = 16 end
        DotSpreadCheckerDB.dbVersion = 1
    end

    -- v2 replaced the free-form anchor point with a fixed left edge; the old
    -- offsets meant something else and cannot be converted.
    if DotSpreadCheckerDB.dbVersion < 2 then
        DotSpreadCheckerDB.point = nil
        DotSpreadCheckerDB.x     = nil
        DotSpreadCheckerDB.y     = nil
        DotSpreadCheckerDB.dbVersion = 2
    end

    -- v3 moved the anchor from the row's vertical centre to the grid's top
    -- edge; a single row is one square tall, so the old centre converts exactly.
    if DotSpreadCheckerDB.dbVersion < 3 then
        if DotSpreadCheckerDB.y then DotSpreadCheckerDB.y = DotSpreadCheckerDB.y + DotSpreadCheckerDB.squareSize / 2 end
        DotSpreadCheckerDB.dbVersion = 3
    end
    if type(DotSpreadCheckerCharDB) ~= "table" then DotSpreadCheckerCharDB = {} end
    applyDefaults(DotSpreadCheckerCharDB, charDefaults)

    -- One view over both tables: layout keys go to the character's own save,
    -- everything else to the account-wide one.
    local account, char = DotSpreadCheckerDB, DotSpreadCheckerCharDB
    self.db = setmetatable({}, {
        __index = function(_, key)
            if CHAR_KEYS[key] then return char[key] end
            return account[key]
        end,
        __newindex = function(_, key, value)
            if CHAR_KEYS[key] then char[key] = value else account[key] = value end
        end,
    })
end
