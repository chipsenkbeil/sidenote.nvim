-- Test runner. Run with `nvim -l spec/runner.lua [path ...]`, or `make test`.
--
-- Follows doug-game's harness shape: `describe` / `it` globals plus an
-- `assert` table, with nesting tracked by a stack

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;%s/?.lua;%s/?/init.lua;%s"):format(
    root,
    root,
    root,
    root,
    package.path
)

---@class spec.Context
---@field name string display name of this group, empty for the root
---@field before function[] hooks run before each test in the group
---@field after function[] hooks run after each test in the group

---@class spec.Test
---@field name string display name of this test
---@field fn function test body
---@field context spec.Context[] enclosing groups, outermost first

---@type spec.Context[]
local stack = { { name = "", before = {}, after = {} } }

---@type spec.Test[]
local tests = {}

_G.assert = dofile(root .. "/spec/assert.lua")

---@param name string
---@param fn function
function _G.describe(name, fn)
    stack[#stack + 1] = { name = name, before = {}, after = {} }
    local ok, err = pcall(fn)
    stack[#stack] = nil
    if not ok then
        error(err, 0)
    end
end

---@param name string
---@param fn function
function _G.it(name, fn)
    local context = {}
    for i, entry in ipairs(stack) do
        context[i] = entry
    end
    tests[#tests + 1] = { name = name, fn = fn, context = context }
end

---@param fn function
function _G.before_each(fn)
    local top = stack[#stack]
    top.before[#top.before + 1] = fn
end

---@param fn function
function _G.after_each(fn)
    local top = stack[#stack]
    top.after[#top.after + 1] = fn
end

---@param test spec.Test
---@return string
local function full_name(test)
    local parts = {}
    for _, entry in ipairs(test.context) do
        if entry.name ~= "" then
            parts[#parts + 1] = entry.name
        end
    end
    parts[#parts + 1] = test.name
    return table.concat(parts, " ")
end

---@param targets string[]
---@return string[]
local function spec_files(targets)
    local found = {}
    for _, target in ipairs(targets) do
        if vim.fn.isdirectory(target) == 1 then
            vim.list_extend(found, vim.fn.glob(target .. "/**/*_spec.lua", false, true))
        else
            found[#found + 1] = target
        end
    end
    if #targets == 0 then
        found = vim.fn.glob(root .. "/spec/**/*_spec.lua", false, true)
    end
    table.sort(found)
    return found
end

local targets = {}
for i = 1, #(_G.arg or {}) do
    targets[#targets + 1] = _G.arg[i]
end

for _, file in ipairs(spec_files(targets)) do
    local chunk, load_err = loadfile(file)
    if not chunk then
        io.stderr:write(("failed to load %s: %s\n"):format(file, load_err))
        os.exit(1)
    end
    local ok, err = pcall(chunk)
    if not ok then
        io.stderr:write(("failed to collect %s: %s\n"):format(file, err))
        os.exit(1)
    end
end

local passed, failures = 0, {}
for _, test in ipairs(tests) do
    for _, entry in ipairs(test.context) do
        for _, fn in ipairs(entry.before) do
            fn()
        end
    end

    local ok, err = xpcall(test.fn, function(message)
        return debug.traceback(tostring(message), 2)
    end)

    for i = #test.context, 1, -1 do
        for _, fn in ipairs(test.context[i].after) do
            fn()
        end
    end

    if ok then
        passed = passed + 1
    else
        failures[#failures + 1] = { name = full_name(test), err = err }
    end
end

for _, failure in ipairs(failures) do
    io.write(("\nFAIL  %s\n%s\n"):format(failure.name, failure.err))
end

io.write(("\n%d passed, %d failed\n"):format(passed, #failures))
os.exit(#failures == 0 and 0 or 1)
