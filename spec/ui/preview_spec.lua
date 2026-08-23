local preview = require("sidenote.preview")
local capture = require("sidenote.capture")
local fixture = require("spec.fixture")
local session = require("sidenote.session")

local opts = fixture.opts

local SOURCE = fixture.SOURCE

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

---@class spec.ui.GlanceOpts
---@field style "float"|"virt_lines"|"split"|"none" where the note is shown
---@field max_lines? integer prose lines the preview keeps, 20 by default

---@param case spec.ui.PreviewCase
---@param glance spec.ui.GlanceOpts
local function show(case, glance)
    preview.show(case.entry, {
        style = glance.style,
        max_lines = glance.max_lines or 20,
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
        show(annotated("why this returns one\n"), { style = "float" })
        assert.eq(vim.api.nvim_buf_get_lines(preview_buf(), 0, 1, false)[1], "why this returns one")
        preview.hide()
    end)

    it("sets the configured filetype so the prose highlights", function()
        show(annotated("* a heading\n"), { style = "float" })
        assert.eq(vim.bo[preview_buf()].filetype, "org")
        preview.hide()
    end)

    it("truncates to max_lines", function()
        show(annotated(string.rep("line\n", 40)), { style = "float", max_lines = 5 })
        assert.lte(vim.api.nvim_buf_line_count(preview_buf()), 5)
        preview.hide()
    end)

    it("shows a placeholder when the note is still empty", function()
        show(annotated(""), { style = "float" })
        assert.match(vim.api.nvim_buf_get_lines(preview_buf(), 0, -1, false)[1], "empty")
        preview.hide()
    end)

    it("leaves the preview buffer unmodifiable", function()
        show(annotated("text\n"), { style = "float" })
        assert.eq(vim.bo[preview_buf()].modifiable, false)
        preview.hide()
    end)

    it("replaces a previous preview rather than stacking windows", function()
        local case = annotated("first\n")
        show(case, { style = "float" })
        local first = preview.winid()
        show(case, { style = "float" })
        assert.falsy(vim.api.nvim_win_is_valid(first))
        preview.hide()
    end)

    it("leaves the cursor in the source buffer", function()
        local before = vim.api.nvim_get_current_win()
        show(annotated("text\n"), { style = "float" })
        assert.eq(vim.api.nvim_get_current_win(), before)
        preview.hide()
    end)
end)

