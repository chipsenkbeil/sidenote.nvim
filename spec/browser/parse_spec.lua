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

---@param text string
---@return string
local function prose(text)
    return (" "):rep(render.PROSE_INDENT) .. text
end

describe("browser.parse.header", function()
    it("splits an id line into its four columns", function()
        local row = assert(parse.header(header(ID, "note  open      m.lua:4    the summary")))
        assert.eq(row.id, ID)
        assert.eq(row.kind, "note")
        assert.eq(row.state, "open")
        assert.eq(row.location, "m.lua:4")
        assert.eq(row.prose[1], "the summary")
    end)

    it("reads a line with no id as a create", function()
        local row = assert(parse.header("todo  open      m.lua    a brand new note"))
        assert.is_nil(row.id)
        assert.eq(row.kind, "todo")
        assert.eq(row.prose[1], "a brand new note")
    end)

    it("keeps a summary containing a double space intact", function()
        -- Only the first three gaps are boundaries; the rest of the line is
        -- the summary, verbatim
        local row = assert(parse.header(header(ID, "note  open      m.lua:4    two  spaces")))
        assert.eq(row.prose[1], "two  spaces")
    end)

    it("accepts a row whose summary is empty", function()
        -- The renderer strips trailing whitespace, so an unwritten note has no
        -- fourth column at all
        local row = assert(parse.header(header(ID, "note  open      m.lua:4")))
        assert.eq(row.location, "m.lua:4")
        assert.eq(row.prose[1], "")
    end)

    it("keeps a single space inside a path", function()
        local row = assert(parse.header(header(ID, "note  open      my file.lua:4    hi")))
        assert.eq(row.location, "my file.lua:4")
    end)

    it("rejects a line with too few columns", function()
        local row, err = parse.header("just some words")
        assert.is_nil(row)
        assert.not_nil(err)
    end)

    it("rejects an unknown kind", function()
        local row, err = parse.header(header(ID, "idea  open      m.lua:4    x"))
        assert.is_nil(row)
        assert.contains(err, "idea")
    end)

    it("rejects an unknown state", function()
        local row, err = parse.header(header(ID, "note  pending   m.lua:4    x"))
        assert.is_nil(row)
        assert.contains(err, "pending")
    end)

    it("rejects a malformed location", function()
        local row, err = parse.header(header(ID, "note  open      m.lua:15:4-20    x"))
        assert.is_nil(row)
        assert.contains(err, "mixed forms")
    end)

    it("reports byte ranges for each column, so <Tab> can jump between them", function()
        local text = header(ID, "note  open      m.lua:4    the summary")
        local row = assert(parse.header(text))
        assert.eq(text:sub(row.fields.kind.first, row.fields.kind.last), "note")
        assert.eq(text:sub(row.fields.state.first, row.fields.state.last), "open")
        assert.eq(text:sub(row.fields.location.first, row.fields.location.last), "m.lua:4")
        assert.eq(text:sub(row.fields.summary.first, row.fields.summary.last), "the summary")
    end)
end)

describe("browser.parse.buffer", function()
    it("attaches an indented line as prose of the header above it", function()
        local rows, errors = parse.buffer({
            header(ID, "note  open      m.lua:4    summary"),
            prose("body one"),
            prose("body two"),
        })
        assert.eq_deep(errors, {})
        assert.eq(#rows, 1)
        assert.eq_deep(rows[1].prose, { "summary", "body one", "body two" })
    end)

    it("keeps a blank line between two prose lines", function()
        local rows = parse.buffer({
            header(ID, "note  open      m.lua:4    summary"),
            prose("body one"),
            "",
            prose("body two"),
        })
        assert.eq_deep(rows[1].prose, { "summary", "body one", "", "body two" })
    end)

    it("drops blank lines trailing a block, so a spacer is not stored as prose", function()
        local rows = parse.buffer({
            header(ID, "note  open      m.lua:4    summary"),
            prose("body"),
            "",
            "",
            header(OTHER, "note  open      m.lua:9    other"),
        })
        assert.eq_deep(rows[1].prose, { "summary", "body" })
        assert.eq_deep(rows[2].prose, { "other" })
    end)

    it("strips no more than the indent the renderer added", function()
        -- Prose that indents itself further keeps that shape
        local rows = parse.buffer({
            header(ID, "note  open      m.lua:4    summary"),
            prose("    deeper"),
        })
        assert.eq(rows[1].prose[2], "    deeper")
    end)

    it("records the line each row was read from", function()
        local rows = parse.buffer({
            header(ID, "note  open      m.lua:4    one"),
            prose("body"),
            header(OTHER, "note  open      m.lua:9    two"),
        })
        assert.eq(rows[1].lnum, 1)
        assert.eq(rows[2].lnum, 3)
    end)

    it("errors on indented prose with no annotation above it", function()
        local _, errors = parse.buffer({ prose("orphaned body") })
        assert.eq(#errors, 1)
        assert.eq(errors[1].lnum, 1)
    end)

    it("errors on the same id appearing twice, naming both lines", function()
        -- Which is exactly what yanking a row and pasting it produces
        local _, errors = parse.buffer({
            header(ID, "note  open      m.lua:4    one"),
            header(ID, "note  open      m.lua:9    two"),
        })
        assert.eq(#errors, 1)
        assert.eq(errors[1].lnum, 2)
        assert.contains(errors[1].message, "1")
    end)

    it("reports a bad row against its own line and keeps the others", function()
        local rows, errors = parse.buffer({
            header(ID, "note  open      m.lua:4    fine"),
            header(OTHER, "note  bogus     m.lua:9    broken"),
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
end)
