local location = require("sidenote.location")

local CONTENT = table.concat({
    "local M = {}", -- 1
    "function M.f()", -- 2
    "  return 1", -- 3
    "end", -- 4
}, "\n")

describe("location.validate", function()
    it("accepts a location inside the file", function()
        local loc, err = location.validate(location.parse("a.lua:2-4"), CONTENT)
        assert.not_nil(loc)
        assert.is_nil(err)
    end)

    it("accepts file scope", function()
        assert.not_nil(location.validate(location.parse("a.lua"), CONTENT))
    end)

    it("errors when the file does not exist", function()
        local loc, err = location.validate(location.parse("a.lua:2"), nil)
        assert.is_nil(loc)
        assert.match(err, "does not exist")
    end)

    it("errors for file scope when the file does not exist", function()
        local loc, err = location.validate(location.parse("a.lua"), nil)
        assert.is_nil(loc)
        assert.match(err, "does not exist")
    end)

    it("errors when the start line is past the end of the file", function()
        local loc, err = location.validate(location.parse("a.lua:99"), CONTENT)
        assert.is_nil(loc)
        assert.match(err, "99")
        assert.match(err, "4 lines")
    end)

    it("errors when the end line is past the end of the file", function()
        local loc, err = location.validate(location.parse("a.lua:2-99"), CONTENT)
        assert.is_nil(loc)
        assert.match(err, "4 lines")
    end)

    it("accepts the very last line", function()
        assert.not_nil(location.validate(location.parse("a.lua:4"), CONTENT))
    end)

    it("clamps a column past the end of its line rather than refusing", function()
        local loc, err = location.validate(location.parse("a.lua:1:99-1:99"), CONTENT)
        assert.is_nil(err)
        assert.eq(loc.col_start, #"local M = {}")
        assert.eq(loc.col_end, #"local M = {}")
    end)

    it("leaves an in-range column untouched", function()
        local loc = location.validate(location.parse("a.lua:1:3-1:5"), CONTENT)
        assert.eq(loc.col_start, 3)
        assert.eq(loc.col_end, 5)
    end)

    it("does not mutate the location it was given", function()
        local loc = location.parse("a.lua:1:99-1:99")
        location.validate(loc, CONTENT)
        assert.eq(loc.col_start, 99)
    end)

    it("errors on an empty file with a line reference", function()
        local loc, err = location.validate(location.parse("a.lua:1"), "")
        assert.is_nil(loc)
        assert.is_type(err, "string")
    end)
end)
