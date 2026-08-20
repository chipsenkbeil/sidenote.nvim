local render = require("sidenote.browser.render")

local ID = "01J9F3K2X7Q4V8M2ZC5T0BQWE"
local OTHER = "01J9F3K2X7Q4V8M2ZC5T0BQWF"

---@class spec.browser.RowOpts
---@field id? string annotation id the row stands for, defaults to a stub ULID
---@field kind? "note"|"todo" defaults to note
---@field state? string lifecycle position, defaults to open
---@field scope? "file"|"lines"|"range" defaults to lines
---@field path? string project-relative path, defaults to lua/lobby.lua
---@field line_start? integer defaults to 42
---@field line_end? integer defaults to line_start
---@field col_start? integer defaults to 0, meaning no columns were captured
---@field col_end? integer defaults to col_start
---@field resolved? integer line the resolver placed it on, when it drifted
---@field prose? string[] defaults to one summary line

---Build a row without touching a store, which is the point of a pure renderer.
---@param opts? spec.browser.RowOpts
---@return sidenote.browser.Row
local function row(opts)
    opts = opts or {}
    local scope = opts.scope or "lines"
    local whole_file = scope == "file"
    local line_start = opts.line_start or 42
    local line_end = opts.line_end or line_start
    local col_start = opts.col_start or 0
    return {
        entry = {
            id = opts.id or ID,
            status = "attached",
            line_start = opts.resolved or line_start,
            line_end = opts.resolved or line_end,
            root = "/store",
            record = {
                id = opts.id or ID,
                kind = opts.kind or "note",
                state = opts.state or "open",
                path = opts.path or "lua/lobby.lua",
                scope = scope,
                line_start = whole_file and 0 or line_start,
                line_end = whole_file and 0 or line_end,
                col_start = col_start,
                col_end = opts.col_end or col_start,
            },
        },
        prose = opts.prose or { "race in lobby join" },
    }
end

---@param line string
---@return string
local function without_id(line)
    return (line:gsub("^/%S+ ", ""))
end

