std = "lua51"
max_line_length = 120
exclude_files = { ".luarocks", "lua_modules" }

-- Game API names the addon reads or writes.
globals = {
    "Forever21DB", "Forever21CharDB",
    "SlashCmdList", "SLASH_FOREVER211", "SLASH_FOREVER212",
}
read_globals = {
    "C_ChatInfo", "SendAddonMessage", "CreateFrame", "UnitName", "DEFAULT_CHAT_FRAME",
}

files["spec/"] = { std = "+busted" }
