local location = require("sidenote.location")

describe("location.format", function()
    it("formats file scope as a bare path", function()
        assert.eq(
            location.format({
                path = "a.lua",
                scope = "file",
                line_start = 0,
                line_end = 0,
                col_start = 0,
                col_end = 0,
            }),
            "a.lua"
        )
    end)

    it("collapses a single line to one number", function()
        assert.eq(
            location.format({
                path = "a.lua",
                scope = "lines",
                line_start = 15,
                line_end = 15,
                col_start = 0,
                col_end = 0,
            }),
            "a.lua:15"
        )
    end)

    it("formats a whole-line range", function()
        assert.eq(
            location.format({
                path = "a.lua",
                scope = "lines",
                line_start = 15,
                line_end = 20,
                col_start = 0,
                col_end = 0,
            }),
            "a.lua:15-20"
        )
    end)

    it("formats a column-precise range", function()
        assert.eq(
            location.format({
                path = "a.lua",
                scope = "range",
                line_start = 15,
                line_end = 20,
                col_start = 4,
                col_end = 10,
            }),
            "a.lua:15:4-20:10"
        )
    end)
end)

describe("location round-trip", function()
    local CASES = {
        "a.lua",
        "lua/lobby.lua:15",
        "lua/lobby.lua:15-20",
        "lua/lobby.lua:15:4-20:10",
        "lua/lobby.lua:15:4-15:10",
        "weird:dir/file.lua:15",
    }

    it("survives parse -> format for every form", function()
        for _, text in ipairs(CASES) do
            assert.eq(location.format(location.parse(text)), text, "round-trip failed for " .. text)
        end
    end)

    it("normalizes a redundant one-line range to a single line", function()
        assert.eq(location.format(location.parse("a.lua:15-15")), "a.lua:15")
    end)

    it("formats a record, which carries the same six fields", function()
        local record = require("sidenote.core.record")
        local rec = record.capture({
            id = "x",
            project_key = "demo",
            path = "lua/m.lua",
            scope = "lines",
            line_start = 3,
            line_end = 5,
            content = "a\nb\nc\nd\ne\nf",
            now = "2026-08-18T00:00:00Z",
        })
        assert.eq(location.format(rec), "lua/m.lua:3-5")
    end)
end)
