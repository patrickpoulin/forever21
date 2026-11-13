-- Renders the table window outside the game for a quick visual check.
-- Usage (repo root): lua5.1 tools/preview.lua <outdir> && python3 tools/render_preview.py <outdir>
package.path = "./?.lua;" .. package.path
local W = require("tools.wowstub")

local outdir = arg[1] or "."

local function json(v)
    local t = type(v)
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local parts = {}
            for i, x in ipairs(v) do parts[i] = json(x) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = json(tostring(k)) .. ":" .. json(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end) .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    end
    return "null"
end

local function dump(player, name)
    local items = {}
    for _, it in ipairs(player:Layout()) do
        local r = it.r
        items[#items + 1] = {
            kind = r.kind, rect = it.rect, fill = r.fill, path = r.path, tint = r.tint,
            text = (r.kind == "FontString" or r.template == "InputBoxTemplate") and r.text or nil, color = r.color, font = r.font,
            button = r.button, close = r.closeButton, input = r.template == "InputBoxTemplate" or nil, enabled = r.enabled,
        }
    end
    local fh = assert(io.open(outdir .. "/" .. name .. ".json", "w"))
    fh:write(json(items))
    fh:close()
end

local function stack(game, cards)
    game.shoe.cards = {}
    for i, c in ipairs(cards) do game.shoe.cards[i] = c end
    for _ = 1, 100 do game.shoe.cards[#game.shoe.cards + 1] = "2C" end
    game.shoe.pos = 1
end

local room = W.NewRoom()
local thrall = room:Player("Thrall")
local patrick = room:Player("Patrick")
local jaina = room:Player("Jaina")
local host, me = thrall.ns, patrick.ns

-- 1: Thrall opened a table and invited two friends who haven't answered yet.
host.UI:Show()
host.UI.frame.newGame:Click()
host.Invite("Patrick")
host.Invite("Jaina")
room:Run(0.5)
dump(thrall, "1-lobby")

-- 2: they joined. Thrall split and doubled, Jaina has blackjack, and it's
-- Patrick's turn, seen from Patrick's own window.
patrick:AnswerPopup(true)
jaina:AnswerPopup(true)
room:Run(0.5)
me.UI:Show()
host.UI.frame.start:Click()
room:Run(0.5)
stack(host.game, { "8S", "TD", "AS", "9H", "8H", "6C", "KD", "7C", "3D", "KC", "9S", "5S" })
host.Bet(10)
jaina.ns.Bet(6)
me.UI:SetBet(10)
me.UI.frame.placeBet:Click()
room:Run(1)
host.Act("split"); room:Run(1)
host.Act("double"); room:Run(1)
host.Act("stand"); room:Run(1)
dump(patrick, "2-your-turn")

-- 3: Patrick hits to 21; the dealer plays out and the round is settled.
me.UI.frame.actions.hit:Click()
room:Run(5)
dump(patrick, "3-results")

-- 4: the dealer shows an ace and offers insurance.
stack(host.game, { "9S", "TD", "4C", "AH", "9D", "8C", "7S", "KH" })
host.Bet(10)
jaina.ns.Bet(6)
me.UI:SetBet(10)
me.UI.frame.placeBet:Click()
room:Run(3)
dump(patrick, "4-insurance")

-- 5: a solo game where Valeera busts.
local valeera = room:Player("Valeera")
valeera.ns.UI:Show()
valeera.ns.UI.frame.newGame:Click()
valeera.ns.UI.frame.start:Click()
stack(valeera.ns.game, { "TS", "9C", "6H", "TD", "KS" })
valeera.ns.UI:SetBet(10)
valeera.ns.UI.frame.placeBet:Click()
valeera.ns.UI.frame.actions.hit:Click()
room:Run(0.5)
dump(valeera, "5-bust")
print("wrote previews to " .. outdir)
