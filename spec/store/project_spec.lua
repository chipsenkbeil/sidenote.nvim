local project = require("sidenote.store.project")

---Build a throwaway directory tree and return its root.
---
---A trailing slash makes a directory; anything else makes an empty file.
---@param paths string[]
---@return string
local function tree(paths)
    local root = vim.fn.tempname()
    for _, rel in ipairs(paths) do
        local full = root .. "/" .. rel
        if rel:sub(-1) == "/" then
            vim.fn.mkdir(full, "p")
        else
            vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
            local fh = assert(io.open(full, "w"))
            fh:write("")
            fh:close()
        end
    end
    return root
end

describe("project.MARKERS", function()
    it("puts .annotations first so a bare directory can opt in", function()
        assert.eq(project.MARKERS[1], ".annotations")
    end)
end)

describe("project.root", function()
    it("finds a root marked by .annotations", function()
        local root = tree({ ".annotations/", "src/a.lua" })
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
        local outer = tree({ ".git/", "inner/.annotations/", "inner/src/a.lua" })
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

describe("project.root with a rockspec", function()
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
        -- The marker the Lua ecosystem actually uses, and the one a Neovim
        -- plugin repo is most likely to carry
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
