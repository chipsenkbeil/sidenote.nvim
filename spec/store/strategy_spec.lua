local strategy = require("sidenote.store.strategy")
local project = require("sidenote.store.project")

local GLOBAL = "/tmp/sidenote-global"

---Build a throwaway tree of empty directories and return its root.
---@param dirs string[] directories to create under the root
---@return string root
local function tree(dirs)
    local root = vim.fn.tempname()
    for _, rel in ipairs(dirs) do
        vim.fn.mkdir(root .. "/" .. rel, "p")
    end
    return root
end

---@param overrides? table<string, any> fields overriding the fixture defaults
---@return sidenote.store.strategy.Opts
local function opts(overrides)
    local base = { strategy = "global", global_dir = GLOBAL, project_dir = ".sidenote" }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

describe("strategy global", function()
    it("always resolves, even with no project", function()
        local roots = strategy.resolve("/nowhere/a.lua", opts())
        assert.eq(#roots, 1)
        assert.eq(roots[1], GLOBAL .. "/" .. project.key("/nowhere"))
    end)

    it("keys the global store by project when there is one", function()
        local root = tree({ ".git" })
        local roots = strategy.resolve(root .. "/a.lua", opts())
        assert.eq(roots[1], GLOBAL .. "/" .. project.key(root))
    end)
end)

describe("strategy project", function()
    it("resolves to the project directory inside the project", function()
        local root = tree({ ".git" })
        local roots = strategy.resolve(root .. "/a.lua", opts({ strategy = "project" }))
        assert.eq_deep(roots, { root .. "/.sidenote" })
    end)

    it("errors rather than silently falling back when there is no project", function()
        local roots, err = strategy.resolve("/nowhere/a.lua", opts({ strategy = "project" }))
        assert.is_nil(roots)
        assert.match(err, "project")
    end)

    it("names the markers it looked for, so the error is actionable", function()
        local _, err = strategy.resolve("/nowhere/a.lua", opts({ strategy = "project" }))
        assert.contains(err, ".sidenote")
    end)
end)

describe("strategy as a list", function()
    it("uses the first entry that resolves as the write target", function()
        local root = tree({ ".git" })
        local roots =
            strategy.resolve(root .. "/a.lua", opts({ strategy = { "project", "global" } }))
        assert.eq(roots[1], root .. "/.sidenote")
    end)

    it("falls through to a later entry when an earlier one fails", function()
        local roots =
            strategy.resolve("/nowhere/a.lua", opts({ strategy = { "project", "global" } }))
        assert.eq(#roots, 1)
        assert.eq(roots[1], GLOBAL .. "/" .. project.key("/nowhere"))
    end)

    it("returns every resolving entry, in order, for union reads", function()
        local root = tree({ ".git" })
        local roots =
            strategy.resolve(root .. "/a.lua", opts({ strategy = { "project", "global" } }))
        assert.eq(#roots, 2)
        assert.eq(roots[1], root .. "/.sidenote")
        assert.eq(roots[2], GLOBAL .. "/" .. project.key(root))
    end)

    it("errors when no entry resolves", function()
        local roots, err = strategy.resolve("/nowhere/a.lua", opts({ strategy = { "project" } }))
        assert.is_nil(roots)
        assert.is_type(err, "string")
    end)
end)

describe("strategy as a function", function()
    it("uses whatever the function returns", function()
        local roots = strategy.resolve(
            "/nowhere/a.lua",
            opts({
                strategy = function(path)
                    return "/custom/" .. vim.fn.fnamemodify(path, ":t")
                end,
            })
        )
        assert.eq_deep(roots, { "/custom/a.lua" })
    end)

    it("treats a nil return as a failed entry", function()
        local roots, err = strategy.resolve(
            "/nowhere/a.lua",
            opts({
                strategy = {
                    function()
                        return nil
                    end,
                },
            })
        )
        assert.is_nil(roots)
        assert.is_type(err, "string")
    end)

    it("can be mixed with named entries in a list", function()
        local roots = strategy.resolve(
            "/nowhere/a.lua",
            opts({
                strategy = {
                    function()
                        return nil
                    end,
                    "global",
                },
            })
        )
        assert.eq(#roots, 1)
        assert.eq(roots[1], GLOBAL .. "/" .. project.key("/nowhere"))
    end)
end)
