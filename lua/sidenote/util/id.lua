---ULID generation.
---
---A ULID is a 48-bit millisecond timestamp followed by 80 bits of randomness,
---rendered in Crockford base32. The encoding sorts lexicographically by
---creation time, so any listing of ids reads chronologically.
---@class sidenote.util.id
local M = {}

---Crockford base32: no I, L, O or U, so an id cannot be misread aloud.
M.ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

local TIME_CHARS = 10
local RANDOM_CHARS = 16

---Return the current time as Unix epoch milliseconds.
---
---`vim.uv.now()` is loop time, which only sorts correctly within one session.
---@return integer
local function now_ms()
    local seconds, microseconds = vim.uv.gettimeofday()
    return seconds * 1000 + math.floor(microseconds / 1000)
end

---Draw one uniform digit below `n`.
---
---Unseeded `math.random` repeats the same sequence in every process.
---@param n integer exclusive upper bound, uniform only for a divisor of 256
---@return integer
local function default_rand(n)
    return vim.uv.random(1):byte(1) % n
end

---Encode `value` as exactly `width` base32 digits, most significant first.
---@param value integer
---@param width integer
---@return string
local function encode_int(value, width)
    local out = {}
    for i = width, 1, -1 do
        local digit = value % 32
        out[i] = M.ALPHABET:sub(digit + 1, digit + 1)
        value = math.floor(value / 32)
    end
    return table.concat(out)
end

---@class sidenote.util.id.Opts
---@field now_ms? integer Unix epoch millisecond to stamp, defaults to the current time
---@field rand? fun(n: integer): integer called once per random digit to return a value below n

---Mint a new ULID.
---@param opts? sidenote.util.id.Opts
---@return string ulid
function M.new(opts)
    opts = opts or {}
    local millis = opts.now_ms or now_ms()
    local rand = opts.rand or default_rand

    local out = { encode_int(millis, TIME_CHARS) }
    for _ = 1, RANDOM_CHARS do
        local digit = rand(32)
        out[#out + 1] = M.ALPHABET:sub(digit + 1, digit + 1)
    end
    return table.concat(out)
end

return M
