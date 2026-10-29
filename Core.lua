local addonName, ns = ...
local L = ns.L

-- Core: settings defaults, AceDB setup, addon keybinds, events.

local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME
local InCombatLockdown = InCombatLockdown
local SetOverrideBindingClick, ClearOverrideBindings = SetOverrideBindingClick, ClearOverrideBindings
local pairs, ipairs, type, tostring, rawget = pairs, ipairs, type, tostring, rawget

-- Menu look defaults. Used by the raid mark menu (root) and as the own look of the
-- other menus (used when their sameLook is off). Adds the fields to t and returns t.
local function Look(t, hl)
    t.anchor    = "CURSOR"   -- CURSOR / FIXED
    t.locked    = true
    t.x, t.y    = 0, 0       -- offset: from cursor (CURSOR) or screen center (FIXED)
    t.layout    = "RING"     -- RING / GRID / HROW / VROW
    t.scale     = 0.8
    t.alpha     = 1
    t.iconSize  = 32
    t.radius    = 48         -- RING only
    t.gap       = 4          -- GRID / HROW / VROW
    t.direction = false      -- RING + CURSOR: pie sectors start at the key-down cursor (matters with X/Y offset)
    t.deadzone  = 7
    t.hlShow, t.hlColor = true, hl or { r = 1, g = 0.82, b = 0, a = 0.35 }             -- selected region
    t.regionShow, t.regionColor = false, { r = 0.5, g = 0.5, b = 0.5, a = 0.25 }  -- not selected regions
    t.iconDim   = 0.15       -- not selected icon brightness
    t.dimIdle   = true       -- dim all icons (not center) while nothing is selected
    t.centerIconSize  = 24   -- center icon (shown when center release is on)
    t.centerIconAlpha = 0.5
    t.centerIconHide  = false -- hide the center icon (release / click still work)
    t.centerIconX, t.centerIconY = 0, 0
    t.dotShow  = true        -- center dot
    t.dotSize  = 6
    t.dotColor = { r = 1, g = 1, b = 1, a = 0.35 }
    -- Texts: font key (ns.FontList), size, outline (ns.OUTLINES), color, offset.
    -- fontLabel: unit label (unitColors = target red / mouseover green / ground blue), fontName: unit name,
    -- fontPing: ping icon text (no atlas), fontPend: pending ping text (world ping, own setting).
    t.fontLabel = { font = "FRIZ", size = 16, outline = "NONE", color = { r = 1, g = 0.82, b = 0, a = 1 }, x = 0, y = -35, unitColors = true }
    t.fontName  = { font = "FRIZ", size = 16, outline = "NONE", color = { r = 1, g = 1, b = 1, a = 1 }, x = 0, y = 0 }
    t.fontPing  = { font = "FRIZ", size = 16, outline = "NONE", color = { r = 1, g = 1, b = 1, a = 1 }, x = 0, y = 0 }
    t.fontPend  = { font = "FRIZ", size = 16, outline = "NONE", color = { r = 1, g = 1, b = 1, a = 1 }, x = 0, y = 0 }
    -- Highlight extras (look).
    if t.hlMarkColor == nil then t.hlMarkColor = false end -- selected region in the mark / ping type color (alpha from hlColor)
    t.hlGradient  = false    -- regions: inner edge faint -> outer edge full
    t.roundRing   = true     -- RING: circle mask, round outer edge
    t.sliceGap    = 0        -- px between regions
    t.curRegion   = true     -- raid mark menu: region of the unit's current mark lit
    t.curRegionColor = { r = 1, g = 0.2, b = 0.2, a = 0.45 }
    t.curRegionMarkColor = true -- current mark region in the mark's own color (alpha from curRegionColor)
    t.curUndim    = true     -- raid mark menu: icon of the unit's current mark never dimmed
    -- Effects (look).
    t.pop       = false      -- selected icon drawn bigger
    t.popSize   = 1.15
    t.glow      = false      -- glow behind the selected icon
    t.glowColor = { r = 1, g = 0.82, b = 0, a = 0.9 }
    t.openAnim  = "OFF"      -- ns.OPEN_ANIMS
    t.openAnimTime = 120     -- ms
    -- Unit info (own setting of the raid mark / ping menu).
    t.portrait  = true       -- unit portrait in the menu center
    t.portraitSize  = 60
    t.portraitAlpha = 0.8
    t.portraitMode  = "HIDE" -- ns.PORTRAIT_MODES: with center icon shown
    t.portraitX, t.portraitY = 0, 0
    t.portraitMark = false   -- unit's current raid mark icon over the portrait
    t.portraitMarkSize = 24
    t.portraitMarkX, t.portraitMarkY = 20, 20 -- from portrait center
    t.portraitMarkGlow = "SOFT" -- ns.MARK_GLOWS
    t.portraitMarkGlowColor = { r = 1, g = 1, b = 1, a = 0.9 }
    t.portraitMarkGlowSize = 2 -- px: soft = extra size, outline = offset
    -- Feedback (own setting of every menu).
    t.sound     = true       -- sound when an icon is applied
    t.soundId   = "OPTION"   -- ns.SOUNDS
    t.hlSound   = true       -- sound when the highlighted icon changes (not on open)
    t.hlSoundId = "CHECK_OFF" -- ns.SOUNDS
    t.pendPulse = false      -- world ping: pending ping icon pulses
    -- Selection (own setting of every menu, kept here so all 4 menus get it).
    t.hover     = true       -- pick by cursor position (off = wheel only)
    t.toggle    = false      -- press = open, press again / left click = apply, Escape = cancel
    t.noPick    = "CANCEL"   -- hover off, no wheel pick: ns.NOPICK_ACTIONS
    t.escClose  = true       -- Escape cancels the open menu (hold and toggle mode)
    t.centerRelease = false  -- key release with cursor in center = centerReleaseMark
    -- Click in center: t.centerClick (on / off) + t.centerBinds (list, not in AceDB defaults:
    -- created by EnsureBinds) = { { btn, mod, mark, place }, ... }, first match wins.
    t.centerClick = false
    t.exclude   = {}         -- [raid icon / ping type] = true: not shown in the menu
    t.keepSlots = false      -- excluded icons leave empty slots (off = re-space)
    t.wheelStart = false     -- wheel on: icon (raid icon / ping type) preselected on open; false = none
    return t
