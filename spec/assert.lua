---Assertions for the test suite.
---
---Ported from doug-game's `testing/assert.lua` so the vocabulary is the same
---across projects.
---@class spec.Assert
local M = {}

---Format a value for inclusion in an error message.
---@param v any
---@return string
local function fmt(v)
    if type(v) == "string" then
        return '"' .. v .. '"'
    end
    if type(v) == "table" then
        return vim.inspect(v)
    end
    return tostring(v)
end

---Compose an error message from the caller's optional `msg` and the
---assertion's `detail`.
---@param msg? string
---@param detail string
---@return string
local function compose(msg, detail)
    if msg then
        return msg .. " (" .. detail .. ")"
    end
    return detail
end

-- Error level that blames the test body, two frames above the raise
local TEST_BODY_LEVEL = 3

---Raise on failure.
---@param ok boolean
---@param msg string
local function check(ok, msg)
    if not ok then
        error(msg, TEST_BODY_LEVEL)
    end
end

---Assert `actual` equals `expected`.
---@param actual any
---@param expected any
---@param msg? string
function M.eq(actual, expected, msg)
    check(actual == expected, compose(msg, "got " .. fmt(actual) .. ", expected " .. fmt(expected)))
end

---Assert `actual` does not equal `expected`.
---@param actual any
---@param expected any
---@param msg? string
function M.neq(actual, expected, msg)
    check(
        actual ~= expected,
        compose(msg, "got " .. fmt(actual) .. ", expected ~= " .. fmt(expected))
    )
end

---Assert value is truthy.
---@param v any
---@param msg? string
function M.truthy(v, msg)
    check(v and true or false, compose(msg, "expected truthy, got " .. fmt(v)))
end

---Assert value is falsy.
---@param v any
---@param msg? string
function M.falsy(v, msg)
    check(not v, compose(msg, "expected falsy, got " .. fmt(v)))
end

---Assert a > b.
---@param a number
---@param b number
---@param msg? string
function M.gt(a, b, msg)
    check(a > b, compose(msg, "got " .. fmt(a) .. ", expected > " .. fmt(b)))
end

---Assert a < b.
---@param a number
---@param b number
---@param msg? string
function M.lt(a, b, msg)
    check(a < b, compose(msg, "got " .. fmt(a) .. ", expected < " .. fmt(b)))
end

---Assert a >= b.
---@param a number
---@param b number
---@param msg? string
function M.gte(a, b, msg)
    check(a >= b, compose(msg, "got " .. fmt(a) .. ", expected >= " .. fmt(b)))
end

---Assert a <= b.
---@param a number
---@param b number
---@param msg? string
function M.lte(a, b, msg)
    check(a <= b, compose(msg, "got " .. fmt(a) .. ", expected <= " .. fmt(b)))
end

---Assert string contains substring (literal, no patterns).
---@param str string?
---@param sub string
---@param msg? string
function M.contains(str, sub, msg)
    local ok = type(str) == "string" and str:find(sub, 1, true) ~= nil
    check(ok, compose(msg, fmt(str) .. " does not contain " .. fmt(sub)))
end

---Assert `str` matches a Lua pattern.
---
---Escape metacharacters with `%`, or reach for `contains` when a literal match
---is what you mean. Paths are a common trap: `-` and `.` are both pattern
---syntax.
---@param str string?
---@param pattern string
---@param msg? string
function M.match(str, pattern, msg)
    local ok = type(str) == "string" and str:find(pattern) ~= nil
    check(ok, compose(msg, fmt(str) .. " does not match " .. fmt(pattern)))
end

---Assert value is nil.
---@param v any
---@param msg? string
function M.is_nil(v, msg)
    check(v == nil, compose(msg, "expected nil, got " .. fmt(v)))
end

---Assert value is not nil.
---
---Returns the value, so a caller can check and bind in one step:
---`local x = assert.not_nil(get_x())`.
---@generic T
---@param v T?
---@param msg? string
---@return T
function M.not_nil(v, msg)
    check(v ~= nil, compose(msg, "expected not nil"))
    return v
end

---Assert calling `fn` raises an error.
---@param fn fun()
---@param msg? string
function M.throws(fn, msg)
    local ok = pcall(fn)
    check(not ok, compose(msg, "expected fn to throw, but it returned normally"))
end

---Assert value is of given type.
---@param v any
---@param expected_type string
---@param msg? string
function M.is_type(v, expected_type, msg)
    check(
        type(v) == expected_type,
        compose(msg, "expected type " .. expected_type .. ", got " .. type(v))
    )
end

---Compare `a` and `b` structurally, including their entry counts.
---@param a any
---@param b any
---@return boolean
local function deep_equal(a, b)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    local count_a = 0
    for k, v in pairs(a) do
        count_a = count_a + 1
        if not deep_equal(v, b[k]) then
            return false
        end
    end
    local count_b = 0
    for _ in pairs(b) do
        count_b = count_b + 1
    end
    return count_a == count_b
end

---Assert `actual` is structurally equal to `expected`, entry counts included.
---@param actual any
---@param expected any
---@param msg? string
function M.eq_deep(actual, expected, msg)
    check(
        deep_equal(actual, expected),
        compose(msg, "got " .. fmt(actual) .. ", expected " .. fmt(expected))
    )
end

-- Callable, so Lua's builtin form still works inside a spec:
-- `local fh = assert(io.open(path, "r"))`
setmetatable(M, {
    __call = function(_, value, ...)
        if not value then
            error((select(1, ...)) or "assertion failed!", 2)
        end
        return value, ...
    end,
})

return M
