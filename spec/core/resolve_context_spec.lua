local resolve = require("sidenote.core.resolve")
local record = require("sidenote.core.record")

local DUPES = table.concat({
    "-- alpha", -- 1
    "function f()", -- 2
    "  return 1", -- 3
    "end", -- 4
    "-- beta", -- 5
    "function f()", -- 6
    "  return 1", -- 7
    "end", -- 8
}, "\n")

---Capture the first of the two identical copies.
---
---Both context sides are non-empty on purpose: an empty suffix at end-of-file
---would match any candidate that also sits at EOF, which would make the
---disambiguation look like it worked when it had not.
---@param content string
---@return sidenote.Annotation
local function first_copy(content)
    return record.capture({
        id = "x",
        project_key = "demo",
        path = "m.lua",
        scope = "range",
        line_start = 2,
        line_end = 4,
        content = content,
        now = "2026-08-18T00:00:00Z",
    })
end

describe("resolve L3 context disambiguation", function()
    it("picks the copy whose surrounding context still matches", function()
        local r = resolve.resolve(first_copy(DUPES), "-- header\n" .. DUPES)
        assert.eq(r.status, "attached")
        assert.eq(r.tier, "L3")
        assert.eq(r.line_start, 3)
        assert.eq(r.line_end, 5)
    end)

    it("reports ambiguous when no candidate's context matches", function()
        -- Padded so neither copy lands on the stored hint lines; without this
        -- L1 matches the first copy outright and L2/L3 never run
        local rewritten = table.concat({
            "-- pad",
            "-- zeta",
            "function f()",
            "  return 1",
            "end",
            "-- zeta",
            "function f()",
            "  return 1",
            "end",
        }, "\n")
        local r = resolve.resolve(first_copy(DUPES), rewritten)
        assert.eq(r.status, "ambiguous")
        assert.gte(#r.candidates, 2)
        assert.is_nil(r.line_start)
    end)

    it("orders ambiguous candidates nearest to the stored hint first", function()
        -- Padded so neither copy lands on the stored hint lines; without this
        -- L1 matches the first copy outright and L2/L3 never run
        local rewritten = table.concat({
            "-- pad",
            "-- zeta",
            "function f()",
            "  return 1",
            "end",
            "-- zeta",
            "function f()",
            "  return 1",
            "end",
        }, "\n")
        local r = resolve.resolve(first_copy(DUPES), rewritten)
        assert.eq(r.candidates[1], 3)
    end)
end)

describe("resolve L4 whitespace normalization", function()
    local ORIGINAL = table.concat({
        "local M = {}",
        "function M.f()",
        "  return 1",
        "end",
    }, "\n")

    it("relocates reindented code", function()
        local rec = record.capture({
            id = "x",
            project_key = "demo",
            path = "m.lua",
            scope = "range",
            line_start = 2,
            line_end = 4,
            content = ORIGINAL,
            now = "2026-08-18T00:00:00Z",
        })
        local reindented = table.concat({
            "local M = {}",
            "    function M.f()",
            "            return 1",
            "    end",
        }, "\n")
        local r = resolve.resolve(rec, reindented)
        assert.eq(r.status, "attached")
        assert.eq(r.tier, "L4")
        assert.eq(r.line_start, 2)
        assert.eq(r.line_end, 4)
    end)
end)
