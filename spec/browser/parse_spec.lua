local parse = require("sidenote.browser.parse")
local render = require("sidenote.browser.render")

local ID = "01J9F3K2X7Q4V8M2ZC5T0BQWE"
local OTHER = "01J9F3K2X7Q4V8M2ZC5T0BQWF"

---@param id string
---@param columns string
---@return string
local function header(id, columns)
    return ("/%s %s"):format(id, columns)
end

---Prose is any unmarked line, verbatim at the margin.
---@param text string
---@return string
local function prose(text)
    return text
end

describe("browser.parse.header", function()
    it("splits an id line into its four columns", function()
        -- No summary here: it is prose line one, sitting below the header
        local row = assert(parse.header(header(ID, "note  open      -  m.lua:4")))
        assert.eq(row.id, ID)
        assert.eq(row.kind, "note")
        assert.eq(row.state, "open")
        assert.is_nil(row.pen, "the placeholder means no pen")
        assert.eq(row.location, "m.lua:4")
        assert.eq_deep(row.prose, {})
    end)

    it("reads a named pen out of its column", function()
        local row = assert(parse.header(header(ID, "note  open      yellow  m.lua:4")))
        assert.eq(row.pen, "yellow")
    end)

    it("rejects a pen that is not a word", function()
        local row, err = parse.header(header(ID, "note  open      ???  m.lua:4"))
        assert.is_nil(row)
        assert.contains(err, "pen")
    end)

    it("treats an unmarked line as no header at all", function()
        -- The concealed id marker is what makes a header; everything else in
        -- the buffer is prose of the note above it
        local row, err = parse.header("todo  open      m.lua")
        assert.is_nil(row)
        assert.is_nil(err)
    end)

    it("never mistakes a prose line mentioning a path for a header", function()
        local row, err = parse.header("/etc/hosts needs a comment")
        assert.is_nil(row)
        assert.is_nil(err)
    end)

    it("keeps a path holding a double space intact", function()
        -- The location is the last column and runs to the end of the line,
        -- so a run of spaces inside it cannot read as a boundary
        local row = assert(parse.header(header(ID, "note  open      -  my  file.lua:4")))
        assert.eq(row.location, "my  file.lua:4")
    end)

    it("trims stray trailing whitespace off the location", function()
        local row = assert(parse.header(header(ID, "note  open      -  m.lua:4   ")))
        assert.eq(row.location, "m.lua:4")
    end)

    it("keeps a single space inside a path", function()
        local row = assert(parse.header(header(ID, "note  open      -  my file.lua:4")))
        assert.eq(row.location, "my file.lua:4")
    end)

    it("rejects a marked header with too few columns", function()
        local row, err = parse.header(header(ID, "note"))
        assert.is_nil(row)
        assert.not_nil(err)
    end)

    it("rejects an unknown kind", function()
        local row, err = parse.header(header(ID, "idea  open      -  m.lua:4"))
        assert.is_nil(row)
        assert.contains(err, "idea")
    end)

    it("rejects an unknown state", function()
        local row, err = parse.header(header(ID, "note  pending   -  m.lua:4"))
        assert.is_nil(row)
        assert.contains(err, "pending")
    end)

    it("rejects answered, which nothing produces", function()
        -- Reserved for an agent verb that was cut; accepting it here would be
        -- the one door back in
        local row = parse.header(header(ID, "note  answered  -  m.lua:4"))
        assert.is_nil(row)
    end)

    it("rejects a malformed location", function()
        local row, err = parse.header(header(ID, "note  open      -  m.lua:15:4-20"))
        assert.is_nil(row)
        assert.contains(err, "mixed forms")
    end)

    it("reports byte ranges for each column, so <Tab> can jump between them", function()
        local text = header(ID, "note  open      -  m.lua:4")
        local row = assert(parse.header(text))
        assert.eq(text:sub(row.fields.kind.first, row.fields.kind.last), "note")
        assert.eq(text:sub(row.fields.state.first, row.fields.state.last), "open")
        assert.eq(text:sub(row.fields.pen.first, row.fields.pen.last), "-")
        assert.eq(text:sub(row.fields.location.first, row.fields.location.last), "m.lua:4")
    end)
end)

