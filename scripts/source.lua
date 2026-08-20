---@class sidenote.source.Fn
---@field name string function name, without the module prefix
---@field summary string one-line description from its doc comment
---@field params string[] `@param` lines, verbatim after the tag
---@field returns string[] `@return` lines, verbatim after the tag

---Reads reference material out of the plugin's own source.
---
---Everything here is derived, never authored: config keys, commands, mappings
---and the public API all live in exactly one place, and the docs quote it.
---@class scripts.source
local M = {}

---@param path string
---@return string[]
local function lines_of(path)
    local out = {}
    for line in io.lines(path) do
        out[#out + 1] = line
    end
    return out
end

---Lines between two patterns, exclusive of both.
---@param path string
---@param first string pattern opening the region
---@param last string pattern closing it
---@return string[]
function M.section(path, first, last)
    local out, inside = {}, false
    for _, line in ipairs(lines_of(path)) do
        if inside and line:match(last) then
            return out
        elseif inside then
            out[#out + 1] = line
        elseif line:match(first) then
            inside = true
        end
    end
    error(("no region matching %s in %s"):format(first, path))
end

---Public functions of a module, in source order.
---
---Only documented functions are reported: an undocumented one has nothing to
---say, and the style audit already refuses a half-documented signature.
---@param path string
---@return sidenote.source.Fn[]
function M.functions(path)
    local lines = lines_of(path)
    local found = {}

    for n, line in ipairs(lines) do
        local name = line:match("^function M%.([%w_]+)%(")
        if name then
            local doc, k = {}, n - 1
            while k > 0 and lines[k]:match("^%-%-%-") do
                table.insert(doc, 1, lines[k])
                k = k - 1
            end

            local fn = { name = name, summary = "", params = {}, returns = {} }
            for _, entry in ipairs(doc) do
                local param = entry:match("^%-%-%-@param%s+(.*)$")
                local ret = entry:match("^%-%-%-@return%s+(.*)$")
                local prose = entry:match("^%-%-%-([^@].*)$")
                if param then
                    fn.params[#fn.params + 1] = param
                elseif ret then
                    fn.returns[#fn.returns + 1] = ret
                elseif prose and fn.summary == "" then
                    fn.summary = prose
                end
            end

            if fn.summary ~= "" then
                found[#found + 1] = fn
            end
        end
    end
    return found
end

---Subcommands the user command completes.
---@param path string
---@return string[]
function M.subcommands(path)
    local body = table.concat(lines_of(path), "\n")
    local listed = assert(body:match("local SUBCOMMANDS =%s*(%b{})"), "no SUBCOMMANDS in " .. path)
    local out = {}
    for name in listed:gmatch('"(%w+)"') do
        out[#out + 1] = name
    end
    return out
end

---`<Plug>` mappings and what each one does.
---@param path string
---@return {name: string, desc: string}[]
function M.mappings(path)
    local body = table.concat(lines_of(path), "\n")
    local out, pos = {}, 1
    while true do
        -- The description trails a multi-line callback, so scan forward from
        -- the name rather than trying to match across the body
        local _, stop, name = body:find('"(<Plug>%(Sidenote%w+%))"', pos)
        if not name then
            return out
        end
        out[#out + 1] = { name = name, desc = body:match('desc%s*=%s*"([^"]+)"', stop) or "" }
        pos = stop + 1
    end
end

return M
