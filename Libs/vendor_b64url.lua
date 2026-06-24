-- Pure-Lua base64url decoder (no padding, URL-safe).
-- Used by raid_assignments_decoder to unpack !iddqd-ra! strings.
-- Compatible with WoW's Lua 5.1 (no `goto`, no bitops).
--
-- The `...` capture is how WoW addon files receive the addon's private
-- namespace table (second return). It's nil under the Lua-CLI test
-- harness, so we tolerate that gracefully.
local ADDON_NAME, iddqd_ns = ...
local b64url = {}

local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local LOOKUP = {}
for i = 1, #CHARS do LOOKUP[CHARS:sub(i, i)] = i - 1 end

function b64url.encode(data)
    if type(data) ~= "string" then return nil end
    local out = {}
    local i = 1
    while i <= #data do
        local a = data:byte(i) or 0
        local b = data:byte(i + 1) or 0
        local c = data:byte(i + 2) or 0
        local n = a * 65536 + b * 256 + c
        out[#out + 1] = CHARS:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        out[#out + 1] = CHARS:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        if i + 1 <= #data then
            out[#out + 1] = CHARS:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        end
        if i + 2 <= #data then
            out[#out + 1] = CHARS:sub(n % 64 + 1, n % 64 + 1)
        end
        i = i + 3
    end
    return table.concat(out)
end

-- Decode `s` (URL-safe base64, padding optional) into a binary string.
-- Returns nil on invalid characters.
function b64url.decode(s)
    if type(s) ~= "string" then return nil end
    -- Strip any padding (URL-safe base64 typically omits it).
    s = s:gsub("=", "")
    -- Reject malformed encodings: a remainder of 1 sextet is impossible
    -- in valid base64 — every output byte requires at least 2 sextets.
    if #s % 4 == 1 then return nil end
    local out = {}
    local buf, bits = 0, 0
    for i = 1, #s do
        local v = LOOKUP[s:sub(i, i)]
        if not v then return nil end
        buf = buf * 64 + v
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            local byte = math.floor(buf / (2 ^ bits))
            out[#out + 1] = string.char(byte)
            buf = buf - byte * (2 ^ bits)
        end
    end
    return table.concat(out)
end

-- Module pattern used by both addon and test harness:
--   in WoW:   local b64url = iddqd.raid_assignments_b64url   (the addon-private
--             namespace, NOT the _G.iddqd global — there isn't one; the
--             top-level addon table lives at _G.iddqd)
--   in tests: local b64url = require('raid_assignments_vendor_b64url')
if type(iddqd_ns) == "table" then iddqd_ns.raid_assignments_b64url = b64url end
return b64url
