local addonName, ns = ...

local L = {}
ns.L = L

L.PREFIX          = "|cff33ff99FFmarks|r: "
L.LOADED          = "loaded. /ffm = options, /ffm help = commands."
L.DEBUG_SET       = "debug: %s"
L.BIND_PENDING    = "in combat: keybind applied after combat."
L.HELP = {
    "/ffm - options window, /ffm config - Blizzard options panel",
    "/ffm debug - toggle debug output",
    "Hold the key, point at a mark, release. Key: /ffm > Markers Units > General or Esc > Keybindings > AddOns.",
    "Hold the Markers World key (default: Markers Units key + Ctrl) for ground markers.",
    "Pings: Ping default = Markers Units key + Shift; Ping World: set a key in /ffm > Ping World.",
}

-- Blizzard Key Bindings menu (globals required by Bindings.xml).
BINDING_HEADER_FFMARKS    = "FFmarks"
_G["BINDING_NAME_CLICK FFmarksHoldButton:LeftButton"] = "Hold: Markers Units menu"
_G["BINDING_NAME_CLICK FFmarksWorldButton:LeftButton"] = "Hold: Markers World menu"
_G["BINDING_NAME_CLICK FFmarksPingButton:LeftButton"] = "Hold: Ping menu"
_G["BINDING_NAME_CLICK FFmarksPingWorldButton:LeftButton"] = "Hold: Ping World menu"

L.UNIT_TARGET    = "Target"
L.WORLD_LABEL    = "Markers World"
L.KEY_SAME       = "%s key %s = %s key, not bound. Change the key or the modifiers."
L.MENU_NAMES     = { unit = "Markers Units", world = "Markers World", ping = "Ping", pworld = "Ping World" }
L.UNIT_MOUSEOVER = "Mouseover"
L.UNIT_LOST      = "Lost"

-- Options
L.OPT_TITLE       = "FFmarks"
L.GRP_GENERAL     = "General"
L.GRP_MENU        = "Markers Units"
L.TAB_POSITION    = "Position"
L.TAB_APPEARANCE  = "Appearance"
L.TAB_BEHAVIOR    = "Behavior"

L.SEC_KEYBIND     = "Keybind"
L.SEC_MISC        = "Misc"
L.SEC_POSITION    = "Position"
L.SEC_OFFSET      = "Offset"
L.SEC_LOOK        = "Look"
L.SEC_SELECT      = "Selection"

L.OPT_KEYBIND     = "Hold key"
L.OPT_KEYBIND_TIP = "Addon keybind (override, does not change WoW saved bindings). Empty = off. Esc > Keybindings > AddOns > FFmarks works too."
L.OPT_KEY_CLEAR   = "Clear"
L.OPT_UNIT        = "Unit priority"
L.UNIT_NAMES = {
    MOUSEOVER_TARGET = "Mouseover, else target",
    TARGET_MOUSEOVER = "Target, else mouseover",
    MOUSEOVER        = "Mouseover only",
    TARGET           = "Target only",
}
L.OPT_DEBUG       = "Debug"
L.SEC_ENABLED     = "Enabled menus"
L.OPT_ENABLED_TIP = "Off: menu key does nothing (addon key and Esc > Keybindings), menu options greyed out. Its key still works as base key for menus using 'key + modifiers'."
L.SEC_RESET       = "Default settings"
L.OPT_RESET       = "Reset to defaults"
L.OPT_RESET_NOTE  = "Resets all settings of the current profile (all menus, keys, look)."
L.OPT_RESET_CONFIRM = "Reset all FFmarks settings of the current profile to defaults?"

L.OPT_ANCHOR      = "Anchor"
L.ANCHOR_NAMES    = { CURSOR = "Cursor", FIXED = "Fixed" }
L.OPT_LOCK        = "Lock"
L.OPT_LOCK_TIP    = "Unlock to show the menu and drag it (Fixed anchor only)."
L.OPT_OFFSET_X    = "X"
L.OPT_OFFSET_Y    = "Y"
L.OPT_OFFSET_NOTE = "Cursor: offset from cursor. Fixed: offset from screen center."

