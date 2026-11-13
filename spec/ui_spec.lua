-- Smoke test: load the whole addon on a stubbed game API and play solo rounds
-- through the window's buttons. Catches Lua errors in the UI code; it can't
-- check that the real client draws things the same way.
local W = require("tools.wowstub")

local function stack(game, cards)
    game.shoe.cards = {}
    for i, c in ipairs(cards) do game.shoe.cards[i] = c end
    for _ = 1, 100 do game.shoe.cards[#game.shoe.cards + 1] = "2C" end
    game.shoe.pos = 1
end

local function open()
    local room = W.NewRoom()
    local p = room:Player("Patrick")
    p.env.SlashCmdList.FOREVER21("") -- opens the window
    return room, p, p.ns.UI.frame
end

describe("Table window", function()
    it("plays a solo round with the buttons", function()
        local _, p, f = open()
        local ns = p.ns
        assert.is_true(f:IsShown())
        assert.equal("Press New Game to open a table.", f.status:GetText())

        f.newGame:Click()
        assert.equal("lobby", ns.game.phase)
        assert.is_true(f.start:IsShown())
        assert.is_true(f.inviteBox:IsShown())
        assert.is_false(f.seats[1].glow:IsShown()) -- no highlight before anything happens
        assert.is_false(f.seats[2].glow:IsShown())
        f.start:Click()
        assert.equal("betting", ns.game.phase)
        stack(ns.game, { "TS", "7C", "6H", "TD", "5S" })

        assert.equal("10", f.betBox:GetText())
        f.betDown:Click()
        f.betUp:Click()
        f.betUp:Click()
        assert.equal("12", f.betBox:GetText())
        f.placeBet:Click()
        assert.equal("players", ns.game.phase)
        assert.equal("Your turn: 16", f.status:GetText())
        assert.is_true(f.seats[1].glow:IsShown())
        assert.is_false(f.seats[2].glow:IsShown())
        assert.is_true(f.actions.hit.enabled)
        assert.is_false(f.actions.split.enabled)

        f.actions.hit:Click() -- 21 vs dealer 17
        assert.equal("betting", ns.game.phase)
        assert.equal(112, ns.MySeat().chips)
        assert.is_true(f.banner:IsShown())
        assert.equal("YOU WIN!", f.banner.title:GetText())
        assert.equal("+12 chips", f.banner.sub:GetText())
        assert.is_true(f.seats[1].glow:IsShown())
        assert.truthy(#p.played > 0) -- sound effects fired

        -- The banner clears on the next deal.
        stack(ns.game, { "TS", "7C", "6H", "TD", "KS" })
        f.placeBet:Click()
        assert.is_false(f.banner:IsShown())
        f.actions.hit:Click() -- 26: bust
        assert.equal("BUST - YOU LOSE", f.banner.title:GetText())
        p:Layout() -- every anchor resolves
    end)

    it("turns sound off", function()
        local _, p, f = open()
        f.soundToggle:Click()
        assert.is_false(p.ns.db.sound)
        assert.equal("Sound: Off", f.soundToggle:GetText())
        f.newGame:Click()
        f.start:Click()
        f.placeBet:Click()
        assert.equal(0, #p.played)
    end)

    it("caps the bet at what you have", function()
        local _, p, f = open()
        f.newGame:Click()
        f.start:Click()
        p.ns.MySeat().chips = 7
        f.betMax:Click()
        assert.equal(6, p.ns.UI.pending)
        assert.is_false(f.betUp:IsEnabled())
    end)

    it("takes a typed bet, rounded to an even amount in range", function()
        local _, p, f = open()
        f.newGame:Click()
        f.start:Click()
        local function typed(value)
            f.betBox:SetText(value)
            f.betBox.scripts.OnEnterPressed(f.betBox)
            return p.ns.UI.pending
        end
        assert.equal(12, typed("13"))
        assert.equal(24, typed("99"))
        assert.equal(2, typed("0"))
        assert.is_false(f.betDown:IsEnabled()) -- already at the minimum
        assert.equal(2, typed("")) -- an empty box keeps the bet
    end)
end)