describe("preview dismissal", function()
    it("hides the float on the first real cursor move", function()
        local case = annotated("transient\n")
        vim.api.nvim_set_current_buf(case.bufnr)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        show(case, { style = "float" })
        assert.not_nil(preview.winid())

        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.cmd("doautocmd CursorMoved")
        assert.is_nil(preview.winid())
    end)

    it("survives the move that showed it", function()
        -- The motion that opens a preview can flush its own CursorMoved after it
        local case = annotated("still here\n")
        vim.api.nvim_set_current_buf(case.bufnr)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        show(case, { style = "float" })

        vim.cmd("doautocmd CursorMoved")
        assert.not_nil(preview.winid())
        preview.hide()
    end)

    it("hides when insert mode begins", function()
        local case = annotated("gone on insert\n")
        vim.api.nvim_set_current_buf(case.bufnr)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        show(case, { style = "float" })

        vim.cmd("doautocmd InsertEnter")
        assert.is_nil(preview.winid())
    end)

    it("clears hanging prose on a move too", function()
        local case = annotated("hangs beneath\n")
        vim.api.nvim_set_current_buf(case.bufnr)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        show(case, { style = "virt_lines" })
        assert.eq(#marks(case.bufnr), 1)

        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.cmd("doautocmd CursorMoved")
        assert.eq(#marks(case.bufnr), 0)
    end)
end)

describe("preview.show identity", function()
    it("names what it shows in the float's winbar", function()
        local case = annotated("why this returns one\n")
        show(case, { style = "float" })
        local winbar = vim.wo[assert(preview.winid())].winbar
        assert.contains(winbar, "m.lua:4")
        assert.contains(winbar, "note")
        preview.hide()
    end)

    it("marks a cut float with how much it held back", function()
        local case = annotated(string.rep("line\n", 40))
        show(case, { style = "float", max_lines = 5 })
        local said = {}
        for _, mark in ipairs(marks(preview_buf())) do
            said[#said + 1] = mark[4].virt_lines[1][1][1]
        end
        assert.truthy(
            vim.iter(said):any(function(text)
                return text:find("35 more", 1, true) ~= nil
            end),
            "no mark said how much was held back"
        )
        preview.hide()
    end)

    it("rules the prose off from the identity above it", function()
        show(annotated("why this returns one\n"), { style = "float" })
        local rule = marks(preview_buf())[1]
        assert.eq(rule[2], 0, "the rule sits above the first prose line")
        assert.truthy(rule[4].virt_lines_above)
        local drawn = rule[4].virt_lines[1][1][1]
        assert.contains(drawn, "──")
        assert.eq((drawn:gsub("─", "")), "", "the rule is nothing but the rule")
        preview.hide()
    end)

    it("keeps the rule out of the prose a reader could yank", function()
        -- Virtual, so the buffer holds the note and nothing else
        show(annotated("why this returns one\n"), { style = "float" })
        assert.eq_deep(
            vim.api.nvim_buf_get_lines(preview_buf(), 0, -1, false),
            { "why this returns one" }
        )
        preview.hide()
    end)
end)

describe("preview.show virt_lines", function()
    it("opens no window at all", function()
        -- The whole point of this style is staying in the code
        local case = annotated("why this returns one\n")
        show(case, { style = "virt_lines" })
        assert.is_nil(preview.winid())
        preview.hide()
    end)

    it("leads with the note's identity, prose beneath a divider", function()
        local case = annotated("why this returns one\n")
        show(case, { style = "virt_lines" })

        local placed = marks(case.bufnr)
        assert.eq(#placed, 1)
        assert.eq(placed[1][2], 3, "line 4, zero-indexed")
        local virt = placed[1][4].virt_lines
        assert.contains(virt[1][1][1], "m.lua:4")
        assert.contains(virt[2][1][1], "─")
        assert.eq(virt[3][1][1], "why this returns one")
        preview.hide()
    end)

    it("renders every prose line as its own virtual line", function()
        local case = annotated("first\nsecond\nthird\n")
        show(case, { style = "virt_lines" })
        local virt = marks(case.bufnr)[1][4].virt_lines
        assert.eq(#virt, 5, "identity, divider, then the three lines")
        assert.eq(virt[#virt][1][1], "third")
        preview.hide()
    end)

    it("cuts at max_lines and says how much it held back", function()
        local case = annotated(string.rep("line\n", 40))
        show(case, { style = "virt_lines", max_lines = 5 })
        local virt = marks(case.bufnr)[1][4].virt_lines
        assert.eq(#virt, 8, "identity, divider, five lines, the marker")
        assert.contains(virt[#virt][1][1], "35 more")
        preview.hide()
    end)

    it("shows a placeholder when the note is still empty", function()
        local case = annotated("")
        show(case, { style = "virt_lines" })
        assert.match(marks(case.bufnr)[1][4].virt_lines[3][1][1], "empty")
        preview.hide()
    end)

    it("replaces a previous preview rather than stacking marks", function()
        local case = annotated("text\n")
        show(case, { style = "virt_lines" })
        show(case, { style = "virt_lines" })
        assert.eq(#marks(case.bufnr), 1)
        preview.hide()
    end)

    it("attaches nothing for an annotation the resolver could not place", function()
        -- There is no line to hang it under, and clamping is how an annotation
        -- ends up beside unrelated code
        local case = annotated("text\n")
        vim.api.nvim_buf_set_lines(case.bufnr, 0, -1, false, { "totally", "different" })
        case.entry = session.entries(case.bufnr, opts())[1]

        show(case, { style = "virt_lines" })
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
        show(case, { style = "none" })
        assert.is_nil(preview.winid())
        assert.eq(#marks(case.bufnr), 0)
    end)
end)

describe("preview.hide", function()
    it("closes the window", function()
        show(annotated("text\n"), { style = "float" })
        preview.hide()
        assert.is_nil(preview.winid())
    end)

    it("clears an attached virtual preview", function()
        local case = annotated("text\n")
        show(case, { style = "virt_lines" })
        preview.hide()
        assert.eq(#marks(case.bufnr), 0)
    end)

    it("is safe when nothing is showing", function()
        preview.hide()
        preview.hide()
    end)
end)
