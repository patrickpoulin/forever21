-- Core.lua: addon setup, saved data, and small helpers that touch the game API.
local addonName, ns = ...

ns.VERSION = "0.2.0"
ns.PREFIX = "F21BJ" -- addon message prefix, used from milestone 3

local DB_DEFAULTS = {
    sound = true,
    chat = true,      -- print game events to chat
    point = nil,      -- saved window position
}

local CHAR_DEFAULTS = {
    gamesPlayed = 0,
    gamesWon = 0,
    handsPlayed = 0,
}

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then target[k] = v end
    end
    return target
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Forever21|r: " .. tostring(msg))
end

function ns.PlayerName()
    return (UnitName("player"))
end

-- Which addon-message API this client has. WoW Forever (interface 16001) is
-- Classic-based, so C_ChatInfo is expected; older clients only have the global.
function ns.AddonMessageAPI()
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return "C_ChatInfo"
    elseif SendAddonMessage then
        return "global"
    end
    return nil
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        Forever21DB = applyDefaults(Forever21DB or {}, DB_DEFAULTS)
        Forever21CharDB = applyDefaults(Forever21CharDB or {}, CHAR_DEFAULTS)
        ns.db, ns.charDB = Forever21DB, Forever21CharDB
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
