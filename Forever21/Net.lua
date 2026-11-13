-- Net.lua: hidden addon whispers between players. Messages are Lua tables,
-- serialized, split into chunks that fit the 255-byte limit, and sent through
-- a small queue so a burst of updates doesn't trip the server's spam limits.
local _, ns = ...

local Net = {}
ns.Net = Net

local CHUNK = 230      -- payload bytes per whisper, leaving room for the header
local RATE = 1200      -- bytes per second the queue sends on average
local BURST = 4000     -- bytes it can send at once
local MAX_PARTS = 40   -- refuse anything that would be more than ~9 KB

local queue = {}
local budget = BURST
local lastRefill
local pumping = false
local seq = 0
local inbox = {}

-- "Name-Realm" and "Name" both become "Name". Tables are same-realm only.
function ns.ShortName(name)
    if not name then return nil end
    return (name:gsub("%-.*$", ""))
end

local function rawSend(text, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(ns.PREFIX, text, "WHISPER", target)
    elseif SendAddonMessage then
        SendAddonMessage(ns.PREFIX, text, "WHISPER", target)
    end
end

-- The queue holds whole messages. A message is cut into chunks only when it
-- reaches the front, so a newer table update for a player who is still waiting
-- can replace the older one instead of piling up behind it.
local function encode(m)
    local data = ns.Serialize.Encode(m.msg)
    seq = seq % 9999 + 1
    local parts = math.max(1, math.ceil(#data / CHUNK))
    m.chunks = {}
    for i = 1, parts do
        local header = ("%d~%d~%d~"):format(seq, i, parts)
        m.chunks[i] = header .. data:sub((i - 1) * CHUNK + 1, i * CHUNK)
    end
    m.nextChunk = 1
end

local function pump()
    local now = GetTime()
    budget = math.min(BURST, budget + (now - (lastRefill or now)) * RATE)
    lastRefill = now
    while queue[1] do
        local m = queue[1]
        if not m.chunks then encode(m) end
        local text = m.chunks[m.nextChunk]
        if budget < #text then break end
        budget = budget - #text
        rawSend(text, m.target)
        m.nextChunk = m.nextChunk + 1
        if m.nextChunk > #m.chunks then table.remove(queue, 1) end
    end
    if queue[1] then
        C_Timer.After(0.1, pump)
    else
        pumping = false
    end
end

-- Sends a table to one player. A table update ("upd") waiting in the queue
-- for the same player takes the newer snapshot and keeps all the events.
function Net.Send(target, msg)
    if msg.t == "upd" then
        for _, m in ipairs(queue) do
            if m.target == target and not m.chunks and m.msg.t == "upd" then
                m.msg.s = msg.s
                for _, e in ipairs(msg.e or {}) do
                    m.msg.e[#m.msg.e + 1] = e
                end
                return
            end
        end
        msg = { t = msg.t, s = msg.s, e = { unpack(msg.e or {}) } }
    end
    queue[#queue + 1] = { target = target, msg = msg }
    if not pumping then
        pumping = true
        pump()
    end
end

-- Whispers from one sender arrive in order, so each sender has one message
-- being put back together at a time.
function Net.Receive(text, sender)
    local s, i, n, chunk = text:match("^(%d+)~(%d+)~(%d+)~(.*)$")
    if not s then return end
    s, i, n = tonumber(s), tonumber(i), tonumber(n)
    if n < 1 or n > MAX_PARTS or i < 1 or i > n then return end
    local box = inbox[sender]
    if not box or box.seq ~= s then
        box = { seq = s, parts = {}, got = 0 }
        inbox[sender] = box
    end
    if not box.parts[i] then
        box.parts[i] = chunk
        box.got = box.got + 1
    end
    if box.got == n then
        inbox[sender] = nil
        local msg = ns.Serialize.Decode(table.concat(box.parts, "", 1, n))
        if type(msg) == "table" and ns.Table then
            ns.Table.OnMessage(msg, sender)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, text, _, sender)
    if prefix == ns.PREFIX and type(text) == "string" then
        local name = ns.ShortName(sender)
        if name and name ~= ns.PlayerName() then Net.Receive(text, name) end
    end
end)
