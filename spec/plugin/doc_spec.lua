---Hand-written vimdoc rots unless something checks it, so this compares the
---help file against what the plugin actually registers.

---@param path string
---@return string
local function read(path)
    local fh = assert(io.open(path, "r"))
    local body = fh:read("*a")
    fh:close()
    return body
end

---@return string
local function help()
    return read("doc/sidenote.txt")
end

---@return string
local function entry()
    return read("plugin/sidenote.lua")
end

describe("vimdoc", function()
    it("is where Neovim looks for it", function()
        assert.truthy(vim.uv.fs_stat("doc/sidenote.txt"))
    end)

    it("declares a modeline, so the help file renders as help", function()
        assert.contains(help(), "vim:tw=78:ts=8:noet:ft=help:norl:")
    end)

    it("generates help tags without complaint", function()
        vim.opt.runtimepath:append(vim.fn.getcwd())
        vim.cmd("helptags doc")
        assert.truthy(vim.uv.fs_stat("doc/tags"))
    end)

    it("resolves its own table of contents", function()
        -- Every entry in the contents list is a real tag, so no section of the
        -- help is unreachable from its front page
        vim.cmd("helptags doc")
        local tags = read("doc/tags")
        local contents = help():match("CONTENTS.-\n\n(.-)\n=====")
        for tag in contents:gmatch("|(sidenote%-[%w-]+)|") do
            assert.contains(tags, tag .. "\t", "unreachable section: " .. tag)
        end
    end)
end)

describe("the documented Neovim version", function()
    ---Lowest version the workflow actually runs the suite against.
    ---@return string
    local function ci_floor()
        local workflow = read(".github/workflows/tests.yml")
        local matrix = assert(workflow:match("version:%s*\n(.-)\n%s*os:"))
        local lowest
        for version in matrix:gmatch("v(%d+%.%d+%.%d+)") do
            lowest = lowest or version
        end
        return assert(lowest, "no pinned versions in the matrix")
    end

    it("matches the floor CI proves, in the help", function()
        -- Claiming a version nothing runs against is a claim nobody checked
        assert.contains(help(), "Neovim " .. ci_floor():match("^%d+%.%d+"))
    end)

    it("matches the floor CI proves, in the README", function()
        assert.contains(read("README.md"), "Neovim **" .. ci_floor():match("^%d+%.%d+"))
    end)

    it("names the API that sets the floor, so raising it is a decision", function()
        for _, doc in ipairs({ help(), read("README.md") }) do
            assert.contains(doc, "vim.fs.relpath")
        end
    end)
end)

describe("vimdoc coverage", function()
    -- Each of these walks a real list and asserts the count too: a coverage
    -- test that iterates nothing passes without proving anything

    it("documents every <Plug> mapping the plugin registers", function()
        local documented, found = help(), 0
        for mapping in entry():gmatch("(<Plug>%(Sidenote%w+%))") do
            found = found + 1
            assert.contains(documented, "*" .. mapping .. "*", "undocumented: " .. mapping)
        end
        assert.gt(found, 0, "no mappings found, so this test proved nothing")
    end)

    it("documents every subcommand the plugin completes", function()
        local documented, found = help():match("COMMANDS.-\n(.-)\n====="), 0
        for name in entry():match("local SUBCOMMANDS = (%b{})"):gmatch('"(%w+)"') do
            found = found + 1
            assert.contains(documented, name, "undocumented subcommand: " .. name)
        end
        assert.gt(found, 0, "no subcommands found, so this test proved nothing")
    end)

    it("documents every public API function", function()
        local documented, found = help(), 0
        for name in pairs(require("sidenote")) do
            found = found + 1
            assert.contains(documented, "sidenote." .. name .. "()", "undocumented API: " .. name)
        end
        assert.gt(found, 0, "no API functions found, so this test proved nothing")
    end)

    it("documents every configuration key with a default", function()
        local documented, found = help(), 0
        for key in pairs(require("sidenote.config").defaults()) do
            found = found + 1
            assert.contains(documented, key, "undocumented config key: " .. key)
        end
        assert.gt(found, 0, "no config keys found, so this test proved nothing")
    end)

    it("documents every anchor status the resolver can conclude with", function()
        local documented = help()
        local statuses = require("sidenote.core.resolve").STATUS_NAMES
        for _, status in ipairs(statuses) do
            assert.contains(documented, status, "undocumented status: " .. status)
        end
        assert.gt(#statuses, 0, "no statuses found, so this test proved nothing")
    end)
end)
