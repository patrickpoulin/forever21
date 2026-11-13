-- Rules.lua: table rules and bet checks. Pure Lua, no game API.
local _, ns = ...

local Rules = {}
ns.Rules = Rules

-- Every rule the dealer follows lives here so it can change without touching game logic.
Rules.DEFAULTS = {
    decks = 6,
    penetration = 0.75,       -- reshuffle once this fraction of the shoe is dealt
    blackjackPays = { 3, 2 }, -- 3 to 2
    dealerHitsSoft17 = false, -- S17: dealer stands on all 17s
    dealerPeeks = true,       -- dealer checks for blackjack with an ace or ten showing
    insurance = true,         -- offered when the dealer shows an ace, pays 2 to 1
    doubleAfterSplit = true,
    maxHands = 4,             -- split up to 4 hands
    resplitAces = false,
    minBet = 2,
    maxBet = 24,
    evenBetsOnly = true,
    startingChips = 100,
    maxSeats = 5,
}

function Rules.New(overrides)
    local rules = {}
    for k, v in pairs(Rules.DEFAULTS) do rules[k] = v end
    if overrides then
        for k, v in pairs(overrides) do rules[k] = v end
    end
    return rules
end

-- Returns true, or false plus a reason a player can read.
function Rules.CheckBet(rules, amount, chips)
    if type(amount) ~= "number" or amount ~= math.floor(amount) then
        return false, "Bet must be a whole number of chips."
    end
    if amount < rules.minBet or amount > rules.maxBet then
        return false, ("Bet must be between %d and %d chips."):format(rules.minBet, rules.maxBet)
    end
    if rules.evenBetsOnly and amount % 2 ~= 0 then
        return false, "Bets must be even."
    end
    if amount > chips then
        return false, ("You only have %d chips."):format(chips)
    end
    return true
end

-- Winnings (not counting the returned bet) for a blackjack on this bet.
function Rules.BlackjackWin(rules, bet)
    local num, den = rules.blackjackPays[1], rules.blackjackPays[2]
    return math.floor(bet * num / den)
end

-- A player can keep betting only while they can cover the minimum bet.
function Rules.CanPlay(rules, chips)
    return chips >= rules.minBet
end

return Rules
