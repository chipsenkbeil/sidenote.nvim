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
    vim.fn.mkdir(root .. "/.sidenote", "p")
    local fh = assert(io.open(root .. "/code.lua", "w"))
    fh:write(table.concat(LINES, "\n") .. "\n")
    fh:close()
    return assert(vim.uv.fs_realpath(root))
end

---The one record a test's capture wrote.
---@param root string
---@return sidenote.Annotation
local function only_record(root)
    local ids = store.ids(root .. "/.sidenote")
    assert.eq(#ids, 1, "expected exactly one annotation")
    return assert(store.read(root .. "/.sidenote", ids[1]))
end

---Close the tracked note window, splitting first when it is the last one.
---
---Left open, a later spec's `editor.open` would reuse it instead of
---splitting, and every window assertion there changes meaning.
local function put_away()
    local winid = require("sidenote.editor").winid()
    if not winid then
        return
    end
    if #vim.api.nvim_tabpage_list_wins(0) == 1 then
        vim.cmd.split()
    end
    require("sidenote.window").close(winid)
end

---Run `:Sidenote add` over `range` and put away the note editor it opens.
---@param range string Ex range prefix, or "" for the cursor line
local function add(range)
    local before = vim.api.nvim_get_current_win()
    vim.cmd(range .. "Sidenote add")
    put_away()
    vim.api.nvim_set_current_win(before)
end

describe("the :Sidenote command", function()
    before_each(function()
        vim.g.sidenote = { strategy = "project" }
        vim.g.loaded_sidenote = nil
        dofile("plugin/sidenote.lua")
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

        add("2,4")

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

        add("")

        local rec = only_record(root)
        assert.eq(rec.scope, "lines")
        assert.eq(rec.line_start, 3)
        assert.eq(rec.line_end, 3)
    end)

    it("writes a moved anchor back on :write", function()
        -- The full loop: annotate, edit the code above, save, and the record
        -- on disk follows the code
        local root = project()
        vim.cmd.edit(root .. "/code.lua")
        add("3")

        vim.api.nvim_buf_set_lines(0, 0, 0, false, { "-- a new first line" })
        vim.cmd.write()

        local rec = only_record(root)
        assert.eq(rec.line_start, 4)
        assert.eq(rec.text, "local c = 3")
    end)

    it("narrows a listing with a bare key=value filter", function()
        -- Bare key=value is vim's own convention, the way :set and :Telescope
        -- take options; a -- prefix belongs to shells
        local root = project()
        vim.cmd.edit(root .. "/code.lua")
        add("1")
        add("3")

        vim.cmd("Sidenote browse state=open")
        assert.eq(#vim.api.nvim_buf_get_lines(0, 0, -1, false), 2)
        vim.cmd("edit " .. root .. "/code.lua")
        vim.cmd("Sidenote browse state=resolved")
        assert.eq_deep(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
    end)

    it("rejects a misspelled filter key instead of silently matching all", function()
        local root = project()
        vim.cmd.edit(root .. "/code.lua")

        local messages = {}
        local original = vim.notify
        vim.notify = function(msg)
            messages[#messages + 1] = msg
        end
        vim.cmd("Sidenote browse staus=orphaned")
        vim.notify = original
        assert.contains(table.concat(messages, "\n"), "staus")
    end)

    it("rejects a filter value the plugin never produces", function()
        local root = project()
        vim.cmd.edit(root .. "/code.lua")

        local messages = {}
        local original = vim.notify
        vim.notify = function(msg)
            messages[#messages + 1] = msg
        end
        vim.cmd("Sidenote browse status=banana")
        vim.notify = original
        assert.contains(table.concat(messages, "\n"), "banana")
    end)

    it("narrows a project listing by path= from the command line", function()
        local root = project()
        vim.cmd.edit(root .. "/code.lua")
        add("3")

        vim.cmd("Sidenote project path=code")
        assert.eq(#vim.api.nvim_buf_get_lines(0, 0, -1, false), 1)
        vim.cmd("edit " .. root .. "/code.lua")
        vim.cmd("Sidenote project path=elsewhere")
        assert.eq_deep(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
    end)

    it("completes filter keys and their values", function()
        project()
        local keys = vim.fn.getcompletion("Sidenote browse st", "cmdline")
        assert.contains(table.concat(keys, " "), "status=")
        assert.contains(table.concat(keys, " "), "state=")

        local values = vim.fn.getcompletion("Sidenote browse status=orph", "cmdline")
        assert.eq_deep(values, { "status=orphaned" })
    end)

    it("captures the whole file with add scope=file", function()
        local root = project()
        vim.cmd.edit(root .. "/code.lua")

        local before = vim.api.nvim_get_current_win()
        vim.cmd("Sidenote add scope=file")
        put_away()
        vim.api.nvim_set_current_win(before)

        local rec = only_record(root)
        assert.eq(rec.scope, "file")
        assert.eq(rec.line_start, 0)
    end)

    it("completes scope=file after add", function()
        project()
        assert.eq_deep(vim.fn.getcompletion("Sidenote add sc", "cmdline"), { "scope=file" })
    end)

    it("captures the whole file from its own mapping", function()
        local root = project()
        vim.cmd.edit(root .. "/code.lua")

        local before = vim.api.nvim_get_current_win()
        local plug = vim.api.nvim_replace_termcodes("<Plug>(SidenoteAddFile)", true, false, true)
        vim.api.nvim_feedkeys(plug, "x", false)
        put_away()
        vim.api.nvim_set_current_win(before)

        assert.eq(only_record(root).scope, "file")
    end)

    it("toggles range highlights with the highlight subcommand", function()
        local root = project()
        vim.cmd.edit(root .. "/code.lua")
        add("2,4")

        local render = require("sidenote.render")
        local function range_marks()
            local found = 0
            local marks =
                vim.api.nvim_buf_get_extmarks(0, render.NAMESPACE, 0, -1, { details = true })
            for _, mark in ipairs(marks) do
                if mark[4].hl_group then
                    found = found + 1
                end
            end
            return found
        end

        -- On out of the box; the toggle takes it away and brings it back
        assert.eq(range_marks(), 1)
        vim.cmd("Sidenote highlight")
        assert.eq(range_marks(), 0)
        vim.cmd("Sidenote highlight")
        assert.eq(range_marks(), 1)
    end)

    it("lets the mark track an edit, and :w re-baselines the record to it", function()
        -- Inserting a line inside a span grows the mark over it: the mark is
        -- the truth while you edit, and saving writes that truth back
        vim.g.sidenote = { strategy = "project", indicator = { highlight = "always" } }
        local root = project()
        vim.cmd.edit(root .. "/code.lua")
        add("1,3")

        vim.api.nvim_buf_set_lines(0, 2, 2, false, { "-- a wedge" })

        local render = require("sidenote.render")
        local function widest()
            local most = 0
            local marks =
                vim.api.nvim_buf_get_extmarks(0, render.NAMESPACE, 0, -1, { details = true })
            for _, mark in ipairs(marks) do
                if mark[4].end_row then
                    most = math.max(most, mark[4].end_row - mark[2] + 1)
                end
            end
            return most
        end

        assert.eq(widest(), 4, "the grown mark is the point, not the bug")
        vim.cmd.write()

        local rec = only_record(root)
        assert.eq(rec.line_start, 1)
        assert.eq(rec.line_end, 4)
        assert.contains(rec.text, "wedge")
        assert.eq(widest(), 4, "the repaint agrees with the record")
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
