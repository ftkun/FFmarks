local addonName, ns = ...
local L = ns.L

-- Four menus built by one factory (ns.MENU_KINDS -> ns.Menus[kind]):
--   unit   : "/tm [@unit,exists] N"      raid target icon on mouseover / target
--   world  : "/wm [@cursor] N"           world marker on the ground under cursor
--   ping   : "/ping [@unit,exists] TYPE" ping on mouseover / target (auto: ground)
--   pworld : "/ping TYPE"                ping under cursor (unit there, else ground)
-- SetRaidTarget / world markers / pings are protected: each menu = SecureActionButton (type macro)
-- + secure ring header. Key bound to a click on the button (down + up). The secure snippet
-- (WrapScript, Snippets.lua) shows the ring on key down and builds the macro on key up -> works in combat.

local UIParent = UIParent
local GetCursorPosition = GetCursorPosition
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local ClearOverrideBindings = ClearOverrideBindings
local SecureCmdOptionParse = SecureCmdOptionParse
local UnitGUID, UnitName = UnitGUID, UnitName
local UnitTokenFromGUID = UnitTokenFromGUID
local GetAtlasInfo = C_Texture.GetAtlasInfo
local issecret = issecretvalue or function() return false end
local GetRaidTargetIndex = GetRaidTargetIndex
local SetPortraitTexture = SetPortraitTexture
local CreateColor = CreateColor
local PlaySound = PlaySound
local cos, sin, rad, sqrt, abs, max, floor = math.cos, math.sin, math.rad, math.sqrt, math.abs, math.max, math.floor
local ipairs, pairs, next, type, pcall, tostring = ipairs, pairs, next, type, pcall, tostring
local CreateFrame = CreateFrame
local concat = table.concat

-- Global names needed for click bindings (Bindings.xml + override binds in Core.lua).
ns.BUTTONS = {
    unit = "FFmarksHoldButton", world = "FFmarksWorldButton",
    ping = "FFmarksPingButton", pworld = "FFmarksPingWorldButton",
}
ns.WHEEL_BUTTONS = {
    unit = "FFmarksWheelButton", world = "FFmarksWorldWheelButton",
    ping = "FFmarksPingWheelButton", pworld = "FFmarksPingWorldWheelButton",
}
-- World ping click to place: pending click button (next click = ping) + cancel button.
ns.PEND_BUTTON = "FFmarksPingPlaceButton"
ns.PEND_CANCEL_BUTTON = "FFmarksPingCancelButton"
-- Escape (option, hold and toggle mode; temp bind while open) -> cancel button.
ns.CANCEL_BUTTONS = {
    unit = "FFmarksCancelButton", world = "FFmarksWorldCancelButton",
    ping = "FFmarksPingCancelMenuButton", pworld = "FFmarksPingWorldCancelMenuButton",
}
ns.CENTER_BUTTONS = {
    unit = "FFmarksCenterButton", world = "FFmarksWorldCenterButton",
    ping = "FFmarksPingCenterButton", pworld = "FFmarksPingWorldCenterButton",
}

local ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local ICON_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons" -- 4x4 sheet (secret index path)
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local CUR_SHEET = "Interface\\AddOns\\" .. addonName .. "\\Textures\\CurMark" -- .. item .. ".tga"
local DIM_SHEET = "Interface\\AddOns\\" .. addonName .. "\\Textures\\DimMark" -- .. item .. ".tga" (inverse of CurMark)
-- Full sheet paths per raid icon 1..8 (built once, not per menu open).
local CUR_SHEETS, DIM_SHEETS = {}, {}
for i = 1, 8 do
    CUR_SHEETS[i] = CUR_SHEET .. i .. ".tga"
    DIM_SHEETS[i] = DIM_SHEET .. i .. ".tga"
end

ns.LAYOUTS = { "RING", "GRID", "HROW", "VROW" }
ns.ANCHORS = { "CURSOR", "FIXED" }
ns.CENTER_ACTIONS = { "CANCEL", "CLEAR" }
ns.WORLD_CENTER_ACTIONS = { "CANCEL", "CLEAR_ALL" }
-- Hover off, nothing picked by wheel: Cancel / center action / last used icon.
ns.NOPICK_ACTIONS = { "CANCEL", "CENTER", "LAST" }

