local browser = require("sidenote.browser")
local capture = require("sidenote.capture")
local store = require("sidenote.store")

---@return sidenote.Config
local function opts()
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".sidenote",
        global_dir = vim.fn.tempname(),
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 60 },
        browser = { style = "current" },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Build a project with one source file open in a buffer.
---@return integer
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

---Capture an annotation and write prose the user would have written.
---@param bufnr integer
---@param line integer
---@param prose string[]
---@return string id
local function annotate(bufnr, line, prose)
    local cfg = opts()
    local result =
        assert(capture.run(bufnr, { scope = "lines", range = { line, 0, line, 0 }, config = cfg }))
    local fh = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
    fh:write(table.concat(prose, "\n") .. "\n")
    fh:close()
    return result.id
end

describe("browser.open", function()
    it("names the buffer after the resolved absolute source path", function()
        -- Absolute, so two projects open at once cannot collide on one
        -- relative path, and the browser can recover its roots from its name
        local source = project_buffer()
        local bufnr = assert(browser.open(source, { config = opts() }))
        local path = vim.uv.fs_realpath(vim.api.nvim_buf_get_name(source))
        assert.eq(vim.api.nvim_buf_get_name(bufnr), "sidenote://" .. path)
    end)

    it("uses an acwrite buftype so :w is interceptable", function()
        local bufnr = assert(browser.open(project_buffer(), { config = opts() }))
        assert.eq(vim.bo[bufnr].buftype, "acwrite")
        assert.eq(vim.bo[bufnr].filetype, "sidenote")
    end)

    it("never reads as modified, so abandoning edits cannot complain", function()
        -- The listing is a projection of the store, not a document: `:w` is
        -- the one way anything applies, and closing simply discards
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        local bufnr = assert(browser.open(source, { config = opts() }))
        vim.api.nvim_set_current_buf(bufnr)

        vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "half-typed prose" })
        vim.cmd("doautocmd TextChanged")
        assert.falsy(vim.bo[bufnr].modified)

        vim.api.nvim_set_current_buf(source)
        vim.cmd("bdelete " .. bufnr)
        assert.falsy(vim.api.nvim_buf_is_loaded(bufnr))
    end)

    it("sets the conceal and fold options on the window, not the buffer", function()
        -- Both are window-local; setting them on the buffer would silently do
        -- nothing and leave every id on screen
        assert(browser.open(project_buffer(), { config = opts() }))
        local winid = vim.api.nvim_get_current_win()
        assert.eq(vim.wo[winid].conceallevel, 3)
        assert.eq(vim.wo[winid].concealcursor, "nvic")
        assert.eq(vim.wo[winid].foldmethod, "expr")
        assert.contains(vim.wo[winid].foldtext, "foldtext")
        assert.contains(vim.wo[winid].foldexpr, "^/")
    end)

    it("turns wrapping off, so expanding a row does not change its shape", function()
        -- A closed fold never wraps whatever 'wrap' says, so leaving it on
        -- makes one row reflow the moment it is opened
        assert(browser.open(project_buffer(), { config = opts() }))
        assert.falsy(vim.wo[vim.api.nvim_get_current_win()].wrap)
    end)

    it("reuses the buffer when the same source is browsed again", function()
        local source = project_buffer()
        local first = assert(browser.open(source, { config = opts() }))
        assert.eq(browser.open(source, { config = opts() }), first)
    end)

    it("opens with every note's prose folded, headers in plain sight", function()
        -- Entries sort by line, so the note on line 1 renders first and the
        -- one on line 4 renders second, carrying its body with it
        local source = project_buffer()
        annotate(source, 4, { "has a body", "the body line" })
        annotate(source, 1, { "just a summary" })

        assert(browser.open(source, { config = opts() }))
        assert.eq(vim.fn.foldclosed(1), -1, "a header is never folded")
        assert.eq(vim.fn.foldclosed(2), 2, "the prose folds shut, summary included")
        assert.eq(vim.fn.foldclosedend(2), 2)
        assert.eq(vim.fn.foldclosed(3), -1)
        assert.eq(vim.fn.foldclosed(4), 4)
        assert.eq(vim.fn.foldclosedend(4), 5)
    end)

    it("stands a folded note in with its own summary, org-style", function()
        local source = project_buffer()
        annotate(source, 4, { "something is bacon", "body one", "body two" })
        assert(browser.open(source, { config = opts() }))

        assert.eq(vim.fn.foldclosed(2), 2)
        assert.eq(vim.fn.foldclosedend(2), 4)
        assert.contains(vim.fn.foldtextresult(2), "something is bacon")
    end)

    it("takes a whole note with dj, the closed prose counting once", function()
        -- An operator motion over a closed fold includes the whole fold, so
        -- header and however much prose is two lines to d
        local source = project_buffer()
        annotate(source, 4, { "summary", "body one", "body two" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.cmd("normal! dj")
        assert.eq_deep(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "" })
    end)

    it("renders a row for every annotation targeting the source", function()
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        assert.eq(#lines, 2)
        assert.contains(lines[1], "m.lua:4")
        assert.contains(lines[2], "the note")
    end)

    it("refuses a buffer that resolves to no store, rather than opening empty", function()
        local loose = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(loose, vim.fn.tempname() .. "/loose.lua")
        vim.api.nvim_buf_set_lines(loose, 0, -1, false, SOURCE)

        local bufnr, err = browser.open(loose, { config = opts() })
        assert.is_nil(bufnr)
        assert.not_nil(err)
    end)

    it("refuses a buffer with no file name", function()
        local bufnr, err = browser.open(vim.api.nvim_create_buf(false, true), { config = opts() })
        assert.is_nil(bufnr)
        assert.not_nil(err)
    end)
end)

describe("browser window options", function()
    it("gives a window its own options back once it shows something else", function()
        -- Fold and conceal settings are window-local, not buffer-local: left
        -- behind, the next file shown there collapses into one closed fold
        local winid = vim.api.nvim_get_current_win()
        -- Step out of any listing an earlier test left in this window
        vim.cmd.enew()
        vim.wo[winid].foldmethod = "indent"
        vim.wo[winid].conceallevel = 1
        assert(browser.open(project_buffer(), { config = opts() }))
        assert.eq(vim.wo[winid].foldmethod, "expr")

        vim.cmd.enew()
        assert.eq(vim.wo[winid].foldmethod, "indent")
        assert.eq(vim.wo[winid].conceallevel, 1)
    end)

    it("restores the window even when the listing is wiped out from under it", function()
        -- The hard case for any save-and-restore scheme: the replacement
        -- buffer inherits the window's values as the switch completes
        local winid = vim.api.nvim_get_current_win()
        vim.cmd.enew()
        vim.wo[winid].foldmethod = "indent"

        -- Visit the listing, step out to a real file, and come back, the way
        -- a browse session actually goes, so several buffers are in play
        local source = project_buffer()
        assert(browser.open(source, { config = opts() }))
        vim.cmd.edit(vim.api.nvim_buf_get_name(source))
        assert(browser.open(source, { config = opts() }))
        assert.eq(vim.wo[winid].foldmethod, "expr")

        vim.cmd("silent! %bwipeout!")
        assert.eq(vim.wo[winid].foldmethod, "indent")
    end)

    it("keeps the user's options through a re-listing in one window", function()
        -- Widening with `-` reuses the window; the user's values must be what
        -- comes back however many listings were shown there in a row
        local winid = vim.api.nvim_get_current_win()
        -- Step out of any listing an earlier test left in this window
        vim.cmd.enew()
        vim.wo[winid].foldmethod = "indent"
        local source = project_buffer()
        assert(browser.open(source, { config = opts() }))
        assert(browser.open_project(vim.api.nvim_buf_get_name(source), { config = opts() }))
        assert.eq(vim.wo[winid].foldmethod, "expr")

        vim.cmd.enew()
        assert.eq(vim.wo[winid].foldmethod, "indent")
    end)
end)

describe("browser.state", function()
    it("returns the rows as rendered, in buffer order", function()
        local source = project_buffer()
        annotate(source, 4, { "later" })
        annotate(source, 1, { "earlier" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        local state = assert(browser.state(bufnr))
        assert.eq(#state.rows, 2)
        assert.eq(state.rows[1].prose[1], "earlier")
        assert.eq(state.rows[2].prose[1], "later")
    end)

    it("carries the store root each annotation came from", function()
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        local state = assert(browser.state(assert(browser.open(source, { config = opts() }))))
        assert.contains(state.rows[1].entry.root, ".sidenote")
    end)

    it("keeps the source path so a create knows what it is annotating", function()
        local source = project_buffer()
        local bufnr = assert(browser.open(source, { config = opts() }))
        local state = assert(browser.state(bufnr))
        assert.eq(state.path, vim.uv.fs_realpath(vim.api.nvim_buf_get_name(source)))
    end)

    it("is nil for a buffer that is not a browser", function()
        assert.is_nil(browser.state(vim.api.nvim_create_buf(false, true)))
    end)

    it("normalizes prose the same way the renderer does", function()
        -- The state is the diff baseline; normalized differently from what was
        -- rendered, it would report an edit nobody made
        local source = project_buffer()
        annotate(source, 4, { "the note", "", "" })
        local state = assert(browser.state(assert(browser.open(source, { config = opts() }))))
        assert.eq_deep(state.rows[1].prose, { "the note" })
    end)
end)
