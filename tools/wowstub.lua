-- A stand-in for the bits of the WoW API the addon uses, so the whole addon can
-- run in plain Lua 5.1. Each simulated player gets their own copy of the addon
-- and their own UI, and a shared fake network and clock carry addon whispers
-- and timers between them. It also works out where every frame lands on
-- screen, which tools/preview.lua uses to draw the window.
--
--   local W = require("tools.wowstub")
--   local room = W.NewRoom()
--   local patrick = room:Player("Patrick")   -- loads the addon for Patrick
--   local thrall = room:Player("Thrall")
--   patrick.ns.Invite("Thrall"); room:Run(1)
local W = {}

local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local FONT_SIZES = {
    GameFontNormal = 12, GameFontNormalSmall = 10, GameFontNormalLarge = 16, GameFontNormalHuge = 22,
    GameFontHighlight = 12, GameFontHighlightSmall = 10, GameFontDisableSmall = 10,
}
local FONT_COLORS = {
    GameFontNormal = { 1, 0.82, 0 }, GameFontNormalSmall = { 1, 0.82, 0 }, GameFontNormalLarge = { 1, 0.82, 0 },
    GameFontNormalHuge = { 1, 0.82, 0 }, GameFontHighlight = { 1, 1, 1 }, GameFontHighlightSmall = { 1, 1, 1 },
    GameFontDisableSmall = { 0.5, 0.5, 0.5 },
}

---------------------------------------------------------------------------
-- Regions (frames, textures, font strings)
---------------------------------------------------------------------------

local Region = {}
Region.__index = function(_, k)
    if Region[k] then return Region[k] end
    if type(k) == "string" and k:match("^%u") then
        return function() end -- any API method we don't model is a no-op
    end
end

