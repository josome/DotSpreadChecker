local addonName, ns = ...

-- Options panel in the game's AddOns settings. Lists every supported spec with
-- the DoTs it tracks, and carries the toggles that otherwise live behind slash
-- commands. Rows are rebuilt on every show so spell names that were not cached
-- at login still come through.
local M = {}
ns:RegisterModule("options", M)

local ROW_HEIGHT = 30
local ICON_SIZE  = 22

local panel, category
local rows = {}
local checks = {}
local steppers = {}

local function specInfo(specID)
    if not GetSpecializationInfoByID then return nil end
    local _, name, _, icon, _, classFile, className = GetSpecializationInfoByID(specID)
    return name, icon, classFile, className
end

local function classColor(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    return c and c.colorStr or "ffffffff"
end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end

local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture and GetSpellTexture(id) or nil
end

-- Specs sorted by class name, then spec name, so the list reads like the
-- game's own class order rather than by ID.
local function sortedSpecs()
    local list = {}
    for specID, profile in pairs(ns.PROFILES) do
        local name, icon, classFile, className = specInfo(specID)
        list[#list + 1] = {
            specID    = specID,
            profile   = profile,
            name      = name or tostring(specID),
            icon      = icon,
            classFile = classFile or profile.class,
            className = className or profile.class,
        }
    end
    table.sort(list, function(a, b)
        if a.className ~= b.className then return a.className < b.className end
        return a.name < b.name
    end)
    return list
end

local function createRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(560, ROW_HEIGHT)

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.58, 0.51, 0.79, 0.18)

    row.specIcon = row:CreateTexture(nil, "ARTWORK")
    row.specIcon:SetSize(ICON_SIZE, ICON_SIZE)
    row.specIcon:SetPoint("LEFT", 4, 0)
    row.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.label:SetPoint("LEFT", row.specIcon, "RIGHT", 8, 0)
    row.label:SetWidth(200)
    row.label:SetJustifyH("LEFT")

    row.spells = {}
    rows[index] = row
    return row
end

local function spellWidget(row, i)
    local w = row.spells[i]
    if w then return w end
    w = {}
    w.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    w.check:SetSize(22, 22)
    w.icon = row:CreateTexture(nil, "ARTWORK")
    w.icon:SetSize(ICON_SIZE, ICON_SIZE)
    w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    w.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.text:SetJustifyH("LEFT")
    row.spells[i] = w
    return w
end

local fillRows

-- Opt a single DoT in or out for a spec, then let the tracker rebuild the
-- active spell set; an opted-out DoT no longer has to be on an enemy for its
-- square to fill.
local function setSpellEnabled(specID, spellID, enabled)
    local all = ns.db.disabledSpells
    all[specID] = all[specID] or {}
    all[specID][spellID] = (not enabled) or nil
    if next(all[specID]) == nil then all[specID] = nil end
    local tracker = ns.modules.tracker
    if tracker then tracker:UpdateEligibility() end
    ns:CallSafe(fillRows)
end

