describe("core modules", function()
    local MODULES = { "hash", "record", "score", "resolve" }

    ---@param name string
    ---@return string
    local function source_of(name)
        local path = ("lua/sidenote/core/%s.lua"):format(name)
        local fh = assert(io.open(path, "r"), path .. " not found")
        local src = fh:read("*a")
        fh:close()
        return src
    end

    -- Editor state the core must never reach for. Anchor resolution has to run
    -- headlessly for an agent, and be directly testable without a buffer
    local FORBIDDEN = {
        { "orgmode", "requires orgmode" },
        { "nvim_buf_", "touches buffers" },
        { "nvim_win_", "touches windows" },
        { "nvim_create_autocmd", "registers autocmds" },
        { "vim.fs.root", "probes the filesystem for a project root" },
    }

    -- Ways to shell out. Checked separately from the words "git" and "jj",
    -- which legitimately appear in type annotations describing provenance
    local SHELLS = { "vim.fn.system", "vim.system", "io.popen", "os.execute" }

    it("depend on nothing but the Neovim Lua API", function()
        for _, name in ipairs(MODULES) do
            local src = source_of(name)
            for _, rule in ipairs(FORBIDDEN) do
                local needle, why = rule[1], rule[2]
                assert.is_nil(
                    src:find(needle, 1, true),
                    ("%s %s (found %q)"):format(name, why, needle)
                )
            end
        end
    end)

    it("never shell out", function()
        for _, name in ipairs(MODULES) do
            local src = source_of(name)
            for _, needle in ipairs(SHELLS) do
                assert.is_nil(
                    src:find(needle, 1, true),
                    ("%s shells out via %s"):format(name, needle)
                )
            end
        end
    end)

    it("never read or write files", function()
        -- `core/index.lua` is deliberately absent from MODULES: it is the one
        -- core module that touches disk, because the cache lives somewhere
        for _, name in ipairs(MODULES) do
            local src = source_of(name)
            assert.is_nil(src:find("io.open", 1, true), name .. " opens files")
            assert.is_nil(src:find("vim.uv.fs_", 1, true), name .. " stats files")
        end
    end)
end)