local function newRegion(ui, kind, parent, layer)
    local r = setmetatable({
        ui = ui, kind = kind, parent = parent, points = {}, shown = true, scale = 1,
        layer = LAYERS[layer or "ARTWORK"] or 3, order = #ui.regions + 1, children = {},
    }, Region)
    r.level = parent and (parent.level + (kind == "Frame" and 1 or 0)) or 0
    ui.regions[#ui.regions + 1] = r
    if parent then parent.children[#parent.children + 1] = r end
    return r
end

function Region:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "table" then
        rel, relPoint, x, y = a, b or point, c or 0, d or 0
    elseif type(a) == "string" then
        rel, relPoint, x, y = self.parent, a, b or 0, c or 0
    else
        rel, relPoint, x, y = self.parent, point, a or 0, b or 0
    end
    self.points[point] = { rel = rel, relPoint = relPoint, x = x, y = y }
end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints(rel)
    rel = rel or self.parent
    self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function Region:GetPoint()
    for p, a in pairs(self.points) do return p, a.rel, a.relPoint, a.x, a.y end
end
function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetWidth() return self.w or 0 end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(v) self.shown = not not v end
function Region:IsShown() return self.shown end
function Region:IsVisible()
    local r = self
    while r do
        if not r.shown then return false end
        r = r.parent
    end
    return true
end
function Region:SetScale(s) self.scale = s end
function Region:GetFrameLevel() return self.level end
function Region:SetFrameLevel(l) self.level = l end
function Region:SetEnabled(v) self.enabled = not not v end
function Region:IsEnabled() return self.enabled ~= false end
function Region:SetScript(name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end
function Region:RegisterEvent(event)
    self.ui.eventFrames[event] = self.ui.eventFrames[event] or {}
    table.insert(self.ui.eventFrames[event], self)
end
function Region:UnregisterEvent(event)
    local list = self.ui.eventFrames[event] or {}
    for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
end
-- Clicks only land on buttons that are visible and enabled, like in game.
function Region:Click()
    assert(self:IsVisible(), "clicked a hidden button: " .. tostring(self.text or self.label and self.label.text))
    assert(self.enabled ~= false, "clicked a disabled button: " .. tostring(self.label and self.label.text))
    if self.scripts and self.scripts.OnClick then self.scripts.OnClick(self) end
end
function Region:CreateTexture(_, layer) return newRegion(self.ui, "Texture", self, layer) end
function Region:CreateFontString(_, layer, font)
    local fs = newRegion(self.ui, "FontString", self, layer)
    fs:SetFontObject(font or "GameFontNormal")
    return fs
end
function Region:SetFontObject(font)
    self.font = font
    self.color = FONT_COLORS[font] or { 1, 1, 1 }
end
function Region:SetText(t)
    self.text = t ~= nil and tostring(t) or nil
    if self.label then self.label.text = self.text end
end
function Region:GetText() return self.text end
function Region:SetTextColor(r, g, b) self.color = { r, g, b } end
function Region:SetColorTexture(r, g, b, a) self.fill = { r, g, b, a or 1 } end
function Region:SetTexture(path) self.path = path end
function Region:SetVertexColor(r, g, b, a) self.tint = { r, g, b, a or 1 } end
function Region:SetNormalTexture(path)
    self.normal = newRegion(self.ui, "Texture", self, "ARTWORK")
    self.normal:SetAllPoints(self)
    self.normal.path = path
end
function Region:GetNormalTexture() return self.normal end

local function newUI()
    local ui = { regions = {}, eventFrames = {} }
    ui.UIParent = newRegion(ui, "Frame")
    ui.UIParent.w, ui.UIParent.h = 1280, 800
    ui.CreateFrame = function(kind, _, parent, template)
        local f = newRegion(ui, "Frame", parent or ui.UIParent)
        f.template = template
        if template == "UIPanelButtonTemplate" then
            f.button = true
            f.enabled = true
            f.label = newRegion(ui, "FontString", f, "OVERLAY")
            f.label:SetFontObject("GameFontNormal")
            f.label:SetPoint("CENTER")
        elseif template == "UIPanelCloseButton" then
            f.closeButton = true
            f:SetSize(24, 24)
        elseif kind == "EditBox" then
            f.editBox = true
        end
        return f
    end
    return ui
end

---------------------------------------------------------------------------
-- Layout, for previews
---------------------------------------------------------------------------

local function effScale(r)
    local s = 1
    while r do s = s * r.scale; r = r.parent end
    return s
end

local function anchorXY(rect, point)
    local l, b, w, h = rect[1], rect[2], rect[3], rect[4]
    local x = point:find("LEFT") and l or (point:find("RIGHT") and l + w or l + w / 2)
    local y = point:find("TOP") and b + h or (point:find("BOTTOM") and b or b + h / 2)
    return x, y
end

local rectOf
rectOf = function(r)
    if r.rect then return r.rect end
    local s = effScale(r)
    local w, h = (r.w or 0) * s, (r.h or 0) * s
    if r.kind == "FontString" and not r.w then
        local size = FONT_SIZES[r.font] or 12
        local longest = 0
        for line in ((r.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "\n"):gmatch("(.-)\n") do
            longest = math.max(longest, #line)
        end
        local lines = select(2, (r.text or ""):gsub("\n", "")) + 1
        w, h = longest * size * 0.56 * s, size * lines * 1.2 * s
    end
    local pts = {}
    for p, a in pairs(r.points) do
        local ax, ay = anchorXY(rectOf(a.rel), a.relPoint)
        pts[p] = { ax + a.x * s, ay + a.y * s }
    end
    if pts.TOPLEFT and pts.TOPRIGHT then
        pts.BOTTOMRIGHT = { pts.TOPRIGHT[1], pts.TOPRIGHT[2] - h }
    elseif pts.BOTTOMLEFT and pts.BOTTOMRIGHT then
        pts.TOPLEFT = { pts.BOTTOMLEFT[1], pts.BOTTOMLEFT[2] + h }
    end
    local rect
    if pts.TOPLEFT and pts.BOTTOMRIGHT then
        rect = { pts.TOPLEFT[1], pts.BOTTOMRIGHT[2], pts.BOTTOMRIGHT[1] - pts.TOPLEFT[1], pts.TOPLEFT[2] - pts.BOTTOMRIGHT[2] }
    else
        local p, xy = next(pts)
        if not p then
            local pr = r.parent and rectOf(r.parent) or { 0, 0, w, h }
            rect = { pr[1], pr[2], pr[3], pr[4] }
        else
            local l = p:find("LEFT") and xy[1] or (p:find("RIGHT") and xy[1] - w or xy[1] - w / 2)
            local b = p:find("TOP") and xy[2] - h or (p:find("BOTTOM") and xy[2] or xy[2] - h / 2)
            rect = { l, b, w, h }
        end
    end
    r.rect = rect
    return rect
end

-- Every visible drawable region with its screen rect, in draw order.
local function layout(ui)
    for _, r in ipairs(ui.regions) do r.rect = nil end
    ui.UIParent.rect = { 0, 0, 1280, 800 }
    local out = {}
    for _, r in ipairs(ui.regions) do
        if r.parent and r:IsVisible() then
            local rect = rectOf(r)
            if r.kind ~= "Frame" or r.button or r.closeButton or r.editBox then
                out[#out + 1] = {
                    r = r, rect = rect, level = r.kind == "Frame" and r.level or r.parent.level,
                    layer = r.kind == "Frame" and 0 or r.layer,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.layer ~= b.layer then return a.layer < b.layer end
        return a.r.order < b.r.order
    end)
    return out
end

---------------------------------------------------------------------------
-- A room of players sharing a clock and a network
---------------------------------------------------------------------------

local Room = {}
Room.__index = Room

function W.NewRoom()
    return setmetatable({ now = 0, timers = {}, wire = {}, players = {}, sent = 0 }, Room)
end

function Room:After(seconds, fn)
    self.timers[#self.timers + 1] = { at = self.now + math.max(seconds, 0), fn = fn, n = #self.timers }
end

local function fire(player, event, ...)
    for _, f in ipairs(player.ui.eventFrames[event] or {}) do
        if f.scripts and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- Runs due timers and delivers whispers until nothing is left to do.
function Room:Settle()
    for _ = 1, 10000 do
        local busy = false
        table.sort(self.timers, function(a, b) return a.at < b.at end)
        while self.timers[1] and self.timers[1].at <= self.now do
            local t = table.remove(self.timers, 1)
            t.fn()
            busy = true
        end
        while self.wire[1] do
            local m = table.remove(self.wire, 1)
            local to = self.players[m.to]
            if to then fire(to, "CHAT_MSG_ADDON", m.prefix, m.text, "WHISPER", m.from .. "-Realm") end
            busy = true
        end
        if not busy then return end
    end
    error("network never went quiet")
end

-- Moves the clock forward, in small steps, settling as it goes.
function Room:Run(seconds)
    local stop = self.now + (seconds or 0)
    self:Settle()
    while self.now < stop do
        self.now = math.min(stop, self.now + 0.05)
        self:Settle()
    end
end

-- Loads a fresh copy of the addon for one player.
function Room:Player(name, opts)
    opts = opts or {}
    local ui = newUI()
    local player = { name = name, ui = ui, played = {}, popups = {} }
    local env = setmetatable({}, { __index = _G })
    player.env = env
    env._G = env
    env.CreateFrame = ui.CreateFrame
    env.UIParent = ui.UIParent
    env.UISpecialFrames = {}
    env.tinsert = table.insert
    env.SlashCmdList = {}
    env.UnitName = function(unit)
        if unit == "player" then return name end
        if unit == "target" then return player.target end
    end
    env.UnitExists = function(unit) return unit == "target" and player.target ~= nil end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) player.chat = player.chat or {}; table.insert(player.chat, msg) end }
    env.GetTime = function() return self.now end
    env.C_Timer = { After = function(sec, fn) self:After(sec, fn) end }
    env.SOUNDKIT = { IG_ABILITY_PAGE_TURN = 836, LOOT_WINDOW_COIN_SOUND = 120, IG_QUEST_LIST_COMPLETE = 878,
        IG_QUEST_FAILED = 847, IG_CHARACTER_INFO_TAB = 841 }
    env.PlaySound = function(id) table.insert(player.played, id) end
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function(which, arg) table.insert(player.popups, { which = which, arg = arg }) end
    env.ACCEPT, env.DECLINE = "Accept", "Decline"
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, text, kind, target)
            assert(kind == "WHISPER", "only whispers are used")
            assert(#text <= 255, "addon message over 255 bytes")
            self.sent = self.sent + 1
            table.insert(self.wire, { prefix = prefix, text = text, from = name, to = target })
        end,
    }
    if opts.noAddonMessages then env.C_ChatInfo = nil end

    local ns = {}
    player.ns = ns
    for _, file in ipairs(W.TocFiles()) do
        local chunk = assert(loadfile("Forever21/" .. file))
        setfenv(chunk, env)
        chunk("Forever21", ns)
    end
    fire(player, "ADDON_LOADED", "Forever21")
    self.players[name] = player

    -- Accept or decline the invite popup, as a click would.
    function player:AnswerPopup(accept)
        local dialog = env.StaticPopupDialogs.FOREVER21_INVITE
        if accept then dialog.OnAccept() else dialog.OnCancel(nil, nil, "clicked") end
    end
    function player:Layout() return layout(ui) end
    return player
end

-- The addon's Lua files, in the order the TOC loads them.
function W.TocFiles()
    local files = {}
    for line in io.lines("Forever21/Forever21.toc") do
        local f = line:match("^([%w_/]+%.lua)%s*$")
        if f then files[#files + 1] = f end
    end
    return files
end

return W
