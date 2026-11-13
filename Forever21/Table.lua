-- Table.lua: who runs the table and how moves travel.
--
-- The owner (host) runs the only real Game. Every move from another player is
-- whispered to the owner, who applies it and whispers back the new table state
-- plus the events that produced it. Other players draw a read-only copy of the
-- game built from that state, so every screen shows the same thing and only
-- the owner's client ever decides anything. The dealer's hole card is hidden
-- in what's sent until it's turned over.
local _, ns = ...
local Game, Serialize = ns.Game, ns.Serialize

local T = {}
ns.Table = T

local TIMEOUTS = { bet = 20, insurance = 15, turn = 30 }
local INVITE_SECONDS = 60

T.invites = {}       -- host: name -> true while waiting for an answer
T.outbox = {}        -- host: events not yet sent
T.timerId = 0
T.deadline = nil     -- GetTime() when the current timer runs out

ns.role = nil        -- "host", "client", or nil
ns.hostName = nil

local function me() return ns.PlayerName() end

function ns.IsPlaying()
    return ns.game ~= nil and ns.game.phase ~= "over"
end

function ns.MySeat()
    return ns.game and ns.game:FindSeat(me())
end

function ns.IsHost()
    return ns.role == "host"
end

-- Seconds left on the current timer, or nil.
function T.SecondsLeft()
    if not T.deadline or not ns.IsPlaying() then return nil end
    return math.max(0, math.ceil(T.deadline - GetTime()))
end

