-- A stand-in for the bits of the WoW UI API the addon uses, with enough
-- layout logic to work out where everything lands on screen. Used by
-- tools/preview.lua to render the table window outside the game.
local W = {}
local regions = {}
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local FONT_SIZES = {
    GameFontNormal = 12, GameFontNormalSmall = 10, GameFontNormalLarge = 16,
    GameFontNormalHuge = 22, GameFontHighlight = 12, GameFontHighlightSmall = 10, GameFontDisableSmall = 10,
}
local FONT_COLORS = {
    GameFontNormal = { 1, 0.82, 0 }, GameFontNormalSmall = { 1, 0.82, 0 }, GameFontNormalLarge = { 1, 0.82, 0 },
    GameFontNormalHuge = { 1, 0.82, 0 }, GameFontHighlight = { 1, 1, 1 }, GameFontHighlightSmall = { 1, 1, 1 }, GameFontDisableSmall = { 0.5, 0.5, 0.5 },
}

local Region = {}
Region.__index = function(_, k)
    if Region[k] then return Region[k] end
    if type(k) == "string" and k:match("^%u") then
        return function() end -- any API method we don't model is a no-op
    end
end

local function new(kind, parent, layer)
    local r = setmetatable({
        kind = kind, parent = parent, points = {}, shown = true, scale = 1,
        layer = LAYERS[layer or "ARTWORK"] or 3, order = #regions + 1, children = {},
    }, Region)
    r.level = parent and (parent.level + (kind == "Frame" and 1 or 0)) or 0
    regions[#regions + 1] = r
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
function Region:SetScale(s) self.scale = s end
function Region:GetFrameLevel() return self.level end
function Region:SetFrameLevel(l) self.level = l end
function Region:SetEnabled(v) self.enabled = not not v end
function Region:SetScript(name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end
function Region:Click() if self.scripts and self.scripts.OnClick then self.scripts.OnClick(self) end end
function Region:CreateTexture(_, layer) return new("Texture", self, layer) end
function Region:CreateFontString(_, layer, font)
    local fs = new("FontString", self, layer)
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
    self.normal = new("Texture", self, "ARTWORK")
    self.normal:SetAllPoints(self)
    self.normal.path = path
end
function Region:GetNormalTexture() return self.normal end

W.UIParent = new("Frame")
W.UIParent.w, W.UIParent.h = 1280, 800
W.UIParent.rect = { 0, 0, 1280, 800 }

function W.CreateFrame(kind, _, parent, template)
    local f = new("Frame", parent or W.UIParent)
    f.template = template
    if template == "UIPanelButtonTemplate" then
        f.button = true
        f.enabled = true
        f.label = new("FontString", f, "OVERLAY")
        f.label:SetFontObject("GameFontNormal")
        f.label:SetPoint("CENTER")
    elseif template == "UIPanelCloseButton" then
        f.closeButton = true
        f:SetSize(24, 24)
    end
    return f
end

-- Layout ------------------------------------------------------------------

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
        local plain = (r.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        w, h = #plain * size * 0.56 * s, size * s
    end
    local pts = {}
    for p, a in pairs(r.points) do
        local ax, ay = anchorXY(rectOf(a.rel), a.relPoint)
        pts[p] = { ax + a.x * s, ay + a.y * s }
    end
    local rect
    local tl, br = pts.TOPLEFT, pts.BOTTOMRIGHT
    if pts.TOPLEFT and pts.TOPRIGHT then
        tl, br = pts.TOPLEFT, { pts.TOPRIGHT[1], pts.TOPRIGHT[2] - h }
    elseif pts.BOTTOMLEFT and pts.BOTTOMRIGHT then
        tl, br = { pts.BOTTOMLEFT[1], pts.BOTTOMLEFT[2] + h }, pts.BOTTOMRIGHT
    end
    pts.TOPLEFT, pts.BOTTOMRIGHT = tl, br
    if pts.TOPLEFT and pts.BOTTOMRIGHT then
        rect = { pts.TOPLEFT[1], pts.BOTTOMRIGHT[2], pts.BOTTOMRIGHT[1] - pts.TOPLEFT[1], pts.TOPLEFT[2] - pts.BOTTOMRIGHT[2] }
    else
        local p, xy = next(pts)
        if not p then
            if r.parent then
                local pr = rectOf(r.parent)
                rect = { pr[1], pr[2], pr[3], pr[4] }
            else
                rect = { 0, 0, w, h }
            end
        else
            local l = p:find("LEFT") and xy[1] or (p:find("RIGHT") and xy[1] - w or xy[1] - w / 2)
            local b = p:find("TOP") and xy[2] - h or (p:find("BOTTOM") and xy[2] or xy[2] - h / 2)
            rect = { l, b, w, h }
        end
    end
    r.rect = rect
    return rect
end

local function visible(r)
    while r do
        if not r.shown then return false end
        r = r.parent
    end
    return true
end

-- Returns every visible drawable region with its screen rect, in draw order.
function W.Layout()
    for _, r in ipairs(regions) do r.rect = nil end
    W.UIParent.rect = { 0, 0, 1280, 800 }
    local out = {}
    for _, r in ipairs(regions) do
        if r.parent and visible(r) then
            local rect = rectOf(r)
            local frameLevel = r.kind == "Frame" and r.level or r.parent.level
            if r.kind ~= "Frame" or r.button or r.closeButton then
                out[#out + 1] = { r = r, rect = rect, level = frameLevel, layer = r.kind == "Frame" and 0 or r.layer }
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

-- The addon's Lua files, in the order the TOC loads them.
function W.TocFiles()
    local files = {}
    for line in io.lines("Forever21/Forever21.toc") do
        local f = line:match("^([%w_/]+%.lua)%s*$")
        if f then files[#files + 1] = f end
    end
    return files
end

function W.install(env)
    env.CreateFrame = W.CreateFrame
    env.UIParent = W.UIParent
    env.UISpecialFrames = {}
    env.tinsert = table.insert
    env.SlashCmdList = {}
    env.UnitName = function() return "Patrick" end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    env.SOUNDKIT = { IG_ABILITY_PAGE_TURN = 836, LOOT_WINDOW_COIN_SOUND = 120, IG_QUEST_LIST_COMPLETE = 878,
        IG_QUEST_FAILED = 847, IG_CHARACTER_INFO_TAB = 841 }
    W.played = {}
    env.PlaySound = function(id) W.played[#W.played + 1] = id end
    env.C_ChatInfo = { SendAddonMessage = function() end, RegisterAddonMessagePrefix = function() end }
end

return W