L.OPT_LAYOUT      = "Layout"
L.LAYOUT_NAMES    = { RING = "Ring", GRID = "Grid 3x3", HROW = "Horizontal row", VROW = "Vertical row" }
L.OPT_SCALE       = "Scale"
L.OPT_ALPHA       = "Transparency"
L.OPT_ICON_SIZE   = "Icon size"
L.OPT_CENTER_ICON_TIP   = "Icon in the menu center, shown when Release / tap is on (the release mark / ping)."
L.OPT_RADIUS      = "Ring radius"
L.OPT_GAP         = "Icon gap"
L.SEC_REGIONS     = "Highlight"
L.OPT_HL_SHOW     = "Highlight selected"
L.OPT_HL_COLOR    = "Highlight color"
L.OPT_REGION_SHOW = "Show other regions"
L.OPT_REGION_SHOW_TIP = "Background under not selected marks (pie sectors / cells)."
L.OPT_REGION_COLOR = "Region color"
L.OPT_ICON_DIM    = "Not selected icon brightness"
L.OPT_ICON_DIM_TIP = "100% = no dimming."
L.OPT_DIM_IDLE    = "Dim icons until selected"
L.OPT_HL_MARK_COLOR      = "Color by mark"
L.OPT_HL_MARK_COLOR_TIP  = "Selected region (and glow) takes the color of the highlighted mark instead of Highlight color: Star yellow, Circle orange, Diamond purple, Triangle green, Moon silver, Square blue, Cross red, Skull white. Transparency still from Highlight color."
L.OPT_HL_PING_COLOR      = "Color by ping type"
L.OPT_HL_PING_COLOR_TIP  = "Selected region (and glow) takes the color of the highlighted ping type instead of Highlight color: Attack orange, Warning red, On my way blue, Assist green, Ping light blue. Transparency still from Highlight color."
L.OPT_HL_GRADIENT      = "Gradient"
L.OPT_HL_GRADIENT_TIP  = "Regions fade: inner edge faint, outer edge full (grid / rows: bottom faint, top full)."
L.OPT_ROUND_RING       = "Round ring"
L.OPT_ROUND_RING_TIP   = "Ring layout: round outer edge of the regions (circle mask)."
L.OPT_SLICE_GAP        = "Region gap"
L.OPT_CUR_REGION       = "Highlight current mark"
L.OPT_CUR_REGION_TIP   = "Region of the mark the unit already has is lit (Markers Units menu)."
L.OPT_CUR_REGION_COLOR = "Current mark color"
L.OPT_CUR_REGION_MARK_COLOR_TIP = "Color by mark: current mark region in the mark's own color: Star yellow, Circle orange, Diamond purple, Triangle green, Moon silver, Square blue, Cross red, Skull white (transparency from Current mark color). Custom color: Current mark color."
L.OPT_CUR_REGION_COLOR_MODE = "Current mark coloring"
L.OPT_CUR_COLOR_MARK   = "Color by mark"
L.OPT_CUR_COLOR_CUSTOM = "Custom color"
L.OPT_CUR_UNDIM        = "Current mark not dimmed"
L.OPT_CUR_UNDIM_TIP    = "Markers Units menu: icon of the mark the unit already has keeps full brightness (works in combat)."
L.OPT_SLICE_GAP_TIP    = "Gap in px between regions (ring sectors / grid and row cells)."
L.SEC_EFFECTS          = "Effects"
L.OPT_POP              = "Pop selected icon"
L.OPT_POP_TIP          = "Selected icon is drawn bigger (size: Pop size; below 100% = smaller)."
L.OPT_POP_SIZE         = "Pop size"
L.OPT_GLOW             = "Glow"
L.OPT_GLOW_TIP         = "Glow behind the selected icon. Color by mark / Color by ping type on: glow in that color (transparency from Glow color)."
L.OPT_GLOW_COLOR       = "Glow color"
L.OPT_OPEN_ANIM        = "Open animation"
L.OPT_OPEN_ANIM_TIP    = "Fade: icons fade in. Fade + grow: icons fade in and grow from 85%."
L.OPEN_ANIM_NAMES      = { OFF = "Off", FADE = "Fade", GROW = "Fade + grow" }
L.OPT_OPEN_ANIM_TIME   = "Animation time (ms)"
L.SEC_CENTER_ICON      = "Icon"
L.OPT_CENTER_ICON_HIDE = "Hide icon"
L.OPT_CENTER_ICON_HIDE_TIP = "Center icon is not drawn; release / tap and click in the center region still work (e.g. portrait instead)."
L.SEC_PORTRAIT         = "Portrait"
L.OPT_PORTRAIT_MARK    = "Mark on portrait"
L.OPT_PORTRAIT_MARK_TIP = "Unit's current raid mark icon over the portrait."
L.OPT_PORTRAIT_MARK_SIZE = "Mark size"
L.OPT_PORTRAIT_MARK_X  = "Mark X"
L.OPT_PORTRAIT_MARK_Y  = "Mark Y"
L.OPT_MARK_GLOW        = "Mark glow"
L.OPT_MARK_GLOW_TIP    = "Soft glow: glow around the mark. Hard outline: tinted copies of the mark around it (outline look)."
L.MARK_GLOW_NAMES      = { OFF = "Off", SOFT = "Soft glow", OUTLINE = "Hard outline" }
L.OPT_MARK_GLOW_COLOR  = "Glow color"
L.OPT_MARK_GLOW_SIZE   = "Glow size"
L.OPT_MARK_GLOW_SIZE_TIP = "Soft glow: extra size (px). Hard outline: thickness (px)."
L.SEC_UNIT_LABEL       = "Unit label"
L.SEC_UNIT_NAME        = "Unit name"
L.SEC_PING_TEXT        = "Ping icon text"
L.SEC_PEND_TEXT        = "Pending ping text"
L.SEC_DOT              = "Center dot"
L.OPT_DOT_SHOW         = "Show dot"
L.OPT_DOT_COLOR        = "Dot color"
L.OPT_SIZE             = "Size"
L.OPT_FONT             = "Font"
L.OPT_FONT_SIZE        = "Font size"
L.OPT_OUTLINE          = "Outline"
L.OUTLINE_NAMES        = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" }
L.OPT_FONT_COLOR       = "Color"
L.OPT_UNIT_COLORS      = "Unit colors"
L.OPT_UNIT_COLORS_TIP  = "Target red, mouseover green, ground / world blue. Off: Color."
L.OPT_PORTRAIT         = "Portrait"
L.OPT_PORTRAIT_TIP     = "Round portrait of the unit in the menu center."
L.OPT_PORTRAIT_MODE    = "With center icon"
L.OPT_PORTRAIT_MODE_TIP = "Center icon shown (Center actions Release / tap on, icon not hidden): hide the portrait, or draw it behind the center icon."
L.PORTRAIT_MODE_NAMES  = { HIDE = "Hide portrait", BEHIND = "Behind center icon" }
L.OPT_SOUND            = "Sound on apply"
L.OPT_SOUND_TIP        = "Plays a sound when a mark / marker / ping is applied from this menu."
L.OPT_SOUND_ID         = "Sound"
L.SEC_AUDIO            = "Audio"
L.OPT_SOUND_ON         = "Enable sounds"
L.OPT_SOUND_ON_TIP     = "Master switch for all FFmarks sounds. Off: no sound. On: the 'Sound on apply' / 'Sound on highlight' options of each menu decide."
L.OPT_SOUND_CHANNEL    = "Sound channel"
L.OPT_SOUND_CHANNEL_TIP = "Game volume channel for FFmarks sounds. Master: still heard with Effects / Music / Ambience muted."
L.SOUND_CHANNEL_NAMES  = { Master = "Master", SFX = "Effects", Music = "Music", Ambience = "Ambience", Dialog = "Dialog" }
L.OPT_HL_SOUND         = "Sound on highlight"
L.OPT_HL_SOUND_TIP     = "Plays a sound each time another mark / marker / ping is highlighted (cursor or wheel), before it is applied. Not on menu open, not for the center."
L.SOUND_NAMES          = {
    CHECK = "Check", CHECK_OFF = "Uncheck", OPTION = "Option click", OK = "OK",
    MENU_OPEN = "Menu open", MENU_CLOSE = "Menu close", CHAR_TAB = "Character tab", MINIMAP = "Minimap",
    AGGRO = "Target hostile", NPC = "Target NPC", NEUTRAL = "Target neutral",
}
L.OPT_PEND_PULSE       = "Pulse pending ping icon"
L.OPT_PEND_PULSE_TIP   = "Pending ping icon at the cursor pulses until placed or cancelled."
L.OPT_DIM_IDLE_TIP = "On menu open all icons (not the center icon) use the not selected brightness; the icon under the cursor / wheel lights up."

