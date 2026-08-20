local editor = require("sidenote.editor")
local capture = require("sidenote.capture")
local session = require("sidenote.session")
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
        editor = { style = "split", position = "right", size = 40 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Capture one annotation and return its entry and its source buffer.
---@return sidenote.session.Entry
---@return integer source
local function annotated()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(SOURCE, "\n") .. "\n")
    fh:close()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, SOURCE)
    capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })

    return session.entries(bufnr, opts())[1], bufnr
end

---Flatten one header line's chunks into its text.
---@param line {[1]: string, [2]: string}[]
---@return string
local function text_of(line)
    local parts = {}
    for _, chunk in ipairs(line) do
        parts[#parts + 1] = chunk[1]
    end
    return table.concat(parts)
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

    it("toggle puts away the note it is already showing", function()
        local entry = annotated()
        local config = vim.tbl_extend("force", opts().editor, { style = "toggle" })
        local first = editor.open(entry, config, "org")
        assert.truthy(vim.api.nvim_win_is_valid(first))

        assert.is_nil(editor.open(entry, config, "org"))
        assert.falsy(vim.api.nvim_win_is_valid(first))
    end)

    it("toggle switches to a different note rather than closing", function()
        local config = vim.tbl_extend("force", opts().editor, { style = "toggle" })
        local first = editor.open(annotated(), config, "org")
        local second = editor.open(annotated(), config, "org")
        assert.eq(first, second)
        assert.truthy(vim.api.nvim_win_is_valid(second))
        require("sidenote.window").close(second)
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

describe("editor.header", function()
    it("names the location, kind and state on its first line", function()
        local entry, source = annotated()
        entry.source = source
        local first = text_of(editor.header(entry, source)[1])
        assert.contains(first, "m.lua:4")
        assert.contains(first, "note")
        assert.contains(first, "open")
        assert.falsy(first:find("attached", 1, true), "a healthy anchor needs no label")
    end)

    it("names the pen when the note carries one", function()
        local entry, source = annotated()
        entry.record.pen = "coral"
        assert.contains(text_of(editor.header(entry, source)[1]), "coral")
    end)

    it("snippets the code as it reads in the buffer now", function()
        local entry, source = annotated()
        local lines = editor.header(entry, source)
        assert.gt(#lines, 1)
        assert.contains(text_of(lines[2]), "return 1")
        assert.eq(lines[2][1][2], "SidenoteContext")
    end)

    it("shows drift in the status color, keeping the stored text below", function()
        -- Synthetic drift: the header is display logic, and what the
        -- resolver would grade this edit is not the point here
        local entry, source = annotated()
        vim.api.nvim_buf_set_text(source, 3, 9, 3, 10, { "waited" })
        entry.status = "drifted"
        entry.resolution =
            { status = "drifted", line_start = 4, line_end = 4, confidence = 0.85, tier = "L6" }

        local lines = editor.header(entry, source)
        local first = lines[1]
        assert.contains(text_of(first), "drifted 0.85")
        assert.eq(first[#first][2], require("sidenote.highlight").GROUPS.drifted)
        assert.contains(text_of(lines[2]), "waited", "the snippet reads the buffer as it is now")
        local last = text_of(lines[#lines])
        assert.contains(last, "was:")
        assert.contains(last, "return 1")
    end)

    it("says a file-wide note plainly, never rendering empty", function()
        local entry, source = annotated()
        entry.record.scope = "file"
        entry.record.text = ""
        local lines = editor.header(entry, source)
        assert.eq(#lines, 1)
        assert.contains(text_of(lines[1]), "m.lua")
    end)

    it("clips a snippet line rather than letting it run on", function()
        local _, source = annotated()
        vim.api.nvim_buf_set_lines(source, 3, 4, false, { "  " .. ("x"):rep(200) })
        local entry = session.entries(source, opts())[1]
        for _, line in ipairs(editor.header(entry, source)) do
            assert.lte(vim.fn.strdisplaywidth(text_of(line)), 80)
        end
    end)
end)

describe("editor.open context", function()
    it("paints the header above the prose, revealed by filler lines", function()
        local entry, source = annotated()
        entry.source = source
        local winid = editor.open(entry, opts().editor, "org")
        local bufnr = vim.api.nvim_win_get_buf(winid)

        local marks = vim.api.nvim_buf_get_extmarks(bufnr, editor.NAMESPACE, 0, -1, {
            details = true,
        })
        assert.eq(#marks, 1)
        assert.truthy(marks[1][4].virt_lines_above)
        assert.gt(#marks[1][4].virt_lines, 1)

        local view = vim.api.nvim_win_call(winid, vim.fn.winsaveview)
        assert.eq(view.topfill, #marks[1][4].virt_lines, "the header must be on screen")
        require("sidenote.window").close(winid)
    end)

    it("pins the location into the winbar", function()
        local entry, source = annotated()
        entry.source = source
        local winid = editor.open(entry, opts().editor, "org")
        assert.contains(vim.wo[winid].winbar, "m.lua:4")
        require("sidenote.window").close(winid)
    end)

    it("skips the header for a bare root-and-id note", function()
        local entry = annotated()
        local winid = editor.open({ root = entry.root, id = entry.id }, opts().editor, "org")
        local bufnr = vim.api.nvim_win_get_buf(winid)
        assert.eq(#vim.api.nvim_buf_get_extmarks(bufnr, editor.NAMESPACE, 0, -1, {}), 0)
        require("sidenote.window").close(winid)
    end)
end)
