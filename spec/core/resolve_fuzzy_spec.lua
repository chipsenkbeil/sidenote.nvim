local resolve = require("sidenote.core.resolve")
local record = require("sidenote.core.record")

local ORIGINAL = table.concat({
    "local M = {}", -- 1
    "", -- 2
    "function M.join(a, b)", -- 3
    "  local sep = ', '", -- 4
    "  return a .. sep .. b", -- 5
    "end", -- 6
    "", -- 7
    "return M", -- 8
}, "\n")

---Capture a range anchored on the function, lines 3 to 6.
---@return sidenote.Annotation
local function rec()
    return record.capture({
        id = "x",
        project_key = "demo",
        path = "m.lua",
        scope = "range",
        line_start = 3,
        line_end = 6,
        content = ORIGINAL,
        now = "2026-08-18T00:00:00Z",
    })
end

describe("resolve L6 fuzzy", function()
    it("drifts a block edited in place and records its confidence", function()
        local edited = table.concat({
            "local M = {}",
            "",
            "function M.join(a, b)",
            "  local sep = '; '",
            "  return a .. sep .. b",
            "end",
            "",
            "return M",
        }, "\n")
        local r = resolve.resolve(rec(), edited)
        assert.eq(r.status, "drifted")
        assert.eq(r.tier, "L6")
        assert.eq(r.line_start, 3)
        assert.eq(r.line_end, 6)
        assert.gte(r.confidence, resolve.ACCEPT)
        assert.lt(r.confidence, 1.0000001)
    end)

    it("orphans with no guess when the block is gone", function()
        local r = resolve.resolve(rec(), "print('nothing to see here')\nos.exit(0)")
        assert.eq(r.status, "orphaned")
        assert.is_nil(r.guess)
        assert.is_nil(r.line_start)
    end)

    it("never places an orphan, even when it has a guess", function()
        -- A guess presented as a location points at code that was never the note's subject
        local rewritten = table.concat({
            "local M = {}",
            "",
            "function M.join(first, second)",
            "  return table.concat({ first, second }, ', ')",
            "end",
            "",
            "return M",
        }, "\n")
        local r = resolve.resolve(rec(), rewritten)
        if r.status == "orphaned" then
            assert.is_nil(r.line_start)
            assert.is_nil(r.line_end)
            if r.guess then
                assert.gte(r.guess.score, resolve.GUESS)
                assert.lt(r.guess.score, resolve.ACCEPT)
            end
        else
            assert.eq(r.status, "drifted")
        end
    end)

    it("keeps the accept threshold above the guess threshold", function()
        assert.gt(resolve.ACCEPT, resolve.GUESS)
    end)
end)