function fillRows()
    local L = ns.L
    local current = ns.state and ns.state.specID
    local list = sortedSpecs()

    for index, entry in ipairs(list) do
        local row = rows[index] or createRow(panel.list, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + 4))
        row:Show()

        row.specIcon:SetTexture(entry.icon or 134400)
        local suffix = ""
        if entry.profile.heroName then
            suffix = " |cff9d9d9d" .. L["OPT_HERO_ONLY"]:format(entry.profile.heroName) .. "|r"
        elseif entry.profile.heroSpells then
            suffix = " |cff9d9d9d" .. L["OPT_HERO_DEPENDS"] .. "|r"
        end
        row.label:SetText(("|c%s%s|r |cff9d9d9d(%s)|r%s"):format(
            classColor(entry.classFile), entry.name, entry.className, suffix))
        row.highlight:SetShown(entry.specID == current)

        local anchor, anchorPoint, gap = row.label, "RIGHT", 8
        local spells = entry.profile.spells
        local off = ns.db.disabledSpells[entry.specID]
        for i, id in ipairs(spells) do
            local w = spellWidget(row, i)
            local enabled = not (off and off[id])
            w.check:ClearAllPoints()
            w.check:SetPoint("LEFT", anchor, anchorPoint, gap, 0)
            w.check:SetChecked(enabled)
            w.check:SetScript("OnClick", function(self)
                setSpellEnabled(entry.specID, id, self:GetChecked() and true or false)
            end)
            w.check:Show()
            w.icon:ClearAllPoints()
            w.icon:SetPoint("LEFT", w.check, "RIGHT", 2, 0)
            w.icon:SetDesaturated(not enabled)
            w.icon:SetTexture(spellIcon(id) or 134400)
            w.text:ClearAllPoints()
            w.text:SetPoint("LEFT", w.icon, "RIGHT", 4, 0)
            local name = spellName(id) or ("#" .. id)
            w.text:SetText(i < #spells and (name .. "  +") or name)
            w.text:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5)
            w.icon:Show()
            w.text:Show()
            anchor, anchorPoint, gap = w.text, "RIGHT", 8
        end
        for i = #spells + 1, #row.spells do
            row.spells[i].check:Hide()
            row.spells[i].icon:Hide()
            row.spells[i].text:Hide()
        end
    end
    for index = #list + 1, #rows do rows[index]:Hide() end

    if current and ns.PROFILES[current] then
        local name = specInfo(current) or tostring(current)
        panel.current:SetText(L["OPT_CURRENT"]:format(name))
    else
        panel.current:SetText(L["OPT_CURRENT_NONE"])
    end

    for _, check in ipairs(checks) do check:SetChecked(check.get()) end
    for _, stepper in ipairs(steppers) do stepper.update() end
end

