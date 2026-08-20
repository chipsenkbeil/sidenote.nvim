local capture = require("sidenote.capture")
local editor = require("sidenote.editor")
local follow = require("sidenote.follow")
local store = require("sidenote.store")

---@return sidenote.Config
local function opts()
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".sidenote",
        global_dir = vim.fn.tempname(),
        pens = {},
        indicator = { style = "sign", highlight = "off" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 40 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---@return integer bufnr
local function project_buffer()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(SOURCE, "\n") .. "\n")
    fh:close()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, SOURCE)
    return bufnr
end

---@param bufnr integer
---@param line integer
---@param prose string[]
---@return string id
---@return string root
local function annotate(bufnr, line, prose)
    local cfg = opts()
    local result =
        assert(capture.run(bufnr, { scope = "lines", range = { line, 0, line, 0 }, config = cfg }))
    local fh = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
    fh:write(table.concat(prose, "\n") .. "\n")
    fh:close()
    return result.id, result.root
end

---Move the cursor as a user would, autocmds and all.
---@param bufnr integer
---@param line integer
local function move_to(bufnr, line)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd("doautocmd CursorMoved")
end

---The prose file the editor window currently shows.
---@return string
local function showing()
    local win = assert(editor.winid(), "no editor window is open")
    return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
end

local function put_away()
    follow.disable()
    local win = editor.winid()
    if win then
        require("sidenote.window").close(win)
    end
end

describe("follow", function()
    it("opens the note under the cursor without stealing focus", function()
        local source = project_buffer()
        local id = annotate(source, 4, { "the note" })
        vim.api.nvim_set_current_buf(source)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        local before = vim.api.nvim_get_current_win()

        follow.enable(opts())
        assert.eq(vim.api.nvim_get_current_win(), before)
        assert.contains(showing(), id)
        put_away()
    end)

    it("re-points the one window as the cursor crosses into another note", function()
        local source = project_buffer()
        local first = annotate(source, 3, { "first" })
        local second = annotate(source, 4, { "second" })

        vim.api.nvim_set_current_buf(source)
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
        follow.enable(opts())
        local win = assert(editor.winid())
        assert.contains(showing(), first)

        move_to(source, 4)
        assert.eq(editor.winid(), win, "the same window, re-pointed")
        assert.contains(showing(), second)
        put_away()
    end)

    it("keeps the last note while the cursor rests on unannotated code", function()
        local source = project_buffer()
        local id = annotate(source, 4, { "the note" })
        vim.api.nvim_set_current_buf(source)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        follow.enable(opts())

        move_to(source, 1)
        assert.contains(showing(), id)
        put_away()
    end)

    it("saves the prose it is leaving, so the store never lies", function()
        local source = project_buffer()
        local first, root = annotate(source, 3, { "first" })
        annotate(source, 4, { "second" })

        vim.api.nvim_set_current_buf(source)
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
        follow.enable(opts())
        local prose = vim.api.nvim_win_get_buf(assert(editor.winid()))
        vim.api.nvim_buf_set_lines(prose, 0, -1, false, { "rewritten in the panel" })

        move_to(source, 4)
        assert.eq(store.prose(root, first, "org"), "rewritten in the panel\n")
        put_away()
    end)

    it("turns itself off when the panel is closed", function()
        local source = project_buffer()
        annotate(source, 3, { "first" })
        annotate(source, 4, { "second" })
        vim.api.nvim_set_current_buf(source)
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
        follow.enable(opts())

        require("sidenote.window").close(assert(editor.winid()))
        move_to(source, 4)
        assert.is_nil(editor.winid(), "a closed panel stays closed")
        assert.falsy(follow.active())
        put_away()
    end)

    it("toggles", function()
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        vim.api.nvim_set_current_buf(source)
        assert.eq(follow.toggle(opts()), true)
        assert.eq(follow.toggle(opts()), false)
        put_away()
    end)
end)
