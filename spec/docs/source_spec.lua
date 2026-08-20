local source = require("scripts.source")

describe("source.functions", function()
    it("finds the public API of a module", function()
        local names = {}
        for _, fn in ipairs(source.functions("lua/sidenote/init.lua")) do
            names[#names + 1] = fn.name
        end
        for _, wanted in ipairs({ "add", "browse", "browse_project", "refresh", "entries" }) do
            assert.contains(table.concat(names, " "), wanted)
        end
    end)

    it("reads the summary, parameters and returns of each", function()
        local browse
        for _, fn in ipairs(source.functions("lua/sidenote/init.lua")) do
            if fn.name == "browse" then
                browse = fn
            end
        end

        assert.not_nil(browse)
        assert.contains(browse.summary, "listing")
        assert.contains(table.concat(browse.params, " "), "opts")
        assert.gt(#browse.returns, 0)
    end)

    it("reports functions in source order", function()
        local fns = source.functions("lua/sidenote/init.lua")
        assert.eq(fns[1].name, "add")
    end)

    it("skips anything undocumented, which has nothing to say", function()
        local path = vim.fn.tempname()
        local fh = assert(io.open(path, "w"))
        fh:write("local M = {}\n---Documented.\nfunction M.shown() end\nfunction M.hidden() end\n")
        fh:close()

        local fns = source.functions(path)
        assert.eq(#fns, 1)
        assert.eq(fns[1].name, "shown")
    end)
end)

describe("source.subcommands", function()
    it("lists what the command completes", function()
        local names = source.subcommands("plugin/sidenote.lua")
        assert.contains(table.concat(names, " "), "browse")
        assert.contains(table.concat(names, " "), "project")
        assert.gt(#names, 4)
    end)
end)

describe("source.mappings", function()
    it("lists every <Plug> mapping with its description", function()
        local maps = source.mappings("plugin/sidenote.lua")
        assert.gt(#maps, 4)
        for _, map in ipairs(maps) do
            assert.match(map.name, "^<Plug>%(Sidenote")
            assert.neq(map.desc, "", map.name .. " has no description")
        end
    end)
end)

describe("source.section", function()
    it("returns the lines between two markers, excluding both", function()
        local defaults = source.section("lua/sidenote/config.lua", "^function M%.defaults", "^end$")
        local body = table.concat(defaults, "\n")
        assert.contains(body, "filetype")
        assert.contains(body, "strategy")
        assert.falsy(body:find("function M.defaults", 1, true))
    end)

    it("fails loudly when the region is missing, rather than emitting nothing", function()
        assert.throws(function()
            source.section("lua/sidenote/config.lua", "^no such marker$", "^end$")
        end)
    end)
end)
