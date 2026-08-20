local resolve = require("sidenote.core.resolve")
local record = require("sidenote.core.record")

local ORIGINAL = table.concat({
    "local M = {}", -- 1
    "", -- 2
    "function M.join(a, b)", -- 3
    "  return a .. b", -- 4
    "end", -- 5
    "", -- 6
    "return M", -- 7
}, "\n")

---@return sidenote.Annotation
local function rec()
    return record.capture({
        id = "x",
        project_key = "demo",
        path = "m.lua",
        scope = "range",
        line_start = 3,
        line_end = 5,
        content = ORIGINAL,
        now = "2026-08-18T00:00:00Z",
    })
end

describe("resolve L0 file fast path", function()
    it("attaches at the stored hint when the file is byte-identical", function()
        local r = resolve.resolve(rec(), ORIGINAL)
        assert.eq(r.status, "attached")
        assert.eq(r.tier, "L0")
        assert.eq(r.line_start, 3)
        assert.eq(r.line_end, 5)
        assert.eq(r.confidence, 1)
    end)

    it("attaches a file-scoped annotation without a position", function()
        local file_rec = record.capture({
            id = "f",
            project_key = "demo",
            path = "m.lua",
            scope = "file",
            content = ORIGINAL,
            now = "2026-08-18T00:00:00Z",
        })
        local r = resolve.resolve(file_rec, ORIGINAL .. "\n-- appended")
        assert.eq(r.status, "attached")
        assert.is_nil(r.line_start)
    end)
end)

describe("resolve L1 exact at hint", function()
    it("attaches when the anchor is unchanged but the file is not", function()
        local r = resolve.resolve(rec(), ORIGINAL .. "\n-- trailing comment")
        assert.eq(r.status, "attached")
        assert.eq(r.tier, "L1")
        assert.eq(r.line_start, 3)
    end)
end)

describe("resolve L2 literal search", function()
    it("relocates a block that shifted down", function()
        local r = resolve.resolve(rec(), "-- header\n-- header2\n" .. ORIGINAL)
        assert.eq(r.status, "attached")
        assert.eq(r.tier, "L2")
        assert.eq(r.line_start, 5)
        assert.eq(r.line_end, 7)
    end)

    it("searches the whole file, not a window around the hint", function()
        local far = string.rep("-- pad\n", 400) .. ORIGINAL
        local r = resolve.resolve(rec(), far)
        assert.eq(r.status, "attached")
        assert.eq(r.line_start, 403)
    end)

    it("treats the anchor as a literal, not a pattern", function()
        local tricky = "local arr = {}\nlocal v = arr[0] + (y * 2)\nreturn v"
        local pattern_rec = record.capture({
            id = "y",
            project_key = "demo",
            path = "m.lua",
            scope = "lines",
            line_start = 2,
            line_end = 2,
            content = tricky,
            now = "2026-08-18T00:00:00Z",
        })
        local r = resolve.resolve(pattern_rec, "-- pad\n" .. tricky)
        assert.eq(r.status, "attached")
        assert.eq(r.line_start, 3)
    end)

    it("does not silently pick one of several identical blocks", function()
        local r = resolve.resolve(rec(), ORIGINAL .. "\n" .. ORIGINAL)
        assert.neq(r.tier, "L2")
    end)
end)

describe("resolve anchorless records", function()
    it("orphans a lines record with no anchor text once the file changes", function()
        -- Capture refuses blank selections now; a record like this predates
        -- that and cannot be searched for, so honesty beats a ghost attach
        local ghost = rec()
        ghost.scope = "lines"
        ghost.text = ""
        local r = resolve.resolve(ghost, ORIGINAL .. "\nchanged = true")
        assert.eq(r.status, "orphaned")
        assert.is_nil(r.line_start)
    end)
end)

describe("resolve missing file", function()
    it("reports filegone and keeps no position", function()
        local r = resolve.resolve(rec(), nil)
        assert.eq(r.status, "filegone")
        assert.is_nil(r.line_start)
    end)

    it("names no tier for a missing file, since none ran", function()
        assert.eq(resolve.resolve(rec(), nil).tier, "-")
    end)
end)
