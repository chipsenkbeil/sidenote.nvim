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

    it("seeds org-remark's four pens, each pointing at its own group", function()
        local pens = config.defaults().pens
        for _, name in ipairs({ "yellow", "coral", "blue", "green" }) do
            local group = "SidenotePen" .. name:sub(1, 1):upper() .. name:sub(2)
            assert.eq(pens[name], group)
        end
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
        -- The promise is defaults alongside the error; indexing 5 would throw
        -- and take every entry point down with it
        local resolved, err = config.resolve({ indicator = 5 })
        assert.contains(err, "vim.g.sidenote.indicator")
        assert.eq(resolved.indicator.style, "sign")
    end)

    it("says a string is not a section, which is the common slip", function()
        -- `preview = "float"` for `preview = { style = "float" }`
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
end)
