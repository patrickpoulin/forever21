-- Sound.lua: sound effects for game events, using sounds built into the game
-- client. Each effect lists a few sound names, and the first one this client
-- knows is played, so a missing sound is skipped instead of causing an error.
local _, ns = ...

local EFFECTS = {
    card = { "IG_ABILITY_PAGE_TURN", "IG_SPELLBOOK_OPEN" },
    chip = { "LOOT_WINDOW_COIN_SOUND", "MONEY_FRAME_OPEN" },
    turn = { "IG_CHARACTER_INFO_TAB", "IG_MAINMENU_OPTION_CHECKBOX_ON" },
    win = { "IG_QUEST_LIST_COMPLETE", "IG_QUEST_LIST_OPEN" },
    blackjack = { "LEVELUPSOUND", "IG_QUEST_LIST_COMPLETE" },
    lose = { "IG_QUEST_FAILED", "IG_PLAYER_INVITE_DECLINE" },
    push = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", "IG_MAINMENU_CLOSE" },
    bust = { "IG_PLAYER_INVITE_DECLINE", "IG_QUEST_FAILED" },
    gameWon = { "LEVELUPSOUND", "READY_CHECK" },
    gameLost = { "RAID_WARNING", "IG_QUEST_FAILED" },
}

function ns.PlayEffect(name)
    if not ns.db or ns.db.sound == false then return end
    if type(PlaySound) ~= "function" or type(SOUNDKIT) ~= "table" then return end
    for _, key in ipairs(EFFECTS[name] or {}) do
        local id = SOUNDKIT[key]
        if id then
            PlaySound(id, "SFX")
            return key
        end
    end
end

-- Net chips won or lost on a "result" event, insurance included.
function ns.NetResult(d)
    local net = -(d.insurance or 0) + (d.insurancePaid or 0)
    for _, r in ipairs(d.hands) do net = net + r.payout - r.bet end
    return net
end

ns.Listen(function(event, d)
    local me = ns.PlayerName()
    if event == "card" and d.name == me then
        ns.PlayEffect("card")
    elseif event == "dealerCard" then
        ns.PlayEffect("card")
    elseif event == "bet" and d.name == me then
        ns.PlayEffect("chip")
    elseif event == "turn" and d.name == me then
        ns.PlayEffect("turn")
    elseif event == "bust" and d.name == me then
        ns.PlayEffect("bust")
    elseif event == "result" and d.name == me then
        local net = ns.NetResult(d)
        if d.hands[1] and d.hands[1].result == "blackjack" and #d.hands == 1 then
            ns.PlayEffect("blackjack")
        elseif net > 0 then
            ns.PlayEffect("win")
        elseif net < 0 then
            ns.PlayEffect("lose")
        else
            ns.PlayEffect("push")
        end
    elseif event == "out" and d.name == me then
        ns.PlayEffect("gameLost")
    elseif event == "over" and d.winner == me then
        ns.PlayEffect("gameWon")
    end
end)
