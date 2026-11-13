-- Serialize.lua: turns Lua values into compact strings for addon messages and
-- back. Pure Lua, no game API. Short plain words (names, keys, cards) are
-- written as 'word; other strings are length-prefixed, so no escaping is
-- needed. Keys and values can be strings, numbers, booleans, or tables.
local _, ns = ...

local Serialize = {}
ns.Serialize = Serialize

local function encode(v, out)
    local t = type(v)
    if t == "string" then
        if #v > 0 and #v <= 60 and not v:find("[^%w_]") then
            out[#out + 1] = "'" .. v
        else
            out[#out + 1] = "$" .. #v .. ":" .. v
        end
    elseif t == "number" then
        if v == math.floor(v) and v > -1e15 and v < 1e15 then
            out[#out + 1] = "#" .. string.format("%d", v) .. ";"
        else
            out[#out + 1] = "#" .. tostring(v) .. ";"
        end
    elseif t == "boolean" then
        out[#out + 1] = v and "+" or "-"
    elseif t == "table" then
        -- Lists (keys 1..n, no gaps) skip the keys: [a b c]
        local n, count = #v, 0
        for _ in pairs(v) do count = count + 1 end
        if n > 0 and count == n then
            out[#out + 1] = "["
            for i = 1, n do encode(v[i], out) end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            for k, x in pairs(v) do
                encode(k, out)
                encode(x, out)
            end
            out[#out + 1] = "}"
        end
    else
        out[#out + 1] = "!"
    end
end

function Serialize.Encode(v)
    local out = {}
    encode(v, out)
    return table.concat(out)
end

local MAX_DEPTH = 20

local function decode(s, i, depth)
    if depth > MAX_DEPTH then error("too deep") end
    local c = s:sub(i, i)
    if c == "'" then
        local word = s:match("^[%w_]+", i + 1)
        if not word then error("bad word") end
        return word, i + 1 + #word
    elseif c == "$" then
        local colon = s:find(":", i, true)
        local len = colon and tonumber(s:sub(i + 1, colon - 1))
        if not len or colon + len > #s then error("bad string") end
        return s:sub(colon + 1, colon + len), colon + len + 1
    elseif c == "#" then
        local semi = s:find(";", i, true)
        local n = semi and tonumber(s:sub(i + 1, semi - 1))
        if not n then error("bad number") end
        return n, semi + 1
    elseif c == "+" then
        return true, i + 1
    elseif c == "-" then
        return false, i + 1
    elseif c == "!" then
        return nil, i + 1
    elseif c == "[" then
        local t = {}
        i = i + 1
        while s:sub(i, i) ~= "]" do
            if i > #s then error("unterminated list") end
            local v
            v, i = decode(s, i, depth + 1)
            t[#t + 1] = v
        end
        return t, i + 1
    elseif c == "{" then
        local t = {}
        i = i + 1
        while s:sub(i, i) ~= "}" do
            if i > #s then error("unterminated table") end
            local k, v
            k, i = decode(s, i, depth + 1)
            v, i = decode(s, i, depth + 1)
            if k == nil then error("nil key") end
            t[k] = v
        end
        return t, i + 1
    end
    error("bad data")
end

-- Returns the value, or nil if the string isn't valid.
function Serialize.Decode(s)
    if type(s) ~= "string" then return nil end
    local ok, v, i = pcall(decode, s, 1, 0)
    if not ok or i ~= #s + 1 then return nil end
    return v
end

-- Deep copy of plain data (no metatables, no cycles).
function Serialize.Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Serialize.Copy(x) end
    return t
end

return Serialize
