local addonName, ns = ...

-- Secure snippets of the mark menus (Marks.lua wraps them with ring:WrapScript).
-- Run in the restricted environment: only ring / button attributes, no addon Lua state.
local S = {}
ns.SNIPPETS = S

-- PRE_CLICK: self = button, owner = ring (header).
-- No math lib needed: squared distance, pre-normalized icon directions, manual abs.
-- Macro built at key up (k = shown icon index):
--   ground (non-unit menu, or unit menu without unit: world fallback / ping auto) = attribute "gm"..k;
--   unit = cmd .. " [@" .. unit .. attribute "ua"..k, where "ua"..k = ",exists] ARG"
--   or ",exists]" (no ARG: contextual /ping).
S.PRE_CLICK = [[
    local ring = owner
    local no = owner:GetAttribute("nother") or 0
    if down then
        -- Menu off (General > Enabled menus): key down ignored, so key up finds nothing active.
        if ring:GetAttribute("off") then return false end
        ring:SetAttribute("fdone", nil) -- fast icon index applied at key up (PostClick reads it)
        -- A menu left open by a lost key up (other button) is closed first,
        -- incl. its temp wheel binds (else wheel / camera zoom stays blocked in combat).
        for j = 1, no do
            local o = owner:GetFrameRef("o" .. j)
            if o and o:GetAttribute("active") then
                o:SetAttribute("active", nil)
                o:SetAttribute("wsel", 0)
                o:SetAttribute("fire", nil)
                o:SetAttribute("cfin", nil)
                o:ClearBindings()
                if not o:GetAttribute("preview") then o:Hide() end
            end
        end
        -- Combat fast press left active by a lost key up: reset, treat as a new press.
        if ring:GetAttribute("cfin") then
            ring:SetAttribute("cfin", nil)
            ring:SetAttribute("active", nil)
        end
        if ring:GetAttribute("active") then
            -- Toggle mode, menu open: 2nd key press or left click (Button5) = pick on key up.
            if not ring:GetAttribute("toggle") then return false end
            ring:SetAttribute("fire", button == "Button5" and "click" or "key")
            return false
        end
        -- Fast mark in combat (option): no menu, no timer; key up places the combat fast icon.
        if ring:GetAttribute("cfast") and SecureCmdOptionParse("[combat] 1") == "1" then
            local cf = true
            ring:SetAttribute("ffground", nil)
            if ring:GetAttribute("isunit") then
                local unit = SecureCmdOptionParse(ring:GetAttribute("cfucond"))
                if not unit or unit == "" then
                    local nu = ring:GetAttribute("cfnounit")
                    if nu == "GROUND" then
                        ring:SetAttribute("ffunit", nil)
                        ring:SetAttribute("ffground", true)
                    elseif nu == "MENU" then
                        cf = false -- normal menu path below
                    else
                        return false
                    end
                else
                    ring:SetAttribute("ffunit", unit)
                end
            end
            if cf then
                ring:SetAttribute("fire", nil)
                ring:SetAttribute("pend", nil)
                ring:SetAttribute("finst", nil)
                ring:SetAttribute("ftap", nil)
                ring:SetAttribute("fidx", nil)
                ring:SetAttribute("wsel", 0)
                ring:SetAttribute("active", true)
                ring:SetAttribute("cfin", true)
                owner:ClearBindings()
                return false
            end
        end
        ring:SetAttribute("fire", nil)
        ring:SetAttribute("ffground", nil)
        ring:SetAttribute("pend", nil) -- own key again = pending ping cancelled (binds cleared below)
        if ring:GetAttribute("isunit") then
            local unit = SecureCmdOptionParse(ring:GetAttribute("ucond"))
            if not unit or unit == "" then
                -- Auto (ping menu): no unit = ground ping under cursor.
                if not ring:GetAttribute("auto") then return false end
                ring:SetAttribute("ffunit", nil)
                ring:SetAttribute("ffground", true)
            else
                ring:SetAttribute("ffunit", unit)
            end
        end
        ring:SetAttribute("active", true)
        -- Fast mark: GetTime is not available in secure code. Tap result "ftap" / double-tap
        -- index "fidx" are set by the insecure PreClick at key up, out of combat only.
        ring:SetAttribute("ftap", nil)
        ring:SetAttribute("fidx", nil)
        if ring:GetAttribute("fast") == "INSTANT" then
            -- Instant: no menu, key up places the fast icon.
            ring:SetAttribute("finst", true)
            owner:ClearBindings()
            return false
        end
        ring:SetAttribute("finst", nil)
        -- Wheel select (option): temp wheel bindings -> wheel button, only while held.
        ring:SetAttribute("wsel", 0)
        owner:ClearBindings()
        if ring:GetAttribute("wheel") then
            -- Every modifier combo: held key modifiers (e.g. CTRL-ALT) must not block the wheel.
            local btn = ring:GetAttribute("wheelbtn")
            for i = 1, 8 do
                local p = ring:GetAttribute("wp" .. i)
                owner:SetBindingClick(true, p .. "MOUSEWHEELUP", btn, "LeftButton")
                owner:SetBindingClick(true, p .. "MOUSEWHEELDOWN", btn, "RightButton")
            end
        end
        -- Center click (option): temp mouse button bindings (every bind row) -> center button,
        -- only while held. Mouse binding (not a mouse-enabled frame): cursor stays over the world.
        -- Raid mark world fallback (no unit): world menu bind rows ("g" prefix).
        local cp = (ring:GetAttribute("ffground") and ring:GetAttribute("gset")) and "g" or ""
        if ring:GetAttribute(cp .. "cclick") then
            local btn = ring:GetAttribute("cbtnname")
            for b = 1, ring:GetAttribute(cp .. "cbn") or 0 do
                local key = ring:GetAttribute(cp .. "cbk" .. b)
                local mb = ring:GetAttribute(cp .. "cbb" .. b)
                for i = 1, 8 do
                    owner:SetBindingClick(true, ring:GetAttribute("wp" .. i) .. key, btn, mb)
                end
            end
        end
        -- Toggle mode: left click (any modifiers) -> own button as Button5 = apply.
        -- Set after center click binds: left click wins, center click handled in the apply below.
        if ring:GetAttribute("toggle") then
            local btn = ring:GetAttribute("mainbtn")
            for i = 1, 8 do
                owner:SetBindingClick(true, ring:GetAttribute("wp" .. i) .. "BUTTON1", btn, "Button5")
            end
        end
        -- Escape = cancel (option, hold and toggle mode), only while the menu is open.
        if ring:GetAttribute("escclose") then
            owner:SetBindingClick(true, "ESCAPE", ring:GetAttribute("cancelbtn"), "LeftButton")
        end
        if ring:GetAttribute("anchor") == "CURSOR" then
            ring:ClearAllPoints()
            ring:SetPoint("CENTER", "$cursor", "CENTER", ring:GetAttribute("offx"), ring:GetAttribute("offy"))
        end
        ring:Show()
        return false
    end

    local fire
    self:SetAttribute("macrotext", "") -- set again only when something is applied (sound: PostClick)
    if not ring:GetAttribute("active") then
        -- Key up can arrive on another button when a modifier changed while holding
        -- (Shift-F1 down, Shift released, F1 up -> unit button). Finish the open hold menu.
        ring = nil
        for j = 1, no do
            local o = owner:GetFrameRef("o" .. j)
            if o and o:GetAttribute("active") and (o:GetAttribute("cfin") or not o:GetAttribute("toggle")) then ring = o break end
        end
        if not ring then return false end
    end
    -- Fast mark in combat: apply the combat fast icon (unit / ground / cursor).
    if ring:GetAttribute("cfin") then
        ring:SetAttribute("cfin", nil)
        ring:SetAttribute("active", nil)
        ring:SetAttribute("fire", nil)
        ring:SetAttribute("wsel", 0)
        ring:ClearBindings()
        if not ring:GetAttribute("isunit") or ring:GetAttribute("ffground") then
            local m = ring:GetAttribute("cfgm")
            if not m or m == "" then return false end
            self:SetAttribute("macrotext", m)
        else
            self:SetAttribute("macrotext", ring:GetAttribute("cmd") .. " [@" .. (ring:GetAttribute("ffunit") or "target") .. ring:GetAttribute("cfua"))
        end
        return
    end
    -- Fast mark: instant mode, or fast tap (PreClick, out of combat).
    local fmode = ring:GetAttribute("fast")
    local tap = ring:GetAttribute("finst") or ((fmode == "TAP" or fmode == "BOTH") and ring:GetAttribute("ftap"))
    ring:SetAttribute("finst", nil)
    ring:SetAttribute("ftap", nil)
    if ring:GetAttribute("toggle") and not tap then
        -- Toggle mode: up of the opening press keeps the menu open; up after 2nd press / click applies.
        fire = ring:GetAttribute("fire")
        if not fire then return false end
    end
    ring:SetAttribute("fire", nil)
    ring:SetAttribute("active", nil)
    local n = ring:GetAttribute("n") or 8
    local click = fire == "click"
    -- Wheel choice wins (cursor not moved = marker at ring center); else mouse position (hover on).
    -- Left click (toggle): icon under cursor wins, else wheel choice.
    local k = ring:GetAttribute("wsel") or 0
    ring:SetAttribute("wsel", 0)
    ring:ClearBindings() -- temp binds of the finished menu (own or other ring)
    local hover = ring:GetAttribute("hover")
    -- Raid mark world fallback (no unit): center release / click in center from the world menu ("g" prefix).
    local cp = (ring:GetAttribute("ffground") and ring:GetAttribute("gset")) and "g" or ""
    local crelease = ring:GetAttribute(cp .. "crelease")
    local pick = click or hover -- cursor may pick an icon / hit an empty slot
    local fx, fy
    local hole, inc -- cursor on an empty slot (keep slots) / in the center area
    if not tap and (click or (k == 0 and (hover or crelease))) then fx, fy = ring:GetMousePosition() end
    if fx then
        local kp = 0
        local mx = (fx - 0.5) * ring:GetWidth()
        local my = (fy - 0.5) * ring:GetHeight()
        -- Slots: ns geometry slots, "sk"..s = icon index 1..n, 0 = empty slot (excluded, keep slots).
        local ns = ring:GetAttribute("ns") or n
        if ring:GetAttribute("ring") then
            -- Pie sectors (360 / ns deg each) around origin: ring center, or key-down cursor (dir).
            local dx, dy = mx, my
            if ring:GetAttribute("dir") then
                dx = mx + ring:GetAttribute("offx")
                dy = my + ring:GetAttribute("offy")
            end
            local dead = ring:GetAttribute("dead")
            if dx * dx + dy * dy >= dead * dead then
                local best, bs
                for i = 1, ns do
                    local d = dx * ring:GetAttribute("ux" .. i) + dy * ring:GetAttribute("uy" .. i)
                    if not best or d > best then best = d bs = i end
                end
                kp = bs and ring:GetAttribute("sk" .. bs) or 0
                if kp == 0 then hole = true end
            else
                inc = true
            end
        else
            -- Grid / row: square cells of one step, touching (no gaps); center cell = none.
            local half = ring:GetAttribute("half")
            local found
            for i = 1, ns do
                local ax = mx - ring:GetAttribute("ix" .. i)
                local ay = my - ring:GetAttribute("iy" .. i)
                if ax < 0 then ax = -ax end
                if ay < 0 then ay = -ay end
                if ax <= half and ay <= half then
                    found = true
                    kp = ring:GetAttribute("sk" .. i) or 0
                    if kp == 0 then hole = true end
                    break
                end
            end
            if not found and mx >= -half and mx <= half and my >= -half and my <= half then inc = true end
        end
        if not pick then kp = 0 hole = nil end -- hover off: cursor only checked for the center
        if kp > 0 then k = kp end
    end
    if not ring:GetAttribute("preview") then ring:Hide() end
    -- Empty slot (excluded icon, keep slots) under the cursor = cancel.
    if k == 0 and hole then return false end
    -- Center release: key release with the cursor in the center = center icon.
    local relHit = k == 0 and inc and crelease
    -- Wheel start icon (preselected on open): used when nothing else is picked.
    if k == 0 and not relHit and not tap then
        local st = ring:GetAttribute("wstart")
        if st and st > 0 then k = st end
    end

    -- Fast mark: tap / instant, or empty release (no time limit modes; not a toggle left click).
    if not tap and k == 0 and not click and not relHit and (fmode == "EMPTY" or fmode == "BOTH") then tap = true end
    if tap then
        local fi = ring:GetAttribute("fidx") or 1 -- 2 = double tap (PreClick, out of combat)
        ring:SetAttribute("fidx", nil)
        ring:SetAttribute("fdone", fi)
        if not ring:GetAttribute("isunit") or ring:GetAttribute("ffground") then
            local m = ring:GetAttribute("fgm" .. fi)
            if not m or m == "" then return false end
            self:SetAttribute("macrotext", m)
        else
            local us = ring:GetAttribute("fua" .. fi)
            if not us then return false end
            self:SetAttribute("macrotext", ring:GetAttribute("cmd") .. " [@" .. (ring:GetAttribute("ffunit") or "target") .. us)
        end
        return
    end

    -- Nothing picked, hover off (and not a click): option Cancel / Center action / Last used.
    if k == 0 and not relHit and not (hover or click) then
        local np = ring:GetAttribute("nopick")
        if np == "LAST" then
            k = ring:GetAttribute("last") or 0
            if k == 0 then return false end
        elseif np ~= "CENTER" then
            return false
        end
    end
    if k > 0 then ring:SetAttribute("last", k) end
    -- Toggle left click with click in center on: first Left bind row whose modifiers match.
    local cb = 0
    if k == 0 and not relHit and click and ring:GetAttribute(cp .. "cclick") then
        for b = 1, ring:GetAttribute(cp .. "cbn") or 0 do
            if ring:GetAttribute(cp .. "cbb" .. b) == "LeftButton" and SecureCmdOptionParse(ring:GetAttribute(cp .. "cbc" .. b)) == "1" then
                cb = b
                break
            end
        end
    end

    if not ring:GetAttribute("isunit") or ring:GetAttribute("ffground") then
        local m
        if k > 0 then m = ring:GetAttribute("gm" .. k)
        elseif relHit then m = ring:GetAttribute(cp .. "crgm")
        elseif cb > 0 then m = ring:GetAttribute(cp .. "cbgm" .. cb)
        else m = ring:GetAttribute("cgm") end
        if not m or m == "" then return false end
        self:SetAttribute("macrotext", m)
    else
        local us
        if k > 0 then us = ring:GetAttribute("ua" .. k)
        elseif relHit then us = ring:GetAttribute("crua")
        elseif cb > 0 then us = ring:GetAttribute("cbua" .. cb)
        else us = ring:GetAttribute("cua") end
        if not us then return false end -- center = cancel
        -- us = ",exists] ARG": unit gone at release = no action (never falls through to target).
        self:SetAttribute("macrotext", ring:GetAttribute("cmd") .. " [@" .. (ring:GetAttribute("ffunit") or "target") .. us)
    end
]]