end

-- Fast mark defaults (own setting of every menu). icon / icon2: raid icon 1..8 or ping type.
local function Fast(t, icon, icon2)
    t.fast           = false
    t.fastIcon       = icon
    t.fastTime       = 200      -- ms: key released faster = fast icon
    t.fastNoLimit    = false    -- no release time limit, behavior: fastNoLimitMode
    t.fastNoLimitMode = "EMPTY" -- ns.FAST_MODES
    t.fastDouble     = false    -- 2nd fast tap within fastDoubleTime = fastIcon2
    t.fastIcon2      = icon2
    t.fastDoubleTime = 400      -- ms between the two key releases
    -- Fast mark in combat: key press in combat = combatFastIcon at key up, no menu, no timer.
    t.combatFast       = false
    t.combatFastIcon   = icon
    t.combatFastUnit   = "MOUSEOVER_TARGET" -- ns.UNIT_ORDERS (raid mark / ping menus)
    t.combatFastNoUnit = "NONE"             -- ns.COMBAT_NOUNIT (raid mark / ping menus)
    return t
end

local DEFAULTS = Fast(Look({
    key        = false,              -- addon override key ("F1", "SHIFT-F", ...); false = off
    -- Menu on / off (General). Off = no addon key, secure button ignores key down (Blizzard bind too).
    enabled    = { unit = true, world = true, ping = true, pworld = true },
    unitOrder  = "MOUSEOVER_TARGET", -- see ns.UNIT_ORDERS
    worldFallback = true,            -- no unit at key down = world marker under cursor
    debug      = false,
    soundOn    = true,                -- master switch for all FFmarks sounds
    soundChannel = "Master",          -- ns.SOUND_CHANNELS
    center     = "CANCEL",           -- CANCEL / CLEAR
    wheel      = false,              -- mouse wheel picks mark while held (cursor stays on the unit)
    wheelDir   = "CW",               -- wheel down = CW (clockwise) / CCW
    centerReleaseMark = 8,           -- raid icon 1..8
    -- World markers menu.
    world = Fast(Look({
        sameKey   = true,     -- key = unit-mark key + modifiers
        modKey    = "CTRL",   -- ns.KEY_MODS
        key       = false,    -- own key when sameKey is off
        center    = "CANCEL", -- CANCEL / CLEAR_ALL
        wheel     = false,    -- mouse wheel picks marker while held (cursor stays = ring center)
        wheelDir  = "CW",     -- wheel down = CW (clockwise) / CCW
        clickPlace  = false,         -- click icon -> green placement circle (/wm N)
        clickButton = "RightButton", -- ns.CLICK_BUTTONS
        clickMod    = "ANY",         -- ns.CLICK_MODS
        centerReleaseMark  = 8,      -- raid icon 1..8 (mapped to /wm index)
        centerReleasePlace = "CURSOR", -- ns.CENTER_PLACES: CURSOR (/wm [@cursor]) / CIRCLE (/wm)
        sameLook  = false,    -- use unit-mark menu look / position
    }, { r = 0.2, g = 0.6, b = 1, a = 0.35 }), 8, 7), -- blue highlight
    -- Ping menu (unit ping, auto: ground ping when no unit).
    ping = Fast(Look({
        sameKey   = true,               -- key = raid mark key + modifiers
        modKey    = "SHIFT",            -- ns.KEY_MODS
        key       = false,              -- own key when sameKey is off
        unitOrder = "MOUSEOVER",        -- ns.UNIT_ORDERS
        auto      = true,               -- no unit at key down = ground ping under cursor
        wheel = false, wheelDir = "CW",
        centerReleaseMark = "ping",
        hlMarkColor = true,             -- highlight in ping type color
        sameLook  = false,              -- use raid mark menu look / position
    }, { r = 0.2, g = 1, b = 0.3, a = 0.35 }), "ping", "attack"), -- green highlight
    -- World ping menu (ping under cursor).
    pworld = Fast(Look({
        sameKey   = false,              -- key = ping key + modifiers (off: own key, unbound by default)
        modKey    = "SHIFT",            -- ns.KEY_MODS
        key       = false,
        clickPlace  = false,            -- click icon -> pending ping, next click places it
        clickButton = "LeftButton",     -- ns.CLICK_BUTTONS
        clickMod    = "ANY",            -- ns.CLICK_MODS
        wheel = false, wheelDir = "CW",
        centerReleaseMark = "ping",
        sameLook  = true,               -- use ping menu look / position
    }, { r = 0.2, g = 1, b = 0.3, a = 0.35 }), "ping", "attack"), -- green highlight
}), 8, 7)

