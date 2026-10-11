local addonName, ns = ...

local M = {}
ns:RegisterModule("minimap", M)

local LDB     = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub("LibDBIcon-1.0", true)

function M:OnDBReady()
    if not LDB or not LDBIcon or self.launcher then return end
    local L = ns.L
    self.launcher = LDB:NewDataObject(addonName, {
        type  = "launcher",
        icon  = 136139, -- Agony
        label = L["ADDON_TITLE"],
        OnClick = function(_, button)
            if button == "RightButton" then
                local options = ns.modules.options
                if options then options:Open() end
            else
                ns:ToggleLocked()
            end
        end,
        OnTooltipShow = function(tip)
            tip:AddLine(L["ADDON_TITLE"] .. " |cff9d9d9dv" .. ns.version .. "|r")
            tip:AddLine(L["TOOLTIP_DESC"], 1, 1, 1)
            tip:AddLine(" ")
            tip:AddLine(L["TOOLTIP_LEFT_CLICK"], 0.8, 0.8, 0.8)
            tip:AddLine(L["TOOLTIP_RIGHT_CLICK"], 0.8, 0.8, 0.8)
        end,
    })
    LDBIcon:Register(addonName, self.launcher, ns.db.minimap)
    self:StripBorder()
end

-- LibDBIcon draws the round tracking border and a dark backdrop behind every
-- button. Hide both and let the icon fill the button instead.
local BORDER_TEXTURE     = 136430 -- Interface\Minimap\MiniMap-TrackingBorder
local BACKGROUND_TEXTURE = 136467 -- Interface\Minimap\UI-Minimap-Background

function M:StripBorder()
    local button = LDBIcon.GetMinimapButton and LDBIcon:GetMinimapButton(addonName)
    if not button then return end
    for _, region in ipairs({ button:GetRegions() }) do
        if region.GetTexture and region ~= button.icon then
            local texture = region:GetTexture()
            if texture == BORDER_TEXTURE or texture == BACKGROUND_TEXTURE
                or (type(texture) == "string" and (texture:find("TrackingBorder") or texture:find("Minimap%-Background"))) then
                region:Hide()
            end
        end
    end
    if button.icon then
        button.icon:ClearAllPoints()
        button.icon:SetPoint("CENTER")
        button.icon:SetSize(24, 24)
    end
end

function M:Toggle()
    if not LDBIcon then return end
    ns.db.minimap.hide = not ns.db.minimap.hide
    if ns.db.minimap.hide then
        LDBIcon:Hide(addonName)
        ns:Print(ns.L["MSG_MINIMAP_HIDDEN"])
    else
        LDBIcon:Show(addonName)
        ns:Print(ns.L["MSG_MINIMAP_SHOWN"])
    end
end
