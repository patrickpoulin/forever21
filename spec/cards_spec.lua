local helper = require("spec.helper")
local ns = helper.load()
local Cards = ns.Cards

describe("Cards", function()
    it("values cards", function()
        assert.equal(11, Cards.Value("AS"))
        assert.equal(10, Cards.Value("TH"))
        assert.equal(10, Cards.Value("KD"))
        assert.equal(7, Cards.Value("7C"))
    end)

    it("totals hard and soft hands", function()
        local total, soft = Cards.Total({ "AS", "6H" })
        assert.equal(17, total); assert.is_true(soft)
        total, soft = Cards.Total({ "AS", "6H", "TC" })
        assert.equal(17, total); assert.is_false(soft)
        total, soft = Cards.Total({ "AS", "AH", "9C" })
        assert.equal(21, total); assert.is_true(soft)
        assert.equal(22, (Cards.Total({ "KS", "QH", "2C" })))
    end)

    it("detects naturals and busts", function()
        assert.is_true(Cards.IsNatural({ "AS", "KH" }))
        assert.is_false(Cards.IsNatural({ "7S", "7H", "7C" }))
        assert.is_true(Cards.IsBust({ "KS", "QH", "5C" }))
    end)

    it("builds a full six-deck shoe", function()
        local shoe = Cards.NewShoe(6)
        assert.equal(312, #shoe.cards)
        local counts = {}
        for _, c in ipairs(shoe.cards) do counts[c] = (counts[c] or 0) + 1 end
        assert.equal(6, counts.AS)
        assert.equal(6, counts["7D"])
    end)

    it("tracks how much of the shoe is dealt", function()
        local shoe = Cards.NewShoe(1)
        for _ = 1, 13 do Cards.Draw(shoe) end
        assert.equal(0.25, Cards.Dealt(shoe))
    end)

    it("prints short names", function()
        assert.equal("10h", Cards.Short("TH"))
        assert.equal("As", Cards.Short("AS"))
    end)
end)
