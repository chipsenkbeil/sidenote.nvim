local editor = require("sidenote.editor")
local capture = require("sidenote.capture")
local session = require("sidenote.session")
local store = require("sidenote.store")

---@return sidenote.Config
local function opts()
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".annotations",
        global_dir = vim.fn.tempname(),
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 40 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Capture one annotation and return its entry.
---@return sidenote.session.Entry
local function annotated()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.annotations", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(SOURCE, "\n") .. "\n")
    fh:close()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, SOURCE)
    capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })

    return session.entries(bufnr, opts())[1]
end

describe("editor.open", function()
    it("opens the real prose file, not a copy", function()
        local entry = annotated()
        local winid = editor.open(entry, opts().editor, "org")
        local bufnr = vim.api.nvim_win_get_buf(winid)
        assert.eq(
            vim.api.nvim_buf_get_name(bufnr),
            vim.uv.fs_realpath(store.prose_path(entry.root, entry.id, "org"))
        )
        require("sidenote.window").close(winid)
    end)

    it("opens the file on disk when the configured extension has changed", function()
        -- The note was written as org; asking for txt must not create an
        -- empty second prose file beside it
        local entry = annotated()
        local winid = editor.open(entry, opts().editor, "txt")
        local bufnr = vim.api.nvim_win_get_buf(winid)
        assert.eq(
            vim.api.nvim_buf_get_name(bufnr),
            vim.uv.fs_realpath(store.prose_path(entry.root, entry.id, "org"))
        )
        assert.eq(vim.bo[bufnr].filetype, "org")
        require("sidenote.window").close(winid)
    end)

    it("sets the configured filetype so the user's plugins apply", function()
        local winid = editor.open(annotated(), opts().editor, "org")
        assert.eq(vim.bo[vim.api.nvim_win_get_buf(winid)].filetype, "org")
        require("sidenote.window").close(winid)
    end)

    it("leaves the cursor in the source buffer by default", function()
        local before = vim.api.nvim_get_current_win()
        local winid = editor.open(annotated(), opts().editor, "org")
        assert.eq(vim.api.nvim_get_current_win(), before)
        require("sidenote.window").close(winid)
    end)

    it("moves the cursor into the note when focus is asked for", function()
        local config = opts().editor
        config.focus = true
        local winid = editor.open(annotated(), config, "org")
        assert.eq(vim.api.nvim_get_current_win(), winid)
        require("sidenote.window").close(winid)
    end)

    it("writes the user's prose through to the store", function()
        local entry = annotated()
        local winid = editor.open(entry, opts().editor, "org")
        local bufnr = vim.api.nvim_win_get_buf(winid)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "what I think about this" })
        vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("silent write")
        end)
        require("sidenote.window").close(winid)

        assert.eq(store.prose(entry.root, entry.id, "org"), "what I think about this\n")
    end)

    it("reuses one window rather than stacking them", function()
        local entry = annotated()
        local first = editor.open(entry, opts().editor, "org")
        local second = editor.open(entry, opts().editor, "org")
        assert.eq(first, second)
        require("sidenote.window").close(second)
    end)

    it("opens a fresh window after the previous one was closed", function()
        local entry = annotated()
        local first = editor.open(entry, opts().editor, "org")
        require("sidenote.window").close(first)
        local second = editor.open(entry, opts().editor, "org")
        assert.truthy(vim.api.nvim_win_is_valid(second))
        require("sidenote.window").close(second)
    end)
end)
