local config = require("sidenote.config")

describe("config.defaults", function()
    it("defaults the prose filetype to something format-neutral", function()
        assert.eq(config.defaults().filetype, "txt")
    end)

    it("defaults the strategy to project then global", function()
        assert.eq_deep(config.defaults().strategy, { "project", "global" })
    end)

    it("names the project store after the tool", function()
        assert.eq(config.defaults().project_dir, ".sidenote")
    end)

    it("puts the global store under a data path, not a cache path", function()
        assert.contains(config.defaults().global_dir, "/share/")
    end)

    it("returns a fresh copy each call, so callers cannot corrupt it", function()
        config.defaults().filetype = "mutated"
        assert.eq(config.defaults().filetype, "txt")
    end)

    it("shows range highlights by default, toggleable off per buffer", function()
        assert.eq(config.defaults().indicator.highlight, "on")
    end)

    it("seeds org-remark's four pens, each pointing at its own group", function()
        local pens = config.defaults().pens
        for _, name in ipairs({ "yellow", "coral", "blue", "green" }) do
            local group = "SidenotePen" .. name:sub(1, 1):upper() .. name:sub(2)
            assert.eq(pens[name], group)
        end
    end)

    it("opens the browser in a bottom split, sized to its rows", function()
        local browser = config.defaults().browser
        assert.eq(browser.style, "split")
        assert.eq(browser.position, "bottom")
        assert.is_nil(browser.size, "no fixed size means sized to content")
    end)
end)

describe("config.resolve", function()
    it("returns defaults for no input", function()
        assert.eq(config.resolve().filetype, "txt")
    end)

    it("overrides only the keys given", function()
        local resolved = config.resolve({ filetype = "org" })
        assert.eq(resolved.filetype, "org")
        assert.eq_deep(resolved.strategy, { "project", "global" })
    end)

    it("merges nested display tables rather than replacing them wholesale", function()
        local resolved = config.resolve({ editor = { position = "left" } })
        assert.eq(resolved.editor.position, "left")
        assert.eq(resolved.editor.style, config.defaults().editor.style)
    end)

    it("accepts a function returning a table", function()
        assert.eq(
            config.resolve(function()
                return { filetype = "md" }
            end).filetype,
            "md"
        )
    end)

    it("rejects an unknown indicator style", function()
        local _, err = config.resolve({ indicator = { style = "fireworks" } })
        assert.match(err, "indicator")
    end)

    it("accepts the summary indicator style", function()
        local _, err = config.resolve({ indicator = { style = "summary" } })
        assert.is_nil(err)
    end)

    it("rejects a filetype that is not a string", function()
        local _, err = config.resolve({ filetype = 42 })
        assert.match(err, "filetype")
    end)

    it("rejects an unknown strategy entry", function()
        local _, err = config.resolve({ strategy = { "telepathy" } })
        assert.match(err, "strategy")
    end)

    it("accepts a function as a strategy entry", function()
        local _, err = config.resolve({
            strategy = {
                function()
                    return "/tmp/store"
                end,
            },
        })
        assert.is_nil(err)
    end)

    it("names the offending path in the error, not just the field", function()
        local _, err = config.resolve({ editor = { style = "hologram" } })
        assert.contains(err, "vim.g.sidenote.editor.style")
    end)

    it("rejects a browser style or position the window module cannot open", function()
        local _, err = config.resolve({ browser = { style = "hologram" } })
        assert.contains(err, "vim.g.sidenote.browser.style")

        _, err = config.resolve({ browser = { position = "sideways" } })
        assert.contains(err, "vim.g.sidenote.browser.position")
    end)

    it("returns defaults alongside an error so a caller can degrade", function()
        local resolved, err = config.resolve({ filetype = 42 })
        assert.not_nil(err)
        assert.eq(resolved.filetype, "txt")
    end)

    it("rejects a non-table, non-function value", function()
        local _, err = config.resolve("org")
        assert.match(err, "expected a table")
    end)

    it("degrades on a section that is not a table, rather than erroring", function()
        -- Indexing 5 would throw and take every entry point down with it
        local resolved, err = config.resolve({ indicator = 5 })
        assert.contains(err, "vim.g.sidenote.indicator")
        assert.eq(resolved.indicator.style, "sign")
    end)

    it("says a string is not a section, which is the common slip", function()
        -- The intended form is `preview = { style = "float" }`
        local _, err = config.resolve({ preview = "float" })
        assert.contains(err, "vim.g.sidenote.preview")
        assert.contains(err, "expected a table")
    end)

    it("merges custom pens over the seeded ones", function()
        local resolved, err = config.resolve({ pens = { pink = "MyPinkWash" } })
        assert.is_nil(err)
        assert.eq(resolved.pens.pink, "MyPinkWash")
        assert.eq(resolved.pens.yellow, "SidenotePenYellow")
    end)

    it("rejects a pen name that could not sit in a browser column", function()
        local _, err = config.resolve({ pens = { ["two words"] = "Group" } })
        assert.contains(err, "vim.g.sidenote.pens")
    end)

    it("rejects a pen whose group is not a string", function()
        local _, err = config.resolve({ pens = { pink = 5 } })
        assert.contains(err, "vim.g.sidenote.pens.pink")
    end)

    it("accepts a default pen the pens table knows", function()
        local resolved, err = config.resolve({ pen = "coral" })
        assert.is_nil(err)
        assert.eq(resolved.pen, "coral")
    end)

    it("rejects a default pen no pen entry defines", function()
        local _, err = config.resolve({ pen = "sparkles" })
        assert.contains(err, "vim.g.sidenote.pen")
    end)

    it("accepts a default pen split by kind", function()
        local resolved, err = config.resolve({ pen = { note = "green", todo = "coral" } })
        assert.is_nil(err)
        assert.eq(resolved.pen.todo, "coral")
    end)

    it("rejects a kind-split pen with an unknown kind or pen", function()
        local _, err = config.resolve({ pen = { idea = "green" } })
        assert.contains(err, "vim.g.sidenote.pen")

        _, err = config.resolve({ pen = { todo = "sparkles" } })
        assert.contains(err, "vim.g.sidenote.pen.todo")
    end)
end)

