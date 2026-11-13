-- Cards.lua: cards, the shoe, and hand totals. Pure Lua, no game API.
local _, ns = ...

local Cards = {}
ns.Cards = Cards

Cards.RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K" }
Cards.SUITS = { "S", "H", "D", "C" }

local RANK_NAMES = {
    A = "Ace", ["2"] = "2", ["3"] = "3", ["4"] = "4", ["5"] = "5", ["6"] = "6",
    ["7"] = "7", ["8"] = "8", ["9"] = "9", T = "10", J = "Jack", Q = "Queen", K = "King",
}
local SUIT_SYMBOLS = { S = "s", H = "h", D = "d", C = "c" }

-- A card is a two-character string: rank then suit, e.g. "AS", "TH", "QD".
function Cards.Rank(card)
    return card:sub(1, 1)
end

function Cards.Suit(card)
    return card:sub(2, 2)
end

-- Blackjack value of one card, counting an ace as 11.
function Cards.Value(card)
    local rank = Cards.Rank(card)
    if rank == "A" then
        return 11
    elseif rank == "T" or rank == "J" or rank == "Q" or rank == "K" then
        return 10
    end
    return tonumber(rank)
end

-- Short display name, e.g. "Ks", "10h", "Ad".
function Cards.Short(card)
    local rank = Cards.Rank(card)
    if rank == "T" then rank = "10" end
    return rank .. SUIT_SYMBOLS[Cards.Suit(card)]
end

function Cards.Name(card)
    return RANK_NAMES[Cards.Rank(card)]
end

-- Returns the best total and whether it is soft (an ace still counted as 11).
function Cards.Total(cards)
    local total, aces = 0, 0
    for _, card in ipairs(cards) do
        local v = Cards.Value(card)
        total = total + v
        if v == 11 then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end
    return total, aces > 0
end

function Cards.IsBust(cards)
    return (Cards.Total(cards)) > 21
end

-- Two cards totalling 21. Callers decide whether a split hand can count.
function Cards.IsNatural(cards)
    return #cards == 2 and (Cards.Total(cards)) == 21
end

-- rng(n) must return an integer from 1 to n. Defaults to math.random.
local function defaultRng(n)
    return math.random(n)
end

function Cards.NewShoe(decks, rng)
    local shoe = { cards = {}, pos = 1, rng = rng or defaultRng }
    for _ = 1, decks do
        for _, suit in ipairs(Cards.SUITS) do
            for _, rank in ipairs(Cards.RANKS) do
                shoe.cards[#shoe.cards + 1] = rank .. suit
            end
        end
    end
    Cards.Shuffle(shoe)
    return shoe
end

-- Fisher-Yates shuffle of the whole shoe; resets the deal position.
function Cards.Shuffle(shoe)
    local cards = shoe.cards
    for i = #cards, 2, -1 do
        local j = shoe.rng(i)
        cards[i], cards[j] = cards[j], cards[i]
    end
    shoe.pos = 1
end

function Cards.Draw(shoe)
    if shoe.pos > #shoe.cards then
        Cards.Shuffle(shoe)
    end
    local card = shoe.cards[shoe.pos]
    shoe.pos = shoe.pos + 1
    return card
end

-- Fraction of the shoe already dealt, from 0 to 1.
function Cards.Dealt(shoe)
    return (shoe.pos - 1) / #shoe.cards
end

return Cards
