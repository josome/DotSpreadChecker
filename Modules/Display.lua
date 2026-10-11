local addonName, ns = ...

-- Display renders ns.state as a grid of squares, db.columns wide and wrapping
-- downward, and owns the drag anchor shown while unlocked.
--
-- How the red state works without reading aura data (12.x secret values):
-- each square is a white texture with a clipping frame on top. Inside the
-- clipping frame lives a Blizzard AuraContainer bound to that nameplate unit
-- with a single group filtered to "HARMFUL|PLAYER" and includeSpellIDs =
-- the tracked DoTs. The client creates one aura button per matching aura and
-- flows them left to right; each button paints itself solid red. The
-- container is shifted left by (#DoTs - 1) button widths, so every button but
-- the last falls outside the clip region. The last button exists only when
-- every tracked DoT is present, which is exactly the condition we want to
-- show. Addon code never inspects the buttons, so nothing here touches
-- secret values.
local M = {}
ns:RegisterModule("display", M)

local WHITE = { 1, 1, 1, 1 }
local RED   = { 1, 0.15, 0.15, 1 }

-- "Applied" colour: the player's class colour when enabled, red otherwise.
local function appliedColor()
    if ns.db.classColor then
        local _, classFile = UnitClass("player")
        local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then return { c.r, c.g, c.b, 1 } end
    end
    return RED
end

-- With class colours on, a square without the DoT is only an outline in the
-- class colour and an applied DoT fills it. With them off, the original look:
-- white square, red when applied.
local function paintOutline(slot, size, c)
    local t = math.max(1, math.floor(size / 8))
    slot.edges = slot.edges or {}
    local specs = {
        { "TOPLEFT", "TOPRIGHT", size, t },
        { "BOTTOMLEFT", "BOTTOMRIGHT", size, t },
        { "TOPLEFT", "BOTTOMLEFT", t, size },
        { "TOPRIGHT", "BOTTOMRIGHT", t, size },
    }
    for i, s in ipairs(specs) do
        local edge = slot.edges[i] or slot.clip:CreateTexture(nil, "BORDER")
        slot.edges[i] = edge
        edge:ClearAllPoints()
        edge:SetPoint(s[1])
        edge:SetSize(s[3], s[4])
        edge:SetColorTexture(c[1], c[2], c[3], c[4])
    end
end

-- Every visible region bleeds this far past the clipping frame on all sides.
-- The clip rect is then the single thing that defines a square's edges, so the
-- white base and the red aura button cannot disagree by a pixel when the UI
-- scale puts a square's origin on a fractional coordinate.
local BLEED = 2

-- Horizontal gap between aura buttons inside a container. It must exceed BLEED
-- so that the bleed of the button parked outside the clip region cannot reach
-- into the visible square.
local BUTTON_PAD = 4

local HAS_AURA_CONTAINERS = C_XMLUtil and C_XMLUtil.GetTemplateInfo
    and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") and true or false

local root, anchor = nil, nil

-- Slots follow units, not positions. Re-binding a container to a different
-- unit forces the client to re-parse that unit's auras, so a slot keeps its
-- unit for as long as the unit is on screen and only its anchor moves when the
-- left-to-right order changes.
local pool       = {}   -- every slot ever created
local slotByUnit = {}   -- [unit] = slot
local unitSet    = {}   -- scratch: units present in the current render
local freeSlots  = {}   -- scratch: slots not currently bound to a unit

-- Length covered by n squares laid side by side, for either axis.
local function span(n)
    return n * ns.db.squareSize + (n - 1) * ns.db.squareGap
end

-- The grid is anchored by its top-left corner only, so adding squares always
-- extends it right and then down instead of pushing the existing ones around.
-- Screen clamping happens on release rather than through SetClampedToScreen,
-- which would shift the anchor whenever the grid grew past the screen edge.
local function defaultPosition()
    return (GetScreenWidth() - span(ns.db.columns)) / 2, GetScreenHeight() / 2 - 120
end

local function applyPosition()
    if not ns.db.x or not ns.db.y then
        ns.db.x, ns.db.y = defaultPosition()
    end
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.x, ns.db.y)
end

-- A full row is the widest the grid ever gets, so all of it is kept on screen.
-- The height depends on how many enemies are engaged, so only the first row is.
local function savePosition()
    local left, top = root:GetLeft(), root:GetTop()
    if not left or not top then return end

    local scale = root:GetEffectiveScale() / UIParent:GetEffectiveScale()
    ns.db.x = math.max(0, math.min(left * scale, GetScreenWidth() - span(ns.db.columns)))
    ns.db.y = math.max(ns.db.squareSize, math.min(top * scale, GetScreenHeight()))
