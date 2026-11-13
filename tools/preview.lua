-- Renders the table window outside the game for a quick visual check.
-- Usage (repo root): lua5.1 tools/preview.lua <outdir> && python3 tools/render_preview.py <outdir>
package.path = "./?.lua;" .. package.path
local W = require("tools.wowstub")
W.install(_G)

local ns = {}
for _, f in ipairs(W.TocFiles()) do
    assert(loadfile("Forever21/" .. f))("Forever21", ns)
end
-- Fire ADDON_LOADED on Core's event frame.
for _, r in ipairs({ W.UIParent }) do
    for _, c in ipairs(r.children) do
        if c.scripts and c.scripts.OnEvent then c.scripts.OnEvent(c, "ADDON_LOADED", "Forever21") end
    end
end
assert(ns.db, "saved variables not set up")

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

local function dump(name)
    local items = {}
    for _, it in ipairs(W.Layout()) do
        local r = it.r
        items[#items + 1] = {
            kind = r.kind, rect = it.rect, fill = r.fill, path = r.path, tint = r.tint,
            text = r.kind == "FontString" and r.text or nil, color = r.color, font = r.font,
            button = r.button, close = r.closeButton, enabled = r.enabled,
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

-- 1: window just opened, no game.
ns.UI:Show()
dump("1-empty")

-- 2: three players; Thrall split and doubled, Jaina has blackjack, Patrick to act.
ns.game = ns.Game.New({ onEvent = function(e, d)
    for _, fn in ipairs(ns.listeners) do fn(e, d) end
end })
for _, n in ipairs({ "Thrall", "Patrick", "Jaina" }) do ns.game:AddPlayer(n) end
ns.game:Start()
stack(ns.game, { "8S", "TD", "AS", "9H", "8H", "6C", "KD", "7C", "3D", "KC", "9S", "5S" })
ns.game:PlaceBet("Thrall", 10); ns.game:PlaceBet("Jaina", 6)
ns.UI.pending = 10
ns.UI.frame.placeBet:Click()
ns.game:Act("Thrall", "split")
ns.game:Act("Thrall", "double")
ns.game:Act("Thrall", "stand")
dump("2-your-turn")

-- 3: Patrick hits to 21; the dealer plays out and the round is settled.
ns.UI.frame.actions.hit:Click()
dump("3-results")

-- 4: Dealer shows an ace and offers insurance.
stack(ns.game, { "9S", "TD", "4C", "AH", "9D", "8C", "7S", "KH" })
ns.game:PlaceBet("Thrall", 10); ns.game:PlaceBet("Jaina", 6)
ns.UI.frame.placeBet:Click()
dump("4-insurance")
-- 5: a fresh solo game where Patrick busts.
ns.game:Close()
ns.UI.frame.newGame:Click()
stack(ns.game, { "TS", "9C", "6H", "TD", "KS" })
ns.UI.frame.placeBet:Click()
ns.UI.frame.actions.hit:Click()
dump("5-bust")
print("wrote previews to " .. outdir)
