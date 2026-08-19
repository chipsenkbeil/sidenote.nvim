local preview = require("sidenote.preview")
local capture = require("sidenote.capture")
local session = require("sidenote.session")

---@return sidenote.Config
local function opts()
    return {
        filetype = "org",
        strategy = { "project" },
        project_dir = ".annotations",
        global_dir = vim.fn.tempname(),
        indicator = { style = "sign" },
        preview = { style = "float", max_lines = 20 },
        editor = { style = "split", position = "right", size = 60 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Capture one annotation and return its entry, with prose already written.
---@param prose string
---@return sidenote.session.Entry
local function annotated(prose)
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.annotations", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(SOURCE, "\n") .. "\n")
    fh:close()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, SOURCE)

    local result = capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
    local write = assert(io.open(result.paths.prose, "w"))
    write:write(prose)
    write:close()

    return session.entries(bufnr, opts())[1]
end

---@return integer
local function preview_buf()
    return vim.api.nvim_win_get_buf(assert.not_nil(preview.winid()))
end

describe("preview.show float", function()
    it("shows the prose in a floating window", function()
        preview.show(
            annotated("why this returns one\n"),
            { style = "float", max_lines = 20 },
            "org"
        )
        assert.eq(vim.api.nvim_buf_get_lines(preview_buf(), 0, 1, false)[1], "why this returns one")
        preview.hide()
    end)

    it("sets the configured filetype so the prose highlights", function()
        preview.show(annotated("* a heading\n"), { style = "float", max_lines = 20 }, "org")
        assert.eq(vim.bo[preview_buf()].filetype, "org")
        preview.hide()
    end)

    it("truncates to max_lines", function()
        preview.show(annotated(string.rep("line\n", 40)), { style = "float", max_lines = 5 }, "org")
        assert.lte(vim.api.nvim_buf_line_count(preview_buf()), 5)
        preview.hide()
    end)

    it("shows a placeholder when the note is still empty", function()
        preview.show(annotated(""), { style = "float", max_lines = 20 }, "org")
        assert.match(vim.api.nvim_buf_get_lines(preview_buf(), 0, -1, false)[1], "empty")
        preview.hide()
    end)

    it("leaves the preview buffer unmodifiable", function()
        preview.show(annotated("text\n"), { style = "float", max_lines = 20 }, "org")
        assert.eq(vim.bo[preview_buf()].modifiable, false)
        preview.hide()
    end)

    it("replaces a previous preview rather than stacking windows", function()
        local entry = annotated("first\n")
        preview.show(entry, { style = "float", max_lines = 20 }, "org")
        local first = preview.winid()
        preview.show(entry, { style = "float", max_lines = 20 }, "org")
        assert.falsy(vim.api.nvim_win_is_valid(first))
        preview.hide()
    end)

    it("leaves the cursor in the source buffer", function()
        local before = vim.api.nvim_get_current_win()
        preview.show(annotated("text\n"), { style = "float", max_lines = 20 }, "org")
        assert.eq(vim.api.nvim_get_current_win(), before)
        preview.hide()
    end)
end)

describe("preview.show none", function()
    it("opens nothing", function()
        preview.show(annotated("text\n"), { style = "none", max_lines = 20 }, "org")
        assert.is_nil(preview.winid())
    end)
end)

describe("preview.hide", function()
    it("closes the window", function()
        preview.show(annotated("text\n"), { style = "float", max_lines = 20 }, "org")
        preview.hide()
        assert.is_nil(preview.winid())
    end)

    it("is safe when nothing is showing", function()
        preview.hide()
        preview.hide()
    end)
end)