end

-- ---------------------------------------------------------------------------
-- Aura container
-- ---------------------------------------------------------------------------

local function includeSpellMap()
    local map = {}
    for _, spellID in ipairs(ns.TRACKED_SPELLS) do
        map[spellID] = true
    end
    return map
end

-- Runs once per aura button, before Blizzard applies access restrictions.
-- This callback is the only place button APIs may be called at all; from here
-- on the button is forbidden and even :IsShown() raises.
--
-- CustomAuraButtonTemplate carries no size of its own and the flow layout
-- only anchors buttons, so the red region is given an explicit size instead
-- of :SetAllPoints(); a zero-sized button would otherwise render nothing.
local function paintBleedTexture(tex, size, r, g, b, a)
    tex:SetPoint("TOPLEFT", -BLEED, BLEED)
    tex:SetSize(size + BLEED * 2, size + BLEED * 2)
    tex:SetColorTexture(r, g, b, a)
    -- Independent pixel snapping is exactly what makes the two anchor chains
    -- disagree; let the clip rect do the rounding for everything.
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
end

-- Remaining time: the button hands the aura's duration object straight to a
-- Cooldown frame (SetDurationCooldown), so the client draws the swipe and the
-- addon never sees a number. Reversed, the dark part is the elapsed time and
-- the coloured part shrinks as the DoT runs out.
local function addDurationSwipe(button, size)
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", -BLEED, BLEED)
    cd:SetSize(size + BLEED * 2, size + BLEED * 2)
    cd:SetReverse(true)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetSwipeColor(0, 0, 0, 0.7)
    button:SetDurationCooldown(cd)
end

-- Pandemic window: the client shows this region only while refreshing the DoT
-- would carry over its remaining time. It is a white inner frame with a black
-- line inside it, which reads on every class colour. (An animated version did
-- not work: the client hides and shows the region itself, and the flipbook
-- never played, leaving the whole sprite sheet on screen.)
local function addPandemicMark(button, size)
    local mark = CreateFrame("Frame", nil, button)
    mark:SetSize(size, size)
    mark:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    mark:SetFrameLevel(button:GetFrameLevel() + 5)

    local t = math.max(2, math.floor(size / 6))
    local function frameEdges(inset, thickness, r, g, b, layer)
        local inner = size - inset * 2
        local specs = {
            { "TOPLEFT", inset, -inset, inner, thickness },
            { "BOTTOMLEFT", inset, inset, inner, thickness },
            { "TOPLEFT", inset, -inset, thickness, inner },
            { "TOPRIGHT", -inset, -inset, thickness, inner },
        }
        for _, sp in ipairs(specs) do
            local edge = mark:CreateTexture(nil, layer)
            edge:SetPoint(sp[1], sp[2], sp[3])
            edge:SetSize(sp[4], sp[5])
            edge:SetColorTexture(r, g, b, 1)
        end
    end
    frameEdges(0, t, 1, 1, 1, "ARTWORK")
    frameEdges(t, 1, 0, 0, 0, "OVERLAY")

    mark:Hide()
    button:AddPandemicRegion(mark)
end

-- The colour and the duration options are captured when the container is
-- built; changing them later means rebuilding the slots (see M:Relayout).
local function makeButtonInitializer(size)
    local pitch = size + BUTTON_PAD
    local c = appliedColor()
    local swipe, pandemic = ns.db.durationSwipe, ns.db.pandemicFrame
    return function(button)
        pcall(button.SetMouseMotionEnabled, button, false)
        pcall(button.SetSize, button, pitch, pitch)
        paintBleedTexture(button:CreateTexture(nil, "ARTWORK"), size, c[1], c[2], c[3], c[4])
        if swipe then
            local ok, err = pcall(addDurationSwipe, button, size)
            if not ok then ns:Debug("duration swipe failed: %s", tostring(err)) end
        end
        if pandemic then
            local ok, err = pcall(addPandemicMark, button, size)
            if not ok then ns:Debug("pandemic mark failed: %s", tostring(err)) end
        end
    end
end

