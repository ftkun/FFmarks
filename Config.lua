local addonName, ns = ...
local L = ns.L

local function Slash(msg)
    msg = (msg or ""):upper()
    local cmd = msg:match("^%s*(%S*)")

    if cmd == "" then
        ns.Options.ToggleWindow()
    elseif cmd == "CONFIG" then
        ns.Options.OpenSettings()
    elseif cmd == "DEBUG" then
        ns.db.debug = not ns.db.debug
        ns.Print(L.DEBUG_SET:format(tostring(ns.db.debug)))
        ns.Options.Refresh()
    else
        for _, line in ipairs(L.HELP) do ns.Print(line) end
    end
end

SLASH_FFMARKS1 = "/ffm"
SLASH_FFMARKS2 = "/FFmarks"
SlashCmdList.FFMARKS = Slash
