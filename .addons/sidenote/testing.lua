---@meta
---LSP-only definitions for the globals `spec/runner.lua` injects into every
---spec file, implemented there and in `spec/assert.lua`.
---
---Every `assert.*` helper throws on failure, so a failing assertion ends its
---`it` block and nothing after it in that test runs.

---Group related tests.
---
---Groups nest; a nested group's reported name is its parents' names joined
---with its own.
---@param name string
---@param fn fun()
function describe(name, fn) end

---Declare a single test.
---@param name string
---@param fn fun()
function it(name, fn) end

---Run before every test in the enclosing group, outermost group first.
---@param fn fun()
function before_each(fn) end

---Run after every test in the enclosing group, innermost group first.
---@param fn fun()
function after_each(fn) end

---Test-scope `assert`: the spec assertion surface plus the builtin's callable
---form, so `assert(io.open(path))` still works.
---@class spec.AssertGlobal
---@operator call:any
assert = {}

---Assert `actual` equals `expected`.
---@param actual any
---@param expected any
---@param msg? string
function assert.eq(actual, expected, msg) end

---Assert `actual` does not equal `expected`.
---@param actual any
---@param expected any
---@param msg? string
function assert.neq(actual, expected, msg) end

---Assert `actual` is structurally equal to `expected`, entry counts included.
---@param actual any
---@param expected any
---@param msg? string
function assert.eq_deep(actual, expected, msg) end

---Assert value is truthy.
---@param v any
---@param msg? string
function assert.truthy(v, msg) end

---Assert value is falsy.
---@param v any
---@param msg? string
function assert.falsy(v, msg) end

---Assert a > b.
---@param a number
---@param b number
---@param msg? string
function assert.gt(a, b, msg) end

---Assert a < b.
---@param a number
---@param b number
---@param msg? string
function assert.lt(a, b, msg) end

---Assert a >= b.
---@param a number
---@param b number
---@param msg? string
function assert.gte(a, b, msg) end

---Assert a <= b.
---@param a number
---@param b number
---@param msg? string
function assert.lte(a, b, msg) end

---Assert string contains substring, matched literally.
---@param str string?
---@param sub string
---@param msg? string
function assert.contains(str, sub, msg) end

---Assert `str` matches a Lua pattern.
---
---Escape metacharacters with `%`, or reach for `contains` when a literal match
---is what you mean. Paths are a common trap: `-` and `.` are both pattern
---syntax.
---@param str string?
---@param pattern string
---@param msg? string
function assert.match(str, pattern, msg) end

---Assert value is nil.
---@param v any
---@param msg? string
function assert.is_nil(v, msg) end

---Assert value is not nil, returning it so callers can check and bind at once.
---@generic T
---@param v T?
---@param msg? string
---@return T
function assert.not_nil(v, msg) end

---Assert calling `fn` raises an error.
---@param fn fun()
---@param msg? string
function assert.throws(fn, msg) end

---Assert value is of the given type.
---@param v any
---@param expected_type string
---@param msg? string
function assert.is_type(v, expected_type, msg) end
