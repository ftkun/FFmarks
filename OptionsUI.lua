local addonName, ns = ...
local L = ns.L

-- Options: AceConfig option table shown by AceConfigDialog (standalone via /ffm and
-- embedded in Esc > Options > AddOns). Built on first open (lazy). Needs Libs/ (embeds.xml).
local Options = {}
ns.Options = Options

local LibStub = LibStub
local ipairs, pairs = ipairs, pairs
local C_Timer = C_Timer
local APP = "FFmarks"

local ACR = LibStub("AceConfigRegistry-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local ADBO = LibStub("AceDBOptions-3.0")

-- Option parts rebuilt on refresh (rows depend on saved lists, e.g. center click binds).
local rebuilders = {}

function Options.Refresh()
    for _, f in ipairs(rebuilders) do f() end
    ACR:NotifyChange(APP)
end

---------------------------------------------------------------- helpers
local function DB() return ns.db end

-- AceGUI only enables the slider mouse wheel after a click on it. Own widget type =
-- stock Slider with the wheel always on. Pooled under its own type.
local WHEEL_SLIDER = "FFmarks_WheelSlider"
if not AceGUI:GetWidgetVersion(WHEEL_SLIDER) then
    AceGUI:RegisterWidgetType(WHEEL_SLIDER, function()
        local w = AceGUI.WidgetRegistry.Slider()
        w.type = WHEEL_SLIDER
        local acquire = w.OnAcquire
        w.OnAcquire = function(self)
            acquire(self)
            self.slider:EnableMouseWheel(true)
            self.frame:EnableMouseWheel(true)
        end
        w.frame:SetScript("OnMouseWheel", function(_, d)
            local f = w.slider:GetScript("OnMouseWheel")
            if f then f(w.slider, d) end
        end)
        return w
    end, 1)
end

-- Sound select: stock Dropdown, item under the mouse plays its sound (preview).
-- Callbacks are cleared when AceGUI releases the items (SetList rebuilds them).
local SOUND_DROPDOWN = "FFmarks_SoundDropdown"
if not AceGUI:GetWidgetVersion(SOUND_DROPDOWN) then
    local function ItemEnter(item)
        local v = item.userdata and item.userdata.value
        if v then ns.PlayApplySound(v) end
    end
    AceGUI:RegisterWidgetType(SOUND_DROPDOWN, function()
        local w = AceGUI.WidgetRegistry.Dropdown()
        w.type = SOUND_DROPDOWN
        local setList = w.SetList
        w.SetList = function(self, ...)
            setList(self, ...)
            for _, item in self.pullout:IterateItems() do
                item:SetCallback("OnEnter", ItemEnter)
            end
        end
        return w
    end, 1)
end

local function SoundSelect(t)
    t.dialogControl = SOUND_DROPDOWN
    t.type = "select"
    return t
end

-- Keybind "Clear": stock Button, aligned with the keybinding button (44 px widget, 24 px
-- button at its bottom). Flow layout aligns row centers: alignoffset 10 = same top as that button.
local KEY_CLEAR = "FFmarks_KeyClear"
if not AceGUI:GetWidgetVersion(KEY_CLEAR) then
    AceGUI:RegisterWidgetType(KEY_CLEAR, function()
        local w = AceGUI.WidgetRegistry.Button()
        w.type = KEY_CLEAR
        local acquire = w.OnAcquire
        w.OnAcquire = function(self)
            acquire(self)
            self.alignoffset = 10
        end
        return w
    end, 1)
end

local function Range(t)
    t.dialogControl = WHEEL_SLIDER
    t.type = "range"
    return t
end

local function Values(list, names)
    local v = {}
    for _, k in ipairs(list) do v[k] = names[k] or k end
    return v
end

-- Range bound to T()[key]; apply() after set.
local function DBRange(T, key, name, order, min, max, step, apply, extra)
    local t = {
        name = name, order = order, min = min, max = max, step = step, width = 1.2,
        get = function() return T()[key] end,
        set = function(_, v) T()[key] = v if apply then apply() end end,
    }
    if extra then for k, v in pairs(extra) do t[k] = v end end
    return Range(t)
end

-- Re-apply menus after an option change. Batched: many changes in one frame (slider drag)
-- = one ApplyAllLayouts on the next frame.
local layoutQueued = false
local function LayoutNow()
    layoutQueued = false
    ns.ApplyAllLayouts()
end
local function Layout()
    if layoutQueued then return end
    layoutQueued = true
    C_Timer.After(0, LayoutNow)
end

-- RGBA color option bound to T()[key] = { r, g, b, a }.
local function Color(T, key, name, order, disabled)
    return {
        type = "color", name = name, order = order, width = 1, hasAlpha = true, disabled = disabled,
        get = function() local c = T()[key] return c.r, c.g, c.b, c.a end,
        set = function(_, r, g, b, a) T()[key] = { r = r, g = g, b = b, a = a } Layout() end,
    }
end
local function W() return ns.db.world end

---------------------------------------------------------------- shared selection args
-- Selection section (General tab of every menu): center action, wheel, hover, toggle, nothing picked, sound.
-- centerList nil: no center action select (ping menus: release in center = cancel).
-- withUnit: unit priority select on top (unit menus: Markers Units, Ping).
local function SelectionArgs(T, centerList, wheelTip, withUnit)
    local args = {
        wheel = {
            type = "toggle", name = L.OPT_WHEEL, desc = wheelTip, order = 3, width = 1,
            get = function() return T().wheel end,
            set = function(_, v) T().wheel = v Layout() end,
        },
        wheelDir = {
            type = "select", name = L.OPT_WHEEL_DIR, order = 4, width = 1,
            values = Values(ns.WHEEL_DIRS, L.WHEEL_DIR_NAMES), sorting = ns.WHEEL_DIRS,
            disabled = function() return not T().wheel end,
            get = function() return T().wheelDir end,
            set = function(_, v) T().wheelDir = v Layout() end,
        },
        br2 = { type = "description", name = "", order = 5 },
        hover = {
            type = "toggle", name = L.OPT_HOVER, desc = L.OPT_HOVER_TIP, order = 6, width = 1,
            get = function() return T().hover end,
            set = function(_, v) T().hover = v Layout() Options.Refresh() end,
        },
        toggle = {
            type = "toggle", name = L.OPT_TOGGLE, desc = L.OPT_TOGGLE_TIP, order = 7, width = 1,
            get = function() return T().toggle end,
            set = function(_, v) T().toggle = v Layout() end,
        },
        noPick = {
            type = "select", name = L.OPT_NOPICK, desc = L.OPT_NOPICK_TIP, order = 8, width = 1.2,
            values = Values(ns.NOPICK_ACTIONS, L.NOPICK_NAMES), sorting = ns.NOPICK_ACTIONS,
            disabled = function() return T().hover end,
            get = function() return T().noPick end,
            set = function(_, v) T().noPick = v Layout() end,
        },
        br3 = { type = "description", name = "", order = 9 },
        hlSound = {
            type = "toggle", name = L.OPT_HL_SOUND, desc = L.OPT_HL_SOUND_TIP, order = 9.1, width = 1,
            get = function() return T().hlSound end,
            set = function(_, v) T().hlSound = v end,
        },
        hlSoundId = SoundSelect({
            name = L.OPT_SOUND_ID, order = 9.2, width = 1,
            values = Values(ns.SOUNDS, L.SOUND_NAMES), sorting = ns.SOUNDS,
            disabled = function() return not T().hlSound end,
            get = function() return T().hlSoundId end,
            set = function(_, v) T().hlSoundId = v ns.PlayApplySound(v) end,
        }),
        br4 = { type = "description", name = "", order = 9.5 },
        sound = {
            type = "toggle", name = L.OPT_SOUND, desc = L.OPT_SOUND_TIP, order = 10, width = 1,
            get = function() return T().sound end,
            set = function(_, v) T().sound = v end,
        },
        soundId = SoundSelect({
            name = L.OPT_SOUND_ID, order = 11, width = 1,
            values = Values(ns.SOUNDS, L.SOUND_NAMES), sorting = ns.SOUNDS,
            disabled = function() return not T().sound end,
            get = function() return T().soundId end,
            set = function(_, v) T().soundId = v ns.PlayApplySound(v) end,
        }),
    }
    if centerList then
        args.center = {
            type = "select", name = L.OPT_CENTER, order = 1, width = 1.4,
            values = Values(centerList, L.CENTER_NAMES), sorting = centerList,
            get = function() return T().center end,
            set = function(_, v) T().center = v Layout() end,
        }
        args.br1 = { type = "description", name = "", order = 2 }
    end
    if withUnit then
        args.unit = {
            type = "select", name = L.OPT_UNIT, order = 0, width = 1.4,
            values = Values(ns.UNIT_ORDERS, L.UNIT_NAMES), sorting = ns.UNIT_ORDERS,
            get = function() return T().unitOrder end,
            set = function(_, v) T().unitOrder = v Layout() end,
        }
        args.br0 = { type = "description", name = "", order = 0.5 }
    end
    return args
end

-- Raid icon select values: 1..8 with icon.
local MARK_LIST = { 8, 7, 6, 5, 4, 3, 2, 1 }
local function MarkValues()
    local v = {}
    for _, i in ipairs(MARK_LIST) do
        v[i] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":0|t " .. (_G["RAID_TARGET_" .. i] or L.MARK_NAMES[i])
    end
    return v
end

-- Ping type select values: icon (atlas, if any) + name.
local function PingValues()
    local v = {}
    for _, t in ipairs(ns.PING_TYPES) do
        local atlas = ns.PingAtlas(t)
        v[t] = (atlas and ("|A:" .. atlas .. ":16:16|a ") or "") .. (L.PING_NAMES[t] or t)
    end
    return v
end

-- Center actions section (Center region tab of all menus): release (key release / tap in center) with its mark,
-- click in center with a list of bind rows (button + modifiers + mark), first match wins.
-- mode: "unit" / "world" / "ping".
local function CenterActionArgs(T, mode)
    local isWorld, isPing = mode == "world", mode == "ping"
    local tip = isPing and L.OPT_CENTER_CLICK_PING_TIP or (isWorld and L.OPT_CENTER_CLICK_WORLD_TIP or L.OPT_CENTER_CLICK_TIP)
    local markName = isPing and L.OPT_CENTER_PING or L.OPT_CENTER_MARK
    local function marks() return isPing and PingValues() or MarkValues() end
    local sorting = isPing and ns.PING_TYPES or MARK_LIST
    local function binds() return T().centerBinds end
    local function off() return not T().centerClick end
    local args = {
        centerRelease = {
            type = "toggle", name = L.OPT_CENTER_RELEASE, desc = L.OPT_CENTER_RELEASE_TIP, order = 1, width = 0.7,
            get = function() return T().centerRelease end,
            set = function(_, v) T().centerRelease = v Layout() end,
        },
        centerReleaseMark = {
            type = "select", name = markName, order = 2, width = 0.9,
            values = marks, sorting = sorting,
            disabled = function() return not T().centerRelease end,
            get = function() return T().centerReleaseMark end,
            set = function(_, v) T().centerReleaseMark = v Layout() end,
        },
        br0 = { type = "description", name = "", order = 4 },
        centerClick = {
            type = "toggle", name = L.OPT_CENTER_CLICK, desc = tip, order = 5, width = 0.7,
            get = function() return T().centerClick end,
            set = function(_, v) T().centerClick = v Layout() end,
        },
        br1 = { type = "description", name = "", order = 6 },
    }
    if isWorld then
        args.centerReleasePlace = {
            type = "select", name = L.OPT_CENTER_PLACE, order = 3, width = 1.1,
            values = Values(ns.CENTER_PLACES, L.CENTER_PLACE_NAMES), sorting = ns.CENTER_PLACES,
            disabled = function() return not T().centerRelease end,
            get = function() return T().centerReleasePlace end,
            set = function(_, v) T().centerReleasePlace = v Layout() end,
        }
    end
    -- Bind rows: keys "b<i>_*", order 10 + i (row i). Rebuilt when the row count changes.
    local built = 0
    local function Rebuild()
        local list = binds()
        local n = list and #list or 0
        if n == built then return end
        for i = 1, built do
            args["b" .. i .. "_btn"], args["b" .. i .. "_mod"], args["b" .. i .. "_mark"] = nil, nil, nil
            args["b" .. i .. "_place"], args["b" .. i .. "_del"], args["b" .. i .. "_br"] = nil, nil, nil
        end
        for i = 1, n do
            local function Row() return binds()[i] or {} end
            local o = 10 + i
            args["b" .. i .. "_btn"] = {
                type = "select", name = L.OPT_CLICK_BUTTON, order = o + 0.1, width = 0.6, disabled = off,
                values = Values(ns.CLICK_BUTTONS, L.CLICK_BUTTON_NAMES), sorting = ns.CLICK_BUTTONS,
                get = function() return Row().btn end,
                set = function(_, v) Row().btn = v Layout() end,
            }
            args["b" .. i .. "_mod"] = {
                type = "select", name = L.OPT_CLICK_MOD, order = o + 0.2, width = 0.8, disabled = off,
                values = Values(ns.CLICK_MODS, L.CLICK_MOD_NAMES), sorting = ns.CLICK_MODS,
                get = function() return Row().mod end,
                set = function(_, v) Row().mod = v Layout() end,
            }
            args["b" .. i .. "_mark"] = {
                type = "select", name = markName, order = o + 0.3, width = 0.8, disabled = off,
                values = marks, sorting = sorting,
                get = function() return Row().mark end,
                set = function(_, v) Row().mark = v Layout() end,
            }
            if isWorld then
                args["b" .. i .. "_place"] = {
                    type = "select", name = L.OPT_CENTER_PLACE, order = o + 0.4, width = 0.9, disabled = off,
                    values = Values(ns.CENTER_PLACES, L.CENTER_PLACE_NAMES), sorting = ns.CENTER_PLACES,
                    get = function() return Row().place or "CURSOR" end,
                    set = function(_, v) Row().place = v Layout() end,
                }
            end
            args["b" .. i .. "_del"] = {
                type = "execute", name = L.OPT_BIND_REMOVE, order = o + 0.5, width = 0.4,
                disabled = function() return off() or #binds() <= 1 end,
                func = function()
                    if #binds() <= 1 then return end
                    table.remove(binds(), i)
                    Layout()
                    Options.Refresh()
                end,
            }
            args["b" .. i .. "_br"] = { type = "description", name = "", order = o + 0.9 }
        end
        built = n
    end
    args.add = {
        type = "execute", name = L.OPT_BIND_ADD, desc = L.OPT_BIND_ADD_TIP, order = 9999, width = 0.8,
        disabled = off,
        func = function()
            local list = binds()
            local last = list[#list] or {}
            list[#list + 1] = {
                btn = "RightButton", mod = "ANY",
                mark = last.mark or (isPing and "ping" or 8),
                place = isWorld and (last.place or "CURSOR") or nil,
            }
            Layout()
            Options.Refresh()
        end,
    }
    rebuilders[#rebuilders + 1] = Rebuild
    if ns.db then Rebuild() end
    return args
end

-- Fast mark section (Fast mark tab of all menus). isPing: icons are ping types.
local function FastGroup(T, isPing, order)
    local function off() return not T().fast end
    local function vals() return isPing and PingValues() or MarkValues() end
    local sorting = isPing and ns.PING_TYPES or MARK_LIST
    return {
        type = "group", inline = true, name = L.SEC_FAST, order = order,
        args = {
            fast = {
                type = "toggle", name = L.OPT_FAST, desc = L.OPT_FAST_TIP, order = 1, width = 1.2,
                get = function() return T().fast end,
                set = function(_, v) T().fast = v Layout() end,
            },
            fastIcon = {
                type = "select", name = isPing and L.OPT_CENTER_PING or L.OPT_CENTER_MARK, order = 2, width = 0.9,
                values = vals, sorting = sorting, disabled = off,
                get = function() return T().fastIcon end,
                set = function(_, v) T().fastIcon = v Layout() end,
            },
            br1 = { type = "description", name = "", order = 3 },
            fastTime = DBRange(T, "fastTime", L.OPT_FAST_TIME, 4, 50, 1000, 10, nil, {
                desc = L.OPT_FAST_TIME_TIP,
                disabled = function()
                    local o = T()
                    return not o.fast or (o.fastNoLimit and o.fastNoLimitMode ~= "BOTH")
                end,
            }),
            br2 = { type = "description", name = "", order = 5 },
            fastNoLimit = {
                type = "toggle", name = L.OPT_FAST_NOLIMIT, desc = L.OPT_FAST_NOLIMIT_TIP, order = 6, width = 1.2,
                disabled = off,
                get = function() return T().fastNoLimit end,
                set = function(_, v) T().fastNoLimit = v Layout() end,
            },
            fastNoLimitMode = {
                type = "select", name = L.OPT_FAST_MODE, desc = L.OPT_FAST_MODE_TIP, order = 7, width = 1.4,
                values = Values(ns.FAST_MODES, L.FAST_MODE_NAMES), sorting = ns.FAST_MODES,
                disabled = function() return not T().fast or not T().fastNoLimit end,
                get = function() return T().fastNoLimitMode end,
                set = function(_, v) T().fastNoLimitMode = v Layout() end,
            },
            br3 = { type = "description", name = "", order = 8 },
            fastDouble = {
                type = "toggle", name = L.OPT_FAST_DOUBLE, desc = L.OPT_FAST_DOUBLE_TIP, order = 9, width = 1.2,
                disabled = off,
                get = function() return T().fastDouble end,
                set = function(_, v) T().fastDouble = v end,
            },
            fastIcon2 = {
                type = "select", name = isPing and L.OPT_FAST_PING2 or L.OPT_FAST_MARK2, order = 10, width = 0.9,
                values = vals, sorting = sorting,
                disabled = function() return not T().fast or not T().fastDouble end,
                get = function() return T().fastIcon2 end,
                set = function(_, v) T().fastIcon2 = v Layout() end,
            },
            br4 = { type = "description", name = "", order = 11 },
            fastDoubleTime = DBRange(T, "fastDoubleTime", L.OPT_FAST_DOUBLE_TIME, 12, 100, 1000, 10, nil, {
                desc = L.OPT_FAST_DOUBLE_TIME_TIP,
                disabled = function() return not T().fast or not T().fastDouble end,
            }),
            note = { type = "description", name = L.OPT_FAST_NOTE, order = 13, fontSize = "medium" },
        },
    }
end

-- Fast mark in combat section (Fast mark tab of all menus). hasUnit: raid mark / ping menus.
local function CombatFastGroup(T, isPing, hasUnit, order)
    local function off() return not T().combatFast end
    local args = {
        combatFast = {
            type = "toggle", name = L.OPT_COMBAT_FAST, desc = L.OPT_COMBAT_FAST_TIP, order = 1, width = 1.2,
            get = function() return T().combatFast end,
            set = function(_, v) T().combatFast = v Layout() end,
        },
        combatFastIcon = {
            type = "select", name = isPing and L.OPT_CENTER_PING or L.OPT_CENTER_MARK, order = 2, width = 0.9,
            values = function() return isPing and PingValues() or MarkValues() end,
            sorting = isPing and ns.PING_TYPES or MARK_LIST, disabled = off,
            get = function() return T().combatFastIcon end,
            set = function(_, v) T().combatFastIcon = v Layout() end,
        },
    }
    if hasUnit then
        args.br1 = { type = "description", name = "", order = 3 }
        args.combatFastUnit = {
            type = "select", name = L.OPT_UNIT, order = 4, width = 1.4,
            values = Values(ns.UNIT_ORDERS, L.UNIT_NAMES), sorting = ns.UNIT_ORDERS, disabled = off,
            get = function() return T().combatFastUnit end,
            set = function(_, v) T().combatFastUnit = v Layout() end,
        }
        args.combatFastNoUnit = {
            type = "select", name = L.OPT_COMBAT_FAST_NOUNIT, desc = L.OPT_COMBAT_FAST_NOUNIT_TIP, order = 5, width = 1.2,
            values = Values(ns.COMBAT_NOUNIT, L.COMBAT_NOUNIT_NAMES), sorting = ns.COMBAT_NOUNIT, disabled = off,
            get = function() return T().combatFastNoUnit end,
            set = function(_, v) T().combatFastNoUnit = v Layout() end,
        }
    end
    return { type = "group", inline = true, name = L.SEC_COMBAT_FAST, order = order, args = args }
end

---------------------------------------------------------------- General
-- Enabled menus: one checkbox per menu kind (all on by default).
local function EnabledArgs()
    local args = {}
    for i, kind in ipairs(ns.MENU_KINDS) do
        args[kind] = {
            type = "toggle", name = L.MENU_NAMES[kind], desc = L.OPT_ENABLED_TIP, order = i, width = 0.9,
            get = function() return ns.MenuOn(kind) end,
            set = function(_, v)
                DB().enabled[kind] = v
                ns.ApplyBinding()
                Layout()
                Options.Refresh()
            end,
        }
    end
    return args
end

-- Menu off: every section of every tab greyed out (tabs stay selectable). Keeps own disabled.
local function GreyOut(args, kind)
    local function off() return not ns.MenuOn(kind) end
    for _, tab in pairs(args) do
        if type(tab) == "table" and type(tab.args) == "table" then
            for _, sec in pairs(tab.args) do
                if type(sec) == "table" then
                    local old = sec.disabled
                    sec.disabled = function(...)
                        if off() then return true end
                        if type(old) == "function" then return old(...) end
                        return old
                    end
                end
            end
        end
    end
end

local function GeneralGroup()
    return {
        type = "group", name = L.GRP_GENERAL, order = 1,
        args = {
            enabled = {
                type = "group", inline = true, name = L.SEC_ENABLED, order = 0,
                args = EnabledArgs(),
            },
            audio = {
                type = "group", inline = true, name = L.SEC_AUDIO, order = 0.5,
                args = {
                    soundOn = {
                        type = "toggle", name = L.OPT_SOUND_ON, desc = L.OPT_SOUND_ON_TIP, order = 1, width = 1,
                        get = function() return DB().soundOn end,
                        set = function(_, v) DB().soundOn = v end,
                    },
                    channel = {
                        type = "select", name = L.OPT_SOUND_CHANNEL, desc = L.OPT_SOUND_CHANNEL_TIP, order = 2, width = 1,
                        values = Values(ns.SOUND_CHANNELS, L.SOUND_CHANNEL_NAMES), sorting = ns.SOUND_CHANNELS,
                        disabled = function() return not DB().soundOn end,
                        get = function() return DB().soundChannel end,
                        set = function(_, v) DB().soundChannel = v ns.PlayApplySound(DB().soundId) end,
                    },
                },
            },
            misc = {
                type = "group", inline = true, name = L.SEC_MISC, order = 1,
                args = {
                    debug = {
                        type = "toggle", name = L.OPT_DEBUG, order = 1,
                        get = function() return DB().debug end,
                        set = function(_, v) DB().debug = v end,
                    },
                },
            },
            reset = {
                type = "group", inline = true, name = L.SEC_RESET, order = 2,
                args = {
                    note = { type = "description", name = L.OPT_RESET_NOTE, order = 1 },
                    reset = {
                        type = "execute", name = L.OPT_RESET, order = 2, width = 1,
                        -- confirm as function: runs on button click, before the Yes / No popup.
                        -- Sound = game menu open (Escape), General > Audio settings apply.
                        confirm = function()
                            ns.PlayApplySound("MENU_OPEN")
                            return L.OPT_RESET_CONFIRM
                        end,
                        func = function() ns.dbObj:ResetProfile() end, -- OnProfileReset reapplies
                    },
                },
            },
        },
    }
end

---------------------------------------------------------------- Mark menu tabs
-- Icons section (Appearance tab, own setting of every menu, editable with shared look):
-- shown icons (exclude), keep empty slots, wheel start icon (single choice, none = off).
local function IconsGroup(T, isPing, order)
    local list = isPing and ns.PING_TYPES or MARK_LIST
    local function name(it)
        if isPing then
            local atlas = ns.PingAtlas(it)
            return (atlas and ("|A:" .. atlas .. ":16:16|a ") or "") .. (L.PING_NAMES[it] or it)
        end
        return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. it .. ":0|t " .. (_G["RAID_TARGET_" .. it] or L.MARK_NAMES[it])
    end
    local function shownCount()
        local c = 0
        for _, it in ipairs(list) do if not T().exclude[it] then c = c + 1 end end
        return c
    end
    local w = isPing and 0.65 or 0.55
    local args = {
        shownHead = { type = "description", name = L.OPT_ICONS_SHOWN, order = 1, fontSize = "medium" },
        keepSlots = {
            type = "toggle", name = L.OPT_KEEP_SLOTS, desc = L.OPT_KEEP_SLOTS_TIP, order = 30, width = 1.2,
            get = function() return T().keepSlots end,
            set = function(_, v) T().keepSlots = v Layout() end,
        },
        startHead = { type = "description", name = L.OPT_WHEEL_START, order = 40, fontSize = "medium" },
    }
    for i, it in ipairs(list) do
        args["show" .. i] = {
            type = "toggle", name = name(it), order = 1 + i, width = w,
            get = function() return not T().exclude[it] end,
            set = function(_, v)
                -- At least one icon stays shown.
                if not v and shownCount() <= 1 then Options.Refresh() return end
                T().exclude[it] = (not v) or nil
                Layout()
                Options.Refresh()
            end,
        }
        args["start" .. i] = {
            type = "toggle", name = name(it), desc = L.OPT_WHEEL_START_TIP, order = 40 + i, width = w,
            disabled = function() return not T().wheel or T().exclude[it] end,
            get = function() return T().wheelStart == it end,
            set = function(_, v) T().wheelStart = v and it or false Layout() Options.Refresh() end,
        }
    end
    args.br1 = { type = "description", name = "", order = 29 }
    return { type = "group", inline = true, name = L.SEC_ICONS, order = order, args = args }
end

-- Text settings section: font, size, outline / color, X, Y. F() = text setting table
-- { font, size, outline, color, x, y }. unitColors: extra toggle (unit label).
local function FontGroup(F, name, order, disabled, unitColors, hidden)
    local args = {
        font = {
            type = "select", name = L.OPT_FONT, order = 1, width = 1,
            values = function() return (ns.FontList()) end,
            sorting = function() local _, o = ns.FontList() return o end,
            get = function() return F().font end,
            set = function(_, v) F().font = v Layout() end,
        },
        size = DBRange(F, "size", L.OPT_FONT_SIZE, 2, 6, 32, 1, Layout),
        br1 = { type = "description", name = "", order = 3 },
        outline = {
            type = "select", name = L.OPT_OUTLINE, order = 4, width = 1,
            values = Values(ns.OUTLINES, L.OUTLINE_NAMES), sorting = ns.OUTLINES,
            get = function() return F().outline end,
            set = function(_, v) F().outline = v Layout() end,
        },
        color = {
            type = "color", name = L.OPT_FONT_COLOR, order = 5, width = 1, hasAlpha = true,
            disabled = unitColors and function() return F().unitColors end or nil,
            get = function() local c = F().color return c.r, c.g, c.b, c.a end,
            set = function(_, r, g, b, a) F().color = { r = r, g = g, b = b, a = a } Layout() end,
        },
        br2 = { type = "description", name = "", order = 7 },
        x = DBRange(F, "x", L.OPT_OFFSET_X, 8, -200, 200, 1, Layout),
        y = DBRange(F, "y", L.OPT_OFFSET_Y, 9, -200, 200, 1, Layout),
    }
    if unitColors then
        args.unitColors = {
            type = "toggle", name = L.OPT_UNIT_COLORS, desc = L.OPT_UNIT_COLORS_TIP, order = 6, width = 1,
            get = function() return F().unitColors end,
            set = function(_, v) F().unitColors = v Layout() end,
        }
    end
    return { type = "group", inline = true, name = name, order = order, disabled = disabled, hidden = hidden, args = args }
end

-- Center region sections (Center region tab): icon, portrait, unit label, unit name, dot.
-- disabled: look sections (shared look); portrait = own setting.
local function CenterLookGroups(args, T, disabled, kind)
    local hasUnit = kind == "unit" or kind == "ping"
    local function iconOff() return T().centerIconHide end
    args.icon = {
        type = "group", inline = true, name = L.SEC_CENTER_ICON, order = 2, disabled = disabled,
        args = {
            hide = {
                type = "toggle", name = L.OPT_CENTER_ICON_HIDE, desc = L.OPT_CENTER_ICON_HIDE_TIP, order = 1, width = 1,
                get = function() return T().centerIconHide end,
                set = function(_, v) T().centerIconHide = v Layout() end,
            },
            note = { type = "description", name = L.OPT_CENTER_ICON_TIP, order = 2, width = 1.4 },
            size  = DBRange(T, "centerIconSize", L.OPT_SIZE, 3, 8, 128, 1, Layout, { disabled = iconOff }),
            alpha = DBRange(T, "centerIconAlpha", L.OPT_ALPHA, 4, 0.05, 1, 0.01, Layout, { isPercent = true, disabled = iconOff }),
            x = DBRange(T, "centerIconX", L.OPT_OFFSET_X, 5, -200, 200, 1, Layout, { disabled = iconOff }),
            y = DBRange(T, "centerIconY", L.OPT_OFFSET_Y, 6, -200, 200, 1, Layout, { disabled = iconOff }),
        },
    }
    if hasUnit then
        local function off() return not T().portrait end
        args.portrait = {
            type = "group", inline = true, name = L.SEC_PORTRAIT, order = 3,
            args = {
                portrait = {
                    type = "toggle", name = L.OPT_PORTRAIT, desc = L.OPT_PORTRAIT_TIP, order = 1, width = 1,
                    get = function() return T().portrait end,
                    set = function(_, v) T().portrait = v Layout() end,
                },
                portraitMode = {
                    type = "select", name = L.OPT_PORTRAIT_MODE, desc = L.OPT_PORTRAIT_MODE_TIP, order = 2, width = 1.2,
                    values = Values(ns.PORTRAIT_MODES, L.PORTRAIT_MODE_NAMES), sorting = ns.PORTRAIT_MODES,
                    disabled = off,
                    get = function() return T().portraitMode end,
                    set = function(_, v) T().portraitMode = v end,
                },
                size  = DBRange(T, "portraitSize", L.OPT_SIZE, 3, 12, 128, 1, Layout, { disabled = off }),
                alpha = DBRange(T, "portraitAlpha", L.OPT_ALPHA, 4, 0.05, 1, 0.01, Layout, { isPercent = true, disabled = off }),
                x = DBRange(T, "portraitX", L.OPT_OFFSET_X, 5, -200, 200, 1, Layout, { disabled = off }),
                y = DBRange(T, "portraitY", L.OPT_OFFSET_Y, 6, -200, 200, 1, Layout, { disabled = off }),
                br1 = { type = "description", name = "", order = 7 },
                portraitMark = {
                    type = "toggle", name = L.OPT_PORTRAIT_MARK, desc = L.OPT_PORTRAIT_MARK_TIP, order = 8, width = 1,
                    disabled = off,
                    get = function() return T().portraitMark end,
                    set = function(_, v) T().portraitMark = v end,
                },
                markSize = DBRange(T, "portraitMarkSize", L.OPT_PORTRAIT_MARK_SIZE, 9, 8, 64, 1, Layout, {
                    disabled = function() return off() or not T().portraitMark end,
                }),
                br2 = { type = "description", name = "", order = 10 },
                markX = DBRange(T, "portraitMarkX", L.OPT_PORTRAIT_MARK_X, 11, -100, 100, 1, Layout, {
                    disabled = function() return off() or not T().portraitMark end,
                }),
                markY = DBRange(T, "portraitMarkY", L.OPT_PORTRAIT_MARK_Y, 12, -100, 100, 1, Layout, {
                    disabled = function() return off() or not T().portraitMark end,
                }),
                br3 = { type = "description", name = "", order = 13 },
                markGlow = {
                    type = "select", name = L.OPT_MARK_GLOW, desc = L.OPT_MARK_GLOW_TIP, order = 14, width = 1,
                    values = Values(ns.MARK_GLOWS, L.MARK_GLOW_NAMES), sorting = ns.MARK_GLOWS,
                    disabled = function() return off() or not T().portraitMark end,
                    get = function() return T().portraitMarkGlow end,
                    set = function(_, v) T().portraitMarkGlow = v Layout() end,
                },
                markGlowColor = Color(T, "portraitMarkGlowColor", L.OPT_MARK_GLOW_COLOR, 15, function()
                    return off() or not T().portraitMark or T().portraitMarkGlow == "OFF"
                end),
                markGlowSize = DBRange(T, "portraitMarkGlowSize", L.OPT_MARK_GLOW_SIZE, 16, 1, 12, 1, Layout, {
                    desc = L.OPT_MARK_GLOW_SIZE_TIP,
                    disabled = function() return off() or not T().portraitMark or T().portraitMarkGlow == "OFF" end,
                }),
            },
        }
    end
    args.label = FontGroup(function() return T().fontLabel end, L.SEC_UNIT_LABEL, 4, disabled, true)
    if hasUnit then
        args.name = FontGroup(function() return T().fontName end, L.SEC_UNIT_NAME, 5, disabled)
    end
    args.dot = {
        type = "group", inline = true, name = L.SEC_DOT, order = 6, disabled = disabled,
        args = {
            show = {
                type = "toggle", name = L.OPT_DOT_SHOW, order = 1, width = 1,
                get = function() return T().dotShow end,
                set = function(_, v) T().dotShow = v Layout() end,
            },
            color = Color(T, "dotColor", L.OPT_DOT_COLOR, 2, function() return not T().dotShow end),
            size = DBRange(T, "dotSize", L.OPT_SIZE, 3, 2, 32, 1, Layout, { disabled = function() return not T().dotShow end }),
        },
    }
end

-- Position / Appearance / Behavior tabs for settings table T() (own table of the menu).
-- disabled: look sections disabled (shared look); Icons and Close sections stay editable.
-- kind: menu kind (current mark options: raid mark menu only).
local function MenuTabs(T, disabled, isPing, kind)
    local function isRing() return T().layout == "RING" end
    local tabs = {
        position = {
            type = "group", name = L.TAB_POSITION, order = 11, disabled = disabled,
            args = {
                pos = {
                    type = "group", inline = true, name = L.SEC_POSITION, order = 1,
                    args = {
                        anchor = {
                            type = "select", name = L.OPT_ANCHOR, order = 1, width = 1,
                            values = Values(ns.ANCHORS, L.ANCHOR_NAMES), sorting = ns.ANCHORS,
                            get = function() return T().anchor end,
                            set = function(_, v) T().anchor = v Layout() end,
                        },
                        lock = {
                            type = "toggle", name = L.OPT_LOCK, desc = L.OPT_LOCK_TIP, order = 2,
                            disabled = function() return T().anchor ~= "FIXED" end,
                            get = function() return T().locked end,
                            set = function(_, v) T().locked = v Layout() end,
                        },
                    },
                },
                offset = {
                    type = "group", inline = true, name = L.SEC_OFFSET, order = 2,
                    args = {
                        x = DBRange(T, "x", L.OPT_OFFSET_X, 1, -1000, 1000, 1, Layout, { softMin = -400, softMax = 400 }),
                        y = DBRange(T, "y", L.OPT_OFFSET_Y, 2, -1000, 1000, 1, Layout, { softMin = -400, softMax = 400 }),
                        note = { type = "description", name = L.OPT_OFFSET_NOTE, order = 3 },
                    },
                },
            },
        },
        appearance = {
            type = "group", name = L.TAB_APPEARANCE, order = 12,
            args = {
                look = {
                    type = "group", inline = true, name = L.SEC_LOOK, order = 1, disabled = disabled,
                    args = {
                        layout = {
                            type = "select", name = L.OPT_LAYOUT, order = 1, width = 1,
                            values = Values(ns.LAYOUTS, L.LAYOUT_NAMES), sorting = ns.LAYOUTS,
                            get = function() return T().layout end,
                            set = function(_, v) T().layout = v Layout() end,
                        },
                        pad = { type = "description", name = "", order = 2, width = 1.2 },
                        scale    = DBRange(T, "scale", L.OPT_SCALE, 3, 0.5, 2, 0.01, Layout, { isPercent = true }),
                        alpha    = DBRange(T, "alpha", L.OPT_ALPHA, 4, 0.05, 1, 0.01, Layout, { isPercent = true }),
                        iconSize = DBRange(T, "iconSize", L.OPT_ICON_SIZE, 5, 12, 64, 1, Layout),
                        radius   = DBRange(T, "radius", L.OPT_RADIUS, 6, 16, 160, 1, Layout, { hidden = function() return not isRing() end }),
                        gap      = DBRange(T, "gap", L.OPT_GAP, 7, 0, 32, 1, Layout, { hidden = isRing }),
                    },
                },
                regions = {
                    type = "group", inline = true, name = L.SEC_REGIONS, order = 2, disabled = disabled,
                    args = {
                        hlShow = {
                            type = "toggle", name = L.OPT_HL_SHOW, order = 1, width = 1,
                            get = function() return T().hlShow end,
                            set = function(_, v) T().hlShow = v Layout() end,
                        },
                        hlMarkColor = {
                            type = "toggle", order = 1.5, width = 1,
                            name = isPing and L.OPT_HL_PING_COLOR or L.OPT_HL_MARK_COLOR,
                            desc = isPing and L.OPT_HL_PING_COLOR_TIP or L.OPT_HL_MARK_COLOR_TIP,
                            get = function() return T().hlMarkColor end,
                            set = function(_, v) T().hlMarkColor = v Layout() end,
                        },
                        hlColor = (function()
                            local t = Color(T, "hlColor", L.OPT_HL_COLOR, 2, function() return not T().hlShow end)
                            -- Grey label while colored by mark / ping type (picker stays usable: alpha still applies).
                            t.name = function() return T().hlMarkColor and ("|cff808080" .. L.OPT_HL_COLOR .. "|r") or L.OPT_HL_COLOR end
                            return t
                        end)(),
                        br0 = { type = "description", name = "", order = 2.5 },
                        regionShow = {
                            type = "toggle", name = L.OPT_REGION_SHOW, desc = L.OPT_REGION_SHOW_TIP, order = 3, width = 1,
                            get = function() return T().regionShow end,
                            set = function(_, v) T().regionShow = v Layout() end,
                        },
                        regionColor = Color(T, "regionColor", L.OPT_REGION_COLOR, 4, function() return not T().regionShow end),
                        iconDim = DBRange(T, "iconDim", L.OPT_ICON_DIM, 5, 0, 1, 0.01, Layout, { isPercent = true, desc = L.OPT_ICON_DIM_TIP }),
                        dimIdle = {
                            type = "toggle", name = L.OPT_DIM_IDLE, desc = L.OPT_DIM_IDLE_TIP, order = 6, width = 1.2,
                            get = function() return T().dimIdle end,
                            set = function(_, v) T().dimIdle = v Layout() end,
                        },
                        br1 = { type = "description", name = "", order = 7 },
                        hlGradient = {
                            type = "toggle", name = L.OPT_HL_GRADIENT, desc = L.OPT_HL_GRADIENT_TIP, order = 9, width = 1,
                            get = function() return T().hlGradient end,
                            set = function(_, v) T().hlGradient = v Layout() end,
                        },
                        br2 = { type = "description", name = "", order = 10 },
                        roundRing = {
                            type = "toggle", name = L.OPT_ROUND_RING, desc = L.OPT_ROUND_RING_TIP, order = 11, width = 1,
                            disabled = function() return not isRing() end,
                            get = function() return T().roundRing end,
                            set = function(_, v) T().roundRing = v Layout() end,
                        },
                        sliceGap = DBRange(T, "sliceGap", L.OPT_SLICE_GAP, 12, 0, 6, 1, Layout, { desc = L.OPT_SLICE_GAP_TIP }),
                        br3 = { type = "description", name = "", order = 13, hidden = kind ~= "unit" },
                        curRegion = {
                            type = "toggle", name = L.OPT_CUR_REGION, desc = L.OPT_CUR_REGION_TIP, order = 14, width = 1,
                            hidden = kind ~= "unit",
                            get = function() return T().curRegion end,
                            set = function(_, v) T().curRegion = v Layout() end,
                        },
                        curRegionColor = (function()
                            local t = Color(T, "curRegionColor", L.OPT_CUR_REGION_COLOR, 15, function() return not T().curRegion end)
                            t.hidden = kind ~= "unit"
                            return t
                        end)(),
                        curRegionMarkColor = {
                            type = "select", name = L.OPT_CUR_REGION_COLOR_MODE, desc = L.OPT_CUR_REGION_MARK_COLOR_TIP, order = 14.5, width = 1,
                            hidden = kind ~= "unit",
                            disabled = function() return not T().curRegion end,
                            values = { MARK = L.OPT_CUR_COLOR_MARK, CUSTOM = L.OPT_CUR_COLOR_CUSTOM },
                            sorting = { "MARK", "CUSTOM" },
                            get = function() return T().curRegionMarkColor and "MARK" or "CUSTOM" end,
                            set = function(_, v) T().curRegionMarkColor = (v == "MARK") Layout() end,
                        },
                        curUndim = {
                            type = "toggle", name = L.OPT_CUR_UNDIM, desc = L.OPT_CUR_UNDIM_TIP, order = 16, width = 1.2,
                            hidden = kind ~= "unit",
                            get = function() return T().curUndim end,
                            set = function(_, v) T().curUndim = v Layout() end,
                        },
                    },
                },
                effects = {
                    type = "group", inline = true, name = L.SEC_EFFECTS, order = 2.5, disabled = disabled,
                    args = {
                        pop = {
                            type = "toggle", name = L.OPT_POP, desc = L.OPT_POP_TIP, order = 1, width = 1,
                            get = function() return T().pop end,
                            set = function(_, v) T().pop = v Layout() end,
                        },
                        popSize = DBRange(T, "popSize", L.OPT_POP_SIZE, 2, 0.5, 3, 0.01, Layout, {
                            isPercent = true, disabled = function() return not T().pop end,
                        }),
                        br1 = { type = "description", name = "", order = 3 },
                        glow = {
                            type = "toggle", name = L.OPT_GLOW, desc = L.OPT_GLOW_TIP, order = 4, width = 1,
                            get = function() return T().glow end,
                            set = function(_, v) T().glow = v Layout() end,
                        },
                        glowColor = Color(T, "glowColor", L.OPT_GLOW_COLOR, 5, function() return not T().glow end),
                        br2 = { type = "description", name = "", order = 6 },
                        openAnim = {
                            type = "select", name = L.OPT_OPEN_ANIM, desc = L.OPT_OPEN_ANIM_TIP, order = 7, width = 1,
                            values = Values(ns.OPEN_ANIMS, L.OPEN_ANIM_NAMES), sorting = ns.OPEN_ANIMS,
                            get = function() return T().openAnim end,
                            set = function(_, v) T().openAnim = v Layout() end,
                        },
                        openAnimTime = DBRange(T, "openAnimTime", L.OPT_OPEN_ANIM_TIME, 8, 40, 250, 5, Layout, {
                            disabled = function() return T().openAnim == "OFF" end,
                        }),
                    },
                },
                icons = IconsGroup(T, isPing, 3),
                pingText = isPing and FontGroup(function() return T().fontPing end, L.SEC_PING_TEXT, 4, disabled) or nil,
            },
        },
        behavior = {
            type = "group", name = L.TAB_BEHAVIOR, order = 13,
            args = {
                select = {
                    type = "group", inline = true, name = L.SEC_SELECT, order = 1, disabled = disabled,
                    args = {
                        direction = {
                            type = "toggle", name = L.OPT_DIRECTION, desc = L.OPT_DIRECTION_TIP, order = 1, width = 1.2,
                            disabled = function() return not isRing() or T().anchor ~= "CURSOR" or not T().hover end,
                            get = function() return T().direction end,
                            set = function(_, v) T().direction = v Layout() end,
                        },
                        deadzone = DBRange(T, "deadzone", L.OPT_DEADZONE, 2, 2, 60, 1, Layout, {
                            desc = L.OPT_DEADZONE_TIP,
                            disabled = function() return not isRing() end,
                        }),
                    },
                },
                close = {
                    type = "group", inline = true, name = L.SEC_CLOSE, order = 2,
                    args = {
                        escClose = {
                            type = "toggle", name = L.OPT_ESC_CLOSE, desc = L.OPT_ESC_CLOSE_TIP, order = 1, width = 1.2,
                            get = function() return T().escClose end,
                            set = function(_, v) T().escClose = v Layout() end,
                        },
                    },
                },
            },
        },
    }
    return tabs
end

-- Center region / Fast mark tabs. mode: CenterActionArgs mode; hasUnit: CombatFastGroup.
local function ExtraTabs(args, T, mode, isPing, hasUnit, disabled, kind)
    args.center = {
        type = "group", name = L.TAB_CENTER, order = 14,
        args = {
            centerClick = {
                type = "group", inline = true, name = L.SEC_CENTER_ACTIONS, order = 1,
                args = CenterActionArgs(T, mode),
            },
        },
    }
    CenterLookGroups(args.center.args, T, disabled, kind)
    args.fast = {
        type = "group", name = L.TAB_FAST, order = 15,
        args = {
            fast = FastGroup(T, isPing, 1),
            combatFast = CombatFastGroup(T, isPing, hasUnit, 2),
        },
    }
end

local function MenuGroup()
    local args = MenuTabs(DB, nil, false, "unit")
    args.general = {
        type = "group", name = L.GRP_GENERAL, order = 1,
        args = {
            keybind = {
                type = "group", inline = true, name = L.SEC_KEYBIND, order = 1,
                args = {
                    key = {
                        type = "keybinding", name = L.OPT_KEYBIND, desc = L.OPT_KEYBIND_TIP, order = 1, width = 1,
                        get = function() return DB().key or "" end,
                        set = function(_, v) DB().key = (v ~= "" and v) or false ns.ApplyBinding() Options.Refresh() end,
                    },
                    clear = {
                        type = "execute", name = L.OPT_KEY_CLEAR, order = 2, width = 0.5, dialogControl = KEY_CLEAR,
                        func = function() DB().key = false ns.ApplyBinding() Options.Refresh() end,
                    },
                },
            },
            noUnit = {
                type = "group", inline = true, name = L.SEC_NO_UNIT, order = 0.5,
                args = {
                    worldFallback = {
                        type = "toggle", name = L.OPT_WORLD_FALLBACK, desc = L.OPT_WORLD_FALLBACK_TIP, order = 1, width = 1.4,
                        get = function() return DB().worldFallback end,
                        set = function(_, v) DB().worldFallback = v Layout() end,
                    },
                },
            },
            behavior = {
                type = "group", inline = true, name = L.SEC_SELECT, order = 2,
                args = SelectionArgs(DB, ns.CENTER_ACTIONS, L.OPT_WHEEL_UNIT_TIP, true),
            },
        },
    }
    ExtraTabs(args, DB, "unit", false, true, nil, "unit")
    GreyOut(args, "unit")
    return { type = "group", name = L.GRP_MENU, order = 2, childGroups = "tab", args = args }
end

---------------------------------------------------------------- World markers
local function WorldGroup()
    local args = MenuTabs(W, function() return W().sameLook end, false, "world")
    args.general = {
        type = "group", name = L.GRP_GENERAL, order = 1,
        args = {
            keybind = {
                type = "group", inline = true, name = L.SEC_WORLD_KEY, order = 1,
                args = {
                    sameKey = {
                        type = "toggle", name = L.OPT_SAME_KEY, desc = L.OPT_SAME_KEY_TIP, order = 1, width = 1.6,
                        get = function() return W().sameKey end,
                        set = function(_, v) W().sameKey = v ns.ApplyBinding() Options.Refresh() end,
                    },
                    modifier = {
                        type = "select", name = L.OPT_MODIFIER, order = 2, width = 0.9,
                        values = Values(ns.KEY_MODS, L.CLICK_MOD_NAMES), sorting = ns.KEY_MODS,
                        disabled = function() return not W().sameKey end,
                        get = function() return W().modKey end,
                        set = function(_, v) W().modKey = v ns.ApplyBinding() Options.Refresh() end,
                    },
                    key = {
                        type = "keybinding", name = L.OPT_WORLD_KEY, desc = L.OPT_KEYBIND_TIP, order = 3, width = 1,
                        disabled = function() return W().sameKey end,
                        get = function() return W().key or "" end,
                        set = function(_, v) W().key = (v ~= "" and v) or false ns.ApplyBinding() Options.Refresh() end,
                    },
                    clear = {
                        type = "execute", name = L.OPT_KEY_CLEAR, order = 4, width = 0.5, dialogControl = KEY_CLEAR,
                        disabled = function() return W().sameKey end,
                        func = function() W().key = false ns.ApplyBinding() Options.Refresh() end,
                    },
                    now = {
                        type = "description", order = 5, fontSize = "medium",
                        name = function() return L.OPT_WORLD_KEY_NOW:format(ns.MenuKey("world") or "-") end,
                    },
                },
            },
            behavior = {
                type = "group", inline = true, name = L.SEC_SELECT, order = 2,
                args = SelectionArgs(W, ns.WORLD_CENTER_ACTIONS, L.OPT_WHEEL_TIP),
            },
            place = {
                type = "group", inline = true, name = L.SEC_CLICK_PLACE, order = 2.5,
                args = {
                    clickPlace = {
                        type = "toggle", name = L.OPT_CLICK_PLACE, desc = L.OPT_CLICK_PLACE_TIP, order = 1, width = 1.2,
                        get = function() return W().clickPlace end,
                        set = function(_, v) W().clickPlace = v Layout() end,
                    },
                    clickButton = {
                        type = "select", name = L.OPT_CLICK_BUTTON, order = 2, width = 0.9,
                        values = Values(ns.CLICK_BUTTONS, L.CLICK_BUTTON_NAMES), sorting = ns.CLICK_BUTTONS,
                        disabled = function() return not W().clickPlace end,
                        get = function() return W().clickButton end,
                        set = function(_, v) W().clickButton = v Layout() end,
                    },
                    clickMod = {
                        type = "select", name = L.OPT_CLICK_MOD, order = 3, width = 1,
                        values = Values(ns.CLICK_MODS, L.CLICK_MOD_NAMES), sorting = ns.CLICK_MODS,
                        disabled = function() return not W().clickPlace end,
                        get = function() return W().clickMod end,
                        set = function(_, v) W().clickMod = v Layout() end,
                    },
                },
            },
            look = {
                type = "group", inline = true, name = L.SEC_WORLD_LOOK, order = 0,
                args = {
                    sameLook = {
                        type = "toggle", name = L.OPT_SAME_LOOK, order = 1, width = 2,
                        get = function() return W().sameLook end,
                        set = function(_, v) W().sameLook = v Layout() end,
                    },
                    note = { type = "description", name = L.OPT_WORLD_NOTE, order = 2 },
                },
            },
        },
    }
    ExtraTabs(args, W, "world", false, false, function() return W().sameLook end, "world")
    GreyOut(args, "world")
    return { type = "group", name = L.GRP_WORLD, order = 3, childGroups = "tab", args = args }
end

---------------------------------------------------------------- Ping menus
-- kind "ping" (unit ping) / "pworld" (world ping): same tabs as the mark menus.
local function PingGroup(kind, order)
    local isWorld = kind == "pworld"
    local function T() return ns.db[kind] end
    local function Key() ns.ApplyBinding() Options.Refresh() end
    local args = MenuTabs(T, function() return T().sameLook end, true, kind)
    local keyArgs = {
        sameKey = {
            type = "toggle", order = 1, width = 1.6,
            name = isWorld and L.OPT_SAME_PING_KEY or L.OPT_SAME_KEY,
            desc = isWorld and L.OPT_SAME_PING_KEY_TIP or L.OPT_SAME_KEY_PING_TIP,
            get = function() return T().sameKey end,
            set = function(_, v) T().sameKey = v Key() end,
        },
        modifier = {
            type = "select", name = L.OPT_MODIFIER, order = 2, width = 0.9,
            values = Values(ns.KEY_MODS, L.CLICK_MOD_NAMES), sorting = ns.KEY_MODS,
            disabled = function() return not T().sameKey end,
            get = function() return T().modKey end,
            set = function(_, v) T().modKey = v Key() end,
        },
        key = {
            type = "keybinding", name = L.OPT_OWN_KEY, desc = L.OPT_KEYBIND_TIP, order = 3, width = 1,
            disabled = function() return T().sameKey end,
            get = function() return T().key or "" end,
            set = function(_, v) T().key = (v ~= "" and v) or false Key() end,
        },
        clear = {
            type = "execute", name = L.OPT_KEY_CLEAR, order = 4, width = 0.5, dialogControl = KEY_CLEAR,
            disabled = function() return T().sameKey end,
            func = function() T().key = false Key() end,
        },
        now = {
            type = "description", order = 5, fontSize = "medium",
            name = function() return L.OPT_WORLD_KEY_NOW:format(ns.MenuKey(kind) or "-") end,
        },
    }
    args.general = {
        type = "group", name = L.GRP_GENERAL, order = 1,
        args = {
            noUnit = not isWorld and {
                type = "group", inline = true, name = L.SEC_NO_UNIT, order = 0.5,
                args = {
                    auto = {
                        type = "toggle", name = L.OPT_PING_AUTO, desc = L.OPT_PING_AUTO_TIP, order = 1, width = 1.4,
                        get = function() return T().auto end,
                        set = function(_, v) T().auto = v Layout() end,
                    },
                },
            } or nil,
            keybind = { type = "group", inline = true, name = L.SEC_KEYBIND, order = 1, args = keyArgs },
            behavior = {
                type = "group", inline = true, name = L.SEC_SELECT, order = 2,
                args = SelectionArgs(T, nil, isWorld and L.OPT_WHEEL_PWORLD_TIP or L.OPT_WHEEL_PING_TIP, not isWorld),
            },
            place = isWorld and {
                type = "group", inline = true, name = L.SEC_CLICK_PLACE, order = 2.5,
                args = {
                    clickPlace = {
                        type = "toggle", name = L.OPT_CLICK_PLACE_PING, desc = L.OPT_CLICK_PLACE_PING_TIP, order = 1, width = 1.2,
                        get = function() return T().clickPlace end,
                        set = function(_, v) T().clickPlace = v Layout() end,
                    },
                    clickButton = {
                        type = "select", name = L.OPT_CLICK_BUTTON, order = 2, width = 0.9,
                        values = Values(ns.CLICK_BUTTONS, L.CLICK_BUTTON_NAMES), sorting = ns.CLICK_BUTTONS,
                        disabled = function() return not T().clickPlace end,
                        get = function() return T().clickButton end,
                        set = function(_, v) T().clickButton = v Layout() end,
                    },
                    clickMod = {
                        type = "select", name = L.OPT_CLICK_MOD, order = 3, width = 1,
                        values = Values(ns.CLICK_MODS, L.CLICK_MOD_NAMES), sorting = ns.CLICK_MODS,
                        disabled = function() return not T().clickPlace end,
                        get = function() return T().clickMod end,
                        set = function(_, v) T().clickMod = v Layout() end,
                    },
                    pendPulse = {
                        type = "toggle", name = L.OPT_PEND_PULSE, desc = L.OPT_PEND_PULSE_TIP, order = 4, width = 1.2,
                        disabled = function() return not T().clickPlace end,
                        get = function() return T().pendPulse end,
                        set = function(_, v) T().pendPulse = v end,
                    },
                },
            } or nil,
            pendText = isWorld and FontGroup(function() return T().fontPend end, L.SEC_PEND_TEXT, 2.6,
                function() return not T().clickPlace end) or nil,
            look = {
                type = "group", inline = true, name = L.SEC_WORLD_LOOK, order = 0,
                args = {
                    sameLook = {
                        type = "toggle", order = 1, width = 2,
                        name = isWorld and L.OPT_SAME_LOOK_PING or L.OPT_SAME_LOOK,
                        get = function() return T().sameLook end,
                        set = function(_, v) T().sameLook = v Layout() end,
                    },
                    note = { type = "description", name = isWorld and L.OPT_PWORLD_NOTE or L.OPT_PING_NOTE, order = 2 },
                },
            },
        },
    }
    ExtraTabs(args, T, "ping", true, not isWorld, function() return T().sameLook end, kind)
    GreyOut(args, kind)
    return { type = "group", name = isWorld and L.GRP_PWORLD or L.GRP_PING, order = order, childGroups = "tab", args = args }
end

---------------------------------------------------------------- registration
-- Option table built on the first request (window / Esc panel open), then reused.
local root

local function Build()
    if root then return root end
    root = {
        type = "group", name = L.OPT_TITLE, childGroups = "tree",
        args = {
            general = GeneralGroup(),
            menu    = MenuGroup(),
            world   = WorldGroup(),
            ping    = PingGroup("ping", 4),
            pworld  = PingGroup("pworld", 5),
        },
    }
    -- Profiles (AceDBOptions): new / switch / copy / delete / reset.
    local prof = ADBO:GetOptionsTable(ns.dbObj)
    prof.order = 6
    root.args.profiles = prof
    return root
end

function Options.ToggleWindow()
    if ACD.OpenFrames[APP] then
        ACD:Close(APP)
    else
        ACD:Open(APP)
    end
end

function Options.OpenSettings()
    if Options.categoryID then
        Settings.OpenToCategory(Options.categoryID)
    else
        Options.ToggleWindow()
    end
end

function Options.Init()
    ACR:RegisterOptionsTable(APP, Build)
    ACD:SetDefaultSize(APP, 760, 520)
    local ok, frame, id = pcall(ACD.AddToBlizOptions, ACD, APP, "FFmarks")
    if ok and frame then
        Options.categoryID = id or frame.name
    else
        ns.Debug("AddToBlizOptions failed: " .. tostring(frame))
    end
end