local function createCheck(parent, label, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check.get = get
    local text = check.Text or check.text
    if not text then
        text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    end
    text:SetText(label)
    check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    check:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    check:SetChecked(get())
    checks[#checks + 1] = check
    return check
end

-- A small "label  [-] value [+]" control. Plain buttons rather than a slider
-- template, so it does not depend on which slider templates the client ships.

local function createStepper(parent, label, minValue, maxValue, step, get, set)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(360, 26)

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", 4, 0)
    text:SetWidth(200)
    text:SetJustifyH("LEFT")
    text:SetText(label)

    local minus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minus:SetSize(26, 22)
    minus:SetPoint("LEFT", text, "RIGHT", 8, 0)
    minus:SetText("-")

    local value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    value:SetWidth(36)

    local plus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    plus:SetSize(26, 22)
    plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
    plus:SetText("+")

    function frame.update()
        local v = get()
        value:SetText(tostring(v))
        minus:SetEnabled(v > minValue)
        plus:SetEnabled(v < maxValue)
    end

    local function change(delta)
        local v = math.max(minValue, math.min(maxValue, get() + delta))
        if v ~= get() then set(v) end
        frame.update()
    end
    minus:SetScript("OnClick", function() change(-step) end)
    plus:SetScript("OnClick", function() change(step) end)
    -- Fill the value straight away and on every show of the control itself,
    -- rather than relying on the panel's OnShow, which the settings canvas
    -- does not fire for the first open.
    frame:SetScript("OnShow", frame.update)
    frame.update()

    steppers[#steppers + 1] = frame
    return frame
end

local function relayout(sizeChanged)
    local display = ns.modules.display
    if display then display:Relayout(sizeChanged) end
end

local function createPanel()
    local L = ns.L
    panel = CreateFrame("Frame")
    panel.name = L["ADDON_TITLE"]

    -- Everything lives on a scroll child, so the list of specs and the
    -- settings below it stay reachable however short the settings window is.
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(640, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(math.max(width, 1))
        if panel.updateHeight then C_Timer.After(0, panel.updateHeight) end
    end)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L["ADDON_TITLE"] .. " |cff9d9d9dv" .. ns.version .. "|r")

    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(600)
    desc:SetJustifyH("LEFT")
    desc:SetText(L["OPT_DESC"])

    panel.current = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.current:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)

    local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    header:SetPoint("TOPLEFT", panel.current, "BOTTOMLEFT", 0, -16)
    header:SetText(L["OPT_TRACKED_HEADER"])

    panel.list = CreateFrame("Frame", nil, content)
    panel.list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    panel.list:SetSize(600, 1)

    local count = 0
    for _ in pairs(ns.PROFILES) do count = count + 1 end
    local listHeight = count * (ROW_HEIGHT + 4)

    local settingsHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    settingsHeader:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, -listHeight - 16)
    settingsHeader:SetText(L["OPT_SETTINGS_HEADER"])

    local lock = createCheck(content, L["OPT_LOCKED"],
        function() return ns.db.locked end,
        function(v) ns:SetLocked(v) end)
    lock:SetPoint("TOPLEFT", settingsHeader, "BOTTOMLEFT", -4, -6)

    local combat = createCheck(content, L["OPT_COMBAT_ONLY"],
        function() return ns.db.combatOnly end,
        function(v) if v ~= ns.db.combatOnly then ns:ToggleCombatOnly() end end)
    combat:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -2)

    local minimap = createCheck(content, L["OPT_MINIMAP"],
        function() return not ns.db.minimap.hide end,
        function(v)
            if v == ns.db.minimap.hide then
                local mod = ns.modules.minimap
                if mod then mod:Toggle() end
            end
        end)
    minimap:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -2)

    local classColor = createCheck(content, L["OPT_CLASS_COLOR"],
        function() return ns.db.classColor end,
        function(v) ns.db.classColor = v; relayout(true) end)
    classColor:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 0, -2)

    local swipe = createCheck(content, L["OPT_SWIPE"],
        function() return ns.db.swipeOptIn end,
        function(v) ns.db.swipeOptIn = v; relayout(true) end)
    swipe:SetPoint("TOPLEFT", classColor, "BOTTOMLEFT", 0, -2)

    local pandemic = createCheck(content, L["OPT_PANDEMIC"],
        function() return ns.db.pandemicFrame end,
        function(v) ns.db.pandemicFrame = v; relayout(true) end)
    pandemic:SetPoint("TOPLEFT", swipe, "BOTTOMLEFT", 0, -2)

    local columns = createStepper(content, L["OPT_COLUMNS"], 1, 20, 1,
        function() return ns.db.columns end,
        function(v) ns.db.columns = v; relayout(false) end)
    columns:SetPoint("TOPLEFT", pandemic, "BOTTOMLEFT", 4, -8)

    local size = createStepper(content, L["OPT_SIZE"], 8, 48, 2,
        function() return ns.db.squareSize end,
        function(v) ns.db.squareSize = v; relayout(true) end)
    size:SetPoint("TOPLEFT", columns, "BOTTOMLEFT", 0, -4)

    local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    reset:SetSize(180, 24)
    reset:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -10)
    reset:SetText(L["OPT_RESET"])
    reset:SetScript("OnClick", function() ns:ResetPosition() end)

    -- The scroll range follows the real bottom of the last control. Until the
    -- frames have been laid out once, a generous estimate stands in for it.
    content:SetHeight(480 + listHeight)
    panel.updateHeight = function()
        local top, bottom = content:GetTop(), reset:GetBottom()
        if top and bottom and top > bottom then content:SetHeight(top - bottom + 16) end
    end
    content:SetScript("OnShow", function() C_Timer.After(0, panel.updateHeight) end)

    panel:SetScript("OnShow", function()
        ns:CallSafe(fillRows)
        ns:CallSafe(panel.updateHeight)
    end)
    -- Start hidden so the first open is a real hide-to-show transition, and
    -- fill once now so nothing is blank even if OnShow is skipped.
    panel:Hide()
    ns:CallSafe(fillRows)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- Opens the settings window on this addon's page (minimap right-click).
function M:Open()
    if category and Settings and Settings.OpenToCategory then
        local id = category.GetID and category:GetID() or category.ID
        Settings.OpenToCategory(id)
    elseif panel and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

-- Keep checkboxes and the current-spec highlight in step with slash commands
-- and spec changes while the panel is open.
function M:Refresh()
    if panel and panel:IsVisible() then ns:CallSafe(fillRows) end
end

function M:OnPlayerLogin()
    createPanel()
end
