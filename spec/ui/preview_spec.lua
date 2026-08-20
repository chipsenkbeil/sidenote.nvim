local preview = require("sidenote.preview")
local capture = require("sidenote.capture")
local session = require("sidenote.session")

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
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---@class spec.ui.PreviewCase
---@field entry sidenote.session.Entry the annotation to preview
---@field bufnr integer buffer it was captured from

---Capture one annotation and return its entry, with prose already written.
---@param prose string
---@return spec.ui.PreviewCase
local function annotated(prose)
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
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

    return { entry = session.entries(bufnr, opts())[1], bufnr = bufnr }
end

---@param case spec.ui.PreviewCase
---@param style string
---@param max_lines? integer defaults to 20
local function show(case, style, max_lines)
    preview.show(case.entry, {
        style = style,
        max_lines = max_lines or 20,
        filetype = "org",
        bufnr = case.bufnr,
    })
end

---@return integer
local function preview_buf()
    return vim.api.nvim_win_get_buf(assert.not_nil(preview.winid()))
end

---@param bufnr integer
---@return vim.api.keyset.get_extmark_item[]
local function marks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, preview.NAMESPACE, 0, -1, { details = true })
end

describe("preview.show float", function()
    it("shows the prose in a floating window", function()
        show(annotated("why this returns one\n"), "float")
        assert.eq(vim.api.nvim_buf_get_lines(preview_buf(), 0, 1, false)[1], "why this returns one")
        preview.hide()
    end)

    it("sets the configured filetype so the prose highlights", function()
        show(annotated("* a heading\n"), "float")
        assert.eq(vim.bo[preview_buf()].filetype, "org")
        preview.hide()
    end)

    it("truncates to max_lines", function()
        show(annotated(string.rep("line\n", 40)), "float", 5)
        assert.lte(vim.api.nvim_buf_line_count(preview_buf()), 5)
        preview.hide()
    end)

    it("shows a placeholder when the note is still empty", function()
        show(annotated(""), "float")
        assert.match(vim.api.nvim_buf_get_lines(preview_buf(), 0, -1, false)[1], "empty")
        preview.hide()
    end)

    it("leaves the preview buffer unmodifiable", function()
        show(annotated("text\n"), "float")
        assert.eq(vim.bo[preview_buf()].modifiable, false)
        preview.hide()
    end)

    it("replaces a previous preview rather than stacking windows", function()
        local case = annotated("first\n")
        show(case, "float")
        local first = preview.winid()
        show(case, "float")
        assert.falsy(vim.api.nvim_win_is_valid(first))
        preview.hide()
    end)

    it("leaves the cursor in the source buffer", function()
        local before = vim.api.nvim_get_current_win()
        show(annotated("text\n"), "float")
        assert.eq(vim.api.nvim_get_current_win(), before)
        preview.hide()
    end)
end)

describe("preview.show virt_lines", function()
    it("opens no window at all", function()
        -- The whole point of this style is staying in the code
        local case = annotated("why this returns one\n")
        show(case, "virt_lines")
        assert.is_nil(preview.winid())
        preview.hide()
    end)

    it("attaches the prose below the annotated line", function()
        local case = annotated("why this returns one\n")
        show(case, "virt_lines")

        local placed = marks(case.bufnr)
        assert.eq(#placed, 1)
        assert.eq(placed[1][2], 3, "line 4, zero-indexed")
        assert.eq(placed[1][4].virt_lines[1][1][1], "why this returns one")
        preview.hide()
    end)

    it("renders every prose line as its own virtual line", function()
        local case = annotated("first\nsecond\nthird\n")
        show(case, "virt_lines")
        assert.eq(#marks(case.bufnr)[1][4].virt_lines, 3)
        preview.hide()
    end)

    it("truncates to max_lines like every other style", function()
        local case = annotated(string.rep("line\n", 40))
        show(case, "virt_lines", 5)
        assert.lte(#marks(case.bufnr)[1][4].virt_lines, 5)
        preview.hide()
    end)

    it("shows a placeholder when the note is still empty", function()
        local case = annotated("")
        show(case, "virt_lines")
        assert.match(marks(case.bufnr)[1][4].virt_lines[1][1][1], "empty")
        preview.hide()
    end)

    it("replaces a previous preview rather than stacking marks", function()
        local case = annotated("text\n")
        show(case, "virt_lines")
        show(case, "virt_lines")
        assert.eq(#marks(case.bufnr), 1)
        preview.hide()
    end)

    it("attaches nothing for an annotation the resolver could not place", function()
        -- There is no line to hang it under, and clamping is how an annotation
        -- ends up beside unrelated code
        local case = annotated("text\n")
        vim.api.nvim_buf_set_lines(case.bufnr, 0, -1, false, { "totally", "different" })
        case.entry = session.entries(case.bufnr, opts())[1]

        show(case, "virt_lines")
        assert.eq(#marks(case.bufnr), 0)
        preview.hide()
    end)

    it("uses a namespace of its own, so dismissing it leaves the signs alone", function()
        local render = require("sidenote.render")
        assert.neq(preview.NAMESPACE, render.NAMESPACE)
    end)
end)

describe("preview.show none", function()
    it("opens nothing", function()
        local case = annotated("text\n")
        show(case, "none")
        assert.is_nil(preview.winid())
        assert.eq(#marks(case.bufnr), 0)
    end)
end)

describe("preview.hide", function()
    it("closes the window", function()
        show(annotated("text\n"), "float")
        preview.hide()
        assert.is_nil(preview.winid())
    end)

    it("clears an attached virtual preview", function()
        local case = annotated("text\n")
        show(case, "virt_lines")
        preview.hide()
        assert.eq(#marks(case.bufnr), 0)
    end)

    it("is safe when nothing is showing", function()
        preview.hide()
        preview.hide()
    end)
end)
