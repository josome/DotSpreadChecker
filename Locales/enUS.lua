local addonName, ns = ...

-- enUS is the default locale: every key must exist here. Other locales fall
-- back to these strings through the metatable installed in Init.lua.
ns.locales = ns.locales or {}
ns.locales.enUS = {
    ADDON_TITLE          = "DotSpreadChecker",
    TOOLTIP_DESC         = "DoT spread monitor (Affliction, Shadow, Fire, Unholy, Assassination, Arms, Enhancement, Balance, Feral)",
    TOOLTIP_LEFT_CLICK   = "Left-click: lock / unlock the anchor",
    TOOLTIP_RIGHT_CLICK  = "Right-click: reset position",
    ANCHOR_LABEL         = "DoTs (drag)",
    MSG_LOCKED           = "anchor locked",
    MSG_UNLOCKED         = "anchor unlocked (drag to move)",
    MSG_RESET            = "position reset",
    MSG_COMBAT_ONLY_ON   = "showing enemies in combat only",
    MSG_COMBAT_ONLY_OFF  = "showing every enemy nameplate",
    MSG_MINIMAP_SHOWN    = "minimap icon shown",
    MSG_MINIMAP_HIDDEN   = "minimap icon hidden",
    MSG_NO_AURA_CONTAINER = "This client has no AuraContainer support; squares will stay white.",
    MSG_HELP             = "commands: lock | unlock | reset | combat | minimap | debug | probe",
    OPT_DESC             = "One square per enemy in combat. A square turns red once every DoT listed for your spec is on that enemy.",
    OPT_CURRENT          = "Current spec: %s",
    OPT_CURRENT_NONE     = "Current spec: not supported, the display stays hidden.",
    OPT_TRACKED_HEADER   = "Tracked DoTs per spec (untick to ignore a DoT)",
    OPT_SETTINGS_HEADER  = "Settings",
    OPT_LOCKED           = "Lock position",
    OPT_COMBAT_ONLY      = "Only enemies in combat with you",
    OPT_MINIMAP          = "Show minimap button",
    OPT_RESET            = "Reset position",
    OPT_CLASS_COLOR      = "Class colours (outline when missing, filled when applied)",
    OPT_COLUMNS          = "Squares per row",
    OPT_SIZE             = "Square size (pixels)",
}
