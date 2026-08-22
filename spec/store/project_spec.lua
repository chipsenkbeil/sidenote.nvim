local fixture = require("spec.fixture")
local project = require("sidenote.store.project")

local tree = fixture.tree

describe("project.MARKERS", function()
    it("leads with .sidenote, the marker an error names first", function()
        assert.eq(project.MARKERS[1], ".sidenote")
    end)
end)

describe("project.root", function()
    it("finds a root marked by .sidenote", function()
        local root = tree({ ".sidenote/", "src/a.lua" })
        assert.eq(project.root(root .. "/src/a.lua"), root)
    end)

    it("finds a root marked by .git", function()
        local root = tree({ ".git/", "src/a.lua" })
        assert.eq(project.root(root .. "/src/a.lua"), root)
    end)

    it("finds a root marked by .jj", function()
        local root = tree({ ".jj/", "src/a.lua" })
        assert.eq(project.root(root .. "/src/a.lua"), root)
    end)

    it("finds a root marked by a language manifest", function()
        local root = tree({ "Cargo.toml", "src/a.rs" })
        assert.eq(project.root(root .. "/src/a.rs"), root)
    end)

    it("walks up through several directories", function()
        local root = tree({ ".git/", "a/b/c/d.lua" })
        assert.eq(project.root(root .. "/a/b/c/d.lua"), root)
    end)

    it("prefers the nearest root when nested", function()
        local outer = tree({ ".git/", "inner/.sidenote/", "inner/src/a.lua" })
        assert.eq(project.root(outer .. "/inner/src/a.lua"), outer .. "/inner")
    end)

    it("prefers the nearest root even when a marker listed earlier sits above", function()
        -- Any one marker is enough, so the list order chooses nothing here:
        -- `.git` below wins over `.sidenote` above by being nearer
        local outer = tree({ ".sidenote/", "inner/.git/", "inner/src/a.lua" })
        assert.eq(project.root(outer .. "/inner/src/a.lua"), outer .. "/inner")
    end)

    it("accepts a directory as well as a file", function()
        local root = tree({ ".git/", "src/a.lua" })
        assert.eq(project.root(root .. "/src"), root)
    end)

    it("returns nil when nothing marks a root", function()
        local root = tree({ "src/a.lua" })
        assert.is_nil(project.root(root .. "/src/a.lua"))
    end)
end)

---Run `fn` with `vim.g.sidenote` set to `cfg`, restoring it afterwards.
---@param cfg table<string, any> what `vim.g.sidenote` holds while fn runs
---@param fn fun()
local function configured(cfg, fn)
    local before = vim.g.sidenote
    vim.g.sidenote = cfg
    local ok, err = pcall(fn)
    vim.g.sidenote = before
    assert(ok, err)
end

