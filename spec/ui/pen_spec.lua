local pen = require("sidenote.pen")

---@return sidenote.Config
local function opts()
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".sidenote",
        global_dir = vim.fn.tempname(),
        pens = { blue = "SidenotePenBlue", green = "SidenotePenGreen" },
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 40 },
    }
end

describe("pen", function()
    after_each(function()
        pen.reset()
        vim.g.sidenote = nil
    end)

    it("starts on the configured pen", function()
        local cfg = opts()
        cfg.pen = "green"
        assert.eq(pen.get(cfg), "green")
    end)

    it("starts penless when the config names none", function()
        assert.is_nil(pen.get(opts()))
    end)

    it("holds a chosen pen over the configured one", function()
        local cfg = opts()
        cfg.pen = "green"
        assert.truthy(pen.set("blue", cfg))
        assert.eq(pen.get(cfg), "blue")
    end)

    it("puts every pen down for none", function()
        local cfg = opts()
        cfg.pen = "green"
        assert.truthy(pen.set("none", cfg))
        assert.is_nil(pen.get(cfg))
    end)

    it("refuses a pen the config does not know, naming the ring", function()
        local ok, err = pen.set("sparkles", opts())
        assert.falsy(ok)
        assert.contains(err, "sparkles")
        assert.contains(err, "blue")
    end)

    it("inks each kind from its own configured default", function()
        local cfg = opts()
        cfg.pen = { note = "green", todo = "blue" }
        assert.eq(pen.for_kind("note", cfg), "green")
        assert.eq(pen.for_kind("todo", cfg), "blue")
        assert.is_nil(pen.get(cfg), "no single pen is held")
    end)

    it("lets one configured name ink both kinds", function()
        local cfg = opts()
        cfg.pen = "green"
        assert.eq(pen.for_kind("note", cfg), "green")
        assert.eq(pen.for_kind("todo", cfg), "green")
    end)

    it("holds a chosen pen over every kind default", function()
        local cfg = opts()
        cfg.pen = { note = "green", todo = "blue" }
        assert.truthy(pen.set("blue", cfg))
        assert.eq(pen.for_kind("note", cfg), "blue")
        assert.eq(pen.for_kind("todo", cfg), "blue")
    end)

    it("rotates none -> pens sorted -> none", function()
        local cfg = opts()
        assert.eq(pen.cycle(cfg), "blue")
        assert.eq(pen.cycle(cfg), "green")
        assert.eq(pen.cycle(cfg), "none")
    end)

    it("mirrors every change into the state global", function()
        local cfg = opts()
        pen.set("green", cfg)
        assert.eq(vim.g.sidenote_state.pen, "green")
        pen.set("none", cfg)
        assert.eq(vim.g.sidenote_state.pen, "")
    end)
end)

describe("sidenote.statusline", function()
    after_each(function()
        pen.reset()
        vim.g.sidenote = nil
    end)

    it("shows the active pen as a chip in its own ink", function()
        vim.g.sidenote = { pen = "coral" }
        local chip = require("sidenote").statusline()
        assert.contains(chip, "coral")
        assert.contains(chip, "%#SidenotePenCoral#")
        assert.contains(chip, "%*")
    end)

    it("is empty with no pen up, so the statusline loses nothing", function()
        assert.eq(require("sidenote").statusline(), "")
    end)
end)
