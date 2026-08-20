---What `:Sidenote add` and `<Plug>(SidenoteAdd)` actually store.
---
---`entry_spec` reads the plugin file as text; these run it. Registration is
---rebuilt before each test and torn down after, so the autocmds it installs
---cannot fire during any other spec.

local store = require("sidenote.store")

local LINES = { "local a = 1", "local b = 2", "local c = 3", "local d = 4", "local e = 5" }

---@return string root
local function project()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.annotations", "p")
    local fh = assert(io.open(root .. "/code.lua", "w"))
    fh:write(table.concat(LINES, "\n") .. "\n")
    fh:close()
    return assert(vim.uv.fs_realpath(root))
end

---The one record a test's capture wrote.
---@param root string
---@return sidenote.Annotation
local function only_record(root)
    local ids = store.ids(root .. "/.annotations")
    assert.eq(#ids, 1, "expected exactly one annotation")
    return assert(store.read(root .. "/.annotations", ids[1]))
end

describe("the :Sidenote command", function()
    before_each(function()
        vim.g.sidenote = { strategy = "project" }
        vim.g.loaded_sidenote = nil
        dofile("plugin/sidenote.lua")
        -- A browser opened in this shared window earlier left its fold options
        -- behind, and an Ex range on a closed fold expands to the whole fold
        vim.wo.foldenable = false
        vim.wo.foldmethod = "manual"
    end)

    after_each(function()
        vim.g.sidenote = nil
        pcall(vim.api.nvim_del_augroup_by_name, "sidenote")
        pcall(vim.api.nvim_del_user_command, "Sidenote")
        vim.cmd("silent! %bwipeout!")
    end)

    it("captures a command range as lines scope, which has no columns", function()
        local root = project()
        vim.cmd.edit(root .. "/code.lua")

        vim.cmd("2,4Sidenote add")

        local rec = only_record(root)
        assert.eq(rec.scope, "lines")
        assert.eq(rec.line_start, 2)
        assert.eq(rec.line_end, 4)
        assert.eq(rec.col_start, 0)
    end)

    it("captures the cursor line when no range is given", function()
        local root = project()
        vim.cmd.edit(root .. "/code.lua")
        vim.api.nvim_win_set_cursor(0, { 3, 0 })

        vim.cmd("Sidenote add")

        local rec = only_record(root)
        assert.eq(rec.scope, "lines")
        assert.eq(rec.line_start, 3)
        assert.eq(rec.line_end, 3)
    end)

    it("captures a visual selection as lines scope too", function()
        local root = project()
        vim.cmd.edit(root .. "/code.lua")
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        local plug = vim.api.nvim_replace_termcodes("<Plug>(SidenoteAdd)", true, false, true)
        vim.api.nvim_feedkeys("V2j" .. plug, "x", false)
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "x",
            false
        )

        local rec = only_record(root)
        assert.eq(rec.scope, "lines")
        assert.eq(rec.line_start, 1)
        assert.eq(rec.line_end, 3)
        assert.eq(rec.col_start, 0)
    end)
end)
