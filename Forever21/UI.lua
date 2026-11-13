-- UI.lua: the blackjack table window. Draws the game from ns.game on every
-- event and sends button clicks to the same actions /f21 uses.
local addonName, ns = ...
local Cards = ns.Cards

local UI = {}
ns.UI = UI

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local WIDTH, HEIGHT = 720, 480
local CARD_W, CARD_H = 40, 56
local CARD_STEP = 16 -- how far each card overlaps the one before
local SEAT_W, SEAT_H, SEAT_GAP = 134, 196, 6

local SUIT_TEXTURE = { S = "SuitSpade", H = "SuitHeart", D = "SuitDiamond", C = "SuitClub" }
local RED = { 0.78, 0.08, 0.1 }
local BLACK = { 0.08, 0.08, 0.1 }
local GOLD = { 1, 0.82, 0.2 }

local CHIPS = {
    { value = 2, color = { 0.95, 0.95, 0.95 } },
    { value = 4, color = { 0.85, 0.15, 0.15 } },
    { value = 10, color = { 0.2, 0.4, 0.9 } },
}

local RESULT_TEXT = {
    win = "|cff40ff40WIN|r", lose = "|cffff4040LOSE|r", push = "|cffffff80PUSH|r",
    blackjack = "|cffffd040BLACKJACK|r",
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function texture(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer)
    if r then t:SetColorTexture(r, g, b, a or 1) end
    return t
end

local function text(parent, font, point, x, y, relative, relPoint)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetPoint(point, relative or parent, relPoint or point, x or 0, y or 0)
    return fs
end

local function button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 72, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------

local function CreateCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(CARD_W, CARD_H)
    c.edge = texture(c, "BACKGROUND", 0, 0, 0, 0.85)
    c.edge:SetAllPoints()
    c.face = texture(c, "BORDER", 0.97, 0.96, 0.92)
    c.face:SetPoint("TOPLEFT", 1, -1)
    c.face:SetPoint("BOTTOMRIGHT", -1, 1)
    c.rank = text(c, "GameFontNormal", "TOPLEFT", 3, -3)
    c.pip = texture(c, "ARTWORK")
    c.pip:SetSize(10, 10)
    c.pip:SetPoint("TOP", c.rank, "BOTTOM", 0, -1)
    c.suit = texture(c, "ARTWORK")
    c.suit:SetSize(22, 22)
    c.suit:SetPoint("CENTER", 3, -7)
    c.back = texture(c, "ARTWORK", 0.12, 0.22, 0.55)
    c.back:SetPoint("TOPLEFT", 3, -3)
    c.back:SetPoint("BOTTOMRIGHT", -3, 3)
    c.backInner = texture(c, "OVERLAY", 0.2, 0.33, 0.7)
    c.backInner:SetPoint("TOPLEFT", 7, -7)
    c.backInner:SetPoint("BOTTOMRIGHT", -7, 7)
    return c
end

-- card nil shows the back.
local function SetCard(c, card)
    local faceUp = card ~= nil
    c.rank:SetShown(faceUp)
    c.pip:SetShown(faceUp)
    c.suit:SetShown(faceUp)
    c.back:SetShown(not faceUp)
    c.backInner:SetShown(not faceUp)
    if faceUp then
        local rank, suit = Cards.Rank(card), Cards.Suit(card)
        local color = (suit == "H" or suit == "D") and RED or BLACK
        c.rank:SetText(rank == "T" and "10" or rank)
        c.rank:SetTextColor(color[1], color[2], color[3])
        for _, t in ipairs({ c.pip, c.suit }) do
            t:SetTexture(MEDIA .. SUIT_TEXTURE[suit])
            t:SetVertexColor(color[1], color[2], color[3])
        end
    end
    c:Show()
end

-- A row of overlapping cards inside a parent. Reuses card frames.
local function CreateHand(parent)
    local hand = CreateFrame("Frame", nil, parent)
    hand:SetSize(CARD_W, CARD_H)
    hand.cards = {}
    hand.total = text(hand, "GameFontHighlightSmall", "LEFT", 4, 0, hand, "RIGHT")
    hand.result = text(hand, "GameFontNormalSmall", "TOPLEFT", 0, -2, hand, "BOTTOMLEFT")
    return hand
end

-- Shows cards; hideFrom hides every card from that index on (the hole card).
local function ShowHand(hand, cards, hideFrom)
    for i, card in ipairs(cards) do
        local c = hand.cards[i]
        if not c then
            c = CreateCard(hand)
            c:SetFrameLevel(hand:GetFrameLevel() + i)
            c:SetPoint("TOPLEFT", (i - 1) * CARD_STEP, 0)
            hand.cards[i] = c
        end
        if hideFrom and i >= hideFrom then
            SetCard(c, nil) -- face down
        else
            SetCard(c, card)
        end
    end
    for i = #cards + 1, #hand.cards do hand.cards[i]:Hide() end
    hand:SetWidth(CARD_W + math.max(#cards - 1, 0) * CARD_STEP)
    hand:SetShown(#cards > 0)
end

local function TotalText(cards)
    local total, soft = Cards.Total(cards)
    if Cards.IsNatural(cards) then return "21" end
    if soft and total < 21 then return ("%d/%d"):format(total - 10, total) end
    return tostring(total)
end

---------------------------------------------------------------------------
-- Seats
---------------------------------------------------------------------------

local function CreateSeat(parent, index)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(SEAT_W, SEAT_H)
    s:SetPoint("BOTTOMLEFT", 12 + (index - 1) * (SEAT_W + SEAT_GAP), 62)
    s.glow = texture(s, "BACKGROUND", GOLD[1], GOLD[2], GOLD[3], 0.9)
    s.glow:SetPoint("TOPLEFT", -2, 2)
    s.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    s.bg = texture(s, "BORDER", 0.02, 0.22, 0.11)
    s.bg:SetAllPoints()
    s.name = text(s, "GameFontNormal", "TOP", 0, -6)
    s.chips = text(s, "GameFontHighlightSmall", "TOP", 0, -22)
    s.status = text(s, "GameFontDisableSmall", "CENTER", 0, 10)

    s.hands = {}
    for h = 1, ns.Rules.DEFAULTS.maxHands do
        s.hands[h] = CreateHand(s)
    end

    s.ring = texture(s, "ARTWORK")
    s.ring:SetTexture(MEDIA .. "Ring")
    s.ring:SetVertexColor(1, 1, 1, 0.45)
    s.ring:SetSize(30, 30)
    s.ring:SetPoint("BOTTOM", 0, 6)
    s.chip = texture(s, "OVERLAY")
    s.chip:SetTexture(MEDIA .. "Chip")
    s.chip:SetSize(26, 26)
    s.chip:SetPoint("CENTER", s.ring)
    s.bet = text(s, "GameFontHighlightSmall", "LEFT", 6, 0, s.ring, "RIGHT")
    return s
end

-- Lays out up to 4 hands; split hands shrink so they fit in the seat.
local function ShowSeatHands(s, hands, current)
    local n = #hands
    local scale = (n >= 3) and 0.6 or (n == 2 and 0.8 or 1)
    local rowH = (CARD_H + 16) * scale
    for h, frame in ipairs(s.hands) do
        local hand = hands[h]
        if hand then
            frame:SetScale(scale)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", s, "TOPLEFT", 10 / scale, (-40 - (h - 1) * rowH) / scale)
            ShowHand(frame, hand.cards)
            local marker = (current == h and n > 1) and "> " or ""
            frame.total:SetText(marker .. TotalText(hand.cards))
            frame.result:SetText(hand.result and RESULT_TEXT[hand.result] or (hand.bust and RESULT_TEXT.lose) or "")
        else
            frame:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

function UI:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "Forever21TableFrame", UIParent)
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        ns.db.point = { point, relPoint, x, y }
    end)
    local p = ns.db and ns.db.point
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER")
    end
    tinsert(UISpecialFrames, "Forever21TableFrame") -- Escape closes it

    local wood = texture(f, "BACKGROUND", 0.24, 0.13, 0.06)
    wood:SetAllPoints()
    local felt = texture(f, "BORDER", 0.04, 0.3, 0.16)
    felt:SetPoint("TOPLEFT", 8, -8)
    felt:SetPoint("BOTTOMRIGHT", -8, 8)

    f.title = text(f, "GameFontNormalLarge", "TOP", 0, -14)
    f.title:SetText("Forever21 Blackjack")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Dealer
    f.dealerLabel = text(f, "GameFontNormal", "TOP", 0, -40)
    f.dealerLabel:SetText("Dealer")
    f.dealer = CreateHand(f)
    f.dealer:SetPoint("TOP", 0, -58)
    f.dealer.total:ClearAllPoints()
    f.dealer.total:SetPoint("TOP", f.dealer, "BOTTOM", 0, -4)
    f.dealer.total:SetFontObject("GameFontHighlight")

    -- Shoe, for looks: a card back and how much of the shoe is left.
    f.shoe = CreateCard(f)
    f.shoe:SetPoint("TOPRIGHT", -48, -44)
    SetCard(f.shoe, nil)
    f.shoeText = text(f, "GameFontDisableSmall", "TOP", 0, -4, f.shoe, "BOTTOM")

    f.rules = text(f, "GameFontDisableSmall", "TOP", 0, -150)
    f.rules:SetText("BLACKJACK PAYS 3 TO 2  -  DEALER STANDS ON ALL 17s  -  INSURANCE PAYS 2 TO 1")
    f.status = text(f, "GameFontHighlight", "TOP", 0, -172)

    f.seats = {}
    for i = 1, ns.Rules.DEFAULTS.maxSeats do f.seats[i] = CreateSeat(f, i) end

    -- Bottom bar: chips and bet on the left, actions on the right.
    f.chipButtons = {}
    for i, chip in ipairs(CHIPS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(34, 34)
        b:SetPoint("BOTTOMLEFT", 16 + (i - 1) * 38, 18)
        b:SetNormalTexture(MEDIA .. "Chip")
        b:GetNormalTexture():SetVertexColor(chip.color[1], chip.color[2], chip.color[3])
        b:SetHighlightTexture(MEDIA .. "Ring", "ADD")
        local label = text(b, "GameFontNormalSmall", "CENTER", 0, 0)
        label:SetText(chip.value)
        label:SetTextColor(0, 0, 0)
        b:SetScript("OnClick", function() UI:AddToBet(chip.value) end)
        f.chipButtons[i] = b
    end
    f.pending = text(f, "GameFontHighlight", "BOTTOMLEFT", 136, 27)
    f.clearBet = button(f, "Clear", 56, function() UI:ClearBet() end)
    f.clearBet:SetPoint("BOTTOMLEFT", 196, 22)
    f.placeBet = button(f, "Bet", 64, function() UI:PlaceBet() end)
    f.placeBet:SetPoint("LEFT", f.clearBet, "RIGHT", 4, 0)

    f.actions = {}
    local prev
    for _, a in ipairs({ { "split", "Split" }, { "double", "Double" }, { "stand", "Stand" }, { "hit", "Hit" } }) do
        local action = a[1]
        local b = button(f, a[2], 66, function() UI:Report(ns.Act(action)) end)
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("BOTTOMRIGHT", -16, 22) end
        f.actions[action] = b
        prev = b
    end
    f.insureNo = button(f, "No Insurance", 104, function() UI:Report(ns.Insure(false)) end)
    f.insureNo:SetPoint("BOTTOMRIGHT", -16, 22)
    f.insureYes = button(f, "Insure", 72, function() UI:Report(ns.Insure(true)) end)
    f.insureYes:SetPoint("RIGHT", f.insureNo, "LEFT", -4, 0)

    f.newGame = button(f, "New Game", 96, function()
        UI:Report(ns.StartSolo())
    end)
    f.newGame:SetPoint("BOTTOM", 0, 22)
    f.leave = button(f, "Leave", 64, function() UI:Report(ns.Quit()) end)
    f.leave:SetPoint("TOPLEFT", 14, -12)

    self.pending = 10
    f:Hide()
end

function UI:Show()
    self:Create()
    self.frame:Show()
    self:Refresh()
end

function UI:Toggle()
    self:Create()
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

---------------------------------------------------------------------------
-- Betting
---------------------------------------------------------------------------

function UI:MaxBet()
    local seat = ns.MySeat()
    local max = ns.game and ns.game.rules.maxBet or ns.Rules.DEFAULTS.maxBet
    if seat then max = math.min(max, seat.chips - seat.chips % 2) end
    return max
end

function UI:AddToBet(value)
    self.pending = math.min((self.pending or 0) + value, self:MaxBet())
    self:Refresh()
end

function UI:ClearBet()
    self.pending = 0
    self:Refresh()
end

function UI:PlaceBet()
    self:Report(ns.Bet(self.pending))
end

function UI:Report(ok, err)
    if not ok and err then
        self.error = err
    else
        self.error = nil
    end
    self:Refresh()
end

---------------------------------------------------------------------------
-- Drawing the game
---------------------------------------------------------------------------

-- Copies what's on the table so a finished round stays visible until the
-- next deal (the game itself clears it as soon as betting reopens).
local function Snapshot(game)
    local snap = { dealer = {}, seats = {} }
    for i, c in ipairs(game.dealer.cards) do snap.dealer[i] = c end
    for i, seat in ipairs(game.seats) do
        local hands = {}
        for h, hand in ipairs(seat.hands) do
            local cards = {}
            for k, c in ipairs(hand.cards) do cards[k] = c end
            hands[h] = { cards = cards, result = hand.result, bust = hand.bust, bet = hand.bet }
        end
        snap.seats[i] = hands
    end
    return snap
end

local function MyResultText(d)
    local net = -(d.insurance or 0) + (d.insurancePaid or 0)
    for _, r in ipairs(d.hands) do net = net + r.payout - r.bet end
    if #d.hands == 1 and d.hands[1].result == "blackjack" then
        return ("Blackjack! You win %d."):format(net)
    elseif net > 0 then
        return ("You win %d."):format(net)
    elseif net < 0 then
        return ("You lose %d."):format(-net)
    end
    return "Push. Your bet comes back."
end

-- Events update the status line and the round snapshot, then redraw.
function UI:OnEvent(event, d)
    local me = ns.PlayerName()
    if event == "newGame" then
        self.snapshot, self.message, self.error = nil, nil, nil
    elseif event == "betting" then
        local seat = ns.MySeat()
        if seat and not seat.out and not self.message then self.message = "Place your bet." end
    elseif event == "dealing" then
        self.snapshot, self.message, self.error = nil, nil, nil
    elseif event == "insuranceOffered" then
        self.message = "Dealer shows an ace. Insurance?"
    elseif event == "dealerPeeked" then
        self.message = "Dealer checked: no blackjack."
    elseif event == "turn" then
        self.message = (d.name == me) and ("Your turn: " .. TotalText(d.cards)) or ("Waiting for " .. d.name .. "...")
    elseif event == "dealerReveal" and d.blackjack then
        self.message = "Dealer has blackjack."
    elseif event == "dealerDone" then
        self.message = d.bust and ("Dealer busts with %d."):format(d.total) or ("Dealer stands on %d."):format(d.total)
    elseif event == "result" then
        self.snapshot = Snapshot(ns.game)
        if d.name == me then self.message = MyResultText(d) end
    elseif event == "out" and d.name == me then
        self.message = "You're out of chips. You lose!"
    elseif event == "over" then
        if d.winner then
            self.message = (d.winner == me) and "You win the game!" or (d.winner .. " wins the game!")
        elseif d.reason == "closed" then
            self.message = "The table was closed."
        elseif not (self.message and self.message:find("You lose")) then
            self.message = "Game over."
        end
    end
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

ns.Listen(function(event, d) UI:OnEvent(event, d) end)

function UI:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local game = ns.game
    local playing = ns.IsPlaying()
    local me = ns.PlayerName()
    local mySeat = ns.MySeat()

    -- Status line
    if self.error then
        f.status:SetText("|cffff6060" .. self.error .. "|r")
    elseif not game then
        f.status:SetText("Press New Game to play against the dealer.")
    else
        f.status:SetText(self.message or "")
    end

    -- Which round to draw: the live one, or the last one until the next deal.
    local snap = game and (game.phase == "betting" or game.phase == "over") and self.snapshot
    local dealerCards = snap and snap.dealer or (game and game.dealer.cards) or {}
    local hidden = game and (game.phase == "insurance" or game.phase == "players") and not snap
    ShowHand(f.dealer, dealerCards, hidden and 2 or nil)
    if #dealerCards == 0 then
        f.dealer.total:SetText("")
    elseif hidden then
        f.dealer.total:SetText(tostring(Cards.Value(dealerCards[1])))
    else
        f.dealer.total:SetText(TotalText(dealerCards))
    end

    if game then
        local left = #game.shoe.cards - game.shoe.pos + 1
        f.shoeText:SetText(("%d cards"):format(left))
    else
        f.shoeText:SetText("")
    end

    -- Seats
    local current = game and game.current
    for i, s in ipairs(f.seats) do
        local seat = game and game.seats[i]
        s.glow:SetShown(seat ~= nil and current ~= nil and game.phase == "players" and current.seat == i)
        if seat then
            local isMe = seat.name == me
            s.name:SetText(isMe and (seat.name .. " (you)") or seat.name)
            if seat.out then
                s.name:SetTextColor(0.5, 0.5, 0.5)
            else
                s.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            end
            s.chips:SetText(("%d chips"):format(seat.chips))
            local hands = snap and snap.seats[i] or seat.hands
            ShowSeatHands(s, hands, current and current.seat == i and current.hand or nil)
            local bet = seat.bet
            if game.phase ~= "betting" and game.phase ~= "over" then
                bet = 0
                for _, hand in ipairs(seat.hands) do bet = bet + hand.bet end
            end
            s.chip:SetShown(bet > 0)
            s.bet:SetText(bet > 0 and tostring(bet) or "")
            s.ring:Show()
            if seat.left then
                s.status:SetText("Left")
            elseif seat.out then
                s.status:SetText("OUT")
            elseif #hands == 0 and game.phase == "betting" then
                s.status:SetText(seat.bet > 0 and "" or "Betting...")
            else
                s.status:SetText("")
            end
        else
            s.name:SetText("")
            s.chips:SetText("")
            s.status:SetText("Empty seat")
            ShowSeatHands(s, {})
            s.chip:Hide()
            s.ring:Hide()
            s.bet:SetText("")
        end
    end

    -- Bet controls
    local canBet = playing and game.phase == "betting" and mySeat and not mySeat.out and mySeat.bet == 0
    if canBet then self.pending = math.min(self.pending or 0, self:MaxBet()) end
    for _, b in ipairs(f.chipButtons) do b:SetShown(canBet) end
    f.pending:SetShown(canBet)
    f.pending:SetText(("Bet: %d"):format(self.pending or 0))
    f.clearBet:SetShown(canBet)
    f.placeBet:SetShown(canBet)
    f.placeBet:SetEnabled(canBet and (self.pending or 0) >= (game and game.rules.minBet or 2))

    -- Insurance
    local insuring = playing and game.phase == "insurance" and mySeat and mySeat.bet > 0 and mySeat.insurance == nil
    f.insureYes:SetShown(insuring)
    f.insureNo:SetShown(insuring)

    -- Actions
    local seat, hand = nil, nil
    if playing then seat, hand = game:CurrentHand() end
    local myTurn = seat ~= nil and seat.name == me
    local allowed = myTurn and game:AllowedActions(seat, hand) or {}
    for action, b in pairs(f.actions) do
        b:SetShown(playing and not insuring)
        b:SetEnabled(allowed[action] == true)
    end

    f.newGame:SetShown(not playing)
    f.leave:SetShown(playing)
end
