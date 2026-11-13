std = "lua51"
self = false
max_line_length = 120
exclude_files = { ".luarocks", "lua_modules" }

-- Game API names the addon reads or writes.
globals = {
    "Forever21DB", "Forever21CharDB",
    "SlashCmdList", "SLASH_FOREVER211", "SLASH_FOREVER212", "StaticPopupDialogs",
}
read_globals = {
    "C_ChatInfo", "SendAddonMessage", "CreateFrame", "UnitName", "DEFAULT_CHAT_FRAME",
    "UIParent", "UISpecialFrames", "tinsert", "PlaySound", "SOUNDKIT",
    "GetTime", "C_Timer", "UnitExists", "StaticPopup_Show", "ACCEPT", "DECLINE",
}

files["spec/"] = { std = "+busted" }

-- The WoW API stub only needs to be good enough for previews and smoke tests.
files["tools/"] = { ignore = { "212", "512", "631" } }
