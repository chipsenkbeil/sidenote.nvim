local navigate = require("sidenote.navigate")

---@param status sidenote.Status
---@param line integer|nil
---@return sidenote.session.Entry
local function entry(status, line)
    return { id = tostring(line), status = status, line_start = line, line_end = line }
end

local ENTRIES = {
    entry("attached", 2),
    entry("drifted", 5),
    entry("attached", 9),
}

describe("navigate.NAVIGABLE", function()
    it("includes the statuses that have a real position", function()
        assert.eq(navigate.NAVIGABLE.attached, true)
        assert.eq(navigate.NAVIGABLE.drifted, true)
    end)

    it("excludes the statuses whose position means nothing", function()
        -- Jumping to a meaningless line is worse than not jumping
        assert.falsy(navigate.NAVIGABLE.ambiguous)
        assert.falsy(navigate.NAVIGABLE.orphaned)
        assert.falsy(navigate.NAVIGABLE.filegone)
    end)
end)

describe("navigate.next", function()
    it("returns the first entry after the cursor", function()
        assert.eq(navigate.next(ENTRIES, 1).line_start, 2)
    end)

    it("skips an entry sitting exactly on the cursor line", function()
        assert.eq(navigate.next(ENTRIES, 2).line_start, 5)
    end)

    it("wraps to the first entry from the end of the file", function()
        assert.eq(navigate.next(ENTRIES, 99).line_start, 2)
    end)

    it("skips statuses that are not navigable", function()
        local mixed = { entry("orphaned", nil), entry("ambiguous", 3), entry("attached", 7) }
        assert.eq(navigate.next(mixed, 1).line_start, 7)
    end)

    it("returns nil when nothing is navigable", function()
        assert.is_nil(navigate.next({ entry("orphaned", nil) }, 1))
    end)

    it("returns nil for an empty list", function()
        assert.is_nil(navigate.next({}, 1))
    end)
end)

describe("navigate.prev", function()
    it("returns the last entry before the cursor", function()
        assert.eq(navigate.prev(ENTRIES, 7).line_start, 5)
    end)

    it("skips an entry sitting exactly on the cursor line", function()
        assert.eq(navigate.prev(ENTRIES, 5).line_start, 2)
    end)

    it("wraps to the last entry from the start of the file", function()
        assert.eq(navigate.prev(ENTRIES, 1).line_start, 9)
    end)

    it("skips statuses that are not navigable", function()
        local mixed = { entry("attached", 2), entry("ambiguous", 6), entry("orphaned", nil) }
        assert.eq(navigate.prev(mixed, 8).line_start, 2)
    end)

    it("returns nil when nothing is navigable", function()
        assert.is_nil(navigate.prev({ entry("filegone", nil) }, 3))
    end)
end)