ns.MENU_KINDS = { "unit", "world", "ping", "pworld" }

ns.WHEEL_DIRS = { "CW", "CCW" }
-- Modifier combos, one list for all options (names: L.CLICK_MOD_NAMES).
-- Clicks: ns.CLICK_MODS (+ NONE / ANY); "key + modifiers": ns.KEY_MODS (at least one modifier).
ns.CLICK_MODS = { "NONE", "ANY", "SHIFT", "CTRL", "ALT", "CTRL-SHIFT", "ALT-SHIFT", "ALT-CTRL", "ALT-CTRL-SHIFT" }
ns.KEY_MODS = { "SHIFT", "CTRL", "ALT", "CTRL-SHIFT", "ALT-SHIFT", "ALT-CTRL", "ALT-CTRL-SHIFT" }
ns.CENTER_PLACES = { "CURSOR", "CIRCLE" }
-- Fast mark, no time limit: EMPTY = release with nothing picked; BOTH = fast tap or empty release;
-- INSTANT = key press places the fast icon, menu never opens.
ns.FAST_MODES = { "EMPTY", "BOTH", "INSTANT" }
-- Fast mark in combat, no unit: NONE = nothing; GROUND = world marker / ground ping under cursor;
-- MENU = normal menu opens.
ns.COMBAT_NOUNIT = { "NONE", "GROUND", "MENU" }

ns.UNIT_ORDERS = { "MOUSEOVER_TARGET", "TARGET_MOUSEOVER", "MOUSEOVER", "TARGET" }

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(L.PREFIX .. tostring(msg))
end

function ns.Debug(msg)
    if ns.db and ns.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888FFmarks dbg:|r " .. tostring(msg))
    end
end

-- Menu kind enabled (General > Enabled menus). Missing = on.
function ns.MenuOn(kind)
    local e = ns.db and ns.db.enabled
    return not (e and e[kind] == false)
end

---------------------------------------------------------------- keybind
-- Addon key = override click binding on the secure button, owned by bindOwner
-- (WoW saved bindings untouched). Blizzard Keybindings entry (Bindings.xml) works independently.
local bindOwner = CreateFrame("Frame")
local bindPending = false

function ns.ApplyBinding()
    if InCombatLockdown() then
        if not bindPending then ns.Print(L.BIND_PENDING) end
        bindPending = true
        return
    end
    bindPending = false
    ClearOverrideBindings(bindOwner)
    -- One key per menu; a key already used by an earlier menu is skipped.
    local used = {}
    for _, kind in ipairs(ns.MENU_KINDS) do
        -- Off menu: not bound. Its key still serves as base key of sameKey menus (MenuKey).
        local key = ns.MenuOn(kind) and ns.MenuKey(kind)
        if key then
            if used[key] then
                ns.Print(L.KEY_SAME:format(L.MENU_NAMES[kind], key, L.MENU_NAMES[used[key]]))
            else
                used[key] = kind
                SetOverrideBindingClick(bindOwner, false, key, ns.BUTTONS[kind], "LeftButton")
                ns.Debug("bind " .. kind .. " " .. key)
            end
        end
    end
