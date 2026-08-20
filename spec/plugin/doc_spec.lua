---`doc/sidenote.txt` is generated from README.md and the plugin's own source.
---These check the pipeline's contract: that the help file is a real help file,
---that its tags resolve, and that the README declares a block for every
---reference section. Coverage of the API, commands and config is no longer
---asserted here — generation is what guarantees it.

---@param path string
---@return string
local function read(path)
    local fh = assert(io.open(path, "r"), path .. " is missing")
    local body = fh:read("*a")
    fh:close()
    return body
end

---@return string
local function help()
    return read("doc/sidenote.txt")
end

describe("the generated help file", function()
    it("is where Neovim looks for it", function()
        assert.truthy(vim.uv.fs_stat("doc/sidenote.txt"))
    end)

    it("declares a modeline, so it renders as help", function()
        assert.contains(help(), "vim:tw=78:ts=8:ft=help:norl:")
    end)

    it("opens with the help-file tag and a description", function()
        local first = help():match("^([^\n]*)")
        assert.contains(first, "*sidenote.txt*")
        assert.contains(first, "Notes on your code")
    end)

    it("wraps every line to the page", function()
        for line in help():gmatch("([^\n]*)\n") do
            assert.lte(#line, 78, "overlong line: " .. line)
        end
    end)

    it("generates help tags without complaint", function()
        vim.opt.runtimepath:append(vim.fn.getcwd())
        vim.cmd("helptags doc")
        assert.truthy(vim.uv.fs_stat("doc/tags"))
    end)

    it("resolves every tag it links to", function()
        -- A |link| with no matching *tag* is a dead end for a reader
        vim.cmd("helptags doc")
        local tags = read("doc/tags")
        local linked = 0
        for tag in help():gmatch("|(sidenote[%w.-]*)|") do
            linked = linked + 1
            assert.contains(tags, tag .. "\t", "dangling link: " .. tag)
        end
        assert.gt(linked, 5, "no links found, so this test proved nothing")
    end)

    it("keeps the tags a reader may already have bookmarked", function()
        -- Pinned in README with `vimdoc:tag` or `vimdoc:anchor`, so renaming a
        -- heading cannot silently break `:help sidenote-export-gate`
        local pinned = {
            ":Sidenote",
            "vim.g.sidenote",
            "sidenote-browser",
            "sidenote-export-gate",
            "sidenote-storage",
            "sidenote-filtering",
            "sidenote-api",
            "sidenote-agents",
            "sidenote-never-deleted",
        }
        for _, tag in ipairs(pinned) do
            assert.contains(help(), ("*%s*"):format(tag), "lost tag: " .. tag)
        end
    end)
end)

describe("the README as documentation source", function()
    ---@return string
    local function readme()
        return read("README.md")
    end

    it("declares a generated block for every reference section", function()
        for _, name in ipairs({ "config", "commands", "mappings", "api", "statuses" }) do
            assert.contains(readme(), ("<!-- gen:%s -->"):format(name))
            assert.contains(readme(), ("<!-- /gen:%s -->"):format(name))
        end
    end)

    it("has its generated blocks filled in", function()
        -- An empty block means the generator has not run since the marker was
        -- added, and `make docs-check` would be the only thing to notice
        local body = readme()
        for name in body:gmatch("<!%-%- gen:(%w+) %-%->") do
            local block = body:match(("<!%%-%%- gen:%s %%-%%->\n(.-)<!%%-%%- /gen:"):format(name))
            assert.not_nil(block, name .. " has no closing marker")
            assert.truthy(block:match("%S"), name .. " is empty")
        end
    end)

    it("documents the minimum Neovim version the matrix proves", function()
        local matrix =
            assert(read(".github/workflows/tests.yml"):match("version:%s*\n(.-)\n%s*os:"))
        local floor = assert(matrix:match("v(%d+%.%d+)"))
        assert.contains(readme(), "Neovim " .. floor)
        assert.contains(help(), "Neovim " .. floor)
    end)

    it("names the API that sets that floor, so raising it is a decision", function()
        assert.contains(readme(), "vim.fs.relpath")
    end)

    it("ships the agent skill it advertises", function()
        assert.contains(readme(), "skills/sidenote/SKILL.md")
        assert.truthy(vim.uv.fs_stat("skills/sidenote/SKILL.md"))
    end)
end)
