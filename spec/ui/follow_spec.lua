local editor = require("sidenote.editor")
local fixture = require("spec.fixture")
local follow = require("sidenote.follow")
local store = require("sidenote.store")
local window = require("sidenote.window")

---@return sidenote.Config
local function opts()
    return fixture.opts({
        pens = {},
        indicator = { highlight = "off" },
        editor = { size = 40 },
    })
end

local project_buffer = fixture.project_buffer

---@param bufnr integer
---@param line integer
---@param prose string[]
---@return string id
---@return string root
local function annotate(bufnr, line, prose)
    local note = fixture.annotate({ bufnr = bufnr, line = line, prose = prose, config = opts() })
    return note.id, note.root
end

---Move the cursor as a user would, autocmds and all.
---@param bufnr integer
---@param line integer
local function move_to(bufnr, line)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd("doautocmd CursorMoved")
end

---Return the prose file the editor window currently shows.
---@return string
local function showing()
    local win = assert(editor.winid(), "no editor window is open")
    return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
end

describe("follow", function()
    after_each(function()
        follow.disable()
        local win = editor.winid()
        if win then
            window.close(win)
        end
    end)

    it("opens the note under the cursor without stealing focus", function()
        local source = project_buffer()
        local id = annotate(source, 4, { "the note" })
        vim.api.nvim_set_current_buf(source)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        local before = vim.api.nvim_get_current_win()

        follow.enable(opts())
        assert.eq(vim.api.nvim_get_current_win(), before)
        assert.contains(showing(), id)
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
    end)

    it("keeps the last note while the cursor rests on unannotated code", function()
        local source = project_buffer()
        local id = annotate(source, 4, { "the note" })
        vim.api.nvim_set_current_buf(source)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        follow.enable(opts())

        move_to(source, 1)
        assert.contains(showing(), id)
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
    end)

    it("turns itself off when the panel is closed", function()
        local source = project_buffer()
        annotate(source, 3, { "first" })
        annotate(source, 4, { "second" })
        vim.api.nvim_set_current_buf(source)
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
        follow.enable(opts())

        window.close(assert(editor.winid()))
        move_to(source, 4)
        assert.is_nil(editor.winid(), "a closed panel stays closed")
        assert.falsy(follow.active())
    end)

    it("toggles", function()
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        vim.api.nvim_set_current_buf(source)
        assert.eq(follow.toggle(opts()), true)
        assert.eq(follow.toggle(opts()), false)
    end)
end)