describe("browser.parse.buffer", function()
    it("attaches an unmarked line as prose of the header above it", function()
        local rows, errors = parse.buffer({
            header(ID, "note  open      -  m.lua:4"),
            prose("summary"),
            prose("body one"),
            prose("body two"),
        })
        assert.eq_deep(errors, {})
        assert.eq(#rows, 1)
        assert.eq_deep(rows[1].prose, { "summary", "body one", "body two" })
    end)

    it("keeps a blank line between two prose lines", function()
        local rows = parse.buffer({
            header(ID, "note  open      -  m.lua:4"),
            prose("summary"),
            prose("body one"),
            "",
            prose("body two"),
        })
        assert.eq_deep(rows[1].prose, { "summary", "body one", "", "body two" })
    end)

    it("drops blank lines trailing a block, so a spacer is not stored as prose", function()
        local rows = parse.buffer({
            header(ID, "note  open      -  m.lua:4"),
            prose("summary"),
            prose("body"),
            "",
            "",
            header(OTHER, "note  open      -  m.lua:9"),
            prose("other"),
        })
        assert.eq_deep(rows[1].prose, { "summary", "body" })
        assert.eq_deep(rows[2].prose, { "other" })
    end)

    it("keeps a prose line's own indentation verbatim", function()
        -- Nothing is added on render, so nothing is stripped here
        local rows = parse.buffer({
            header(ID, "note  open      -  m.lua:4"),
            prose("summary"),
            prose("    a code block"),
        })
        assert.eq(rows[1].prose[2], "    a code block")
    end)

    it("records the line each row was read from", function()
        local rows = parse.buffer({
            header(ID, "note  open      -  m.lua:4"),
            prose("body"),
            header(OTHER, "note  open      -  m.lua:9"),
        })
        assert.eq(rows[1].lnum, 1)
        assert.eq(rows[2].lnum, 3)
    end)

    it("errors on prose with no annotation above it", function()
        local _, errors = parse.buffer({ prose("orphaned body") })
        assert.eq(#errors, 1)
        assert.eq(errors[1].lnum, 1)
    end)

    it("errors on the same id appearing twice, naming both lines", function()
        -- Which is exactly what yanking a row and pasting it produces
        local _, errors = parse.buffer({
            header(ID, "note  open      -  m.lua:4"),
            header(ID, "note  open      -  m.lua:9"),
        })
        assert.eq(#errors, 1)
        assert.eq(errors[1].lnum, 2)
        assert.contains(errors[1].message, "1")
    end)

    it("reports a bad row against its own line and keeps the others", function()
        local rows, errors = parse.buffer({
            header(ID, "note  open      -  m.lua:4"),
            header(OTHER, "note  bogus     -  m.lua:9"),
        })
        assert.eq(#rows, 1)
        assert.eq(#errors, 1)
        assert.eq(errors[1].lnum, 2)
    end)

    it("ignores a wholly blank buffer", function()
        local rows, errors = parse.buffer({ "", "" })
        assert.eq_deep(rows, {})
        assert.eq_deep(errors, {})
    end)
end)

describe("browser render and parse round-trip", function()
    ---@param annotation_prose string[]
    ---@return sidenote.browser.Row
    local function row(annotation_prose)
        return {
            entry = {
                id = ID,
                status = "attached",
                line_start = 42,
                line_end = 42,
                root = "/store",
                record = {
                    id = ID,
                    kind = "todo",
                    state = "wontfix",
                    pen = "coral",
                    path = "lua/lobby.lua",
                    scope = "lines",
                    line_start = 42,
                    line_end = 57,
                    col_start = 0,
                    col_end = 0,
                },
            },
            prose = annotation_prose,
        }
    end

    ---Rendering then parsing must return exactly what went in, or an untouched
    ---row reports an edit nobody made.
    ---@param annotation_prose string[]
    local function round_trips(annotation_prose)
        local rows, errors = parse.buffer(render.rows({ row(annotation_prose) }))
        assert.eq_deep(errors, {})
        assert.eq(rows[1].id, ID)
        assert.eq(rows[1].kind, "todo")
        assert.eq(rows[1].state, "wontfix")
        assert.eq(rows[1].pen, "coral")
        assert.eq(rows[1].location, "lua/lobby.lua:42-57")
        assert.eq_deep(rows[1].prose, render.normalize(annotation_prose))
    end

    it("round-trips a single-line note", function()
        round_trips({ "just a summary" })
    end)

    it("round-trips a note with a body", function()
        round_trips({ "summary", "body one", "body two" })
    end)

    it("round-trips a note with a blank line inside its body", function()
        round_trips({ "summary", "", "after the gap" })
    end)

    it("round-trips a note with no prose at all", function()
        round_trips({})
    end)

    it("round-trips a summary holding two consecutive spaces", function()
        round_trips({ "two  spaces", "body" })
    end)

    it("round-trips a summary that opens with whitespace", function()
        -- The summary stays trimmed in canonical form: it is what a closed
        -- fold previews, and the preview trims
        round_trips({ "  leading spaces", "body" })
    end)

    it("round-trips a summary that opens with a tab", function()
        round_trips({ "\ttab first", "body" })
    end)

    it("round-trips a summary with trailing whitespace", function()
        round_trips({ "trailing spaces   ", "body" })
    end)

    it("round-trips a body line that indents itself further", function()
        -- Body lines keep their own indentation; only the summary cannot
        round_trips({ "summary", "    a code block", "        deeper still" })
    end)

    it("round-trips prose whose every line is blank", function()
        round_trips({ "   ", "" })
    end)

    it("round-trips a summary of nothing but whitespace", function()
        round_trips({ "  ", "a real body line" })
    end)
end)
