local helper = require("spec.helper")
local ns = helper.load()

-- One player's deal order: player, dealer up, player, dealer hole, then draws.
local function solo(cards, bet, rules)
    local game, events = helper.stackedGame(ns, { "P" }, cards, rules)
    assert.is_true(game:PlaceBet("P", bet or 10))
    assert.is_true(game:Deal())
    return game, events, game:FindSeat("P")
end

describe("Game", function()
    it("starts everyone at 100 chips and opens betting", function()
        local game = helper.stackedGame(ns, { "A", "B" }, {})
        assert.equal("betting", game.phase)
        assert.equal(100, game:FindSeat("A").chips)
        assert.equal(100, game:FindSeat("B").chips)
    end)

    it("seats at most 5 players and only before the game starts", function()
        local game = ns.Game.New()
        for _, n in ipairs({ "A", "B", "C", "D", "E" }) do assert.truthy(game:AddPlayer(n)) end
        assert.is_nil((game:AddPlayer("F")))
        game:Start()
        local g2 = ns.Game.New(); g2:AddPlayer("A"); g2:Start()
        assert.is_nil((g2:AddPlayer("B")))
    end)

    it("rejects odd bets", function()
        local game = helper.stackedGame(ns, { "P" }, {})
        local ok, err = game:PlaceBet("P", 5)
        assert.is_nil(ok); assert.matches("even", err)
    end)

    it("pays even money on a win", function()
        local game, _, seat = solo({ "TS", "7C", "9H", "TD" })
        assert.equal("players", game.phase)
        assert.is_true(game:Act("P", "stand"))
        assert.equal(110, seat.chips)
        assert.equal("betting", game.phase)
        assert.equal(2, game.round)
    end)

    it("pays 3 to 2 on blackjack and the dealer doesn't draw", function()
        local _, events, seat = solo({ "AS", "9C", "KH", "8D" })
        assert.equal(115, seat.chips)
        assert.equal(2, helper.count(events, "dealerCard"))
        assert.equal("blackjack", helper.has(events, "result").hands[1].result)
    end)

    it("dealer peeks with a ten up and settles a dealer blackjack at once", function()
        local game, events, seat = solo({ "9S", "KC", "9H", "AD" })
        assert.equal(90, seat.chips)
        assert.truthy(helper.has(events, "dealerReveal").blackjack)
        assert.is_nil(helper.has(events, "turn"))
        assert.equal("betting", game.phase)
    end)

    it("pushes a player blackjack against a dealer blackjack", function()
        local _, _, seat = solo({ "AS", "KC", "KH", "AD" })
        assert.equal(100, seat.chips)
    end)

    it("pays insurance 2 to 1 when the dealer has blackjack", function()
        local game, _, seat = solo({ "TS", "AC", "9H", "KD" })
        assert.equal("insurance", game.phase)
        assert.is_true(game:Insure("P", true))
        -- bet 10 lost, insurance 5 returns 15
        assert.equal(100, seat.chips)
    end)

    it("loses insurance when the dealer has no blackjack, then plays on", function()
        local game, events, seat = solo({ "TS", "AC", "9H", "6D" })
        assert.is_true(game:Insure("P", true))
        assert.equal("players", game.phase)
        game:Act("P", "stand")
        -- soft 17: dealer stands (S17). 19 beats 17: +10, insurance -5
        assert.equal(105, seat.chips)
        assert.equal(2, helper.count(events, "dealerCard"))
    end)

    it("busts on a hit over 21 and the dealer doesn't draw", function()
        local game, events, seat = solo({ "TS", "9C", "6H", "TD", "KS" })
        assert.is_true(game:Act("P", "hit"))
        assert.equal(90, seat.chips)
        assert.equal(2, helper.count(events, "dealerCard"))
    end)

    it("doubles for one card", function()
        -- dealer 16 draws a 2 (padding) to 18; player 21
        local game, _, seat = solo({ "6S", "9C", "5H", "7D", "TS" })
        assert.is_true(game:Act("P", "double"))
        assert.equal(120, seat.chips)
    end)

    it("doesn't allow doubling after a hit", function()
        local game = solo({ "2S", "9C", "3H", "7D", "4C" })
        game:Act("P", "hit")
        local ok, err = game:Act("P", "double")
        assert.is_nil(ok); assert.matches("can't double", err)
    end)

    it("splits a pair into two hands played in order", function()
        local game, _, seat = solo({ "8S", "6C", "8H", "TD", "TS", "9S" })
        assert.is_true(game:Act("P", "split"))
        assert.equal(2, #seat.hands)
        assert.equal(80, seat.chips)
        assert.equal(1, game.current.hand)
        game:Act("P", "stand") -- 18
        assert.equal(2, game.current.hand)
        game:Act("P", "stand") -- 17
        -- dealer 16 + 2 = 18: hand 1 pushes, hand 2 loses
        assert.equal(90, seat.chips)
    end)

    it("gives split aces one card each, and 21 there is not blackjack", function()
        local game, _, seat = solo({ "AS", "9C", "AH", "8D", "KS", "5C" })
        assert.is_true(game:Act("P", "split"))
        -- both hands finished at once; dealer stands on 17
        assert.equal("betting", game.phase)
        assert.equal(100, seat.chips) -- +10 on the 21, -10 on the 16
    end)

    it("refuses actions out of turn", function()
        local game = helper.stackedGame(ns, { "A", "B" }, { "TS", "9S", "7C", "8H", "8D", "TD" })
        game:PlaceBet("A", 10); game:PlaceBet("B", 10)
        game:Deal()
        local ok, err = game:Act("B", "stand")
        assert.is_nil(ok); assert.matches("A's turn", err)
        assert.is_true(game:Act("A", "stand"))
        assert.is_true(game:Act("B", "stand"))
    end)

    it("skips a player who leaves on their turn", function()
        local game = helper.stackedGame(ns, { "A", "B" }, { "TS", "9S", "7C", "8H", "8D", "TD" })
        game:PlaceBet("A", 10); game:PlaceBet("B", 10)
        game:Deal()
        game:RemovePlayer("A")
        assert.equal("B", game.seats[game.current.seat].name)
    end)

    it("knocks out a player below the minimum bet and ends with a winner", function()
        local game, events = helper.stackedGame(ns, { "A", "B" }, { "TS", "9S", "7C", "8H", "8D", "TD" })
        game:FindSeat("B").chips = 2
        game:PlaceBet("A", 10); game:PlaceBet("B", 2)
        game:Deal()
        game:Act("A", "stand") -- 18 vs 17: wins
        game:Act("B", "stand") -- 17 vs 17: push, keeps 2
        assert.equal("betting", game.phase)
        helper.stack(game, { "TS", "9S", "TD", "7H", "7D", "TC" })
        game:PlaceBet("A", 10); game:PlaceBet("B", 2)
        game:Deal()
        game:Act("A", "stand") -- 17 vs 20
        game:Act("B", "stand") -- 16 vs 20: B drops to 0
        assert.truthy(helper.has(events, "out"))
        assert.equal("over", game.phase)
        assert.equal("A", helper.has(events, "over").winner)
    end)

    it("ends a solo game when the player runs out", function()
        local game, events, seat = solo({ "TS", "9C", "6H", "TD", "KS" }, 2)
        seat.chips = 0 -- as if this was the last bet
        game:Act("P", "hit")
        assert.equal("over", game.phase)
        assert.is_nil(helper.has(events, "over").winner)
    end)

    it("ends the game when the last player of two quits between rounds", function()
        local game, events = helper.stackedGame(ns, { "A", "B" }, {})
        game:RemovePlayer("B")
        assert.equal("over", game.phase)
        assert.equal("A", helper.has(events, "over").winner)
    end)

    it("reshuffles at the start of a round past 75% penetration", function()
        local events = {}
        local game = ns.Game.New({ onEvent = function(e) events[#events + 1] = e end })
        game:AddPlayer("P"); game:Start()
        game.shoe.pos = math.floor(#game.shoe.cards * 0.8)
        game:PlaceBet("P", 2); game:Deal()
        while game.phase == "players" do game:Act("P", "stand") end
        while game.phase == "insurance" do game:Insure("P", false) end
        local found = false
        for _, e in ipairs(events) do if e == "shuffled" then found = true end end
        assert.is_true(found)
    end)
end)
