-- Loads the addon's pure-Lua modules the way the game would, sharing one ns table.
local M = {}

function M.load()
    local ns = {}
    for _, file in ipairs({ "Cards.lua", "Rules.lua", "Game.lua" }) do
        local chunk = assert(loadfile("Forever21/" .. file))
        chunk("Forever21", ns)
    end
    return ns
end

-- A game whose shoe deals exactly the given cards, in order, and records events.
function M.stackedGame(ns, players, cards, rules)
    local events = {}
    local r = { penetration = 2 } -- never reshuffle mid-test
    for k, v in pairs(rules or {}) do r[k] = v end
    local game = ns.Game.New({
        rules = r,
        onEvent = function(e, d) events[#events + 1] = { e, d } end,
    })
    for _, name in ipairs(players) do game:AddPlayer(name) end
    game:Start()
    M.stack(game, cards)
    return game, events
end

function M.stack(game, cards)
    game.shoe.cards = {}
    for i, c in ipairs(cards) do game.shoe.cards[i] = c end
    -- pad so draws past the stacked cards don't trigger a reshuffle
    for _ = 1, 50 do game.shoe.cards[#game.shoe.cards + 1] = "2C" end
    game.shoe.pos = 1
end

function M.has(events, name)
    for _, e in ipairs(events) do
        if e[1] == name then return e[2] end
    end
end

function M.count(events, name)
    local n = 0
    for _, e in ipairs(events) do
        if e[1] == name then n = n + 1 end
    end
    return n
end

return M
