local helper = require("spec.helper")
local ns = helper.load()
local Rules = ns.Rules

describe("Rules", function()
    local rules = Rules.New()

    it("accepts even bets from 2 to 24", function()
        assert.is_true(Rules.CheckBet(rules, 2, 100))
        assert.is_true(Rules.CheckBet(rules, 24, 100))
    end)

    it("rejects odd, out-of-range, fractional, and unaffordable bets", function()
        assert.is_false((Rules.CheckBet(rules, 3, 100)))
        assert.is_false((Rules.CheckBet(rules, 0, 100)))
        assert.is_false((Rules.CheckBet(rules, 26, 100)))
        assert.is_false((Rules.CheckBet(rules, 2.5, 100)))
        assert.is_false((Rules.CheckBet(rules, 10, 8)))
        assert.is_false((Rules.CheckBet(rules, nil, 100)))
    end)

    it("pays 3 to 2 on blackjack in whole chips", function()
        assert.equal(15, Rules.BlackjackWin(rules, 10))
        assert.equal(3, Rules.BlackjackWin(rules, 2))
    end)

    it("lets overrides change rules", function()
        local r = Rules.New({ decks = 2 })
        assert.equal(2, r.decks)
        assert.equal(6, Rules.DEFAULTS.decks)
    end)
end)
