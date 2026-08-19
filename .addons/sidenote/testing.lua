---@meta
---LSP-only definitions for the globals `spec/runner.lua` injects into every
---spec file. The runtime implementations live at `spec/runner.lua` and
---`spec/assert.lua`; this file mirrors their surface so editors resolve
---`describe`, `it`, and `assert.eq` inside `spec/`.
---
---IMPORTANT: every `assert.*` helper is throw-on-failure. On failure it raises
---a Lua error at the test-body call site; the runner catches it and reports the
---test as failed. Later assertions in the same `it` block do not run.

---Group related tests. Nests arbitrarily; a nested group's reported name is its
---parents' names joined with its own.
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

---Assert two values are equal. Actual first, expected second.
---@param a any
---@param b any
---@param msg? string
function assert.eq(a, b, msg) end

---Assert two values are not equal.
---@param a any
---@param b any
---@param msg? string
function assert.neq(a, b, msg) end

---Assert deep structural equality, including matching entry counts.
---@param a any
---@param b any
---@param msg? string
function assert.eq_deep(a, b, msg) end

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
---@param str string
---@param sub string
---@param msg? string
function assert.contains(str, sub, msg) end

---Assert string matches a Lua pattern.
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
---@param fn function
---@param msg? string
function assert.throws(fn, msg) end

---Assert value is of the given type.
---@param v any
---@param expected_type string
---@param msg? string
function assert.is_type(v, expected_type, msg) end