L.OPT_DIRECTION     = "Select by direction"
L.OPT_DIRECTION_TIP = "Ring + Cursor anchor: pie sectors start at the cursor position at key down (matters only with X/Y offset). Off = sectors start at ring center."
L.OPT_DEADZONE    = "Center deadzone"
L.OPT_DEADZONE_TIP = "Ring: radius of the center area (release = center action)."
L.OPT_CENTER      = "Release in center"
L.CENTER_NAMES    = { CANCEL = "Cancel", CLEAR = "Clear mark", CLEAR_ALL = "Clear all world markers" }

-- World markers
L.GRP_WORLD        = "Markers World"
L.SEC_WORLD_KEY    = "Keybind"
L.SEC_WORLD_LOOK   = "Look"
L.SEC_NO_UNIT      = "No unit"
L.OPT_SAME_KEY     = "Use Markers Units key + modifiers"
L.OPT_SAME_KEY_TIP = "On: Markers Units key with the modifier(s) below opens the Markers World menu. Off: own key."
L.OPT_MODIFIER     = "Modifiers"
L.OPT_WORLD_KEY    = "Own key"
L.OPT_WORLD_KEY_NOW = "Current key: |cffffd100%s|r"
L.OPT_SAME_LOOK    = "Use Markers Units menu look and position"
L.SEC_CLICK_PLACE = "Click to place"
L.OPT_CLICK_PLACE = "Click icon = placement circle"
L.OPT_CLICK_PLACE_TIP = "While the key is held, click an icon with the button + modifiers below: green placement circle opens, click the ground to place the marker. Menu closes; key release does nothing."
L.OPT_CLICK_BUTTON = "Mouse button"
L.CLICK_BUTTON_NAMES = { LeftButton = "Left", RightButton = "Right", MiddleButton = "Middle", Button4 = "Button 4", Button5 = "Button 5" }
L.OPT_CLICK_MOD   = "Modifiers"
L.CLICK_MOD_NAMES = {
    NONE = "None", ANY = "Any", SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt",
    ["CTRL-SHIFT"] = "Ctrl+Shift", ["ALT-SHIFT"] = "Alt+Shift", ["ALT-CTRL"] = "Alt+Ctrl", ["ALT-CTRL-SHIFT"] = "Alt+Ctrl+Shift",
}
L.SEC_CENTER_ACTIONS = "Center actions"
L.OPT_CENTER_CLICK = "Click (key held)"
L.OPT_CENTER_CLICK_TIP = "While the key is held, click in the menu center (ring: deadzone, grid / rows: center cell) with a button + modifiers from the rows below: that row's mark is set on the unit. Rows are checked top to bottom, the first match wins (put Any modifiers rows last). Menu closes; key release does nothing. The mouse buttons are bound only while the key is held."
L.OPT_CENTER_CLICK_WORLD_TIP = "While the key is held, click in the menu center (ring: deadzone, grid / rows: center cell) with a button + modifiers from the rows below: that row's marker is placed (row Placement). Rows are checked top to bottom, the first match wins (put Any modifiers rows last). Menu closes; key release does nothing. The mouse buttons are bound only while the key is held."
L.OPT_CENTER_MARK = "Mark"
L.OPT_CENTER_RELEASE = "Release / tap"
L.OPT_BIND_ADD     = "Add click"
L.OPT_BIND_ADD_TIP = "Adds a click row (mouse button + modifiers + mark)."
L.OPT_BIND_REMOVE  = "X"
L.OPT_CENTER_RELEASE_TIP = "Key release with the cursor in the menu center (ring: deadzone, grid / rows: center cell) = center icon. Cursor not moved = center, so a quick tap (in combat too) sets the center icon. Wheel choice and icon under the cursor still win. Works with Hover select off too (cursor checked only for the center)."
L.SEC_ICONS = "Icons"
L.OPT_ICONS_SHOWN = "Shown icons (unchecked = removed from ring / grid / rows; at least one stays):"
L.OPT_KEEP_SLOTS = "Keep empty slots"
L.OPT_KEEP_SLOTS_TIP = "On: icons keep their positions, a removed icon leaves an empty slot (release there = cancel). Off: remaining icons are spread evenly (ring) / fill the slots in order (grid, rows)."
L.OPT_WHEEL_START = "Wheel start icon (needs Mouse wheel select; none checked = off):"
L.OPT_WHEEL_START_TIP = "Menu opens with this icon selected. Wheel continues from it; icon under the cursor wins. Cursor in center: Center actions Release / tap on = center icon, else this icon."
L.MARK_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
L.OPT_CENTER_PLACE = "Placement"
L.CENTER_PLACE_NAMES = { CURSOR = "At cursor (instant)", CIRCLE = "Placement circle" }
L.SEC_FAST        = "Fast mark"
L.OPT_FAST        = "Fast mark"
L.OPT_FAST_TIP    = "Short key tap = the icon below is set without picking from the menu (raid mark on the unit / marker or ping under the cursor). Toggle mode: a short tap applies it and the menu closes."
L.OPT_FAST_TIME   = "Max tap time (ms)"
L.OPT_FAST_TIME_TIP = "Key released faster than this = fast icon. Longer hold = normal menu. Out of combat only."
L.OPT_FAST_NOLIMIT = "No time limit"
L.OPT_FAST_NOLIMIT_TIP = "Fast icon does not depend on tap time; behavior: mode on the right. Works in combat (except the tap part of 'Tap or empty release')."
L.OPT_FAST_MODE   = "No limit mode"
L.OPT_FAST_MODE_TIP = "Empty release: release with nothing picked (center / deadzone, no wheel pick) = fast icon, hold time ignored. Tap or empty release: short tap (out of combat) or empty release. Instant: key press = fast icon, menu never opens."
L.FAST_MODE_NAMES = { EMPTY = "Empty release", BOTH = "Tap or empty release", INSTANT = "Instant (no menu)" }
L.OPT_FAST_DOUBLE = "Double tap = 2nd icon"
L.OPT_FAST_DOUBLE_TIP = "A second fast tap within the time below replaces the first icon: Markers Units / Ping = the 2nd one is set; Markers World = 1st marker removed, 2nd placed under the cursor. Out of combat only."
L.OPT_FAST_MARK2  = "2nd mark"
L.OPT_FAST_PING2  = "2nd ping"
L.OPT_FAST_DOUBLE_TIME = "Double tap window (ms)"
L.OPT_FAST_DOUBLE_TIME_TIP = "Max time between the two key releases."
L.OPT_FAST_NOTE   = "|cffff8800In combat:|r tap time and double tap are not measured (WoW secure code has no timer), so 'Max tap time' and 'Double tap' work out of combat only; in combat the key opens the normal menu. 'No time limit' modes 'Empty release' and 'Instant' work in combat too."
L.SEC_COMBAT_FAST = "Fast mark in combat"
L.OPT_COMBAT_FAST = "Enable"
L.OPT_COMBAT_FAST_TIP = "In combat: key press = the icon below is set at key release, menu never opens (no timer needed). Markers Units / Ping: on the unit by the priority below. Markers World / Ping World: under the cursor. In combat it replaces Fast mark; out of combat everything works as before."
L.OPT_COMBAT_FAST_NOUNIT = "No unit"
L.OPT_COMBAT_FAST_NOUNIT_TIP = "In combat, no unit found by the priority: Nothing = no action; Ground = Markers Units: world marker under the cursor, Ping: ground ping under the cursor; Open menu = normal menu opens."
L.COMBAT_NOUNIT_NAMES = { NONE = "Nothing", GROUND = "Ground (cursor)", MENU = "Open menu" }
L.OPT_WHEEL       = "Mouse wheel select"
L.OPT_WHEEL_DIR   = "Wheel down direction"
L.OPT_HOVER       = "Hover select"
L.OPT_HOVER_TIP   = "On: icon under the cursor is picked (wheel choice wins). Off: cursor position ignored, only mouse wheel picks (and left click in toggle mode)."
L.OPT_TOGGLE      = "Toggle mode"
L.OPT_TOGGLE_TIP  = "On: press the key to open the menu (no holding). Press the key again or left click to apply (left click on an icon = that icon). Left click is bound only while the menu is open. Off: hold and release."
L.OPT_ESC_CLOSE   = "Escape closes menu"
L.OPT_ESC_CLOSE_TIP = "Escape cancels the open menu (hold and toggle mode). Escape is bound only while the menu is open."
L.TAB_CENTER      = "Center region"
L.TAB_FAST        = "Fast mark"
L.SEC_CLOSE       = "Close"
L.OPT_NOPICK      = "Nothing picked"
L.OPT_NOPICK_TIP  = "Hover select off and nothing picked with the wheel: Cancel = nothing, Center action = same as release in center, Last used = icon picked last time in this menu (this session)."
L.NOPICK_NAMES    = { CANCEL = "Cancel", CENTER = "Center action", LAST = "Last used" }
L.WHEEL_DIR_NAMES = { CW = "Clockwise", CCW = "Counterclockwise" }
L.OPT_WHEEL_UNIT_TIP = "While the key is held, mouse wheel cycles marks (direction: option), works with any modifiers held. Cursor stays on the mouseover unit. Moving the mouse to an icon still works; a wheel choice wins."
L.OPT_WHEEL_TIP   = "While the key is held, mouse wheel cycles markers (direction: option). Keep the cursor still: marker is placed at ring center. Moving the mouse to an icon still works; a wheel choice wins."
L.OPT_WORLD_NOTE   = "Marker is placed on the ground under the cursor at key release (where the chosen icon is). Needs group (raid: lead / assist)."

