-- Game.lua: the dealer and the round state machine. Pure Lua, no game API.
--
-- The table owner's client runs one Game. Everything a player does goes
-- through a method here, and everything that happens comes back out as an
-- event through opts.onEvent(event, data). Chat output, the table window and
-- (later) addon messages all just listen to those events.
local _, ns = ...
local Cards, Rules = ns.Cards, ns.Rules

local Game = {}
Game.__index = Game
ns.Game = Game

-- Phases: lobby -> betting -> (insurance) -> players -> betting ... -> over
function Game.New(opts)
    opts = opts or {}
    local self = setmetatable({}, Game)
    self.rules = Rules.New(opts.rules)
    self.shoe = Cards.NewShoe(self.rules.decks, opts.rng)
    self.emit = opts.onEvent or function() end
    self.seats = {}
    self.phase = "lobby"
    self.round = 0
    self.dealer = { cards = {} }
    return self
end

function Game:Emit(event, data)
    self.emit(event, data or {})
end

function Game:FindSeat(name)
    for i, seat in ipairs(self.seats) do
        if seat.name == name then return seat, i end
    end
end

function Game:ActiveSeats()
    local list = {}
    for _, seat in ipairs(self.seats) do
        if not seat.out then list[#list + 1] = seat end
    end
    return list
end

---------------------------------------------------------------------------
-- Seating and game start
---------------------------------------------------------------------------

function Game:AddPlayer(name)
    if self.phase ~= "lobby" then return nil, "The game has already started." end
    if self:FindSeat(name) then return nil, name .. " is already seated." end
    if #self.seats >= self.rules.maxSeats then return nil, "The table is full." end
    local seat = { name = name, chips = 0, bet = 0, hands = {}, out = false }
    self.seats[#self.seats + 1] = seat
    self:Emit("seated", { name = name, seat = #self.seats })
    return seat
end

function Game:Start()
    if self.phase ~= "lobby" then return nil, "The game has already started." end
    if #self.seats == 0 then return nil, "Nobody is seated." end
    self.startedWith = #self.seats
    self.lastRound = nil
    for _, seat in ipairs(self.seats) do
        seat.chips = self.rules.startingChips
    end
    self:Emit("started", { chips = self.rules.startingChips, players = #self.seats })
    self:OpenBetting()
    return true
end

-- A player quitting. In the lobby they just lose the seat; once the game has
-- started they keep it (so seat numbers don't shift) but are out.
function Game:RemovePlayer(name)
    local seat, index = self:FindSeat(name)
    if not seat then return nil, name .. " is not seated." end
    if self.phase == "lobby" then
        table.remove(self.seats, index)
        self:Emit("left", { name = name })
        return true
    end
    seat.left, seat.out = true, true
    self:Emit("left", { name = name })
    if self.phase == "over" then return true end

    if self.phase == "betting" then
        seat.bet = 0
        if not self:CheckGameOver() and self:AllBetsIn() then self:Deal() end
    elseif self.phase == "insurance" then
        if seat.insurance == nil then seat.insurance = false end
        for _, hand in ipairs(seat.hands) do hand.done = true end
        if self:InsurancePending() == 0 then self:AfterInsurance() end
    elseif self.phase == "players" then
        local current = self.current and self.seats[self.current.seat]
        for _, hand in ipairs(seat.hands) do hand.done = true end
        if current == seat then self:NextTurn() end
    end
    return true
end

function Game:Close()
    self.phase = "over"
    self:Emit("over", { reason = "closed" })
end

---------------------------------------------------------------------------
-- Betting
---------------------------------------------------------------------------

function Game:OpenBetting()
    self.round = self.round + 1
    self.phase = "betting"
    self.dealer = { cards = {} }
    self.current = nil
    for _, seat in ipairs(self.seats) do
        seat.bet, seat.hands, seat.insurance = 0, {}, nil
    end
    if Cards.Dealt(self.shoe) >= self.rules.penetration then
        Cards.Shuffle(self.shoe)
        self:Emit("shuffled")
    end
    self:Emit("betting", { round = self.round })
end

-- Placing a second bet in the same window replaces the first.
function Game:PlaceBet(name, amount)
    if self.phase ~= "betting" then return nil, "Betting is closed." end
    local seat = self:FindSeat(name)
    if not seat then return nil, "You are not seated." end
    if seat.out then return nil, "You are out of the game." end
    local ok, err = Rules.CheckBet(self.rules, amount, seat.chips + seat.bet)
    if not ok then return nil, err end
    seat.chips = seat.chips + seat.bet - amount
    seat.bet = amount
    self:Emit("bet", { name = name, amount = amount, chips = seat.chips })
    return true
end

function Game:AllBetsIn()
    local any = false
    for _, seat in ipairs(self:ActiveSeats()) do
        if seat.bet == 0 then return false end
        any = true
    end
    return any
end

---------------------------------------------------------------------------
-- Dealing, insurance and the dealer's peek
---------------------------------------------------------------------------

function Game:DrawTo(seat, handIndex)
    local card = Cards.Draw(self.shoe)
    local hand = seat.hands[handIndex]
    hand.cards[#hand.cards + 1] = card
    self:Emit("card", { name = seat.name, hand = handIndex, card = card, total = (Cards.Total(hand.cards)) })
    return card
end

function Game:DrawDealer(hidden)
    local card = Cards.Draw(self.shoe)
    self.dealer.cards[#self.dealer.cards + 1] = card
    self:Emit("dealerCard", {
        card = (not hidden) and card or nil, hidden = hidden or false, index = #self.dealer.cards,
    })
    return card
end

-- Seats that bet this round. Active seats that didn't bet sit the round out.
function Game:Bettors()
    local list = {}
    for _, seat in ipairs(self:ActiveSeats()) do
        if seat.bet > 0 then list[#list + 1] = seat end
    end
    return list
end

function Game:Deal()
    if self.phase ~= "betting" then return nil, "Not time to deal." end
    local bettors = self:Bettors()
    if #bettors == 0 then return nil, "No bets placed." end

    for _, seat in ipairs(bettors) do
        seat.hands = { { cards = {}, bet = seat.bet } }
    end
    self.lastRound = nil
    self:Emit("dealing", { round = self.round })
    for pass = 1, 2 do
        for _, seat in ipairs(bettors) do self:DrawTo(seat, 1) end
        self:DrawDealer(pass == 2)
    end
    for _, seat in ipairs(bettors) do
        local hand = seat.hands[1]
        if Cards.IsNatural(hand.cards) then
            hand.done, hand.natural = true, true
            self:Emit("blackjack", { name = seat.name })
        end
    end

    local up = self.dealer.cards[1]
    if self.rules.insurance and Cards.Rank(up) == "A" then
        self.phase = "insurance"
        local offered = {}
        for _, seat in ipairs(bettors) do
            if seat.chips >= seat.bet / 2 then
                seat.insurance = nil -- waiting on an answer
                offered[#offered + 1] = seat.name
            else
                seat.insurance = false
            end
        end
        if #offered > 0 then
            self:Emit("insuranceOffered", { names = offered })
            return true
        end
    end
    self:AfterInsurance()
    return true
end

function Game:InsurancePending()
    local n = 0
    for _, seat in ipairs(self:Bettors()) do
        if seat.insurance == nil then n = n + 1 end
    end
    return n
end

function Game:Insure(name, take)
    if self.phase ~= "insurance" then return nil, "Insurance isn't on offer." end
    local seat = self:FindSeat(name)
    if not seat or seat.bet == 0 or seat.out then return nil, "You have no bet this round." end
    if seat.insurance ~= nil then return nil, "You already answered." end
    if take then
        local cost = seat.bet / 2
        seat.chips = seat.chips - cost
        seat.insurance = cost
    else
        seat.insurance = false
    end
    self:Emit("insured", { name = name, amount = seat.insurance or 0, chips = seat.chips })
    if self:InsurancePending() == 0 then self:AfterInsurance() end
    return true
end

function Game:AfterInsurance()
    local up = self.dealer.cards[1]
    if self.rules.dealerPeeks and Cards.Value(up) >= 10 then
        if Cards.IsNatural(self.dealer.cards) then
            self:Emit("dealerReveal", { cards = self.dealer.cards, total = 21, blackjack = true })
            return self:Settle(true)
        end
        self:Emit("dealerPeeked", { blackjack = false })
    end
    self.phase = "players"
    self.current = nil
    self:NextTurn()
end

---------------------------------------------------------------------------
-- Player turns
---------------------------------------------------------------------------

-- Hands are always finished in order, so the first unfinished hand is next.
function Game:NextTurn()
    for s, seat in ipairs(self.seats) do
        if not seat.out then
            for h, hand in ipairs(seat.hands) do
                if not hand.done then
                    self.current = { seat = s, hand = h }
                    self:Emit("turn", {
                        name = seat.name, hand = h, hands = #seat.hands,
                        cards = hand.cards, total = (Cards.Total(hand.cards)),
                        actions = self:AllowedActions(seat, hand),
                    })
                    return
                end
            end
        end
    end
    self.current = nil
    self:DealerPlay()
end

function Game:CardsLeft()
    return #self.shoe.cards - self.shoe.pos + 1
end

function Game:CurrentHand()
    if self.phase ~= "players" or not self.current then return nil end
    local seat = self.seats[self.current.seat]
    return seat, seat.hands[self.current.hand], self.current.hand
end

function Game:AllowedActions(seat, hand)
    local rules = self.rules
    local actions = { hit = true, stand = true }
    local two = #hand.cards == 2
    if two and seat.chips >= hand.bet and (not hand.fromSplit or rules.doubleAfterSplit) then
        actions.double = true
    end
    if two and Cards.Rank(hand.cards[1]) == Cards.Rank(hand.cards[2])
        and #seat.hands < rules.maxHands and seat.chips >= hand.bet
        and not (hand.splitAces and not rules.resplitAces) then
        actions.split = true
    end
    return actions
end

-- After a card lands on a player hand: bust or 21 finishes it.
function Game:CheckHand(seat, hand, index)
    local total = Cards.Total(hand.cards)
    if total > 21 then
        hand.done, hand.bust = true, true
        self:Emit("bust", { name = seat.name, hand = index, total = total })
    elseif total == 21 then
        hand.done = true
    end
end

function Game:Act(name, action)
    local seat, hand, index = self:CurrentHand()
    if not seat then return nil, "It isn't anyone's turn." end
    if seat.name ~= name then return nil, "It's " .. seat.name .. "'s turn." end
    local allowed = self:AllowedActions(seat, hand)
    if not allowed[action] then return nil, "You can't " .. tostring(action) .. " now." end

    if action == "hit" then
        self:DrawTo(seat, index)
        self:CheckHand(seat, hand, index)
    elseif action == "stand" then
        hand.done = true
        self:Emit("stand", { name = name, hand = index, total = (Cards.Total(hand.cards)) })
    elseif action == "double" then
        seat.chips = seat.chips - hand.bet
        hand.bet = hand.bet * 2
        hand.doubled = true
        self:Emit("double", { name = name, hand = index, bet = hand.bet, chips = seat.chips })
        self:DrawTo(seat, index)
        hand.done = true
        self:CheckHand(seat, hand, index)
    elseif action == "split" then
        seat.chips = seat.chips - hand.bet
        local aces = Cards.Rank(hand.cards[1]) == "A"
        local second = table.remove(hand.cards, 2)
        local newHand = { cards = { second }, bet = hand.bet, fromSplit = true, splitAces = aces }
        hand.fromSplit, hand.splitAces = true, aces
        table.insert(seat.hands, index + 1, newHand)
        self:Emit("split", { name = name, hand = index, hands = #seat.hands, chips = seat.chips })
        self:DrawTo(seat, index)
        self:DrawTo(seat, index + 1)
        if aces then
            hand.done, newHand.done = true, true
        end
        self:CheckHand(seat, hand, index)
        self:CheckHand(seat, newHand, index + 1)
    end

    if hand.done then
        self:NextTurn()
    else
        self:Emit("turn", {
            name = name, hand = index, hands = #seat.hands,
            cards = hand.cards, total = (Cards.Total(hand.cards)),
            actions = self:AllowedActions(seat, hand),
        })
    end
    return true
end

---------------------------------------------------------------------------
-- Dealer play, settlement, elimination
---------------------------------------------------------------------------

function Game:DealerPlay()
    self.phase = "dealer"
    local cards = self.dealer.cards
    self:Emit("dealerReveal", { cards = cards, total = (Cards.Total(cards)) })

    -- The dealer only draws if some hand is still waiting on the dealer's total.
    local live = false
    for _, seat in ipairs(self:Bettors()) do
        for _, hand in ipairs(seat.hands) do
            if not hand.bust and not hand.natural then live = true end
        end
    end
    if live then
        while true do
            local total, soft = Cards.Total(cards)
            if total < 17 or (total == 17 and soft and self.rules.dealerHitsSoft17) then
                self:DrawDealer(false)
            else
                break
            end
        end
    end
    local total = Cards.Total(cards)
    self:Emit("dealerDone", { total = total, bust = total > 21 })
    return self:Settle(false)
end

-- Works out each hand. Bets were already taken from chips when placed, so
-- payout is what goes back: 0 on a loss, the bet on a push, more on a win.
function Game:Settle(dealerBlackjack)
    self.phase = "settle"
    local rules = self.rules
    local dealerTotal = Cards.Total(self.dealer.cards)
    local dealerBust = dealerTotal > 21
    -- What was on the table, kept so the finished round can still be shown
    -- after betting reopens.
    local last = { dealer = {}, seats = {}, nets = {} }
    for i, c in ipairs(self.dealer.cards) do last.dealer[i] = c end

    for _, seat in ipairs(self.seats) do
        if #seat.hands > 0 and not seat.left then
            local results = {}
            for i, hand in ipairs(seat.hands) do
                local total = Cards.Total(hand.cards)
                local result, payout
                if dealerBlackjack then
                    if hand.natural then result, payout = "push", hand.bet
                    else result, payout = "lose", 0 end
                elseif hand.bust then
                    result, payout = "lose", 0
                elseif hand.natural then
                    result, payout = "blackjack", hand.bet + Rules.BlackjackWin(rules, hand.bet)
                elseif dealerBust or total > dealerTotal then
                    result, payout = "win", hand.bet * 2
                elseif total == dealerTotal then
                    result, payout = "push", hand.bet
                else
                    result, payout = "lose", 0
                end
                hand.result, hand.payout = result, payout
                seat.chips = seat.chips + payout
                results[i] = { result = result, bet = hand.bet, payout = payout, total = total }
            end
            local insurance = 0
            if seat.insurance then
                if dealerBlackjack then
                    insurance = seat.insurance * 3 -- stake back plus 2 to 1
                    seat.chips = seat.chips + insurance
                end
            end
            local net = insurance - (seat.insurance or 0)
            for _, hand in ipairs(seat.hands) do
                net = net + hand.payout - hand.bet
            end
            last.nets[seat.name] = net
            self:Emit("result", {
                name = seat.name, hands = results, chips = seat.chips,
                insurance = seat.insurance or 0, insurancePaid = insurance,
            })
        end
    end
    for i, seat in ipairs(self.seats) do
        local hands = {}
        if not seat.left then
            for h, hand in ipairs(seat.hands) do
                local cards = {}
                for k, c in ipairs(hand.cards) do cards[k] = c end
                hands[h] = {
                    cards = cards, bet = hand.bet, result = hand.result, payout = hand.payout, bust = hand.bust,
                }
            end
        end
        last.seats[i] = hands
    end
    self.lastRound = last

    for _, seat in ipairs(self:ActiveSeats()) do
        if not Rules.CanPlay(rules, seat.chips) then
            seat.out = true
            self:Emit("out", { name = seat.name, chips = seat.chips })
        end
    end
    if not self:CheckGameOver() then
        self:OpenBetting()
    end
    return true
end

-- A game with 2+ players ends when one is left with chips. A solo game ends
-- when the player is out. Either ends when nobody is left.
function Game:CheckGameOver()
    if self.phase == "over" then return true end
    local active = self:ActiveSeats()
    local winner
    if #active == 0 then
        winner = nil
    elseif (self.startedWith or 0) >= 2 and #active == 1 then
        winner = active[1].name
    else
        return false
    end
    self.phase = "over"
    self:Emit("over", { winner = winner, reason = winner and "winner" or "nobody left" })
    return true
end

return Game