-- Wheel button (one per menu): wheel down = next icon clockwise (default), up = previous.
S.WHEEL_CLICK = [[
    if not owner:GetAttribute("active") then return false end
    local n = owner:GetAttribute("n") or 8
    local s = owner:GetAttribute("wsel") or 0
    -- First tick continues from the preselected start icon (option).
    if s == 0 then s = owner:GetAttribute("wstart") or 0 end
    local back = button ~= "RightButton" -- wheel down (RightButton) = forward in chosen direction
    if owner:GetAttribute("wheelccw") then back = not back end -- option: wheel down = counterclockwise
    if back then
        s = s - 1
        if s < 1 then s = n end
    else
        s = s + 1
        if s > n then s = 1 end
    end
    owner:SetAttribute("wsel", s)
    return false
]]

-- Click to place (world menu, option): icon button click with the chosen mouse button +
-- modifiers -> "/wm N" (no @cursor, button attribute "wm") = green placement circle.
-- Menu closes, key up does nothing. macrotext set only here (PostClick: apply sound).
S.PLACE_PRE = [[
    self:SetAttribute("macrotext", "")
    if not owner:GetAttribute("active") then return false end
    if button ~= owner:GetAttribute("clickbtn") then return false end
    if SecureCmdOptionParse(owner:GetAttribute("clickcond")) ~= "1" then return false end
    owner:SetAttribute("active", nil)
    owner:SetAttribute("wsel", 0)
    owner:ClearBindings()
    self:SetAttribute("macrotext", self:GetAttribute("wm") or "")
    -- Post body runs only when the pre body returns a message: same button + "close".
    return button, "close"
]]
S.PLACE_POST = [[
    if message == "close" and not owner:GetAttribute("preview") then owner:Hide() end
]]

