-- Several players, each with their own copy of the addon, playing over a fake
-- network of addon whispers (tools/wowstub.lua).
local W = require("tools.wowstub")

local function stack(game, cards)
    game.shoe.cards = {}
    for i, c in ipairs(cards) do game.shoe.cards[i] = c end
    for _ = 1, 100 do game.shoe.cards[#game.shoe.cards + 1] = "2C" end
    game.shoe.pos = 1
end

-- Patrick hosts; Thrall joins.
local function table2()
    local room = W.NewRoom()
    local patrick, thrall = room:Player("Patrick"), room:Player("Thrall")
    assert(patrick.ns.HostTable())
    assert(patrick.ns.Invite("thrall"))
    room:Run(0.5)
    thrall:AnswerPopup(true)
    room:Run(0.5)
    return room, patrick, thrall
end

describe("Multiplayer", function()
    it("invites a player who accepts and sees the lobby", function()
        local _, patrick, thrall = table2()
        assert.equal(1, #thrall.popups)
        assert.equal("Patrick", thrall.popups[1].arg)
        assert.equal(2, #patrick.ns.game.seats)
        assert.equal("Thrall", patrick.ns.game.seats[2].name)
        assert.equal("client", thrall.ns.role)
        assert.equal("lobby", thrall.ns.game.phase)
        assert.equal(2, #thrall.ns.game.seats)
    end)

    it("lets an invited player decline", function()
        local room = W.NewRoom()
        local patrick, jaina = room:Player("Patrick"), room:Player("Jaina")
        patrick.ns.HostTable()
        patrick.ns.Invite("Jaina")
        room:Run(0.5)
        jaina:AnswerPopup(false)
        room:Run(0.5)
        assert.equal(1, #patrick.ns.game.seats)
        assert.same({}, patrick.ns.Table.InviteList())
        assert.is_nil(jaina.ns.role)
    end)

    it("expires an invite nobody answers", function()
        local room = W.NewRoom()
        local patrick = room:Player("Patrick")
        patrick.ns.HostTable()
        patrick.ns.Invite("Nobody")
        room:Run(61)
        assert.same({}, patrick.ns.Table.InviteList())
    end)

    it("declines invites across versions", function()
        local room = W.NewRoom()
        local patrick, thrall = room:Player("Patrick"), room:Player("Thrall")
        thrall.ns.VERSION = "0.0.1"
        patrick.ns.HostTable()
        patrick.ns.Invite("Thrall")
        room:Run(1)
        assert.equal(0, #thrall.popups)
        assert.same({}, patrick.ns.Table.InviteList())
    end)

    it("plays a round where both screens agree and the hole card stays hidden", function()
        local room, patrick, thrall = table2()
        local host = patrick.ns
        assert(host.StartGame())
        room:Run(0.5)
        assert.equal("betting", thrall.ns.game.phase)
        assert.equal(100, thrall.ns.MySeat().chips)

        -- Deal order: Patrick, Thrall, dealer up, Patrick, Thrall, dealer hole.
        stack(host.game, { "TS", "9S", "7C", "8H", "6D", "TD", "5C" })
        assert(host.Bet(10))
        assert(thrall.ns.Bet(10))
        room:Run(0.5)
        assert.equal("players", host.game.phase)
        local view = thrall.ns.game
        assert.equal("players", view.phase)
        assert.equal("7C", view.dealer.cards[1])
        assert.equal("XX", view.dealer.cards[2]) -- not sent until it's turned over

        local ok, err = thrall.ns.Act("hit")
        assert.is_nil(ok); assert.equal("It isn't your turn.", err)

        assert(host.Act("stand")) -- Patrick 18
        room:Run(0.5)
        thrall.ns.UI:Show()
        assert.is_true(thrall.ns.UI.frame.actions.hit.enabled)
        thrall.ns.UI.frame.actions.hit:Click() -- 9 + 6 + 5 = 20
        room:Run(0.5)
        thrall.ns.Act("stand")
        room:Run(0.5)

        -- Dealer 17 stands: both win 10.
        assert.equal("betting", host.game.phase)
        assert.equal(110, host.game:FindSeat("Patrick").chips)
        assert.equal(110, host.game:FindSeat("Thrall").chips)
        assert.equal(110, thrall.ns.game:FindSeat("Patrick").chips)
        assert.equal(110, thrall.ns.game:FindSeat("Thrall").chips)
        assert.equal("YOU WIN!", thrall.ns.UI.frame.banner.title:GetText())
        assert.equal(10, thrall.ns.game.lastRound.nets.Thrall)
    end)

    it("deals without a player who doesn't bet in time, and stands for a slow player", function()
        local room, patrick, thrall = table2()
        local host = patrick.ns
        host.StartGame()
        room:Run(0.5)
        assert(host.Bet(10))
        room:Run(19)
        assert.equal("betting", host.game.phase)
        room:Run(2) -- 20 seconds to bet
        assert.equal("players", host.game.phase)
        assert.equal(0, #host.game:FindSeat("Thrall").hands)
        assert.truthy(thrall.ns.Table.SecondsLeft())

        room:Run(31) -- 30 seconds per decision
        assert.equal("betting", host.game.phase)
        local timedOut = false
        for _, line in ipairs(thrall.chat or {}) do
            if line:find("Patrick ran out of time") then timedOut = true end
        end
        assert.is_true(timedOut)
    end)

    it("ends the game when the other player leaves", function()
        local room, patrick, thrall = table2()
        patrick.ns.StartGame()
        room:Run(0.5)
        assert(thrall.ns.Quit())
        room:Run(0.5)
        assert.is_nil(thrall.ns.game)
        assert.equal("over", patrick.ns.game.phase)
    end)

    it("closes the table for everyone when the owner leaves", function()
        local room, patrick, thrall = table2()
        patrick.ns.StartGame()
        room:Run(0.5)
        assert(patrick.ns.Quit())
        room:Run(0.5)
        assert.equal("over", thrall.ns.game.phase)
        assert.is_nil(thrall.ns.role)
    end)

    it("doesn't let a non-seated player send moves", function()
        local room, patrick = table2()
        local stranger = room:Player("Stranger")
        patrick.ns.StartGame()
        room:Run(0.5)
        stranger.ns.role, stranger.ns.hostName = "client", "Patrick"
        stranger.ns.Net.Send("Patrick", { t = "bet", a = 10 })
        room:Run(0.5)
        assert.is_nil(patrick.ns.game:FindSeat("Stranger"))
    end)

    it("keeps every whisper under 255 bytes with five players", function()
        local room = W.NewRoom()
        local names = { "Patrick", "Thrall", "Jaina", "Sylvanas", "Anduin" }
        local players = {}
        for _, n in ipairs(names) do players[n] = room:Player(n) end
        local host = players.Patrick.ns
        host.HostTable()
        for i = 2, 5 do host.Invite(names[i]) end
        room:Run(0.5)
        for i = 2, 5 do players[names[i]]:AnswerPopup(true) end
        room:Run(0.5)
        assert.equal(5, #host.game.seats)
        host.StartGame()
        room:Run(0.5)
        for _, n in ipairs(names) do players[n].ns.Bet(24) end
        room:Run(2)
        if host.game.phase == "insurance" then
            for _, n in ipairs(names) do players[n].ns.Insure(false) end
            room:Run(3)
        end
        -- Play out by standing; whatever happens, all five agree.
        for _ = 1, 20 do
            local seat = host.game:CurrentHand()
            if not seat then break end
            players[seat.name].ns.Act("stand")
            room:Run(1)
        end
        assert.equal("betting", host.game.phase)
        room:Run(5) -- the send queue spreads the round's results out over a few seconds
        for _, n in ipairs(names) do
            for _, m in ipairs(names) do
                assert.equal(host.game:FindSeat(m).chips, players[n].ns.game:FindSeat(m).chips)
            end
        end
    end)
end)