describe("browser.render columns", function()
    it("names three columns, in the order they are written", function()
        -- The summary is not among them: it is prose line one, indented below
        -- its header with the rest of the body
        local names = {}
        for _, column in ipairs(render.COLUMNS) do
            names[#names + 1] = column.name
        end
        assert.eq_deep(names, { "kind", "state", "location" })
    end)

    it("prefixes a header with the concealed id and a single space", function()
        local lines = render.rows({ row() })
        assert.match(lines[1], "^/" .. ID .. " ")
    end)

    it("separates every column by at least two spaces, so parsing can split on the gap", function()
        local rest = without_id(render.rows({ row() })[1])
        assert.eq(select(2, rest:gsub("%s%s+", "")), 2)
    end)

    it("aligns columns across rows so the listing does not jitter", function()
        local lines = render.rows({
            row({ prose = { "short" } }),
            row({ id = OTHER, kind = "todo", state = "wontfix", line_start = 8 }),
        })
        assert.eq(lines[1]:find("lua/lobby%.lua"), lines[3]:find("lua/lobby%.lua"))
    end)

    it("keeps a path holding consecutive spaces, since nothing follows it", function()
        -- The location is the last column now, so a run of spaces inside it
        -- can no longer read as a column boundary
        local line = render.rows({ row({ path = "odd  name.lua" }) })[1]
        assert.match(line, "odd  name%.lua:42$")
    end)
end)

describe("browser syntax", function()
    ---@return string
    local function syntax_source()
        local fh = assert(io.open("syntax/sidenote.vim", "r"))
        local src = fh:read("*a")
        fh:close()
        return src
    end

    it("conceals the id prefix with the grammar's word class", function()
        -- Ids are word characters, so prose opening with a path such as
        -- /etc/hosts never conceals as a header; \w still spans a whole ULID
        local src = syntax_source()
        assert.contains(src, [[syn match sidenoteId /^\/\w\+ / conceal]])
        for line in src:gmatch("[^\n]+") do
            if line:match("^%s*syn ") then
                assert.falsy(line:find([[\x]], 1, true), "hex class in: " .. line)
            end
        end
    end)

    it("styles prose as every line without the marker", function()
        -- The old rule keyed on indentation, which margin prose no longer has
        local src = syntax_source()
        assert.contains(src, [[syn match sidenoteProse /^\(\/\w\+ \)\@!.*$/]])
        assert.falsy(src:find([[/^\s.*$/]], 1, true))
    end)

    it("guards against being sourced twice", function()
        assert.contains(syntax_source(), "b:current_syntax")
    end)

    it("highlights every column the renderer writes", function()
        local src = syntax_source()
        for _, column in ipairs(render.COLUMNS) do
            local group = "sidenote" .. column.name:sub(1, 1):upper() .. column.name:sub(2)
            assert.contains(src, group)
        end
    end)
end)

describe("browser.render prose", function()
    it("renders every prose line at the margin, verbatim", function()
        -- The header's concealed marker is what distinguishes it, so prose
        -- needs no indentation and copies out exactly as stored
        local lines = render.rows({ row({ prose = { "one", "two", "three" } }) })
        assert.eq(#lines, 4)
        assert.eq(lines[2], "one")
        assert.eq(lines[3], "two")
        assert.eq(lines[4], "three")
    end)

    it("renders the summary untruncated", function()
        -- Truncating would make an untouched row differ from its own stored
        -- prose, and the write path would then replace it with the abbreviation
        local long = ("x"):rep(200)
        assert.contains(render.rows({ row({ prose = { long } }) })[2], long)
    end)

    it("renders a note with no prose as its header alone", function()
        local lines = render.rows({ row({ prose = {} }) })
        assert.eq(#lines, 1)
        assert.match(lines[1], "lua/lobby%.lua:42$")
    end)

    it("renders a blank prose line as an empty line, never as bare indentation", function()
        -- A trim-trailing-whitespace autocmd would strip an indent-only line,
        -- so the renderer never writes one in the first place
        local lines = render.rows({ row({ prose = { "one", "", "three" } }) })
        assert.eq(lines[3], "")
    end)

    it("drops trailing blank prose lines", function()
        local lines = render.rows({ row({ prose = { "one", "two", "", "" } }) })
        assert.eq(#lines, 3)
    end)

    it("keeps rows adjacent, so a fold covers exactly one annotation", function()
        local lines = render.rows({
            row({ prose = { "first", "body" } }),
            row({ id = OTHER, prose = { "second" } }),
        })
        assert.eq(#lines, 5)
        assert.match(lines[4], "^/" .. OTHER .. " ")
    end)
end)

describe("browser.render location", function()
    it("renders a file-scoped entry as a bare path", function()
        local line = without_id(render.rows({ row({ scope = "file" }) })[1])
        assert.match(line, "lua/lobby%.lua$")
    end)

    it("renders a line range through the location grammar", function()
        local line = render.rows({ row({ line_start = 42, line_end = 57 }) })[1]
        assert.contains(line, "lua/lobby.lua:42-57")
    end)

    it("renders a column range through the location grammar", function()
        local line = render.rows({
            row({ scope = "range", line_start = 15, line_end = 20, col_start = 4, col_end = 10 }),
        })[1]
        assert.contains(line, "lua/lobby.lua:15:4-20:10")
    end)

    it("renders the stored location, not where the resolver placed it", function()
        -- Every other column shows what is on disk, so this one does too: an
        -- edit is an assertion against the value you can see
        local line = render.rows({ row({ line_start = 42, resolved = 50 }) })[1]
        assert.contains(line, "lua/lobby.lua:42")
        assert.falsy(line:find("lua/lobby%.lua:50"))
    end)
end)