describe("project.markers", function()
    it("is the built-in list when nothing is configured", function()
        configured({}, function()
            assert.eq_deep(project.markers(), project.MARKERS)
        end)
    end)

    it("replaces the built-ins with a configured list", function()
        configured({ markers = { "WORKSPACE" } }, function()
            assert.eq_deep(project.markers(), { ".sidenote", "WORKSPACE" })
        end)
    end)

    it("keeps .sidenote a marker whatever the configuration leaves out", function()
        configured({ markers = {} }, function()
            assert.eq_deep(project.markers(), { ".sidenote" })
        end)
    end)

    it("never lists .sidenote twice when it is configured too", function()
        configured({ markers = { ".sidenote", ".git" } }, function()
            assert.eq_deep(project.markers(), { ".sidenote", ".git" })
        end)
    end)

    it("hands a configured function the built-ins, for adding to them", function()
        local seen
        configured({
            markers = function(defaults)
                seen = vim.list_extend({}, defaults)
                return vim.list_extend(defaults, { "WORKSPACE" })
            end,
        }, function()
            local names = project.markers()
            assert.eq(#names, #project.MARKERS + 1)
            assert.eq(names[#names], "WORKSPACE")
        end)
        assert.eq_deep(seen, project.MARKERS)
    end)

    it("leaves the built-in list itself alone", function()
        configured({
            markers = function(defaults)
                return vim.list_extend(defaults, { "WORKSPACE" })
            end,
        }, function()
            project.markers()
        end)
        assert.eq(#project.MARKERS, 9)
    end)
end)

describe("project.root with a configured marker", function()
    it("finds a root marked by a configured name", function()
        local root = tree({ "WORKSPACE", "src/a.lua" })
        configured({ markers = { "WORKSPACE" } }, function()
            assert.eq(project.root(root .. "/src/a.lua"), root)
        end)
    end)

    it("stops finding a built-in the configured list leaves out", function()
        local root = tree({ ".git/", "src/a.lua" })
        configured({ markers = { "WORKSPACE" } }, function()
            assert.is_nil(project.root(root .. "/src/a.lua"))
        end)
    end)

    it("finds .sidenote even when the configured list omits it", function()
        local root = tree({ ".sidenote/", "src/a.lua" })
        configured({ markers = { "WORKSPACE" } }, function()
            assert.eq(project.root(root .. "/src/a.lua"), root)
        end)
    end)

    it("accepts a function deciding a directory for itself", function()
        local root = tree({ "marker.txt", "src/a.lua" })
        configured({
            markers = {
                function(dir)
                    return vim.uv.fs_stat(dir .. "/marker.txt") ~= nil
                end,
            },
        }, function()
            assert.eq(project.root(root .. "/src/a.lua"), root)
        end)
    end)

    it("ignores a configured name that marks nothing here", function()
        local root = tree({ "src/a.lua" })
        configured({ markers = { "WORKSPACE" } }, function()
            assert.is_nil(project.root(root .. "/src/a.lua"))
        end)
    end)

    it("accepts a glob, the way the built-in rockspec entry is one", function()
        local root = tree({ "thing.bzl", "src/a.lua" })
        configured({ markers = { "*.bzl" } }, function()
            assert.eq(project.root(root .. "/src/a.lua"), root)
        end)
    end)
end)

describe("project.root with a rockspec", function()
    ---Build a throwaway directory holding a file named `name` and a `lua/`
    ---subdirectory, and return its resolved root.
    ---@param name string
    ---@return string dir
    local function dir_with(name)
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir .. "/lua", "p")
        local fh = assert(io.open(dir .. "/" .. name, "w"))
        fh:write("package = 'demo'\n")
        fh:close()
        return assert(vim.uv.fs_realpath(dir))
    end

    it("treats a rockspec as a project marker", function()
        local dir = dir_with("sidenote-scm-1.rockspec")
        assert.eq(project.root(dir .. "/lua/init.lua"), dir)
    end)

    it("matches a rockspec whatever its version suffix", function()
        local dir = dir_with("demo-1.2.3-4.rockspec")
        assert.eq(project.root(dir .. "/lua/init.lua"), dir)
    end)

    it("is not fooled by a file that merely mentions rockspec", function()
        local dir = dir_with("notes-about-rockspec.md")
        assert.is_nil(project.root(dir .. "/lua/init.lua"))
    end)

    it("lists the rockspec glob among its markers, for error messages", function()
        assert.contains(table.concat(project.MARKERS, " "), "rockspec")
    end)
end)

describe("project.key", function()
    it("combines the basename with a hash of the absolute path", function()
        assert.match(project.key("/tmp/demo"), "^demo%-%x+$")
    end)

    it("is stable for the same path", function()
        assert.eq(project.key("/tmp/demo"), project.key("/tmp/demo"))
    end)

    it("differs for same-named projects in different places", function()
        assert.neq(project.key("/a/demo"), project.key("/b/demo"))
    end)

    it("ignores a trailing slash", function()
        assert.eq(project.key("/tmp/demo/"), project.key("/tmp/demo"))
    end)
end)

describe("project.relative", function()
    it("makes a path relative to the root", function()
        assert.eq(project.relative("/p", "/p/src/a.lua"), "src/a.lua")
    end)

    it("returns the path unchanged when it is outside the root", function()
        assert.eq(project.relative("/p", "/other/a.lua"), "/other/a.lua")
    end)
end)
