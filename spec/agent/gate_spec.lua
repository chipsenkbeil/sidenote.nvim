local export = require("sidenote.export")

local ID = "01J9F3K2X7Q4V8M2ZC5T0BQWE"
local ANCHOR = "function M.join(id)\n  return rooms[id]"

---@class spec.agent.EntryOpts
---@field status? sidenote.Status what the resolver concluded, defaults to attached
---@field confidence? number 0..1, defaults to 1
---@field line_start? integer first resolved line, defaults to 42 when placed
---@field line_end? integer last resolved line inclusive, defaults to line_start
---@field guess? sidenote.Placement best rejected placement the resolver held back
---@field kind? "note"|"todo" defaults to note
---@field state? "open"|"resolved"|"wontfix"|"archived" defaults to open
---@field scope? "file"|"lines"|"range" defaults to lines

---Build a resolved entry without a store, which is what the gate reads.
---@param opts? spec.agent.EntryOpts
---@return sidenote.session.Entry
local function entry(opts)
    opts = opts or {}
    local status = opts.status or "attached"
    local placed = status == "attached" or status == "drifted"
    local line_start = placed and (opts.line_start or 42) or nil
    local line_end = placed and (opts.line_end or line_start) or nil
    return {
        id = ID,
        status = status,
        line_start = line_start,
        line_end = line_end,
        root = "/store",
        record = {
            id = ID,
            kind = opts.kind or "note",
            state = opts.state or "open",
            path = "lua/lobby.lua",
            scope = opts.scope or "lines",
            line_start = 42,
            line_end = 43,
            col_start = 0,
            col_end = 0,
            text = ANCHOR,
        },
        resolution = {
            status = status,
            line_start = line_start,
            line_end = line_end,
            confidence = opts.confidence or (placed and 1 or 0),
            tier = "L1",
            guess = opts.guess,
        },
    }
end

describe("export.PLACED", function()
    it("admits exactly the two statuses that carry a position", function()
        assert.truthy(export.PLACED.attached)
        assert.truthy(export.PLACED.drifted)
        for _, status in ipairs({ "ambiguous", "orphaned", "filegone" }) do
            assert.falsy(export.PLACED[status], status .. " must not carry a position")
        end
    end)
end)

describe("export.entry placed", function()
    it("exports an attached annotation with its range and full confidence", function()
        local record = export.entry(entry({ line_start = 42, line_end = 57 }), "the note")
        assert.eq(record.line_start, 42)
        assert.eq(record.line_end, 57)
        assert.eq(record.confidence, 1)
        assert.falsy(record.code_no_longer_exists)
    end)

    it("exports a drifted annotation with the confidence the resolver measured", function()
        local drifted = entry({ status = "drifted", confidence = 0.86, line_start = 91 })
        local record = export.entry(drifted, "the note")
        assert.eq(record.status, "drifted")
        assert.eq(record.line_start, 91)
        assert.eq(record.confidence, 0.86)
    end)

    it("carries the identity and lifecycle an agent needs to triage", function()
        local record = export.entry(entry({ kind = "todo", state = "wontfix" }), "the note")
        assert.eq(record.id, ID)
        assert.eq(record.kind, "todo")
        assert.eq(record.state, "wontfix")
        assert.eq(record.path, "lua/lobby.lua")
    end)

    it("carries the prose verbatim, newlines and all", function()
        local prose = "race in lobby join\n\nTwo clients can both win"
        assert.eq(export.entry(entry(), prose).prose, prose)
    end)

    it("carries the anchor text even when the annotation is placed", function()
        -- What the note was written against is context, not only a fallback
        assert.eq(export.entry(entry(), "the note").anchor_text, ANCHOR)
    end)
end)

describe("export.entry withheld", function()
    for _, status in ipairs({ "ambiguous", "orphaned", "filegone" }) do
        it(("gives a %s annotation no line numbers at all"):format(status), function()
            local record = export.entry(entry({ status = status }), "the note")
            assert.is_nil(record.line_start)
            assert.is_nil(record.line_end)
        end)

        it(("marks a %s annotation as code that no longer exists"):format(status), function()
            assert.truthy(export.entry(entry({ status = status }), "x").code_no_longer_exists)
        end)

        it(("still gives a %s annotation its original anchor text"):format(status), function()
            -- The agent can search for it
            assert.eq(export.entry(entry({ status = status }), "x").anchor_text, ANCHOR)
        end)
    end

    it("never promotes a resolver guess into a position", function()
        -- The measured 8% precision of naive fuzzy matching is the whole
        -- argument for this gate
        local guessed = entry({
            status = "orphaned",
            guess = { line_start = 88, line_end = 89, confidence = 0.7 },
        })
        local record = export.entry(guessed, "the note")
        assert.is_nil(record.line_start)
        assert.is_nil(record.line_end)
        assert.truthy(record.code_no_longer_exists)
    end)

    it("reports the confidence that was actually reached, not zero by fiat", function()
        local guessed = entry({ status = "orphaned", confidence = 0.7 })
        assert.eq(export.entry(guessed, "x").confidence, 0.7)
    end)

    it("always states whether the code still exists, so no nil check is needed", function()
        assert.is_type(export.entry(entry(), "x").code_no_longer_exists, "boolean")
        assert.is_type(
            export.entry(entry({ status = "orphaned" }), "x").code_no_longer_exists,
            "boolean"
        )
    end)
end)
