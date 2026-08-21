-- Regenerate README.md's reference blocks and doc/sidenote.txt from source.
--
-- Run with `make docs`. CI runs the same target and fails on any diff, so the
-- committed files cannot drift from the code they describe.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = ("%s/?.lua;%s/lua/?.lua;%s"):format(root, root, package.path)

local source = require("scripts.source")
local vimdoc = require("scripts.vimdoc")

local README = root .. "/README.md"
local HELP = root .. "/doc/sidenote.txt"

---@param path string
---@return string[]
local function read(path)
    local out = {}
    for line in io.lines(path) do
        out[#out + 1] = line
    end
    return out
end

---@param path string
---@param lines string[]
local function write(path, lines)
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(lines, "\n") .. "\n")
    fh:close()
end

---@param path string
---@param lines string[]
---@return boolean
local function matches(path, lines)
    return table.concat(read(path), "\n") == table.concat(lines, "\n")
end

---@param lang string fence language, or "" for none
---@param lines string[]
---@return string[]
local function fenced(lang, lines)
    local out = { "```" .. lang }
    vim.list_extend(out, lines)
    out[#out + 1] = "```"
    return out
end

---@return string[]
local function config_block()
    local body = source.section(root .. "/lua/sidenote/config.lua", "^%s*return {", "^%s*}$")
    local out = { "vim.g.sidenote = {" }
    for _, line in ipairs(body) do
        out[#out + 1] = (line:gsub("^        ", "    "))
    end
    out[#out + 1] = "}"
    return fenced("lua", out)
end

---@return string[]
local function commands_block()
    local FENCE_WIDTH = 68 -- Widest line a help file's indented, never-rewrapped fence fits

    local names = source.subcommands(root .. "/plugin/sidenote.lua")
    local lines, line = {}, ":Sidenote"
    for i, name in ipairs(names) do
        local sep = i == 1 and " " or " | "
        if #line + #sep + #name > FENCE_WIDTH then
            lines[#lines + 1] = line
            line = "          | " .. name
        else
            line = line .. sep .. name
        end
    end
    lines[#lines + 1] = line
    return fenced("vim", lines)
end

---@return string[]
local function mappings_block()
    local out = { "| mapping | does |", "|---|---|" }
    for _, map in ipairs(source.mappings(root .. "/plugin/sidenote.lua")) do
        out[#out + 1] = ("| `%s` | %s |"):format(map.name, map.desc)
    end
    return out
end

---@return string[]
local function api_block()
    local out = {}
    for _, fn in ipairs(source.functions(root .. "/lua/sidenote/init.lua")) do
        local args = {}
        for _, param in ipairs(fn.params) do
            args[#args + 1] = "{" .. param:match("^([%w_]+)") .. "}"
        end
        out[#out + 1] = ("`sidenote.%s(%s)`"):format(fn.name, table.concat(args, ", "))
        out[#out + 1] = ""
        out[#out + 1] = fn.summary
        out[#out + 1] = ""
    end
    return out
end

---@return string[]
local function statuses_block()
    local names = require("sidenote.core.resolve").STATUS_NAMES
    return fenced("", { table.concat(names, " | ") })
end

local BLOCKS = {
    config = config_block,
    commands = commands_block,
    mappings = mappings_block,
    api = api_block,
    statuses = statuses_block,
}

---Replace every `gen:` region with what its source says now.
---
---A region whose name is unknown, or which is never closed, is an error rather
---than a silent no-op: a marker that stops matching would quietly freeze that
---part of the docs.
---@param lines string[]
---@return string[]
local function expand(lines)
    local out, skipping, seen = {}, nil, {}

    for _, line in ipairs(lines) do
        local open = line:match("^<!%-%- gen:(%w+) %-%->$")
        local close = line:match("^<!%-%- /gen:(%w+) %-%->$")

        if open then
            assert(BLOCKS[open], "unknown generated block: " .. open)
            seen[open] = true
            skipping = open
            out[#out + 1] = line
            vim.list_extend(out, BLOCKS[open]())
        elseif close then
            assert(skipping == close, "mismatched marker: " .. close)
            skipping = nil
            out[#out + 1] = line
        elseif not skipping then
            out[#out + 1] = line
        end
    end

    assert(not skipping, "unclosed generated block: " .. tostring(skipping))
    for name in pairs(BLOCKS) do
        assert(seen[name], "README has no gen: block for " .. name)
    end
    return out
end

local readme = expand(read(README))
local help = vimdoc.render(readme, {
    project = "sidenote",
    description = "Notes on your code, stored outside it",
    version = "NVIM v0.11.0",
})

-- Compare bytes, not a VCS diff, so other changes in the tree cannot skew it
if _G.arg[1] == "--check" then
    local stale = {}
    for path, wanted in pairs({ [README] = readme, [HELP] = help }) do
        if not matches(path, wanted) then
            stale[#stale + 1] = path:sub(#root + 2)
        end
    end
    if #stale > 0 then
        io.stderr:write(("stale: %s\nrun `make docs`\n"):format(table.concat(stale, ", ")))
        os.exit(1)
    end
    print("docs are up to date")
    os.exit(0)
end

write(README, readme)
write(HELP, help)
print(("wrote %s and %s"):format(README:sub(#root + 2), HELP:sub(#root + 2)))