-- Look extras.
ns.OPEN_ANIMS = { "OFF", "FADE", "GROW" }
ns.MARK_GLOWS = { "OFF", "SOFT", "OUTLINE" }
ns.PORTRAIT_MODES = { "HIDE", "BEHIND" }
-- Sound on apply: key -> SOUNDKIT name (missing in a client = no sound).
ns.SOUNDS = {
    "CHECK", "CHECK_OFF", "OK", "OPTION", "MENU_OPEN", "MENU_CLOSE",     -- UI clicks
    "CHAR_TAB", "MINIMAP",                                               -- windows
    "AGGRO", "NPC", "NEUTRAL",                                           -- targeting
}
local SOUND_KITS = {
    CHECK = "IG_MAINMENU_OPTION_CHECKBOX_ON", CHECK_OFF = "IG_MAINMENU_OPTION_CHECKBOX_OFF",
    OPTION = "IG_MAINMENU_OPTION", OK = "GS_TITLE_OPTION_OK",
    MENU_OPEN = "IG_MAINMENU_OPEN", MENU_CLOSE = "IG_MAINMENU_CLOSE",
    CHAR_TAB = "IG_CHARACTER_INFO_TAB", MINIMAP = "IG_MINIMAP_OPEN",
    AGGRO = "IG_CREATURE_AGGRO_SELECT", NPC = "IG_CHARACTER_NPC_SELECT",
    NEUTRAL = "IG_CREATURE_NEUTRAL_SELECT",
}
-- Dropdowns list only sounds this client has (SOUNDKIT name missing = left out).
do
    local have = {}
    for _, k in ipairs(ns.SOUNDS) do
        if SOUNDKIT[SOUND_KITS[k]] then have[#have + 1] = k end
    end
    ns.SOUNDS = have
end
-- Channel (General > Audio): PlaySound channel names.
ns.SOUND_CHANNELS = { "Master", "SFX", "Music", "Ambience", "Dialog" }
-- Macro acts: conditions of its first line pass ("/tm [@mouseover,exists] 6" with no mouseover = false).
-- No conditions = true (e.g. "/cwm all"). Used to skip the apply sound when nothing was marked.
local function MacroActs(m)
    local args = m:match("^%s*%S+%s*([^\n]*)")
    if not args or not args:find("[", 1, true) then return true end
    local r = SecureCmdOptionParse(args)
    return r ~= nil and r ~= ""
end

function ns.PlayApplySound(key)
    local db = ns.db
    if db and db.soundOn == false then return end -- General > Audio master switch
    local kit = SOUNDKIT[SOUND_KITS[key] or ""]
    if kit then PlaySound(kit, (db and db.soundChannel) or "Master") end
end
-- Highlight color per item (raid icon 1..8 / ping type).
local ITEM_COLORS = {
    [1] = { 1, 0.92, 0 },   [2] = { 1, 0.5, 0 },   [3] = { 0.8, 0.3, 1 }, [4] = { 0.2, 1, 0.2 },
    [5] = { 0.7, 0.85, 1 }, [6] = { 0, 0.6, 1 },   [7] = { 1, 0.2, 0.2 }, [8] = { 1, 1, 1 },
    ping = { 0.3, 0.7, 1 }, attack = { 1, 0.5, 0 }, warning = { 1, 0.2, 0.2 },
    onmyway = { 0.15, 0.4, 1 }, assist = { 0.2, 1, 0.3 },
}
-- Fonts: built-in + LibSharedMedia fonts (if another addon loaded it). Key -> path.
local FONTS = {
    FRIZ = "Fonts\\FRIZQT__.TTF", ARIALN = "Fonts\\ARIALN.TTF",
    SKURRI = "Fonts\\skurri.ttf", MORPHEUS = "Fonts\\MORPHEUS.TTF",
}
local FONT_ORDER = { "FRIZ", "ARIALN", "SKURRI", "MORPHEUS" }
local FONT_NAMES = { FRIZ = "Friz Quadrata", ARIALN = "Arial Narrow", SKURRI = "Skurri", MORPHEUS = "Morpheus" }
ns.OUTLINES = { "NONE", "OUTLINE", "THICKOUTLINE" }
local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
-- Option values: key -> name, and sorted key list.
function ns.FontList()
    local v, order = {}, {}
    for _, k in ipairs(FONT_ORDER) do v[k] = FONT_NAMES[k] order[#order + 1] = k end
    local lsm = LSM()
    if lsm then
        for _, name in ipairs(lsm:List("font") or {}) do
            local k = "LSM:" .. name
            if not v[k] then v[k] = name order[#order + 1] = k end
        end
    end
    return v, order
end
local function FontPath(key)
    if FONTS[key] then return FONTS[key] end
    local lsm = LSM()
    if lsm and type(key) == "string" and key:sub(1, 4) == "LSM:" then
        return lsm:Fetch("font", key:sub(5), true)
    end
end
-- Font, size, outline, color of a FontString from a text setting { font, size, outline, color }.
local function ApplyFont(fs, f)
    if not (fs and f) then return end
    local flags = (f.outline and f.outline ~= "NONE") and f.outline or ""
    fs:SetFont(FontPath(f.font) or FONTS.FRIZ, f.size or 10, flags)
    local col = f.color
    if col then fs:SetTextColor(col.r, col.g, col.b, col.a or 1) end
end

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Mark order, clockwise from top (RING / GRID); HROW: left to right, VROW: top to bottom, center gap in the middle.
local ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
local GRID_CELLS = { { 0, 1 }, { 1, 1 }, { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, -1 }, { -1, 0 }, { -1, 1 } }

-- Ping menus (5 types): ring clockwise from top; grid = arc over the center cell
-- (left, top-left, top, top-right, right); rows = center gap after 2.
ns.PING_TYPES = { "ping", "attack", "warning", "onmyway", "assist" }
local GRID5_CELLS = { { -1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 }, { 1, 0 } }

-- Row cell of slot s of nsl slots: first half floor(nsl / 2), center gap, then the rest
-- (8: -4..-1, 1..4; 5: -2, -1, 1, 2, 3).
local function RowCell(s, nsl)
    local left = floor(nsl / 2)
    if s <= left then return s - left - 1 end
    return s - left
end
-- /ping argument per type; "" = plain /ping (contextual "Ping").
local PING_ARG = { ping = "", attack = "attack", warning = "warning", onmyway = "onmyway", assist = "assist" }
-- Atlas candidates per type (first existing one is used; none = gray square + text).
local PING_ATLAS = {
    ping    = { "Ping_Wheel_Icon_NonThreat", "Ping_Marker_Icon_NonThreat", "Ping_Wheel_Icon_Ping" },
    attack  = { "Ping_Wheel_Icon_Attack", "Ping_Marker_Icon_Attack" },
    warning = { "Ping_Wheel_Icon_Warning", "Ping_Marker_Icon_Warning" },
    onmyway = { "Ping_Wheel_Icon_OnMyWay", "Ping_Marker_Icon_OnMyWay" },
    assist  = { "Ping_Wheel_Icon_Assist", "Ping_Marker_Icon_Assist" },
}

-- First existing atlas for a ping type, or nil. Cached: atlases do not change at runtime
-- (GetAtlasInfo allocates a table per call; options and indicator ask repeatedly).
local atlasCache = {} -- [type] = atlas name / false (none)
function ns.PingAtlas(t)
    local a = atlasCache[t]
    if a == nil then
        a = false
        for _, name in ipairs(PING_ATLAS[t] or {}) do
            if GetAtlasInfo(name) then a = name break end
        end
        atlasCache[t] = a
    end
    return a or nil
end

-- Unit macro suffix after "[@unit": ",exists] ARG", or ",exists]" for no arg.
local function UnitSuffix(arg)
    arg = tostring(arg or "")
    return arg == "" and ",exists]" or (",exists] " .. arg)
end

-- Ground / cursor ping macro for a type.
local function PingMacro(t)
    local arg = PING_ARG[t] or ""
    return arg == "" and "/ping" or ("/ping " .. arg)
end

-- Raid icon -> world marker index (/wm): 1 Square, 2 Triangle, 3 Diamond, 4 Cross,
-- 5 Star, 6 Circle, 7 Moon, 8 Skull.
local WORLD_INDEX = { [1] = 5, [2] = 6, [3] = 3, [4] = 2, [5] = 7, [6] = 1, [7] = 4, [8] = 8 }

-- Unit priority -> macro condition (evaluated in the secure snippet on key down).
local UNIT_COND = {
    MOUSEOVER_TARGET = "[@mouseover,exists] mouseover; [@target,exists] target",
    TARGET_MOUSEOVER = "[@target,exists] target; [@mouseover,exists] mouseover",
    MOUSEOVER        = "[@mouseover,exists] mouseover",
    TARGET           = "[@target,exists] target",
}

-- Menu definitions. isunit: macro on a unit (cmd + per icon arg "ua"); else per icon macro "gm".
local DEFS = {
    unit   = { isunit = true,  cmd = "/tm",   pings = false },
    world  = { isunit = false, cmd = "/wm",   pings = false, place = true },
    ping   = { isunit = true,  cmd = "/ping", pings = true },
    pworld = { isunit = false, cmd = "/ping", pings = true, place = true },
}

local S = ns.SNIPPETS -- secure snippets (Snippets.lua)

-- Modifier prefixes for the temp bindings (wheel, center click, toggle click, pending ping),
-- WoW order ALT-CTRL-SHIFT.
local WHEEL_PREFIXES = { "", "ALT-", "CTRL-", "SHIFT-", "ALT-CTRL-", "ALT-SHIFT-", "CTRL-SHIFT-", "ALT-CTRL-SHIFT-" }

-- Mouse button -> binding key.
local MOUSE_KEYS = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

-- Modifier choice -> macro condition that is "1" when exactly these modifiers are held.
local CLICK_COND = {
    NONE             = "[nomod] 1",
    ANY              = "1",
    SHIFT            = "[mod:shift,nomod:ctrl,nomod:alt] 1",
    CTRL             = "[mod:ctrl,nomod:shift,nomod:alt] 1",
    ALT              = "[mod:alt,nomod:shift,nomod:ctrl] 1",
    ["CTRL-SHIFT"]   = "[mod:ctrl,mod:shift,nomod:alt] 1",
    ["ALT-SHIFT"]    = "[mod:alt,mod:shift,nomod:ctrl] 1",
    ["ALT-CTRL"]     = "[mod:alt,mod:ctrl,nomod:shift] 1",
    ["ALT-CTRL-SHIFT"] = "[mod:alt,mod:ctrl,mod:shift] 1",
}
ns.CLICK_BUTTONS = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }

-- Own settings table of a menu kind.
local function OwnOf(kind)
    if kind == "unit" then return ns.db end
    return ns.db[kind]
end

-- Look settings table: world -> raid mark menu, ping -> raid mark menu,
-- world ping -> ping menu (which may itself use the raid mark menu look).
local function LookOf(kind)
    if kind == "unit" then return ns.db end
    local o = ns.db[kind]
    if not o.sameLook then return o end
    if kind == "pworld" then return LookOf("ping") end
    return ns.db
end

-- Center icon macros: unit suffix + ground macro for a mark (raid icon / ping type).
-- place (world marker): CURSOR = /wm [@cursor], CIRCLE = /wm (placement circle).
local function CenterMacros(pings, mark, place)
    if pings then
        local t = PING_ARG[mark] and mark or "ping"
        return UnitSuffix(PING_ARG[t]), PingMacro(t)
    end
    local m = WORLD_INDEX[mark] and mark or 8
    local at = place == "CIRCLE" and "" or "[@cursor] "
    return UnitSuffix(m), "/wm " .. at .. WORLD_INDEX[m]
end

-- Gradient colors, reused by every SetGradient call (values are read at call time).
local gradFrom, gradTo = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)

-- Unit menu in ground mode (no unit) -> menu whose highlight color is used.
local GROUND_LOOK = { unit = "world", ping = "pworld" }

---------------------------------------------------------------- factory
local function NewMenu(kind)
    local M = {}
    local def = DEFS[kind]
    local buttonName = ns.BUTTONS[kind]
    local items = def.pings and ns.PING_TYPES or ORDER
    local N = #items      -- all icons (8 marks / 5 pings)
    local ring, button, driver, kindText, nameText, centerIcon
    -- j = item index 1..N (all icons), k = shown icon index 1..#act, s = geometry slot 1..#slots.
    local regions = {}    -- [j] = region texture (sector / cell)
    local placeBtns = {}  -- [j] = world menu: secure click-to-place button over icon j
    local icons = {}      -- [j] = texture, .item, .ox, .oy
    local act = {}        -- [k] = j: shown icons in order (excluded icons skipped)
    local kOf = {}        -- [j] = k, 0 = excluded
    local slots = {}      -- [s] = { ox, oy, ux, uy, k (0 = empty slot) }
    local startK = 0      -- wheel start icon (k), 0 = none
    local actKey          -- shown icons at the last layout ("last" reset only when they change)
    local startX, startY  -- cursor at key down (ring units), highlight only
    local selected = 0
    local hlArmed = false -- highlight sound: off for the first highlight after open
    local snapGUID        -- unit menus, out of combat: GUID at key down (drift fix)
    local lost = false    -- unit menus, out of combat: snapshot unit has no token (release would fail)
    local pending = false -- layout change blocked by combat
    -- Look extras (textures placed in ApplyLayout, only shown / hidden in combat).
    local bigs = {}       -- [j] = bigger copy of icon j (pop), nil for text icons
    local glows = {}      -- [j] = glow behind icon j
    local anims = {}      -- open animation entries { ag, a (alpha), s (scale) }
    local regionMask      -- RING round outer edge
    local masked = false
    local portrait, dot, pendText, portraitMark
    local markGlow        -- soft glow behind the portrait mark
    local markOutline = {} -- 8 offset copies of the portrait mark (hard outline)
    local curRegs = {}    -- [j] = raid mark menu: region overlay lit when the unit has mark j
    local dims = {}       -- [j] = raid mark menu: black icon-shaped dim overlay, transparent when the unit has mark j
    local UnitInfo        -- defined before Init
    local CurrentRegion   -- defined before Init

    local function Own() return OwnOf(kind) end
    local function Cfg() return LookOf(kind) end

    local function CursorXY()
        local s = ring:GetEffectiveScale()
        local x, y = GetCursorPosition()
        return x / s, y / s
    end

    -- Pie sectors start at the key-down cursor (not ring center). c = Cfg().
    local function UseDirection(c)
        return c.direction and c.layout == "RING" and c.anchor == "CURSOR"
    end

    ------------------------------------------------------------ highlight (insecure)
    -- Same rules as the secure snippet; visual only.
    -- Icon under the cursor: k (1..#act), 0 = none, -1 = empty slot; 2nd value: cursor in center area.
    local function Selection(c)
        local cx, cy = CursorXY()
        local fx, fy = ring:GetCenter()
        if not fx then return 0 end
        if c.layout == "RING" then
            local ox, oy = fx, fy
            if UseDirection(c) then ox, oy = startX, startY end
            local dx, dy = cx - ox, cy - oy
            local dead = c.deadzone
            if dx * dx + dy * dy < dead * dead then return 0, true end -- squared: no sqrt per frame
            local best, bestDot = 0, nil
            for _, sl in ipairs(slots) do
                local d = dx * sl.ux + dy * sl.uy
                if not bestDot or d > bestDot then best, bestDot = sl.k, d end
            end
            return best > 0 and best or -1
        end
        local half = (c.iconSize + c.gap) / 2
        for _, sl in ipairs(slots) do
            if abs(cx - (fx + sl.ox)) <= half and abs(cy - (fy + sl.oy)) <= half then
                return sl.k > 0 and sl.k or -1
            end
        end
        return 0, abs(cx - fx) <= half and abs(cy - fy) <= half
    end

    -- Regions: pie sector (ring) or cell square (grid / row) per icon, under the icons.
    -- Sector = trapezoid via SetVertexOffset (n sectors tile a polygon ring, no gaps).
    -- Geometry set in ApplyLayout; Highlight only recolors.
    -- j = item, s = its slot of nsl slots.
    local function PlaceRegion(j, s, nsl, tex)
        local c = Cfg()
        local icon = icons[j]
        tex = tex or regions[j]
        tex:ClearAllPoints()
        if c.layout == "RING" then
            local ox, oy = 0, 0
            if UseDirection(c) then ox, oy = -c.x, -c.y end
            local a = rad(90 - (s - 1) * 360 / nsl)
            local h = rad(180 / nsl)
            local a1, a2 = a + h, a - h
            local rIn = c.deadzone
            local rOut = c.radius + c.iconSize * 0.75
            -- Round ring: polygon around the mask circle (outer corners cut by the mask).
            if c.roundRing and nsl >= 3 then rOut = rOut / cos(h) end
            -- Slice gap: both sides moved g px into the sector (parallel), inner edge kept outside the crossing.
            local g = (c.sliceGap or 0) / 2
            if g > 0 and nsl > 1 then rIn = max(rIn, g / sin(h) + 1) else g = 0 end
            local n1x, n1y = g * sin(a1), -g * cos(a1)
            local n2x, n2y = -g * sin(a2), g * cos(a2)
            local function P(r, ang, nx, ny) return ox + r * cos(ang) + nx, oy + r * sin(ang) + ny end
            local ix1, iy1 = P(rIn, a1, n1x, n1y)
            local ix2, iy2 = P(rIn, a2, n2x, n2y)
            local ux1, uy1 = P(rOut, a1, n1x, n1y)
            local ux2, uy2 = P(rOut, a2, n2x, n2y)
            -- 1x1 texture at ring center; corners moved to the 4 points.
            tex:SetPoint("CENTER", ring, "CENTER", 0, 0)
            tex:SetSize(1, 1)
            tex:SetVertexOffset(1, ux1 + 0.5, uy1 - 0.5) -- UPPER_LEFT  = outer edge, side 1
            tex:SetVertexOffset(3, ux2 - 0.5, uy2 - 0.5) -- UPPER_RIGHT = outer edge, side 2
            tex:SetVertexOffset(2, ix1 + 0.5, iy1 + 0.5) -- LOWER_LEFT  = inner edge, side 1
            tex:SetVertexOffset(4, ix2 - 0.5, iy2 + 0.5) -- LOWER_RIGHT = inner edge, side 2
        else
            local step = max(1, c.iconSize + c.gap - (c.sliceGap or 0))
            for v = 1, 4 do tex:SetVertexOffset(v, 0, 0) end
            tex:SetPoint("CENTER", ring, "CENTER", icon.ox, icon.oy)
            tex:SetSize(step, step)
        end
    end

    -- k = selected index or 0. Selected: highlight color; others: region color + dimmed icon.
    -- Ground mode (raid mark world fallback / ping auto): highlight from the world / world ping look.
    -- Region color: solid, or gradient (vertical in texture space: LOWER = inner edge, UPPER = outer).
    local function SetRegionColor(tex, r, g, b, a, grad)
        if grad then
            tex:SetColorTexture(1, 1, 1, 1)
            gradFrom:SetRGBA(r, g, b, a * 0.15)
            gradTo:SetRGBA(r, g, b, a)
            tex:SetGradient("VERTICAL", gradFrom, gradTo)
        else
            tex:SetColorTexture(r, g, b, a)
            tex:SetVertexColor(1, 1, 1, 1)
        end
    end

    local function Highlight(k)
        local c = Cfg()
        local hc, rc, dim = c.hlColor, c.regionColor, c.iconDim
        local grad, markColor, pop, glow = c.hlGradient, c.hlMarkColor, c.pop, c.glow
        local hlShow = c.hlShow
        local gk = GROUND_LOOK[kind]
        if gk and ring:GetAttribute("ffground") then
            local g = LookOf(gk)
            hc, hlShow = g.hlColor, g.hlShow
        end
        local useDim = c.curUndim and next(dims) ~= nil
        for j, icon in ipairs(icons) do
            local kj = kOf[j] or 0
            local sel = kj > 0 and kj == k
            local d = (sel or (k == 0 and not c.dimIdle)) and 1 or dim
            local big = bigs[j]
            local usePop = (sel and pop and big) and true or false
            local dt = dims[j]
            if useDim and dt then
                -- Dim by overlay (its sheet cell is transparent on the unit's current mark).
                icon:SetVertexColor(1, 1, 1)
                dt:SetVertexColor(0, 0, 0, 1 - d)
                dt:SetShown(kj > 0 and not usePop and d < 1)
            else
                icon:SetVertexColor(d, d, d)
                if dt then dt:Hide() end
            end
            icon:SetShown(kj > 0 and not usePop)
            if big then big:SetShown(usePop) end
            glows[j]:SetShown((sel and glow) and true or false)
            if icon.label then icon.label:SetAlpha(d) icon.label:SetShown(kj > 0) end
            local tex = regions[j]
            if kj == 0 then
                tex:Hide() -- excluded icon
            elseif sel and hlShow then
                local mc = markColor and ITEM_COLORS[icon.item]
                if mc then
                    SetRegionColor(tex, mc[1], mc[2], mc[3], hc.a, grad)
                else
                    SetRegionColor(tex, hc.r, hc.g, hc.b, hc.a, grad)
                end
                tex:Show()
            elseif c.regionShow then
                SetRegionColor(tex, rc.r, rc.g, rc.b, rc.a, grad)
                tex:Show()
            else
                tex:Hide()
            end
        end
    end

    -- Runs every frame while the menu is shown. Same priority as the secure snippet:
    -- wheel > icon under cursor (hover) > center (center release: none highlighted) > wheel start icon.
    local lastCX, lastCY, lastW -- cursor / wheel choice at the last check (nil = recheck)
    local function OnUpdate()
        local w = ring:GetAttribute("wsel")
        local cx, cy = GetCursorPosition()
        if cx == lastCX and cy == lastCY and w == lastW then hlArmed = true return end
        lastCX, lastCY, lastW = cx, cy, w
        local o = Own()
        local sel
        if w and w > 0 then
            sel = w
        else
            local k, inc = Selection(Cfg())
            if o.hover == false then k = 0 end
            local crelease = o.centerRelease
            if kind == "unit" and o.worldFallback and ring:GetAttribute("ffground") then crelease = ns.db.world.centerRelease end
            if k == 0 and not (inc and crelease) then sel = startK else sel = max(k, 0) end
        end
        if sel ~= selected then
            if hlArmed and sel > 0 and o.hlSound then ns.PlayApplySound(o.hlSoundId) end
            selected = sel
            Highlight(sel)
        end
        hlArmed = true
    end

    -- Menu open: nothing highlighted, highlight sound off until the first OnUpdate.
    -- (Helper keeps M.Init under the Lua 5.1 limit of 60 upvalues.)
    local function ResetHighlight()
        selected = 0
        hlArmed = false
        lastCX = nil
        Highlight(0)
    end

    ------------------------------------------------------------ layout (out of combat)
    local function PlaceFixed()
        local c = Cfg()
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
    end

    -- Unlocked + Fixed: show and allow drag (preview). Shared look: only the look owner previews.
    function M.ApplyLock()
        if InCombatLockdown() then pending = true return end
        local c = Cfg()
        local preview = ns.MenuOn(kind) and not c.locked and c.anchor == "FIXED" and not (kind ~= "unit" and Own().sameLook)
        ring:SetAttribute("preview", preview or nil)
        ring:EnableMouse(preview)
        ring:SetMovable(preview)
        if c.anchor == "FIXED" then PlaceFixed() end
        if preview then
            ring:Show()
        elseif not ring:GetAttribute("active") then
            ring:Hide()
        end
    end

    -- Offset of slot s of nsl slots (grid: cells filled in order, clockwise from top).
    local function Offset(c, s, step, nsl)
        if c.layout == "GRID" then
            local cell = (N == 8 and GRID_CELLS or GRID5_CELLS)[s]
            return cell[1] * step, cell[2] * step
        elseif c.layout == "HROW" then
            return RowCell(s, nsl) * step, 0
        elseif c.layout == "VROW" then
            return 0, -RowCell(s, nsl) * step
        end
        local a = rad(90 - (s - 1) * 360 / nsl)
        return c.radius * cos(a), c.radius * sin(a)
    end

    -- Shown icons (exclude option, at least one) and geometry slots (keep slots: all N, else shown only).
    local function BuildSlots(o)
        local excl = o.exclude or {}
        for k in ipairs(act) do act[k] = nil end
        for j, it in ipairs(items) do
            if excl[it] then
                kOf[j] = 0
            else
                act[#act + 1] = j
                kOf[j] = #act
            end
        end
        if #act == 0 then act[1] = 1 kOf[1] = 1 end
        local nsl = o.keepSlots and N or #act
        for s in ipairs(slots) do slots[s] = nil end
        for s = 1, nsl do
            local j = o.keepSlots and s or act[s]
            slots[s] = { j = j, k = kOf[j] }
        end
        -- Wheel start icon (wheel on, icon shown).
        startK = 0
        if o.wheel and o.wheelStart then
            for j, it in ipairs(items) do
                if it == o.wheelStart then startK = kOf[j] break end
            end
        end
    end

    function M.ApplyLayout()
        if not ring then return end
        if InCombatLockdown() then pending = true return end
        pending = false
        local c = Cfg()
        local o = Own()
        local size, gap = c.iconSize, c.gap
        local step = size + gap
        local rowMax = 0
        BuildSlots(o)
        local nsl = #slots
        for s, sl in ipairs(slots) do
            sl.ox, sl.oy = Offset(c, s, step, nsl)
            if c.layout == "HROW" or c.layout == "VROW" then rowMax = max(rowMax, abs((sl.ox + sl.oy) / step)) end
            local len = sqrt(sl.ox * sl.ox + sl.oy * sl.oy)
            if len > 0 then sl.ux, sl.uy = sl.ox / len, sl.oy / len else sl.ux, sl.uy = 0, 1 end
            ring:SetAttribute("ix" .. s, sl.ox)
            ring:SetAttribute("iy" .. s, sl.oy)
            ring:SetAttribute("ux" .. s, sl.ux)
            ring:SetAttribute("uy" .. s, sl.uy)
            ring:SetAttribute("sk" .. s, sl.k)
            local icon = icons[sl.j]
            icon.ox, icon.oy = sl.ox, sl.oy
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", ring, "CENTER", sl.ox, sl.oy)
            icon:SetSize(size, size)
            -- Look extras over / around the icon.
            local mc = ITEM_COLORS[icon.item]
            local big = bigs[sl.j]
            if big then
                local ps = size * (c.popSize or 1.15)
                big:ClearAllPoints()
                big:SetPoint("CENTER", ring, "CENTER", sl.ox, sl.oy)
                big:SetSize(ps, ps)
            end
            local cr = curRegs[sl.j]
            if cr then
                local cc = c.curRegionColor or { r = 1, g = 0.2, b = 0.2, a = 0.45 }
                -- White sheet cell tinted by vertex color.
                if c.curRegionMarkColor and mc then cr:SetVertexColor(mc[1], mc[2], mc[3], cc.a) else cr:SetVertexColor(cc.r, cc.g, cc.b, cc.a) end
            end
            local gl = glows[sl.j]
            gl:ClearAllPoints()
            gl:SetPoint("CENTER", ring, "CENTER", sl.ox, sl.oy)
            gl:SetSize(size * 1.9, size * 1.9)
            local gc = c.glowColor or { r = 1, g = 0.82, b = 0, a = 0.9 }
            if c.hlMarkColor and mc then gl:SetVertexColor(mc[1], mc[2], mc[3], gc.a) else gl:SetVertexColor(gc.r, gc.g, gc.b, gc.a) end
            if icon.label then
                icon.label:ClearAllPoints()
                icon.label:SetPoint("CENTER", icon, "CENTER", 0, 0)
                icon.label:SetWidth(size + gap + 8)
            end
            if sl.k > 0 then
                PlaceRegion(sl.j, s, nsl)
                if curRegs[sl.j] then PlaceRegion(sl.j, s, nsl, curRegs[sl.j]) end
            end
        end
        ring:SetAttribute("ns", nsl)
        -- Round ring: circle mask on the regions (RING only).
        local wantMask = c.layout == "RING" and c.roundRing and true or false
        if wantMask ~= masked then
            for _, tex in ipairs(regions) do
                if wantMask then tex:AddMaskTexture(regionMask) else tex:RemoveMaskTexture(regionMask) end
            end
            for _, tex in pairs(curRegs) do
                if wantMask then tex:AddMaskTexture(regionMask) else tex:RemoveMaskTexture(regionMask) end
            end
            masked = wantMask
        end
        if wantMask then
            local mx, my = 0, 0
            if UseDirection(c) then mx, my = -c.x, -c.y end
            local r = c.radius + size * 0.75
            regionMask:ClearAllPoints()
            regionMask:SetPoint("CENTER", ring, "CENTER", mx, my)
            regionMask:SetSize(2 * r, 2 * r)
        end
        -- Open animation: alpha 0 -> 1, scale: GROW 85% -> 100%.
        local am = c.openAnim or "OFF"
        local dur = (c.openAnimTime or 120) / 1000
        for _, e in ipairs(anims) do
            e.a:SetDuration(dur)
            e.s:SetDuration(dur)
            local from = am == "GROW" and 0.85 or 1
            e.s:SetScaleFrom(from, from)
            e.s:SetScaleTo(1, 1)
            e.s:SetOrigin("CENTER", 0, 0)
        end
        -- Unit portrait (raid mark / ping menu).
        local pSize = 0
        if def.isunit and o.portrait then pSize = o.portraitSize or 60 end
        portrait:SetSize(max(pSize, 1), max(pSize, 1))
        portrait:SetAlpha(o.portraitAlpha or 0.8)
        -- Per shown icon k: unit suffix "ua" / ground macro "gm".
        for k, j in ipairs(act) do
            local it = items[j]
            if def.pings then
                ring:SetAttribute("ua" .. k, UnitSuffix(PING_ARG[it]))
                ring:SetAttribute("gm" .. k, PingMacro(it))
            else
                if def.isunit then ring:SetAttribute("ua" .. k, UnitSuffix(it)) end
                ring:SetAttribute("gm" .. k, "/wm [@cursor] " .. WORLD_INDEX[it]) -- raid mark menu: world fallback (no unit)
            end
        end
        -- Click to place buttons (world marker / world ping menu): over each shown icon, mouse only when enabled.
        if def.place then
            local place = o.clickPlace and true or false
            local cbtn = o.clickButton or (def.pings and "LeftButton" or "RightButton")
            for j, b in ipairs(placeBtns) do
                local on = place and kOf[j] > 0
                b:ClearAllPoints()
                b:SetPoint("CENTER", ring, "CENTER", icons[j].ox or 0, icons[j].oy or 0)
                b:SetSize(size, size)
                b:SetAttribute("idx", kOf[j]) -- pending ping: shown icon index (gm..k)
                if not def.pings then b:SetAttribute("wm", "/wm " .. WORLD_INDEX[icons[j].item]) end -- PLACE_PRE -> macrotext
                b:RegisterForClicks(cbtn .. "Up")
                b:EnableMouse(on)
                b:SetShown(on)
            end
            ring:SetAttribute("clickbtn", cbtn)
            ring:SetAttribute("clickcond", CLICK_COND[o.clickMod] or CLICK_COND.ANY)
            if def.pings then
                ring:SetAttribute("pkey", MOUSE_KEYS[cbtn] or "BUTTON1")
                -- Cancel: right click; place button = right -> left click.
                ring:SetAttribute("ckey", cbtn == "RightButton" and "BUTTON1" or "BUTTON2")
            end
        end
        Highlight(selected)
        -- Center icon: shown with center release only (release mark / ping), look from the look settings.
        local cs = 0
        if o.centerRelease and not c.centerIconHide then
            cs = c.centerIconSize or 24
            if def.pings then
                local t = PING_ARG[o.centerReleaseMark] and o.centerReleaseMark or "ping"
                local atlas = ns.PingAtlas(t)
                if atlas then centerIcon:SetAtlas(atlas) else centerIcon:SetColorTexture(0.25, 0.25, 0.25, 0.9) end
            else
                centerIcon:SetTexture(ICON_PATH .. (WORLD_INDEX[o.centerReleaseMark] and o.centerReleaseMark or 8))
            end
            centerIcon:SetSize(cs, cs)
            centerIcon:SetAlpha(c.centerIconAlpha or 0.5)
            centerIcon:ClearAllPoints()
            centerIcon:SetPoint("CENTER", ring, "CENTER", c.centerIconX or 0, c.centerIconY or 0)
            centerIcon:Show()
        else
            centerIcon:Hide()
        end
        portrait:ClearAllPoints()
        portrait:SetPoint("CENTER", ring, "CENTER", o.portraitX or 0, o.portraitY or 0)
        local pms = o.portraitMarkSize or 24
        portraitMark:SetSize(pms, pms)
        portraitMark:ClearAllPoints()
        portraitMark:SetPoint("CENTER", portrait, "CENTER", o.portraitMarkX or 20, o.portraitMarkY or 20)
        -- Mark glow: soft = glow texture around the mark, outline = 8 copies offset by the glow size.
        local gcol = o.portraitMarkGlowColor or { r = 1, g = 1, b = 1, a = 0.9 }
        local gsz = o.portraitMarkGlowSize or 2
        markGlow:ClearAllPoints()
        markGlow:SetPoint("CENTER", portraitMark, "CENTER", 0, 0)
        markGlow:SetSize(pms * 1.9 + gsz * 2, pms * 1.9 + gsz * 2)
        markGlow:SetVertexColor(gcol.r, gcol.g, gcol.b, gcol.a)
        for i, t in ipairs(markOutline) do
            local a = rad((i - 1) * 45)
            t:ClearAllPoints()
            t:SetPoint("CENTER", portraitMark, "CENTER", gsz * cos(a), gsz * sin(a))
            t:SetSize(pms, pms)
            t:SetVertexColor(gcol.r, gcol.g, gcol.b, gcol.a)
        end
        -- Center dot.
        local dc = c.dotColor or { r = 1, g = 1, b = 1, a = 0.35 }
        dot:SetSize(c.dotSize or 6, c.dotSize or 6)
        dot:SetColorTexture(dc.r, dc.g, dc.b, dc.a)
        dot:SetShown(c.dotShow ~= false)
        -- Unit label below the center icon / portrait (+ offset), unit name below the label (+ offset).
        local fl, fn = c.fontLabel or {}, c.fontName or {}
        ApplyFont(kindText, fl)
        ApplyFont(nameText, fn)
        kindText:ClearAllPoints()
        local co = max(cs, pSize)
        kindText:SetPoint("TOP", ring, "CENTER", fl.x or 0, (co > 0 and -(co / 2 + 2) or -6) + (fl.y or 0))
        nameText:ClearAllPoints()
        nameText:SetPoint("TOP", kindText, "BOTTOM", fn.x or 0, -1 + (fn.y or 0))
        -- Ping icon text (no atlas) and pending ping text.
        local fp = c.fontPing or {}
        for _, icon in ipairs(icons) do
            if icon.label then
                ApplyFont(icon.label, fp)
                icon.label:ClearAllPoints()
                icon.label:SetPoint("CENTER", icon, "CENTER", fp.x or 0, fp.y or 0)
            end
        end
        if pendText then
            local fe = o.fontPend or {}
            ApplyFont(pendText, fe)
            pendText:ClearAllPoints()
            pendText:SetPoint("LEFT", pendText:GetParent(), "RIGHT", 2 + (fe.x or 0), fe.y or 0)
        end
        -- Frame size: bounding box of the icons.
        local w, h
        if c.layout == "GRID" then
            w = 3 * size + 2 * gap
            h = w
        elseif c.layout == "HROW" then
            w, h = (2 * rowMax + 1) * size + 2 * rowMax * gap, size
        elseif c.layout == "VROW" then
            w, h = size, (2 * rowMax + 1) * size + 2 * rowMax * gap
        else
            w = 2 * c.radius + size
            h = w
        end
        -- Ring frame = mouse area for the secure pick (GetMousePosition is nil outside it).
        local pad = max(w, h) + 2 * max(abs(c.x), abs(c.y))
        ring:SetSize(w + pad, h + pad)
        ring:SetScale(c.scale)
        ring:SetAlpha(c.alpha)

        ring:SetAttribute("off", not ns.MenuOn(kind) or nil)
        ring:SetAttribute("n", #act)
        ring:SetAttribute("wstart", startK > 0 and startK or nil)
        local ak = concat(act, ",")
        if ak ~= actKey then
            actKey = ak
            ring:SetAttribute("last", nil) -- shown icon indexes changed (exclude)
        end
        ring:SetAttribute("crelease", o.centerRelease or nil)
        -- No unit at key down: ping = ground ping, raid mark = world marker (option).
        ring:SetAttribute("auto", (kind == "ping" and o.auto) or (kind == "unit" and o.worldFallback) or nil)
        ring:SetAttribute("ucond", UNIT_COND[o.unitOrder] or UNIT_COND.MOUSEOVER_TARGET)
        ring:SetAttribute("anchor", c.anchor)
        ring:SetAttribute("offx", c.x)
        ring:SetAttribute("offy", c.y)
        ring:SetAttribute("dir", UseDirection(c) or nil)
        ring:SetAttribute("dead", c.deadzone)
        ring:SetAttribute("half", step / 2)
        ring:SetAttribute("ring", c.layout == "RING" or nil)
        -- Release in center: unit arg "cua" / ground macro "cgm"; nil = cancel.
        local cua, cgm
        if kind == "unit" and o.center == "CLEAR" then cua = UnitSuffix(0) end
        -- Raid mark world fallback: center release follows the world menu center action.
        local wc = (kind == "world" and o.center) or (kind == "unit" and ns.db.world.center)
        if wc == "CLEAR_ALL" then cgm = "/cwm all" end
        ring:SetAttribute("cua", cua)
        ring:SetAttribute("cgm", cgm)
        ring:SetAttribute("hover", o.hover ~= false or nil)
        ring:SetAttribute("toggle", o.toggle or nil)
        ring:SetAttribute("escclose", o.escClose ~= false or nil)
        ring:SetAttribute("nopick", o.noPick or "CANCEL")
        ring:SetAttribute("wheel", o.wheel or nil)
        ring:SetAttribute("wheelccw", o.wheelDir == "CCW" or nil)
        -- Click in center: bind rows "cb*"..b (mouse button, binding key, modifier condition, macros).
        local binds = o.centerBinds or {}
        ring:SetAttribute("cclick", (o.centerClick and #binds > 0) or nil)
        ring:SetAttribute("cbn", #binds)
        for b, row in ipairs(binds) do
            local mb = MOUSE_KEYS[row.btn] and row.btn or "LeftButton"
            ring:SetAttribute("cbb" .. b, mb)
            ring:SetAttribute("cbk" .. b, MOUSE_KEYS[mb])
            ring:SetAttribute("cbc" .. b, CLICK_COND[row.mod] or CLICK_COND.ANY)
            local ua, gm = CenterMacros(def.pings, row.mark, row.place)
            ring:SetAttribute("cbua" .. b, ua)
            ring:SetAttribute("cbgm" .. b, gm)
        end
        -- Fast mark: mode (nil = off), unit suffix "fua" / ground macro "fgm" for icon 1 / 2.
        ring:SetAttribute("fast", o.fast and (o.fastNoLimit and (o.fastNoLimitMode or "EMPTY") or "TAP") or nil)
        local fi1, fi2
        if def.pings then
            fi1 = PING_ARG[o.fastIcon] and o.fastIcon or "ping"
            fi2 = PING_ARG[o.fastIcon2] and o.fastIcon2 or "attack"
            ring:SetAttribute("fua1", UnitSuffix(PING_ARG[fi1]))
            ring:SetAttribute("fua2", UnitSuffix(PING_ARG[fi2]))
            ring:SetAttribute("fgm1", PingMacro(fi1))
            ring:SetAttribute("fgm2", PingMacro(fi2))
        else
            fi1 = WORLD_INDEX[o.fastIcon] and o.fastIcon or 8
            fi2 = WORLD_INDEX[o.fastIcon2] and o.fastIcon2 or 7
            ring:SetAttribute("fua1", UnitSuffix(fi1))
            ring:SetAttribute("fua2", UnitSuffix(fi2))
            ring:SetAttribute("fgm1", "/wm [@cursor] " .. WORLD_INDEX[fi1])
            -- Double tap, ground: 1st marker removed, 2nd placed.
            ring:SetAttribute("fgm2", "/cwm " .. WORLD_INDEX[fi1] .. "\n/wm [@cursor] " .. WORLD_INDEX[fi2])
        end
        -- Fast mark in combat: unit priority / no unit action, unit suffix "cfua" / ground macro "cfgm".
        ring:SetAttribute("cfast", o.combatFast or nil)
        ring:SetAttribute("cfucond", UNIT_COND[o.combatFastUnit] or UNIT_COND.MOUSEOVER_TARGET)
        ring:SetAttribute("cfnounit", o.combatFastNoUnit or "NONE")
        if def.pings then
            local t = PING_ARG[o.combatFastIcon] and o.combatFastIcon or "ping"
            ring:SetAttribute("cfua", UnitSuffix(PING_ARG[t]))
            ring:SetAttribute("cfgm", PingMacro(t))
        else
            local m = WORLD_INDEX[o.combatFastIcon] and o.combatFastIcon or 8
            ring:SetAttribute("cfua", UnitSuffix(m))
            ring:SetAttribute("cfgm", "/wm [@cursor] " .. WORLD_INDEX[m])
        end
        -- Center release: unit suffix "crua" / ground macro "crgm".
        local rua, rgm = CenterMacros(def.pings, o.centerReleaseMark, o.centerReleasePlace)
        ring:SetAttribute("crua", rua)
        ring:SetAttribute("crgm", rgm)
        -- Raid mark world fallback (no unit): center release / click in center from the world menu ("g" prefix).
        local gset = kind == "unit" and o.worldFallback and ns.db.world
        ring:SetAttribute("gset", gset and true or nil)
        if gset then
            local _, grgm = CenterMacros(false, gset.centerReleaseMark, gset.centerReleasePlace)
            ring:SetAttribute("gcrelease", gset.centerRelease or nil)
            ring:SetAttribute("gcrgm", grgm)
            local gb = gset.centerBinds or {}
            ring:SetAttribute("gcclick", (gset.centerClick and #gb > 0) or nil)
            ring:SetAttribute("gcbn", #gb)
            for b, row in ipairs(gb) do
                local mb = MOUSE_KEYS[row.btn] and row.btn or "LeftButton"
                local _, gm = CenterMacros(false, row.mark, row.place)
                ring:SetAttribute("gcbb" .. b, mb)
                ring:SetAttribute("gcbk" .. b, MOUSE_KEYS[mb])
                ring:SetAttribute("gcbc" .. b, CLICK_COND[row.mod] or CLICK_COND.ANY)
                ring:SetAttribute("gcbgm" .. b, gm)
            end
        end
        M.ApplyLock()
    end

    -- Ring attributes that never change (set once from M.Init).
    function M.InitAttributes()
        ring:SetAttribute("isunit", def.isunit or nil)
        ring:SetAttribute("cmd", def.cmd)
        ring:SetAttribute("mainbtn", buttonName)
        ring:SetAttribute("cancelbtn", ns.CANCEL_BUTTONS[kind])
        ring:SetAttribute("wheelbtn", ns.WHEEL_BUTTONS[kind])
        ring:SetAttribute("cbtnname", ns.CENTER_BUTTONS[kind])
        for i, p in ipairs(WHEEL_PREFIXES) do ring:SetAttribute("wp" .. i, p) end
        if def.pings and def.place then
            ring:SetAttribute("pendbtn", ns.PEND_BUTTON)
            ring:SetAttribute("pendcancel", ns.PEND_CANCEL_BUTTON)
        end
    end

    function M.ApplyPending()
        if pending then M.ApplyLayout() end
        -- Stuck temp binds (pending ping keeps its binds).
        if ring and not ring:IsShown() and not ring:GetAttribute("pend") then ClearOverrideBindings(ring) end
    end

    ------------------------------------------------------------ unit drift fix
    -- Insecure PreClick runs before the secure OnClick snippet. Out of combat only.
    -- Hooked on unit menu buttons only (raid mark, ping).
    local function PreClick(_, _, down)
        if InCombatLockdown() then snapGUID = nil return end
        -- Toggle mode: keep the key-down snapshot while the menu is open
        -- (2nd press = no new snapshot; up of the opening press = no fix yet).
        if ring:GetAttribute("active") and ring:GetAttribute("toggle") then
            if down or not ring:GetAttribute("fire") then return end
        end
        if down then
            snapGUID = nil
            local unit = SecureCmdOptionParse(UNIT_COND[Own().unitOrder] or UNIT_COND.MOUSEOVER_TARGET)
            if unit == "mouseover" then
                local guid = UnitGUID("mouseover")
                if guid and not issecret(guid) then snapGUID = guid end
            end
        else
            if snapGUID and ring:GetAttribute("ffunit") == "mouseover" and not ring:GetAttribute("ffground") then
                -- Same unit still under cursor: keep. Moved off: find another token for it
                -- (nameplate / target / ...). Not found: keep "mouseover" (no wrong-unit fallback).
                local mg = UnitGUID("mouseover")
                if not (mg and not issecret(mg) and mg == snapGUID) then
                    local token = UnitTokenFromGUID(snapGUID)
                    if token then ring:SetAttribute("ffunit", token) end
                end
            end
            snapGUID = nil -- always cleared on key up: no stale GUID after an aborted press
        end
    end

    local function PostClick(self, _, down)
        if down then return end
        local m = self:GetAttribute("macrotext")
        if ns.db.debug then ns.Debug(kind .. ": " .. tostring(m)) end
        -- Sound on apply (option): snippets clear macrotext first, set it only when applying.
        if m and m ~= "" and Own().sound and MacroActs(m) then ns.PlayApplySound(Own().soundId) end
    end

    ------------------------------------------------------------ fast mark timing (insecure)
    -- GetTime is not available in secure snippets: hold time / double tap measured here.
    -- Results go to ring attributes ("ftap", "fidx") before the secure snippet runs at key up.
    -- Out of combat only (attributes of the protected ring are locked in combat).
    local fastDown    -- GetTime at key down (new press, menu not open)
    local fastLast    -- GetTime of the last fast icon 1 (double tap window start)
    local function FastPre(_, _, down)
        if down then
            -- Toggle mode 2nd press (menu open) is not a new press.
            if ring:GetAttribute("active") then fastDown = nil else fastDown = GetTime() end
            return
        end
        local t0 = fastDown
        fastDown = nil
        local o = Own()
        if not o.fast or InCombatLockdown() then return end
        local now = GetTime()
        local mode = o.fastNoLimit and (o.fastNoLimitMode or "EMPTY") or "TAP"
        if t0 and (mode == "TAP" or mode == "BOTH") and (now - t0) * 1000 < (o.fastTime or 200) then
            ring:SetAttribute("ftap", true)
        end
        if o.fastDouble and fastLast and (now - fastLast) * 1000 <= (o.fastDoubleTime or 400) then
            ring:SetAttribute("fidx", 2)
        end
    end
    -- After the click: fast icon 1 applied = double tap window starts; anything else = reset.
    local function FastPost(_, _, down)
        if down then return end
        fastLast = ring:GetAttribute("fdone") == 1 and GetTime() or nil
    end

    ------------------------------------------------------------ init
    local function SetIcon(icon, it)
        if not def.pings then
            icon:SetTexture(ICON_PATH .. it)
            return
        end
        local atlas = ns.PingAtlas(it)
        if atlas then
            icon:SetAtlas(atlas)
        else
            -- No atlas in this client: gray square + name.
            icon:SetColorTexture(0.25, 0.25, 0.25, 0.9)
            icon.label = ring:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            icon.label:SetText(L.PING_NAMES[it] or it)
        end
    end

    -- Raid mark icon on a texture. Secret index (Forever): passed straight to texture functions
    -- (no compare / math in our code); first one that does not error wins. Returns method or nil.
    local function SetMarkTexture(tex, idx, secret)
        if secret then
            tex:SetTexture(ICON_SHEET)
            if SetRaidTargetIconTexture and pcall(SetRaidTargetIconTexture, tex, idx) then return "SetRaidTargetIconTexture" end
            if tex.SetSpriteSheetCell and pcall(tex.SetSpriteSheetCell, tex, idx, 4, 4) then return "SetSpriteSheetCell" end
            return nil
        end
        if not idx then return nil end
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetTexture(ICON_PATH .. idx)
        return "plain"
    end

    -- Raid mark menu: light the region of the mark the unit already has. Each region overlay uses
    -- its own 4x4 sheet (Textures\\CurMark<item>.tga): only the cell of its mark is white. The mark
    -- index (secret in Forever) picks the shown cell through texture functions that accept secret
    -- values, so only the region of the unit's mark shows white: no compare / math in our code.
    CurrentRegion = function(idx, secret)
        local how
        for j, tex in pairs(curRegs) do
            if (kOf[j] or 0) > 0 then
                local sheet = CUR_SHEETS[items[j]]
                local m
                if secret then
                    tex:SetTexture(sheet, nil, nil, "NEAREST")
                    if tex.SetSpriteSheetCell and pcall(tex.SetSpriteSheetCell, tex, idx, 4, 4) then
                        m = "SetSpriteSheetCell"
                    elseif SetRaidTargetIconTexture and pcall(SetRaidTargetIconTexture, tex, idx) then
                        tex:SetTexture(sheet, nil, nil, "NEAREST") -- keep own sheet (tex coords stay)
                        m = "SetRaidTargetIconTexture"
                    end
                elseif items[j] == idx then
                    tex:SetTexture(sheet, nil, nil, "NEAREST")
                    local c = idx - 1
                    local x, y = (c % 4) * 0.25, floor(c / 4) * 0.25
                    tex:SetTexCoord(x, x + 0.25, y, y + 0.25)
                    m = "plain"
                end
                if m then tex:Show() how = m end
            end
        end
        if ns.db.debug then ns.Debug("current region: secret " .. tostring(secret) .. ", method " .. tostring(how)) end
    end

    -- Raid mark menu: dim overlays. Default cell 16 (opaque on every sheet) = all icons dimmed.
    -- With a mark index the same cell is picked on every sheet: only the overlay of that mark is
    -- transparent (secret index passed straight to texture functions, as in CurrentRegion).
    local function ResetDims()
        for j, tex in pairs(dims) do
            tex:SetTexture(DIM_SHEETS[items[j]], nil, nil, "NEAREST")
            tex:SetTexCoord(0.75, 1, 0.75, 1)
        end
    end
    local function CurrentDim(idx, secret)
        local how
        for j, tex in pairs(dims) do
            local sheet = DIM_SHEETS[items[j]]
            if secret then
                if tex.SetSpriteSheetCell and pcall(tex.SetSpriteSheetCell, tex, idx, 4, 4) then
                    how = "SetSpriteSheetCell"
                elseif SetRaidTargetIconTexture and pcall(SetRaidTargetIconTexture, tex, idx) then
                    tex:SetTexture(sheet, nil, nil, "NEAREST") -- keep own sheet (tex coords stay)
                    how = "SetRaidTargetIconTexture"
                else
                    tex:SetTexture(sheet, nil, nil, "NEAREST")
                    tex:SetTexCoord(0.75, 1, 0.75, 1)
                end
            elseif idx then
                local c = idx - 1
                local x, y = (c % 4) * 0.25, floor(c / 4) * 0.25
                tex:SetTexCoord(x, x + 0.25, y, y + 0.25)
                how = "plain"
            end
        end
        if ns.db.debug then ns.Debug("current dim: secret " .. tostring(secret) .. ", method " .. tostring(how)) end
    end

    -- Unit info on open: portrait + its raid mark icon (with glow / outline). Insecure, visual only.
    UnitInfo = function(active)
        if ns.db.debug then
            ns.Debug(kind .. " unit info: active " .. tostring(active) .. ", ground " .. tostring(ring:GetAttribute("ffground"))
                .. ", unit " .. tostring(ring:GetAttribute("ffunit")) .. ", portrait mark " .. tostring(Own().portraitMark))
        end
        portrait:Hide()
        portraitMark:Hide()
        markGlow:Hide()
        for _, t in ipairs(markOutline) do t:Hide() end
        for _, t in pairs(curRegs) do t:Hide() end
        ResetDims()
        if not active or not def.isunit or ring:GetAttribute("ffground") then return end
        local unit = ring:GetAttribute("ffunit")
        if not unit then return end
        local o = Own()
        if o.portrait and SetPortraitTexture and not (centerIcon:IsShown() and o.portraitMode ~= "BEHIND") then
            SetPortraitTexture(portrait, unit)
            portrait:Show()
        end
        local wantPortrait = portrait:IsShown() and o.portraitMark
        local wantRegion = not def.pings and Cfg().curRegion
        local wantDim = next(dims) ~= nil and Cfg().curUndim
        if not (wantPortrait or wantRegion or wantDim) then return end
        if not GetRaidTargetIndex then
            if ns.db.debug then ns.Debug("current mark: GetRaidTargetIndex missing") end
            return
        end
        local idx = GetRaidTargetIndex(unit)
        local secret = issecret(idx) -- checked first: no compare on a secret value
        if not secret and idx == nil then return end
        if wantRegion then CurrentRegion(idx, secret) end
        if wantDim then CurrentDim(idx, secret) end
        if not wantPortrait then return end
        -- Mark icon (and outline copies) on the portrait.
        local how = SetMarkTexture(portraitMark, idx, secret)
        if how then
            portraitMark:Show()
            local gm = o.portraitMarkGlow or "OFF"
            if gm == "SOFT" then
                markGlow:Show()
            elseif gm == "OUTLINE" then
                for _, t in ipairs(markOutline) do
                    if SetMarkTexture(t, idx, secret) then t:Show() end
                end
            end
        end
        if ns.db.debug then ns.Debug("portrait mark: secret " .. tostring(secret) .. ", method " .. tostring(how)) end
    end

    -- Unit label color: unit colors (option) or the label font color.
    local function LabelColor(r, g, b)
        local fl = Cfg().fontLabel
        if fl and fl.unitColors == false and fl.color then
            kindText:SetTextColor(fl.color.r, fl.color.g, fl.color.b, fl.color.a or 1)
        else
            kindText:SetTextColor(r, g, b)
        end
    end

    -- Lost unit (out of combat): hovered unit left the cursor and has no other token.
    -- Ring dimmed + red "Lost" label; restored when the unit is reachable again.
    local LOST_ALPHA = 0.4
    local function LostReset()
        if not lost then return end
        lost = false
        -- Protected ring: alpha restored by ApplyLayout after combat if blocked now.
        if InCombatLockdown() then pending = true else ring:SetAlpha(Cfg().alpha) end
    end
    local LOST_PERIOD = 0.1 -- s between checks (UnitTokenFromGUID scans unit tokens)
    local lostWait = 0
    local function LostCheck(_, elapsed)
        lostWait = lostWait - (elapsed or 0)
        if lostWait > 0 then return end
        lostWait = LOST_PERIOD
        if not snapGUID or InCombatLockdown() or ring:GetAttribute("ffunit") ~= "mouseover"
            or ring:GetAttribute("ffground") then return end
        local mg = UnitGUID("mouseover")
        local ok = (mg and not issecret(mg) and mg == snapGUID)
            or UnitTokenFromGUID(snapGUID) ~= nil
        if ok ~= lost then return end -- no change (ok == not lost)
        if ok then
            LostReset()
            kindText:SetText(kind == "ping" and L.PING_UNIT:format(L.UNIT_MOUSEOVER) or L.UNIT_MOUSEOVER)
            LabelColor(0.3, 1, 0.3)
        else
            lost = true
            ring:SetAlpha(Cfg().alpha * LOST_ALPHA)
            kindText:SetText(L.UNIT_LOST)
            kindText:SetTextColor(1, 0.2, 0.2)
        end
    end
    -- Called from M.Init (keeps Init's upvalue count unchanged).
    function M.LostHooks(d)
        d:HookScript("OnUpdate", LostCheck)
        d:HookScript("OnHide", LostReset)
        d:HookScript("OnShow", function() lostWait = 0 end) -- first check right on open
    end

    -- Raid mark menu extras of icon k (kept out of M.Init: Lua 5.1 limit of 60 upvalues per function).
    local function MakeUnitExtras(k, it, icon)
        local cr = ring:CreateTexture(nil, "BORDER", nil, 1) -- above region, under icons
        cr:Hide()
        curRegs[k] = cr
        -- Dim overlay: above the icon, under the pop copy; icon-shaped by a fixed mask.
        local dt = ring:CreateTexture(nil, "ARTWORK", nil, 1)
        dt:SetAllPoints(icon)
        dt:SetTexture(DIM_SHEETS[it], nil, nil, "NEAREST")
        dt:SetTexCoord(0.75, 1, 0.75, 1)
        local dm = ring:CreateMaskTexture()
        dm:SetTexture(ICON_PATH .. it, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        dm:SetAllPoints(icon)
        dt:AddMaskTexture(dm)
        dt:Hide()
        dims[k] = dt
        return dt
    end

    function M.Init()
        ring = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
        ring:SetFrameStrata("DIALOG")
        ring:Hide()
        ring:RegisterForDrag("LeftButton")
        ring:SetScript("OnDragStart", function(self) if self:IsMovable() then self:StartMoving() end end)
        ring:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local fx, fy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            local r = UIParent:GetEffectiveScale() / self:GetEffectiveScale()
            local c = Cfg()
            c.x = floor(fx - ux * r + 0.5)
            c.y = floor(fy - uy * r + 0.5)
            ns.ApplyAllLayouts()
            if ns.Options then ns.Options.Refresh() end
        end)

        -- Center dot (ring center = deadzone center).
        dot = ring:CreateTexture(nil, "BACKGROUND", nil, 2)
        dot:SetPoint("CENTER") -- size / color: ApplyLayout

        -- Center icon (center release on, not hidden): texture / size / point set in ApplyLayout.
        centerIcon = ring:CreateTexture(nil, "ARTWORK")
        centerIcon:Hide()

        -- Unit portrait (round): above the regions (BORDER), under the icons / center icon.
        portrait = ring:CreateTexture(nil, "ARTWORK", nil, -2)
        portrait:SetPoint("CENTER")
        portrait:Hide()
        local pm = ring:CreateMaskTexture()
        pm:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        pm:SetAllPoints(portrait)
        portrait:AddMaskTexture(pm)
        -- Current mark icon over the portrait.
        portraitMark = ring:CreateTexture(nil, "OVERLAY", nil, 1)
        portraitMark:Hide()
        markGlow = ring:CreateTexture(nil, "OVERLAY", nil, -1)
        markGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        markGlow:SetBlendMode("ADD")
        markGlow:Hide()
        for i = 1, 8 do
            local t = ring:CreateTexture(nil, "OVERLAY", nil, 0)
            t:SetDesaturated(true) -- tinted silhouette in the glow color
            t:Hide()
            markOutline[i] = t
        end

        regionMask = ring:CreateMaskTexture()
        regionMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

        -- Label: unit menus = which unit gets the mark / ping (name may be secret: SetText only).
        kindText = ring:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        kindText:SetPoint("TOP", ring, "CENTER", 0, -6)
        nameText = ring:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("TOP", kindText, "BOTTOM", 0, -1)

        for k, it in ipairs(items) do
            local icon = ring:CreateTexture(nil, "ARTWORK")
            icon.item = it
            SetIcon(icon, it)
            icons[k] = icon
            regions[k] = ring:CreateTexture(nil, "BORDER")
            -- Pop copy (not for text icons), glow; raid mark menu: current mark region + dim overlay.
            if not icon.label then
                local big = ring:CreateTexture(nil, "ARTWORK", nil, 2)
                big.item = it
                SetIcon(big, it)
                big:Hide()
                bigs[k] = big
            end
            local gl = ring:CreateTexture(nil, "ARTWORK", nil, -1)
            gl:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            gl:SetBlendMode("ADD")
            gl:Hide()
            glows[k] = gl
            local dimTex = kind == "unit" and MakeUnitExtras(k, it, icon) or nil
            -- Open animation groups: icon, pop copy, dim overlay, region.
            local function AddAnim(tex)
                local ag = tex:CreateAnimationGroup()
                local a = ag:CreateAnimation("Alpha")
                a:SetFromAlpha(0)
                a:SetToAlpha(1)
                a:SetSmoothing("OUT")
                local s = ag:CreateAnimation("Scale")
                s:SetSmoothing("OUT")
                anims[#anims + 1] = { ag = ag, a = a, s = s }
            end
            AddAnim(icon)
            if bigs[k] then AddAnim(bigs[k]) end
            if dimTex then AddAnim(dimTex) end
            AddAnim(regions[k])
            if def.place then
                local b = CreateFrame("Button", nil, ring, "SecureActionButtonTemplate")
                b:SetAttribute("type", "macro")
                b:SetAttribute("macrotext", "")
                b:SetAttribute("useOnKeyDown", false)
                b:SetAttribute("idx", k)
                b:Hide()
                placeBtns[k] = b
            end
        end

        -- Highlight driver: plain frame (no OnUpdate script on the protected ring).
        driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", OnUpdate)
        if def.isunit then M.LostHooks(driver) end
        ring:HookScript("OnShow", function()
            startX, startY = CursorXY() -- cursor at key down
            ResetHighlight()
            local active = ring:GetAttribute("active")
            nameText:SetText("")
            if not active then
                kindText:SetText("")
            elseif kind == "world" then
                kindText:SetText(L.WORLD_LABEL)
                LabelColor(0.4, 0.8, 1)
            elseif kind == "pworld" then
                kindText:SetText(L.PING_WORLD_LABEL)
                LabelColor(0.4, 0.8, 1)
            elseif ring:GetAttribute("ffground") then
                kindText:SetText(kind == "unit" and L.WORLD_LABEL or L.PING_GROUND)
                LabelColor(0.4, 0.8, 1)
            else
                local unit = ring:GetAttribute("ffunit")
                if unit then
                    local who = unit == "target" and L.UNIT_TARGET or L.UNIT_MOUSEOVER
                    kindText:SetText(kind == "ping" and L.PING_UNIT:format(who) or who)
                    if unit == "target" then LabelColor(1, 0.3, 0.3) else LabelColor(0.3, 1, 0.3) end
                    nameText:SetText(UnitName(unit))
                else
                    kindText:SetText("")
                end
            end
            UnitInfo(active)
            -- Open animation (option).
            if (Cfg().openAnim or "OFF") ~= "OFF" then
                for _, e in ipairs(anims) do
                    e.ag:Stop()
                    e.ag:Play()
                end
            end
            driver:Show()
        end)
        ring:HookScript("OnHide", function()
            driver:Hide()
            -- Fallback: stuck temp binds (secure snippet clears them normally). Pending ping keeps its binds.
            if not InCombatLockdown() and not ring:GetAttribute("pend") then ClearOverrideBindings(ring) end
        end)

        button = CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "")
        button:SetAttribute("useOnKeyDown", false) -- act on key up only
        if def.isunit then button:HookScript("PreClick", PreClick) end
        button:HookScript("PostClick", PostClick)
        button:HookScript("PreClick", FastPre)
        button:HookScript("PostClick", FastPost)
        ring:WrapScript(button, "OnClick", S.PRE_CLICK)
        for _, b in ipairs(placeBtns) do
            if def.pings then
                ring:WrapScript(b, "OnClick", S.PLACE_PING)
            else
                ring:WrapScript(b, "OnClick", S.PLACE_PRE, S.PLACE_POST)
                b:HookScript("PostClick", PostClick) -- apply sound (macrotext set only when placed)
            end
        end
        if def.pings and def.place then
            -- Pending ping: binding target buttons (up = place, down = cancel).
            local pb = CreateFrame("Button", ns.PEND_BUTTON, UIParent, "SecureActionButtonTemplate")
            pb:RegisterForClicks("AnyUp")
            pb:SetAttribute("type", "macro")
            pb:SetAttribute("macrotext", "")
            pb:SetAttribute("useOnKeyDown", false)
            pb:HookScript("PostClick", PostClick)
            ring:WrapScript(pb, "OnClick", S.PEND_CLICK)
            local cancel = CreateFrame("Button", ns.PEND_CANCEL_BUTTON, UIParent, "SecureActionButtonTemplate")
            cancel:RegisterForClicks("AnyDown")
            ring:WrapScript(cancel, "OnClick", S.PEND_CANCEL)

            -- Indicator: chosen ping icon follows the cursor while pending (insecure, visual only).
            local ind = CreateFrame("Frame", nil, UIParent)
            ind:SetFrameStrata("TOOLTIP")
            ind:SetSize(24, 24)
            ind:EnableMouse(false)
            ind:Hide()
            local tex = ind:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            local txt = ind:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            txt:SetPoint("LEFT", ind, "RIGHT", 2, 0)
            pendText = txt
            -- Pulse (option): alpha 1 -> 0.35 -> 1 while pending.
            local pulse = tex:CreateAnimationGroup()
            pulse:SetLooping("BOUNCE")
            local pa = pulse:CreateAnimation("Alpha")
            pa:SetFromAlpha(1)
            pa:SetToAlpha(0.35)
            pa:SetDuration(0.45)
            pa:SetSmoothing("IN_OUT")
            ind:HookScript("OnHide", function() pulse:Stop() end)
            ind:SetScript("OnUpdate", function(self)
                local s = self:GetEffectiveScale()
                local x, y = GetCursorPosition()
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s + 16, y / s - 16)
            end)
            ring:HookScript("OnAttributeChanged", function(_, name, value)
                if name ~= "pend" then return end
                local it = value and act[value] and items[act[value]] -- value = shown icon index
                if not it then ind:Hide() return end
                local atlas = ns.PingAtlas(it)
                if atlas then tex:SetAtlas(atlas) txt:SetText("") else
                    tex:SetColorTexture(0.25, 0.25, 0.25, 0.9)
                    txt:SetText(L.PING_NAMES[it] or it)
                end
                ind:Show()
                if Own().pendPulse then pulse:Play() else pulse:Stop() end
            end)
        end

        local mc = CreateFrame("Button", ns.CANCEL_BUTTONS[kind], UIParent, "SecureActionButtonTemplate")
        mc:RegisterForClicks("AnyDown")
        ring:WrapScript(mc, "OnClick", S.MENU_CANCEL)

        local wheel = CreateFrame("Button", ns.WHEEL_BUTTONS[kind], UIParent, "SecureActionButtonTemplate")
        wheel:RegisterForClicks("AnyDown")
        ring:WrapScript(wheel, "OnClick", S.WHEEL_CLICK)

        -- Center click button: macro, fired by the temp mouse binding (release of the mouse button).
        local cb = CreateFrame("Button", ns.CENTER_BUTTONS[kind], UIParent, "SecureActionButtonTemplate")
        cb:RegisterForClicks("AnyUp")
        cb:SetAttribute("type", "macro")
        cb:SetAttribute("macrotext", "")
        cb:SetAttribute("useOnKeyDown", false)
        if def.isunit then
            -- Same drift fix as the hold button: runs only out of combat.
            cb:HookScript("PreClick", function(self) PreClick(self, nil, false) end)
        end
        cb:HookScript("PostClick", PostClick)
        ring:WrapScript(cb, "OnClick", S.CENTER_CLICK)

        M.InitAttributes()
        M.ApplyLayout()
    end

    function M.Ring() return ring end

    return M
end

ns.Menus = {}
for _, k in ipairs(ns.MENU_KINDS) do ns.Menus[k] = NewMenu(k) end

-- Create all menus; each ring knows the others (secure snippet closes / finishes them).
function ns.InitMenus()
    for _, k in ipairs(ns.MENU_KINDS) do ns.Menus[k].Init() end
    for _, k in ipairs(ns.MENU_KINDS) do
        local r, j = ns.Menus[k].Ring(), 0
        for _, o in ipairs(ns.MENU_KINDS) do
            if o ~= k then
                j = j + 1
                r:SetFrameRef("o" .. j, ns.Menus[o].Ring())
            end
        end
        r:SetAttribute("nother", j)
    end
end

function ns.ApplyAllLayouts()
    for _, k in ipairs(ns.MENU_KINDS) do ns.Menus[k].ApplyLayout() end
end