-- Everything here must happen before AddAuraGroup: registering a group marks
-- the container as forbidding untrusted layout scripts, after which addon
-- anchoring of the container may no longer be permitted.
local function createContainer(clip, size)
    if not HAS_AURA_CONTAINERS then return nil end

    local pitch = size + BUTTON_PAD
    local container = CreateFrame("AuraContainer", nil, clip, "CustomAuraContainerTemplate")
    container:SetSize(size, size)
    container:SetFrameLevel(clip:GetFrameLevel() + 1)

    -- Hide every button except the last possible one behind the clip edge.
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", clip, "TOPLEFT", -(#ns.TRACKED_SPELLS - 1) * pitch, 0)

    container:SetFlowLayoutAnchorPoint("TOPLEFT")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutMaximumLineSize(math.huge)

    container:AddAuraGroup("dots", "HARMFUL|PLAYER", {
        maxFrameCount    = #ns.TRACKED_SPELLS,
        candidateFilters = { includeSpellIDs = includeSpellMap() },
        -- Latest expiry first, so the visible last button (and its swipe and
        -- pandemic mark) always belongs to the DoT that runs out soonest.
        sortMethod       = AuraContainerSortMethod and AuraContainerSortMethod.ExpirationOnly,
        sortDirection    = AuraContainerSortDirection and AuraContainerSortDirection.Reverse,
        initializeFrame  = makeButtonInitializer(size),
        layout           = {
            elementWidth   = pitch,
            elementHeight  = pitch,
            elementSpacing = 0,
            lineSpacing    = 0,
        },
    })

    container:SetEnabled(false)
    container:Hide()
    return container
end

-- Containers are built on first use rather than with the slot: each one
-- allocates a fixed batch of aura buttons, and the preview squares shown while
-- the frame is unlocked never need one.
--
-- A container's spell filter is fixed once its aura group is registered, so
-- each slot keeps one container per spec and switches between them.
local function ensureContainer(slot)
    local key = ns.state.profileKey or 0
    slot.containers = slot.containers or {}
    if slot.containers[key] == nil then
        local ok, container = pcall(createContainer, slot.clip, ns.db.squareSize)
        if not ok then
            ns:Debug("container creation failed: %s", tostring(container))
            container = nil
        end
        slot.containers[key] = container or false
    end
    slot.container = slot.containers[key] or nil
    return slot.container
end

local function assignUnit(slot, unit)
    if slot.unit == unit then return end

    if slot.unit then slotByUnit[slot.unit] = nil end
    slot.unit = unit
    if unit then slotByUnit[unit] = slot end

    if unit and slot.container then
        -- The spec may have changed since this slot was last bound.
        slot.container:SetEnabled(false)
        slot.container:Hide()
    end
    local c = unit and ensureContainer(slot) or slot.container
    if not c then return end
    if unit then
        c:SetEnabled(true)
        c:SetUnit(unit)
        c:Show()
        ns:Debug("container bound to %s", unit)
    else
        c:SetEnabled(false)
        c:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

local function createFrames()
    if root then return end

    root = CreateFrame("Frame", "DotSpreadCheckerDisplay", UIParent)
    root:SetSize(ns.db.squareSize, ns.db.squareSize)
    root:SetFrameStrata("MEDIUM")
    root:SetMovable(true)

    -- The anchor is a translucent handle drawn over the square grid; it is the
    -- only part that receives mouse input, and it is shown only while unlocked.
    anchor = CreateFrame("Frame", nil, root)
    anchor:SetPoint("TOPLEFT", root, "TOPLEFT", -6, 16)
    anchor:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 6, -6)
    anchor:SetFrameLevel(root:GetFrameLevel() + 20)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function()
        if not ns.db.locked then root:StartMoving() end
    end)
    anchor:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        savePosition()
        applyPosition()
    end)

    anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.bg:SetAllPoints()
    anchor.bg:SetColorTexture(0, 0.6, 1, 0.35)

    anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    anchor.label:SetPoint("TOP", anchor, "TOP", 0, -1)
    anchor.label:SetText(ns.L["ANCHOR_LABEL"])

    applyPosition()
end

