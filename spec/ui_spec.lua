-- Smoke test: load the whole addon on a stubbed game API and play a round
-- through the window's buttons. Catches Lua errors in the UI code; it can't
-- check that the real client draws things the same way.
local W = require("tools.wowstub")

local function loadAddon()
    W.install(_G)
    local ns = {}
    for _, f in ipairs(W.TocFiles()) do
        assert(loadfile("Forever21/" .. f))("Forever21", ns)
    end
    for _, c in ipairs(W.UIParent.children) do
        if c.scripts and c.scripts.OnEvent then c.scripts.OnEvent(c, "ADDON_LOADED", "Forever21") end
    end
    return ns
end

local function stack(game, cards)
    game.shoe.cards = {}
    for i, c in ipairs(cards) do game.shoe.cards[i] = c end
    for _ = 1, 100 do game.shoe.cards[#game.shoe.cards + 1] = "2C" end
    game.shoe.pos = 1
end

describe("Table window", function()
    it("plays a solo round with the buttons", function()
        local ns = loadAddon()
        local f
        SlashCmdList.FOREVER21("") -- opens the window
        f = ns.UI.frame
        assert.is_true(f:IsShown())
        assert.equal("Press New Game to play against the dealer.", f.status:GetText())

        f.newGame:Click()
        assert.equal("betting", ns.game.phase)
        assert.is_true(f.placeBet:IsShown())
        stack(ns.game, { "TS", "7C", "6H", "TD", "5S" })

        f.clearBet:Click()
        for _ = 1, 3 do f.chipButtons[2]:Click() end -- 3 x 4 chips
        f.placeBet:Click()
        assert.equal("players", ns.game.phase)
        assert.equal("Your turn: 16", f.status:GetText())
        assert.is_true(f.actions.hit.enabled)
        assert.is_false(f.actions.split.enabled)

        f.actions.hit:Click() -- 21 vs dealer 17
        assert.equal("betting", ns.game.phase)
        assert.equal("You win 12.", f.status:GetText())
        assert.equal(112, ns.MySeat().chips)
        assert.is_true(f.banner:IsShown())
        assert.equal("YOU WIN!", f.banner.title:GetText())
        assert.equal("+12 chips", f.banner.sub:GetText())
        assert.is_true(f.seats[1].glow:IsShown())
        assert.truthy(#W.played > 0) -- sound effects fired

        -- The banner clears on the next deal.
        stack(ns.game, { "TS", "7C", "6H", "TD", "KS" })
        f.placeBet:Click()
        assert.is_false(f.banner:IsShown())
        f.actions.hit:Click() -- 26: bust
        assert.equal("BUST - YOU LOSE", f.banner.title:GetText())
        W.Layout() -- every anchor resolves
    end)

    it("turns sound off", function()
        local ns = loadAddon()
        ns.UI:Show()
        ns.UI.frame.soundToggle:Click()
        assert.is_false(ns.db.sound)
        assert.equal("Sound: Off", ns.UI.frame.soundToggle:GetText())
        W.played = {}
        ns.UI.frame.newGame:Click()
        ns.UI.frame.placeBet:Click()
        assert.equal(0, #W.played)
    end)

    it("caps the bet at what you have", function()
        local ns = loadAddon()
        ns.UI:Show()
        ns.UI.frame.newGame:Click()
        ns.MySeat().chips = 7
        for _ = 1, 5 do ns.UI.frame.chipButtons[3]:Click() end
        assert.equal(6, ns.UI.pending)
    end)
end)