-- Click to place (world ping menu, option): icon click with the chosen button + modifiers ->
-- menu closes, pending ping: temp binds (any modifiers) place button -> pending button
-- (next click = "/ping TYPE" under cursor), right click (left if place = right) / Escape -> cancel.
S.PLACE_PING = [[
    if not owner:GetAttribute("active") then return false end
    if button ~= owner:GetAttribute("clickbtn") then return false end
    if SecureCmdOptionParse(owner:GetAttribute("clickcond")) ~= "1" then return false end
    owner:SetAttribute("active", nil)
    owner:SetAttribute("wsel", 0)
    owner:ClearBindings()
    owner:SetAttribute("pend", self:GetAttribute("idx")) -- before Hide: OnHide keeps the binds
    local pb, cb = owner:GetAttribute("pendbtn"), owner:GetAttribute("pendcancel")
    local pk, pm, ck = owner:GetAttribute("pkey"), owner:GetAttribute("clickbtn"), owner:GetAttribute("ckey")
    for i = 1, 8 do
        local p = owner:GetAttribute("wp" .. i)
        owner:SetBindingClick(true, p .. pk, pb, pm)
        owner:SetBindingClick(true, p .. ck, cb, "LeftButton")
    end
    owner:SetBindingClick(true, "ESCAPE", cb, "LeftButton")
    if not owner:GetAttribute("preview") then owner:Hide() end
    return false
]]

