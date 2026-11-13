-- Commands.lua: the event bus, chat output, and /f21 slash commands.
-- The actions the commands call (ns.Bet, ns.Act, ...) live in Table.lua.
local _, ns = ...
local Cards = ns.Cards

-- Anything that wants game events (chat output, the table window) listens here.
ns.listeners = {}
function ns.Listen(fn)
    ns.listeners[#ns.listeners + 1] = fn
end
function ns.Dispatch(event, data)
    for _, fn in ipairs(ns.listeners) do fn(event, data or {}) end
end

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

-- Stats are kept whether or not chat output is on.
ns.Listen(function(event, d)
    local c = ns.charDB
    if event == "started" then
        c.gamesPlayed = c.gamesPlayed + 1
    elseif event == "result" and d.name == ns.PlayerName() then
        c.handsPlayed = c.handsPlayed + #d.hands
    elseif event == "over" and d.winner and d.winner == ns.PlayerName() then
        c.gamesWon = c.gamesWon + 1
    end
end)

-- Turns game events into chat lines. On by default; /f21 chat toggles it.
local function onEvent(event, d)
    if ns.db and ns.db.chat == false then return end
    local P = ns.Print
    if event == "started" then
        P(("Game started. Everyone has %d chips. Bet with /f21 bet <2-24, even>."):format(d.chips))
    elseif event == "shuffled" then
        P("The dealer shuffles the shoe.")
    elseif event == "betting" then
        P(("Round %d: place your bet with /f21 bet <amount>."):format(d.round))
    elseif event == "bet" then
        P(("%s bets %d (%d chips left)."):format(d.name, d.amount, d.chips))
    elseif event == "dealerCard" then
        if d.hidden then
            P("Dealer: [hidden card]")
        elseif (d.index or 0) > 2 then
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
        elseif d.reason == "closed" then
            P("The table was closed.")
        else
            P("Game over.")
        end
    elseif event == "seated" then
        if d.name ~= ns.PlayerName() then P(d.name .. " joined the table.") end
    elseif event == "inviteSent" then
        P(("Invited %s. Waiting for an answer..."):format(d.name))
    elseif event == "declined" then
        P(d.why or (d.name .. " declined the invite."))
    elseif event == "inviteExpired" then
        P(d.name .. " didn't answer. They may not have Forever21 installed.")
    elseif event == "invited" then
        P(d.name .. " invites you to play blackjack. /f21 accept or /f21 decline")
    elseif event == "inviteMismatch" then
        P(("%s invited you, but has Forever21 %s and you have %s."):format(d.name, d.theirs, ns.VERSION))
    elseif event == "joining" then
        P("Joining " .. d.name .. "'s table...")
    elseif event == "denied" then
        P("|cffff5555" .. (d.why or "Couldn't join the table.") .. "|r")
    elseif event == "timedOut" then
        P(d.name .. " ran out of time and stands.")
    elseif event == "error" then
        P("|cffff5555" .. d.message .. "|r")
    end
end

ns.Listen(onEvent)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function report(ok, err)
    if not ok and err then ns.Print("|cffff5555" .. err .. "|r") end
end

local HELP = {
    "/f21 - show or hide the table window",
    "/f21 host - open a table, then invite players",
    "/f21 invite <name> - invite a player (or your target)",
    "/f21 start - start the game (with whoever has joined)",
    "/f21 accept, decline - answer an invite",
    "/f21 solo - play a solo game against the dealer",
    "/f21 bet <amount> - bet an even amount from 2 to 24",
    "/f21 hit, stand, double, split - play your hand",
    "/f21 insure, noinsure - answer the insurance offer",
    "/f21 chips - show your chips",
    "/f21 quit - leave the table (the owner leaving closes it)",
    "/f21 sound - turn sound effects on or off",
    "/f21 chat - turn chat messages on or off",
    "/f21 stats - your games and hands played",
    "/f21 api - check which addon-message API this client has",
}

local handlers = {}

handlers[""] = function()
    if ns.UI then ns.UI:Toggle() else handlers.help() end
end
handlers.solo = function()
    report(ns.StartSolo())
    if ns.UI then ns.UI:Show() end
end
handlers.host = function()
    report(ns.HostTable())
    if ns.UI then ns.UI:Show() end
end
handlers.invite = function(arg)
    report(ns.Invite(arg))
    if ns.UI then ns.UI:Show() end
end
handlers.start = function() report(ns.StartGame()) end
handlers.accept = function()
    local ok, err = ns.AcceptInvite()
    report(ok, err)
    if ok and ns.UI then ns.UI:Show() end
end
handlers.decline = function() report(ns.DeclineInvite()) end
handlers.bet = function(arg) report(ns.Bet(tonumber(arg))) end
for _, action in ipairs({ "hit", "stand", "double", "split" }) do
    handlers[action] = function() report(ns.Act(action)) end
end
handlers.insure = function() report(ns.Insure(true)) end
handlers.noinsure = function() report(ns.Insure(false)) end
handlers.chips = function()
    local seat = ns.MySeat()
    if not ns.IsPlaying() or not seat then return report(nil, "No game running.") end
    ns.Print(("You have %d chips."):format(seat.chips))
end
handlers.quit = function() report(ns.Quit()) end
handlers.sound = function()
    ns.db.sound = not ns.db.sound
    ns.Print("Sound effects " .. (ns.db.sound and "on." or "off."))
    if ns.UI then ns.UI:Refresh() end
end
handlers.chat = function()
    ns.db.chat = not ns.db.chat
    ns.Print("Chat messages " .. (ns.db.chat and "on." or "off."))
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
