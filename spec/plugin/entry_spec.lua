---@return string
local function entry_source()
    local fh = assert(io.open("plugin/sidenote.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    return src
end

describe("plugin entry point", function()
    it("requires the implementation only from inside a callback", function()
        -- A load-time require would defeat the plugin's own lazy loading; every
        -- legitimate one sits inside a block, so it is indented
        for line in entry_source():gmatch("[^\n]+") do
            if line:find('require("sidenote', 1, true) then
                assert.match(line, "^%s", "top-level require: " .. line)
            end
        end
    end)

    it("guards against loading twice", function()
        assert.contains(entry_source(), "vim.g.loaded_sidenote")
    end)

    it("registers exactly one user command", function()
        local _, count = entry_source():gsub("nvim_create_user_command", "")
        assert.eq(count, 1)
    end)

    it("registers no default keymaps, only <Plug> mappings", function()
        local calls = 0
        for args in entry_source():gmatch("vim%.keymap%.set(%b())") do
            calls = calls + 1
            -- The mode is either a quoted string or a table of them, so the
            -- mapping is the quoted string after the first top-level comma
            local mapping = args:match('^%(%s*%b{}%s*,%s*"([^"]+)"')
                or args:match('^%(%s*"[^"]*"%s*,%s*"([^"]+)"')
            assert.not_nil(mapping, "could not read the mapping from: " .. args)
            assert.match(mapping, "^<Plug>%(", "non-<Plug> mapping: " .. mapping)
        end
        assert.gt(calls, 0, "no keymaps found, so this test proved nothing")
    end)

    it("names its autocmd group so a reload cannot orphan handlers", function()
        assert.contains(entry_source(), 'nvim_create_augroup("sidenote"')
    end)
end)

describe("sidenote public API", function()
    it("exposes every verb the command and mappings call", function()
        local sidenote = require("sidenote")
        for _, name in ipairs({
            "add",
            "browse",
            "browse_project",
            "refresh",
            "entries",
            "at_cursor",
            "view",
            "open",
            "next",
            "prev",
        }) do
            assert.is_type(sidenote[name], "function", "missing API function: " .. name)
        end
    end)
end)

describe("command and mapping coverage", function()
    it("registers a <Plug> mapping for every user-facing verb", function()
        local src = entry_source()
        for _, name in ipairs({
            "Add",
            "Browse",
            "BrowseProject",
            "Refresh",
            "View",
            "Open",
            "ViewNext",
            "ViewPrev",
        }) do
            assert.contains(src, ("<Plug>(Sidenote%s)"):format(name))
        end
    end)

    it("completes every subcommand the command actually handles", function()
        local src = entry_source()
        local listed = src:match("local SUBCOMMANDS =%s*(%b{})")
        for _, name in ipairs({
            "add",
            "browse",
            "project",
            "refresh",
            "view",
            "open",
            "next",
            "prev",
        }) do
            assert.contains(listed, ('"%s"'):format(name))
        end
    end)

    it("never lists a subcommand it cannot handle", function()
        -- A completion entry that errors is worse than no completion at all
        local src = entry_source()
        for name in src:match("local SUBCOMMANDS =%s*(%b{})"):gmatch('"(%w+)"') do
            assert.contains(src, ('subcommand == "%s"'):format(name))
        end
    end)
end)

describe("sidenote.health", function()
    it("reports without throwing", function()
        local health = require("sidenote.health")
        assert.is_type(health.check, "function")
        health.check()
    end)
end)