end

-- Add modifiers (combo string "CTRL-SHIFT") to a key string, WoW order ALT-CTRL-SHIFT-KEY
-- ("CTRL-F1" + "SHIFT" = "CTRL-SHIFT-F1").
local MOD_ORDER = { "ALT", "CTRL", "SHIFT" }
local function ComboSet(combo)
    local set = {}
    for m in tostring(combo or ""):gmatch("[^%-]+") do set[m] = true end
    return set
end
local function AddModifiers(key, add)
    add = ComboSet(add)
    local mods, rest = {}, key
    while true do
        local m, r = rest:match("^(%u+)%-(.+)$")
        if m and (m == "ALT" or m == "CTRL" or m == "SHIFT") then
            mods[m] = true
            rest = r
        else
            break
        end
    end
    for m, on in pairs(add) do
        if on then mods[m] = true end
    end
    local out = ""
    for _, m in ipairs(MOD_ORDER) do
        if mods[m] then out = out .. m .. "-" end
    end
    return out .. rest
end

-- Effective key of a menu kind or nil. sameKey: base key + modifiers
-- (world, ping: raid mark key; world ping: ping key).
function ns.MenuKey(kind)
    if kind == "unit" then
        local key = ns.db.key
        return (key and key ~= "") and key or nil
    end
    local o = ns.db[kind]
    if o.sameKey then
        local base = ns.MenuKey(kind == "pworld" and "ping" or "unit")
        if not base then return nil end
        return AddModifiers(base, o.modKey or "SHIFT")
    end
    return (o.key and o.key ~= "") and o.key or nil
end

-- Saved values no longer valid (per profile) -> defaults; center click bind lists exist.
local SOUND_KEYS = { "soundId", "hlSoundId" }
local function Sanitize(db)
    -- Sounds removed from ns.SOUNDS (or missing in this client): nil = back to default.
    local okSound = {}
    for _, k in ipairs(ns.SOUNDS) do okSound[k] = true end
    for _, kind in ipairs(ns.MENU_KINDS) do
        local o = kind == "unit" and db or db[kind]
        for _, key in ipairs(SOUND_KEYS) do
            local v = rawget(o, key)
            if v ~= nil and not okSound[v] then o[key] = nil end
        end
    end
    ns.EnsureBinds(db)
end

-- Center click bind list of every menu exists and has at least one row (default: Left, Any).
function ns.EnsureBinds(db)
    for _, kind in ipairs(ns.MENU_KINDS) do
        local o = kind == "unit" and db or db[kind]
        if type(rawget(o, "centerBinds")) ~= "table" or #o.centerBinds == 0 then
            local isPing = kind == "ping" or kind == "pworld"
            o.centerBinds = { { btn = "LeftButton", mod = "ANY", mark = isPing and "ping" or 8,
                place = kind == "world" and "CURSOR" or nil } }
        end
    end
end

-- Profile switched / copied / reset: new table, re-apply everything.
function ns:OnProfile()
    ns.db = ns.dbObj.profile
    Sanitize(ns.db)
    ns.ApplyAllLayouts()
    ns.ApplyBinding()
    if ns.Options then ns.Options.Refresh() end
end

---------------------------------------------------------------- events
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        if bindPending then ns.ApplyBinding() end
        for _, k in ipairs(ns.MENU_KINDS) do ns.Menus[k].ApplyPending() end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        ns.ApplyBinding()
    elseif arg1 == addonName then -- ADDON_LOADED
        self:UnregisterEvent("ADDON_LOADED")
        ns.dbObj = LibStub("AceDB-3.0"):New("FFmarksDB", { profile = DEFAULTS }, true) -- true = shared "Default"
        ns.dbObj.RegisterCallback(ns, "OnProfileChanged", "OnProfile")
        ns.dbObj.RegisterCallback(ns, "OnProfileCopied", "OnProfile")
        ns.dbObj.RegisterCallback(ns, "OnProfileReset", "OnProfile")
        ns.db = ns.dbObj.profile
        Sanitize(ns.db)
        ns.InitMenus()
        ns.Options.Init()
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.Print(L.LOADED)
    end
end)