describe("config.resolve markers", function()
    it("is absent by default, which means the built-in list", function()
        assert.is_nil(config.resolve({}).markers)
    end)

    it("accepts a list of names", function()
        local resolved, err = config.resolve({ markers = { "WORKSPACE", "*.bzl" } })
        assert.is_nil(err)
        assert.eq_deep(resolved.markers, { "WORKSPACE", "*.bzl" })
    end)

    it("accepts a function, which is handed the built-ins", function()
        local _, err = config.resolve({
            markers = function(defaults)
                return defaults
            end,
        })
        assert.is_nil(err)
    end)

    it("accepts a function as a single entry", function()
        local _, err = config.resolve({
            markers = {
                function()
                    return true
                end,
            },
        })
        assert.is_nil(err)
    end)

    it("replaces rather than merges, the way strategy does", function()
        assert.eq(#config.resolve({ markers = { "WORKSPACE" } }).markers, 1)
    end)

    it("rejects a marker that is neither a name nor a function", function()
        local _, err = config.resolve({ markers = { 5 } })
        assert.contains(err, "vim.g.sidenote.markers")
    end)

    it("rejects an empty marker, which would match every directory", function()
        local _, err = config.resolve({ markers = { "" } })
        assert.contains(err, "vim.g.sidenote.markers")
    end)

    it("rejects markers that are neither a list nor a function", function()
        local _, err = config.resolve({ markers = "WORKSPACE" })
        assert.contains(err, "vim.g.sidenote.markers")
    end)
end)

describe("config.resolve pens with shades", function()
    it("keeps a pen named as a highlight group untouched", function()
        local resolved = config.resolve({ pens = { blue = "MyBlue" } })
        assert.eq(resolved.pens.blue, "MyBlue")
        assert.eq_deep(resolved.pen_washes, {})
    end)

    it("mints a group for a pen carrying its own shades", function()
        local resolved, err = config.resolve({
            pens = { teal = { dark = "#1f4f4a", light = "#ccefe9" } },
        })
        assert.is_nil(err)
        assert.eq(resolved.pens.teal, "SidenotePenTeal")
        assert.eq(resolved.pen_washes.SidenotePenTeal.dark, "#1f4f4a")
    end)

    it("leaves every reader a group name, whichever way a pen was written", function()
        local resolved = config.resolve({
            pens = { teal = { dark = "#1f4f4a", light = "#ccefe9" } },
        })
        for name, group in pairs(resolved.pens) do
            assert.is_type(group, "string", name)
        end
    end)

    it("sanitizes a pen name that a highlight group could not hold", function()
        assert.eq(config.pen_group("my-pen"), "SidenotePenMy_pen")
    end)

    it("accepts a highlight group as a shade, not only a color", function()
        local _, err = config.resolve({
            pens = { themed = { dark = "DiffAdd", light = "DiffChange" } },
        })
        assert.is_nil(err)
    end)

    it("rejects shades missing a background", function()
        local _, err = config.resolve({ pens = { teal = { dark = "#1f4f4a" } } })
        assert.contains(err, "vim.g.sidenote.pens.teal.light")
    end)

    it("rejects a pen that is neither a group nor shades", function()
        local _, err = config.resolve({ pens = { teal = 5 } })
        assert.contains(err, "vim.g.sidenote.pens.teal")
    end)
end)