function T.InviteList()
    if ns.role == "client" then return (ns.game and ns.game.invites) or {} end
    local list = {}
    for name in pairs(T.invites) do list[#list + 1] = name end
    table.sort(list)
    return list
end

---------------------------------------------------------------------------
-- Host: state that goes out to the other players
---------------------------------------------------------------------------

-- Cards travel as one string, two characters each: {"TS","9H"} <-> "TS9H".
local function packCards(cards)
    return table.concat(cards)
end

local function unpackCards(s)
    local cards = {}
    if type(s) ~= "string" then return cards end
    for i = 1, #s - 1, 2 do cards[#cards + 1] = s:sub(i, i + 1) end
    return cards
end

local function packLastRound(last)
    if not last then return nil end
    local seats = {}
    for i, hands in ipairs(last.seats) do
        local packed = {}
        for h, hand in ipairs(hands) do
            packed[h] = { c = packCards(hand.cards), b = hand.bet, r = hand.result, p = hand.payout, x = hand.bust }
        end
        seats[i] = packed
    end
    return { d = packCards(last.dealer), s = seats, n = last.nets }
end

local function unpackLastRound(packed)
    if type(packed) ~= "table" then return nil end
    local seats = {}
    for i, hands in ipairs(packed.s or {}) do
        local list = {}
        for h, x in ipairs(hands) do
            list[h] = { cards = unpackCards(x.c), bet = x.b, result = x.r, payout = x.p, bust = x.x }
        end
        seats[i] = list
    end
    return { dealer = unpackCards(packed.d), seats = seats, nets = packed.n or {} }
end

function T.Snapshot(game)
    local hide = game.phase == "insurance" or game.phase == "players"
    local dealer = {}
    for i, c in ipairs(game.dealer.cards) do dealer[i] = (hide and i == 2) and "XX" or c end
    local seats = {}
    for i, s in ipairs(game.seats) do
        local hands = {}
        for h, hand in ipairs(s.hands) do
            hands[h] = {
                c = packCards(hand.cards), b = hand.bet, d = hand.done, x = hand.bust, nt = hand.natural,
                sp = hand.fromSplit, sa = hand.splitAces, db = hand.doubled, r = hand.result, p = hand.payout,
            }
        end
        -- Defaults (no bet, still in, undecided insurance) are left out.
        seats[i] = {
            n = s.name, c = s.chips, b = s.bet ~= 0 and s.bet or nil, o = s.out or nil, l = s.left or nil,
            i = s.insurance, h = hands,
        }
    end
    return {
        ph = game.phase, r = game.round, sw = game.startedWith, host = me(),
        cur = game.current and { game.current.seat, game.current.hand },
        d = packCards(dealer), left = game:CardsLeft(), seats = seats,
        lr = (game.phase == "betting" or game.phase == "over") and packLastRound(game.lastRound) or nil,
        inv = T.InviteList(), tl = T.SecondsLeft(),
    }
end

-- Recipients: everyone seated except the owner and anyone who left.
local function others(game)
    local list = {}
    for _, s in ipairs(game.seats) do
        if s.name ~= me() and not s.left then list[#list + 1] = s.name end
    end
    return list
end

function T.Flush()
    T.flushQueued = false
    local game = ns.game
    if not game or not ns.IsHost() then return end
    local msg = { t = "upd", s = T.Snapshot(game), e = T.outbox }
    T.outbox = {}
    for _, name in ipairs(others(game)) do ns.Net.Send(name, msg) end
end

local function queueFlush()
    if not T.flushQueued then
        T.flushQueued = true
        C_Timer.After(0, T.Flush)
    end
end

---------------------------------------------------------------------------
-- Host: timers so one slow player can't stall the table
---------------------------------------------------------------------------

function T.StopTimer()
    T.timerId = T.timerId + 1
    T.deadline = nil
end

function T.StartTimer(kind)
    local game = ns.game
    if not game or #game.seats < 2 then return T.StopTimer() end -- solo: take your time
    T.timerId = T.timerId + 1
    local id, seconds = T.timerId, TIMEOUTS[kind]
    T.deadline = GetTime() + seconds
    C_Timer.After(seconds, function()
        if id == T.timerId then T.OnTimeout(kind) end
    end)
end

function T.OnTimeout(kind)
    local game = ns.game
    if not game or not ns.IsHost() then return end
    if kind == "bet" and game.phase == "betting" then
        if #game:Bettors() > 0 then
            game:Deal() -- anyone who didn't bet sits this round out
        else
            T.StartTimer("bet")
            queueFlush()
        end
    elseif kind == "insurance" and game.phase == "insurance" then
        for _, seat in ipairs(game:Bettors()) do
            if seat.insurance == nil then game:Insure(seat.name, false) end
        end
    elseif kind == "turn" and game.phase == "players" then
        local seat = game:CurrentHand()
        if seat then
            T.HostEvent("timedOut", { name = seat.name })
            game:Act(seat.name, "stand")
        end
    end
end

-- Every event from the owner's game: show it here, queue it for the others,
-- and keep the timers in step with the phase.
function T.HostEvent(event, data)
    if event == "betting" then
        T.StartTimer("bet")
    elseif event == "insuranceOffered" then
        T.StartTimer("insurance")
    elseif event == "turn" then
        T.StartTimer("turn")
    elseif event == "dealing" or event == "dealerReveal" or event == "over" then
        T.StopTimer()
    end
    ns.Dispatch(event, data)
    T.outbox[#T.outbox + 1] = { event, Serialize.Copy(data) }
    queueFlush()
end

---------------------------------------------------------------------------
-- Client: a read-only copy of the owner's game
---------------------------------------------------------------------------

function T.Mirror(snap)
    local g = setmetatable({}, Game)
    g.remote = true
    g.rules = ns.Rules.New(T.rules)
    g.phase, g.round, g.startedWith = snap.ph, snap.r, snap.sw
    g.current = snap.cur and { seat = snap.cur[1], hand = snap.cur[2] }
    g.dealer = { cards = unpackCards(snap.d) }
    g.shoe = { cards = {}, pos = 1 }
    local left = snap.left or 0
    g.CardsLeft = function() return left end
    g.lastRound = unpackLastRound(snap.lr)
    g.invites = snap.inv or {}
    g.host = snap.host
    g.seats = {}
    for i, s in ipairs(snap.seats or {}) do
        local hands = {}
        for h, x in ipairs(s.h or {}) do
            hands[h] = {
                cards = unpackCards(x.c), bet = x.b or 0, done = x.d, bust = x.x, natural = x.nt,
                fromSplit = x.sp, splitAces = x.sa, doubled = x.db, result = x.r, payout = x.p,
            }
        end
        g.seats[i] = {
            name = s.n, chips = s.c or 0, bet = s.b or 0, out = s.o, left = s.l, insurance = s.i, hands = hands,
        }
    end
    return g
end

---------------------------------------------------------------------------
-- Incoming messages
---------------------------------------------------------------------------

local function sendError(name, err)
    if err then ns.Net.Send(name, { t = "err", m = err }) end
end

local HOST_HANDLERS = {}

function HOST_HANDLERS.accept(game, sender)
    if not T.invites[sender] then return end
    T.invites[sender] = nil
    if game.phase ~= "lobby" then
        return ns.Net.Send(sender, { t = "denied", m = "The game already started." })
    end
    local ok, err = game:AddPlayer(sender)
    if not ok then
        ns.Net.Send(sender, { t = "denied", m = err })
        queueFlush()
    end
end

function HOST_HANDLERS.decline(_, sender, msg)
    if not T.invites[sender] then return end
    T.invites[sender] = nil
    ns.Dispatch("declined", { name = sender, why = msg.m })
    queueFlush()
end

function HOST_HANDLERS.bet(game, sender, msg)
    local ok, err = game:PlaceBet(sender, tonumber(msg.a))
    if not ok then return sendError(sender, err) end
    if game:AllBetsIn() then game:Deal() end
end

function HOST_HANDLERS.act(game, sender, msg)
    local _, err = game:Act(sender, tostring(msg.a))
    sendError(sender, err)
end

function HOST_HANDLERS.ins(game, sender, msg)
    local _, err = game:Insure(sender, msg.v == true)
    sendError(sender, err)
end

function HOST_HANDLERS.leave(game, sender)
    T.invites[sender] = nil
    game:RemovePlayer(sender)
    queueFlush()
end

function HOST_HANDLERS.sync(game, sender)
    ns.Net.Send(sender, { t = "upd", s = T.Snapshot(game), e = {} })
end

local function hostMessage(msg, sender)
    local game = ns.game
    if not game then return end
    local handler = HOST_HANDLERS[msg.t]
    if not handler then return end
    if msg.t ~= "accept" and msg.t ~= "decline" then
        local seat = game:FindSeat(sender)
        if not seat or seat.left then return end
    end
    handler(game, sender, msg)
end

local function clientMessage(msg, sender)
    if msg.t == "upd" and type(msg.s) == "table" then
        ns.game = T.Mirror(msg.s)
        T.deadline = msg.s.tl and (GetTime() + msg.s.tl) or nil
        for _, e in ipairs(msg.e or {}) do
            if type(e) == "table" and type(e[1]) == "string" then ns.Dispatch(e[1], e[2] or {}) end
        end
        ns.Dispatch("sync", {})
        if ns.game.phase == "over" then ns.role, ns.hostName = nil, nil end
    elseif msg.t == "close" then
        if ns.game then ns.game.phase = "over" end
        ns.role, ns.hostName, T.deadline = nil, nil, nil
        ns.Dispatch("over", { reason = "closed" })
    elseif msg.t == "denied" then
        ns.role, ns.hostName, ns.game = nil, nil, nil
        ns.Dispatch("denied", { name = sender, why = msg.m })
    elseif msg.t == "err" then
        ns.Dispatch("error", { message = tostring(msg.m) })
    end
end

function T.OnMessage(msg, sender)
    if msg.t == "invite" then
        return T.OnInvite(sender, msg)
    end
    if ns.role == "host" then
        hostMessage(msg, sender)
    elseif ns.role == "client" and sender == ns.hostName then
        clientMessage(msg, sender)
    end
end

---------------------------------------------------------------------------
-- Invites
---------------------------------------------------------------------------

function T.OnInvite(sender, msg)
    if ns.IsPlaying() or T.pendingInvite then
        return ns.Net.Send(sender, { t = "decline", m = me() .. " is already at a table." })
    end
    if msg.v ~= ns.VERSION then
        ns.Net.Send(sender, { t = "decline", m = ("%s has Forever21 %s, you have %s. Both need the same version.")
            :format(me(), ns.VERSION, tostring(msg.v)) })
        return ns.Dispatch("inviteMismatch", { name = sender, theirs = tostring(msg.v) })
    end
    T.pendingInvite = sender
    T.rules = type(msg.r) == "table" and msg.r or nil
    ns.Dispatch("invited", { name = sender })
    if StaticPopup_Show then StaticPopup_Show("FOREVER21_INVITE", sender) end
end

function ns.AcceptInvite()
    local host = T.pendingInvite
    if not host then return nil, "You have no invite." end
    T.pendingInvite = nil
    ns.role, ns.hostName, ns.game = "client", host, nil
    ns.Net.Send(host, { t = "accept" })
    ns.Dispatch("newGame", {})
    ns.Dispatch("joining", { name = host })
    return true
end

function ns.DeclineInvite()
    local host = T.pendingInvite
    if not host then return nil, "You have no invite." end
    T.pendingInvite = nil
    ns.Net.Send(host, { t = "decline" })
    return true
end

if StaticPopupDialogs then
    StaticPopupDialogs.FOREVER21_INVITE = {
        text = "%s invites you to play blackjack (Forever21).",
        button1 = ACCEPT or "Accept",
        button2 = DECLINE or "Decline",
        OnAccept = function() ns.AcceptInvite(); if ns.UI then ns.UI:Show() end end,
        OnCancel = function(_, _, reason)
            if reason ~= "override" then ns.DeclineInvite() end
        end,
        timeout = INVITE_SECONDS - 5,
        whileDead = true,
        hideOnEscape = true,
    }
end

---------------------------------------------------------------------------
-- Actions. Each returns true, or nil plus a reason a player can read.
-- The window and /f21 both call these.
---------------------------------------------------------------------------

local function needGame()
    if not ns.IsPlaying() then return nil, "No game running. Press New Game or type /f21 host." end
    return true
end

-- Opens a table in the lobby with you seated. Invite players, then start.
function ns.HostTable()
    if ns.IsPlaying() then return nil, "You're already at a table." end
    ns.role, ns.hostName = "host", me()
    T.invites, T.outbox = {}, {}
    T.StopTimer()
    ns.game = Game.New({ onEvent = T.HostEvent })
    ns.Dispatch("newGame", {})
    ns.game:AddPlayer(me())
    return true
end

function ns.StartGame()
    if not ns.IsHost() or not ns.game then return nil, "Only the table owner can start." end
    if ns.game.phase ~= "lobby" then return nil, "The game already started." end
    for name in pairs(T.invites) do ns.Net.Send(name, { t = "denied", m = "The game started without you." }) end
    T.invites = {}
    return ns.game:Start()
end

-- Solo play is a table with nobody invited.
function ns.StartSolo()
    local ok, err = ns.HostTable()
    if not ok then return nil, err end
    return ns.StartGame()
end

function ns.Invite(name)
    if not name or name == "" then
        name = UnitExists and UnitExists("target") and UnitName("target") or nil
        if not name then return nil, "Type a name or target a player to invite." end
    end
    name = ns.ShortName(name)
    name = name:sub(1, 1):upper() .. name:sub(2):lower()
    if not ns.IsHost() or not ns.game then
        local ok, err = ns.HostTable()
        if not ok then return nil, err end
    end
    local game = ns.game
    if game.phase ~= "lobby" then return nil, "You can only invite before the game starts." end
    if name == me() then return nil, "You're already at the table." end
    if game:FindSeat(name) then return nil, name .. " is already seated." end
    if T.invites[name] then return nil, name .. " is already invited." end
    local count = #game.seats
    for _ in pairs(T.invites) do count = count + 1 end
    if count >= game.rules.maxSeats then return nil, "The table is full." end

    T.invites[name] = true
    ns.Net.Send(name, { t = "invite", v = ns.VERSION })
    ns.Dispatch("inviteSent", { name = name })
    C_Timer.After(INVITE_SECONDS, function()
        if T.invites[name] and ns.game == game then
            T.invites[name] = nil
            ns.Dispatch("inviteExpired", { name = name })
            queueFlush()
        end
    end)
    queueFlush()
    return true
end

function ns.Bet(amount)
    local ok, err = needGame()
    if not ok then return nil, err end
    if ns.role == "client" then
        local seat = ns.MySeat()
        if ns.game.phase ~= "betting" then return nil, "Betting is closed." end
        if not seat or seat.out then return nil, "You can't bet now." end
        ok, err = ns.Rules.CheckBet(ns.game.rules, amount, seat.chips + seat.bet)
        if not ok then return nil, err end
        ns.Net.Send(ns.hostName, { t = "bet", a = amount })
        return true
    end
    ok, err = ns.game:PlaceBet(me(), amount)
    if not ok then return nil, err end
    if ns.game:AllBetsIn() then return ns.game:Deal() end
    return true
end

function ns.Act(action)
    local ok, err = needGame()
    if not ok then return nil, err end
    if ns.role == "client" then
        local seat = ns.game:CurrentHand()
        if not seat or seat.name ~= me() then return nil, "It isn't your turn." end
        ns.Net.Send(ns.hostName, { t = "act", a = action })
        return true
    end
    return ns.game:Act(me(), action)
end

function ns.Insure(take)
    local ok, err = needGame()
    if not ok then return nil, err end
    if ns.role == "client" then
        ns.Net.Send(ns.hostName, { t = "ins", v = take and true or false })
        return true
    end
    return ns.game:Insure(me(), take)
end

-- Leaving: a player gives up their seat; the owner leaving closes the table.
function ns.Quit()
    if ns.role == "client" then
        ns.Net.Send(ns.hostName, { t = "leave" })
        ns.role, ns.hostName, ns.game, T.deadline = nil, nil, nil, nil
        ns.Dispatch("leftTable", {})
        return true
    end
    local ok, err = needGame()
    if not ok then return nil, err end
    local game = ns.game
    if #others(game) == 0 and game.phase ~= "lobby" then
        return game:RemovePlayer(me())
    end
    for _, name in ipairs(others(game)) do ns.Net.Send(name, { t = "close" }) end
    for name in pairs(T.invites) do ns.Net.Send(name, { t = "denied", m = "The table closed." }) end
    T.invites = {}
    T.StopTimer()
    game:Close()
    return true
end