-- Slots are created once and never resized: the aura container is anchored
-- relative to a fixed square size at creation time and must not be re-anchored
-- afterwards.
local function createSlot()
    local size = ns.db.squareSize
    local slot = {}

    -- The clip frame is the square. Everything drawn for this slot lives
    -- inside it and overflows it, so the clip rect alone decides the edges.
    slot.clip = CreateFrame("Frame", nil, root)
    slot.clip:SetSize(size, size)
    slot.clip:SetClipsChildren(true)
    slot.clip:SetFrameLevel(root:GetFrameLevel() + 5)

    local applied = appliedColor()
    if ns.db.classColor then
        paintOutline(slot, size, applied)
    else
        slot.base = slot.clip:CreateTexture(nil, "BACKGROUND")
        paintBleedTexture(slot.base, size, WHITE[1], WHITE[2], WHITE[3], WHITE[4])
    end

    slot.preview = slot.clip:CreateTexture(nil, "ARTWORK")
    paintBleedTexture(slot.preview, size, applied[1], applied[2], applied[3], applied[4])
    slot.preview:Hide()

    pool[#pool + 1] = slot
    return slot
end

local function placeSlot(slot, i)
    if slot.index == i then return end
    slot.index = i

    local pitch   = ns.db.squareSize + ns.db.squareGap
    local columns = ns.db.columns
    slot.clip:ClearAllPoints()
    slot.clip:SetPoint("TOPLEFT", root, "TOPLEFT",
        ((i - 1) % columns) * pitch, -math.floor((i - 1) / columns) * pitch)
end

local function hideSlot(slot)
    slot.index = nil
    slot.preview:Hide()
    slot.clip:Hide()
    assignUnit(slot, nil)
end

-- Unbind slots whose unit left, and collect everything unbound so the assign
-- pass can hand them to units that just arrived.
local function reclaimSlots()
    wipe(freeSlots)
    for i = 1, #pool do
        local slot = pool[i]
        if slot.unit and not unitSet[slot.unit] then
            assignUnit(slot, nil)
        end
        if not slot.unit then
            freeSlots[#freeSlots + 1] = slot
        end
    end
end

local function setGridSize(count)
    if count == 0 then
        root:SetSize(ns.db.squareSize, ns.db.squareSize)
        return
    end
    local columns = ns.db.columns
    root:SetSize(span(math.min(count, columns)), span(math.ceil(count / columns)))
end

local function render()
    local state = ns.state
    local unlocked = not ns.db.locked

    if not state.eligible then
        root:Hide()
        return
    end

    local count
    if state.inCombat then
        count = #state.units
    elseif unlocked then
        -- One full row: the widest the grid gets, which is what placement needs.
        count = ns.db.columns
    else
        for i = 1, #pool do hideSlot(pool[i]) end
        root:Hide()
        return
    end

    wipe(unitSet)
    if state.inCombat then
        for i = 1, count do
            unitSet[state.units[i]] = true
        end
    end
    reclaimSlots()

    local nextFree = #freeSlots
    for i = 1, count do
        local unit = state.inCombat and state.units[i] or nil
        local slot = unit and slotByUnit[unit]

        if not slot then
            slot = freeSlots[nextFree]
            if slot then
                freeSlots[nextFree] = nil
                nextFree = nextFree - 1
            else
                slot = createSlot()
            end
            assignUnit(slot, unit)
        end

        placeSlot(slot, i)
        slot.clip:Show()
        -- Preview alternates colours so both states are visible while placing.
        slot.preview:SetShown(not state.inCombat and i % 2 == 0)
    end

    for i = 1, nextFree do
        hideSlot(freeSlots[i])
    end

    setGridSize(count)
    anchor:SetShown(unlocked)
    root:Show()
end

function M:Render()
    if not root then return end
    ns:CallSafe(render)
end

local renderedSpec = nil

-- Called by the options panel. A new column count only moves squares, but a
-- new square size cannot be applied to existing slots (their aura containers
-- are anchored for a fixed size), so those slots are retired and fresh ones
-- are built at the new size on the next render.
function M:Relayout(sizeChanged)
    if not root then return end
    for i = 1, #pool do
        local slot = pool[i]
        if sizeChanged then
            hideSlot(slot)
        else
            slot.index = nil
        end
    end
    if sizeChanged then wipe(pool) end
    self:Render()
end

function M:Refresh()
    if not root then return end
    -- A spec change swaps the spell filter: unbind every slot so the next
    -- render binds the containers that belong to the new spec.
    if ns.state.profileKey ~= renderedSpec then
        renderedSpec = ns.state.profileKey
        for i = 1, #pool do hideSlot(pool[i]) end
    end
    applyPosition()
    self:Render()
end

function M:OnPlayerLogin()
    if not HAS_AURA_CONTAINERS then
        ns:Print(ns.L["MSG_NO_AURA_CONTAINER"])
    end
    createFrames()
    self:Render()
end