-- Pending ping: next click (place button) = ping of the chosen icon under cursor.
S.PEND_CLICK = [[
    self:SetAttribute("macrotext", "")
    local k = owner:GetAttribute("pend")
    if not k then return false end
    owner:SetAttribute("pend", nil)
    owner:ClearBindings()
    self:SetAttribute("macrotext", owner:GetAttribute("gm" .. k))
]]

-- Menu cancel (Escape while the menu is open, option).
S.MENU_CANCEL = [[
    owner:SetAttribute("active", nil)
    owner:SetAttribute("wsel", 0)
    owner:SetAttribute("fire", nil)
    owner:ClearBindings()
    if not owner:GetAttribute("preview") then owner:Hide() end
    return false
]]

-- Pending ping cancel (right click / Escape).
S.PEND_CANCEL = [[
    owner:SetAttribute("pend", nil)
    owner:ClearBindings()
    return false
]]

-- Click in center (option, all menus): mouse button + modifiers while the key is held,
-- cursor inside the center area (ring: deadzone, grid / row: center cell) -> icon of the
-- first bind row with this button + matching modifiers. Menu closes, key up does nothing.
S.CENTER_CLICK = [[
    self:SetAttribute("macrotext", "")
    if not owner:GetAttribute("active") then return false end
    -- Raid mark world fallback (no unit): world menu bind rows ("g" prefix).
    local cp = (owner:GetAttribute("ffground") and owner:GetAttribute("gset")) and "g" or ""
    local b = 0
    for i = 1, owner:GetAttribute(cp .. "cbn") or 0 do
        if owner:GetAttribute(cp .. "cbb" .. i) == button and SecureCmdOptionParse(owner:GetAttribute(cp .. "cbc" .. i)) == "1" then
            b = i
            break
        end
    end
    if b == 0 then return false end
    local fx, fy = owner:GetMousePosition()
    if not fx then return false end
    local mx = (fx - 0.5) * owner:GetWidth()
    local my = (fy - 0.5) * owner:GetHeight()
    if owner:GetAttribute("ring") then
        if owner:GetAttribute("dir") then
            mx = mx + owner:GetAttribute("offx")
            my = my + owner:GetAttribute("offy")
        end
        local dead = owner:GetAttribute("dead")
        if mx * mx + my * my >= dead * dead then return false end
    else
        local half = owner:GetAttribute("half")
        if mx < -half or mx > half or my < -half or my > half then return false end
    end
    owner:SetAttribute("active", nil)
    owner:SetAttribute("wsel", 0)
    owner:SetAttribute("fire", nil)
    owner:ClearBindings()
    if not owner:GetAttribute("preview") then owner:Hide() end
    if not owner:GetAttribute("isunit") or owner:GetAttribute("ffground") then
        self:SetAttribute("macrotext", owner:GetAttribute(cp .. "cbgm" .. b) or "")
    else
        self:SetAttribute("macrotext", owner:GetAttribute("cmd") .. " [@" .. (owner:GetAttribute("ffunit") or "target") .. owner:GetAttribute("cbua" .. b))
    end
]]
