-- Commands.lua: /f21 slash commands and chat output for solo play.
local _, ns = ...
local Cards = ns.Cards

local game -- the Game this client is running, if any

local function cardList(cards)
    local out = {}
    for i, card in ipairs(cards) do out[i] = Cards.Short(card) end
    return table.concat(out, " ")
end

local function actionList(actions)
    local out = {}
    for _, a in ipairs({ "hit", "stand", "double", "split" }) do
        if actions[a] then out[#out + 1] = "/f21 " .. a end
    end
    return table.concat(out, ", ")
end

local RESULT_WORDS = {
    win = "win", lose = "lose", push = "push", blackjack = "blackjack!",
}

-- Turns game events into chat lines. Later the table window listens too.
local function onEvent(event, d)
    local P = ns.Print
    if event == "started" then
        P(("Game started. Everyone has %d chips. Bet with /f21 bet <2-24, even>."):format(d.chips))
        ns.charDB.gamesPlayed = ns.charDB.gamesPlayed + 1
    elseif event == "shuffled" then
        P("The dealer shuffles the shoe.")
    elseif event == "betting" then
        P(("Round %d: place your bet with /f21 bet <amount>."):format(d.round))
    elseif event == "bet" then
        P(("%s bets %d (%d chips left)."):format(d.name, d.amount, d.chips))
    elseif event == "dealerCard" then
        if d.hidden then
            P("Dealer: [hidden card]")
        elseif game and #game.dealer.cards > 2 then
            P("Dealer draws " .. Cards.Short(d.card) .. ".")
        else
            P("Dealer shows " .. Cards.Short(d.card) .. ".")
        end
    elseif event == "blackjack" then
        P(d.name .. " has blackjack!")
    elseif event == "insuranceOffered" then
        P("Dealer shows an ace. Insurance? /f21 insure or /f21 noinsure")
    elseif event == "insured" then
        if d.amount > 0 then P(("%s takes insurance for %d."):format(d.name, d.amount)) end
    elseif event == "dealerPeeked" then
        P("Dealer checks for blackjack... no blackjack.")
    elseif event == "turn" then
        local label = d.hands > 1 and (" (hand %d of %d)"):format(d.hand, d.hands) or ""
        P(("%s%s: %s = %d. %s"):format(d.name, label, cardList(d.cards), d.total, actionList(d.actions)))
    elseif event == "bust" then
        P(("%s busts with %d."):format(d.name, d.total))
    elseif event == "double" then
        P(("%s doubles to %d."):format(d.name, d.bet))
    elseif event == "split" then
        P(("%s splits into %d hands."):format(d.name, d.hands))
    elseif event == "dealerReveal" then
        P(("Dealer has %s = %d%s."):format(cardList(d.cards), d.total, d.blackjack and " (blackjack)" or ""))
    elseif event == "dealerDone" then
        P(d.bust and ("Dealer busts with %d."):format(d.total) or ("Dealer stands on %d."):format(d.total))
    elseif event == "result" then
        for i, r in ipairs(d.hands) do
            local label = #d.hands > 1 and (" hand %d"):format(i) or ""
            P(("%s%s: %s (%d), gets back %d."):format(d.name, label, RESULT_WORDS[r.result], r.total, r.payout))
            if d.name == ns.PlayerName() then ns.charDB.handsPlayed = ns.charDB.handsPlayed + 1 end
        end
        if d.insurancePaid > 0 then P(("%s's insurance pays %d."):format(d.name, d.insurancePaid)) end
        P(("%s now has %d chips."):format(d.name, d.chips))
    elseif event == "out" then
        P(d.name .. " is out of chips. You lose!")
    elseif event == "left" then
        P(d.name .. " left the table.")
    elseif event == "over" then
        if d.winner then
            P(d.winner .. " wins the game!")
            if d.winner == ns.PlayerName() then ns.charDB.gamesWon = ns.charDB.gamesWon + 1 end
        elseif d.reason == "closed" then
            P("The table was closed.")
        else
            P("Game over.")
        end
    end
end

local function startSolo()
    if game and game.phase ~= "over" then
        ns.Print("A game is already running. /f21 quit to leave it.")
        return
    end
    game = ns.Game.New({ onEvent = onEvent })
    game:AddPlayer(ns.PlayerName())
    game:Start()
end

local function report(ok, err)
    if not ok and err then ns.Print("|cffff5555" .. err .. "|r") end
end

local function needGame()
    if not game or game.phase == "over" then
        ns.Print("No game running. Start one with /f21 solo.")
        return false
    end
    return true
end

local HELP = {
    "/f21 solo - play a solo game against the dealer",
    "/f21 bet <amount> - bet an even amount from 2 to 24",
    "/f21 hit, stand, double, split - play your hand",
    "/f21 insure, noinsure - answer the insurance offer",
    "/f21 chips - show your chips",
    "/f21 quit - leave the game",
    "/f21 stats - your games and hands played",
    "/f21 api - check which addon-message API this client has",
}

local handlers = {}

handlers.solo = startSolo
handlers.bet = function(arg)
    if not needGame() then return end
    local ok, err = game:PlaceBet(ns.PlayerName(), tonumber(arg))
    report(ok, err)
    if ok and game:AllBetsIn() then report(game:Deal()) end
end
for _, action in ipairs({ "hit", "stand", "double", "split" }) do
    handlers[action] = function()
        if needGame() then report(game:Act(ns.PlayerName(), action)) end
    end
end
handlers.insure = function()
    if needGame() then report(game:Insure(ns.PlayerName(), true)) end
end
handlers.noinsure = function()
    if needGame() then report(game:Insure(ns.PlayerName(), false)) end
end
handlers.chips = function()
    if not needGame() then return end
    local seat = game:FindSeat(ns.PlayerName())
    ns.Print(("You have %d chips."):format(seat and seat.chips or 0))
end
handlers.quit = function()
    if needGame() then report(game:RemovePlayer(ns.PlayerName())) end
end
handlers.stats = function()
    local c = ns.charDB
    ns.Print(("Games played %d, won %d. Hands played %d."):format(c.gamesPlayed, c.gamesWon, c.handsPlayed))
end
handlers.api = function()
    local api = ns.AddonMessageAPI()
    ns.Print(("Version %s. Addon messages: %s."):format(ns.VERSION, api or "|cffff5555not available|r"))
end
handlers.help = function()
    for _, line in ipairs(HELP) do ns.Print(line) end
end

SLASH_FOREVER211 = "/f21"
SLASH_FOREVER212 = "/forever21"
SlashCmdList.FOREVER21 = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local handler = handlers[cmd]
    if handler then
        handler(arg)
    else
        handlers.help()
    end
end