-- Pings
L.GRP_PING         = "Ping"
L.GRP_PWORLD       = "Ping World"
L.PING_NAMES       = { ping = "Ping", attack = "Attack", warning = "Warning", onmyway = "On my way", assist = "Assist" }
L.PING_UNIT        = "Ping: %s"
L.PING_GROUND      = "Ping: ground"
L.PING_WORLD_LABEL = "Ping World"
L.OPT_OWN_KEY      = "Own key"
L.OPT_SAME_KEY_PING_TIP = "On: Markers Units key with the modifier(s) below opens the Ping menu. Off: own key."
L.OPT_SAME_PING_KEY     = "Use ping key + modifiers"
L.OPT_SAME_PING_KEY_TIP = "On: Ping key with the modifier(s) below opens the Ping World menu. Off: own key."
L.OPT_PING_AUTO     = "Auto: no unit = ground ping"
L.OPT_PING_AUTO_TIP = "No unit at key down (unit priority): menu still opens, ping goes on the ground under the cursor at release. Off: no unit = menu does not open."
L.OPT_WORLD_FALLBACK     = "Auto: no unit = world marker"
L.OPT_WORLD_FALLBACK_TIP = "No unit at key down (unit priority): menu still opens, world marker is placed under the cursor at release. Center release follows the Markers World menu center action; click in center places the center mark as world marker. Off: no unit = menu does not open."
L.OPT_CENTER_CLICK_PING_TIP = "While the key is held, click in the menu center (ring: deadzone, grid / rows: center cell) with a button + modifiers from the rows below: that row's ping is sent (Ping: on the unit; Ping World: under the cursor). Rows are checked top to bottom, the first match wins (put Any modifiers rows last). Menu closes; key release does nothing. The mouse buttons are bound only while the key is held."
L.OPT_CENTER_PING   = "Ping"
L.OPT_SAME_LOOK_PING = "Use Ping menu look and position"
L.OPT_WHEEL_PING_TIP = "While the key is held, mouse wheel cycles pings (direction: option), works with any modifiers held. Cursor stays on the mouseover unit. Moving the mouse to an icon still works; a wheel choice wins."
L.OPT_WHEEL_PWORLD_TIP = "While the key is held, mouse wheel cycles pings (direction: option). Keep the cursor still: ping goes at ring center. Moving the mouse to an icon still works; a wheel choice wins."
L.OPT_PING_NOTE   = "Ping is sent on the unit at key release (unit priority). Auto on: ground under the cursor when there is no unit. Release in center = cancel."
L.OPT_PWORLD_NOTE = "Ping is sent under the cursor at key release (where the chosen icon is): unit under the cursor if any, else ground. Release in center = cancel."
L.OPT_CLICK_PLACE_PING = "Click icon = pending ping"
L.OPT_CLICK_PLACE_PING_TIP = "While the key is held, click an icon with the button + modifiers below: menu closes, the ping icon follows the cursor, next click with the same button (any modifiers) sends the ping under the cursor. Right click (left if the button is Right) or Escape cancels; pressing the Ping World key again cancels too. Normal clicks of that button are blocked while pending."
