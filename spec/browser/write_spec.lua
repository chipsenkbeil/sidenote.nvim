local browser = require("sidenote.browser")
local capture = require("sidenote.capture")
local render = require("sidenote.render")
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
        editor = { style = "split", position = "right", size = 60 },
        browser = { style = "current" },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Build a project with one source file open in a buffer.
---@return integer source
local function project_buffer()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.sidenote", "p")
    local path = root .. "/m.lua"
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(SOURCE, "\n") .. "\n")
    fh:close()

    local source = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(source, path)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, SOURCE)
    return source
end

---@param source integer
---@param line integer
---@param prose string[]
---@return string id
---@return string root
local function annotate(source, line, prose)
    local cfg = opts()
    local result =
        assert(capture.run(source, { scope = "lines", range = { line, 0, line, 0 }, config = cfg }))
    local fh = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
    fh:write(table.concat(prose, "\n") .. "\n")
    fh:close()
    return result.id, result.root
end

---@return boolean
local function always_yes()
    return true
end

---@return boolean
local function always_no()
    return false
end

describe("browser.write", function()
    it("repaints the source buffer of a rescoped annotation", function()
        -- The code window's mark moves with the record's anchor at write
        -- time, not at that buffer's next save
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        session.refresh(source, opts())
        local bufnr = assert(browser.open(source, { config = opts() }))

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[1] = lines[1]:gsub("m%.lua:4", "m.lua:2")
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

        assert.eq(browser.write(bufnr, { confirm = always_yes }), 1)
        local marks = vim.api.nvim_buf_get_extmarks(source, render.NAMESPACE, 0, -1, {})
        assert.eq(#marks, 1)
        assert.eq(marks[1][2], 1, "the sign sits on the new line")
    end)

    it("repaints an applied move even while a mark tracks the old span", function()
        -- An edit after the paint sends the session to its live tier; the
        -- explicit move must still outrank the stale tracker
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        session.refresh(source, opts())
        vim.api.nvim_buf_set_lines(source, 5, 5, false, { "-- a scratch line" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[1] = lines[1]:gsub("m%.lua:4", "m.lua:3")
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

        assert.eq(browser.write(bufnr, { confirm = always_yes }), 1)
        local marks = vim.api.nvim_buf_get_extmarks(source, render.NAMESPACE, 0, -1, {})
        assert.gt(#marks, 0)
        for _, mark in ipairs(marks) do
            assert.eq(mark[2], 2, "a mark still sits on the old line")
        end
    end)

    it("keeps the moved anchor through the source's next save", function()
        -- Write-back re-baselines attached notes to their marks; a mark
        -- left on the old span would write the move straight back out
        local source = project_buffer()
        local id, root = annotate(source, 4, { "the note" })
        session.refresh(source, opts())
        vim.api.nvim_buf_set_lines(source, 5, 5, false, { "-- a scratch line" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[1] = lines[1]:gsub("m%.lua:4", "m.lua:3")
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        assert.eq(browser.write(bufnr, { confirm = always_yes }), 1)

        session.written(source)
        assert.eq(assert(store.read(root, id)).line_start, 3)
    end)

    it("anchors a move to the buffer's text, not the file on disk", function()
        -- The listing's positions are the buffer's; capturing disk text
        -- would anchor the note to a line the user was not even looking at
        local source = project_buffer()
        local id, root = annotate(source, 4, { "the note" })
        session.refresh(source, opts())
        vim.api.nvim_buf_set_lines(source, 2, 3, false, { "function M.changed()" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[1] = lines[1]:gsub("m%.lua:4", "m.lua:3")
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        assert.eq(browser.write(bufnr, { confirm = always_yes }), 1)

        assert.eq(assert(store.read(root, id)).text, "function M.changed()")
    end)

    it("refuses a write that leaves a deleted note's prose behind", function()
        -- Deleting a header alone glues the dead note's prose onto the
        -- note above; applying that would rewrite an untouched neighbor
        local source = project_buffer()
        annotate(source, 1, { "alpha" })
        local id, root = annotate(source, 4, { "beta" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, {})
        local applied, problems = browser.write(bufnr, { confirm = always_yes })

        assert.eq(applied, 0)
        assert.contains(table.concat(problems, "\n"), id)
        assert.not_nil(store.read(root, id), "nothing was applied")
    end)

    it("applies nothing when the buffer was not edited", function()
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        local applied, problems = browser.write(bufnr, { confirm = always_yes })
        assert.eq(applied, 0)
        assert.eq_deep(problems, {})
    end)

    it("applies nothing for prose of any awkward shape", function()
        -- The load-bearing property of the whole write path: a row nobody
        -- touched must never be reported as edited, whatever it holds
        local shapes = {
            { "plain" },
            { "  leading spaces", "body" },
            { "\ttab first", "body" },
            { "trailing spaces   ", "body" },
            { "two  consecutive  spaces" },
            { "summary", "", "after a blank" },
            { "summary", "    an indented block" },
            { "summary", "note  open      looks.lua:1    like a header row" },
            { ("x"):rep(300) },
            { "unicode: café — ✓ ↩", "body" },
            {},
        }

        local source = project_buffer()

        -- Capture refuses SOURCE's blank line
        local text_lines = { 1, 3, 4, 5 }
        for i, prose in ipairs(shapes) do
            annotate(source, text_lines[math.min(i, #text_lines)], prose)
        end

        local bufnr = assert(browser.open(source, { config = opts() }))
        local applied, problems = browser.write(bufnr, {
            confirm = function()
                error("a dialog appeared for a buffer nobody edited")
            end,
        })
        assert.eq(applied, 0)
        assert.eq_deep(problems, {})
    end)

    it("deletes the annotation behind a row that was removed", function()
        local source = project_buffer()
        local id = annotate(source, 4, { "the note", "with a body" })
        local bufnr = assert(browser.open(source, { config = opts() }))
        local root = assert(browser.state(bufnr)).rows[1].entry.root

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
        local applied, problems = browser.write(bufnr, { confirm = always_yes })

        assert.eq(applied, 1)
        assert.eq_deep(problems, {})
        assert.falsy(vim.uv.fs_stat(store.meta_path(root, id)))
    end)

    it("writes edited prose through to the note's file", function()
        local source = project_buffer()
        local id = annotate(source, 4, { "the note" })
        local bufnr = assert(browser.open(source, { config = opts() }))
        local root = assert(browser.state(bufnr)).rows[1].entry.root

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[#lines + 1] = "a body line"
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

        assert.eq(browser.write(bufnr, { confirm = always_yes }), 1)
        assert.eq(store.prose(root, id, opts().filetype), "the note\na body line\n")
    end)

    it("applies nothing when the confirmation is declined", function()
        local source = project_buffer()
        local id = annotate(source, 4, { "the note" })
        local bufnr = assert(browser.open(source, { config = opts() }))
        local root = assert(browser.state(bufnr)).rows[1].entry.root

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
        assert.eq(browser.write(bufnr, { confirm = always_no }), 0)
        assert.truthy(vim.uv.fs_stat(store.meta_path(root, id)))
    end)

    it("refuses a buffer that does not parse, naming the offending line", function()
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[1] = lines[1]:gsub(" note ", " idea ", 1)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

        local applied, problems = browser.write(bufnr, { confirm = always_yes })
        assert.eq(applied, 0)

        -- Two reports: the bad header, and the prose it orphaned beneath it
        assert.eq(#problems, 2)
        assert.contains(problems[1], "1")
    end)

    it("refuses an edit that validation rejects, before any dialog appears", function()
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[1] = lines[1]:gsub("m%.lua:4", "m.lua:99", 1)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

        local asked = false
        local applied, problems = browser.write(bufnr, {
            confirm = function()
                asked = true
                return true
            end,
        })
        assert.eq(applied, 0)
        assert.falsy(asked, "a dialog must never offer something impossible")
        assert.eq(#problems, 1)
    end)

    it("re-renders from the store once edits land, leaving the buffer unmodified", function()
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        local bufnr = assert(browser.open(source, { config = opts() }))

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
        assert.eq(browser.write(bufnr, { confirm = always_yes }), 1)

        assert.eq_deep(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "" })
        assert.falsy(vim.bo[bufnr].modified)
        assert.eq_deep(assert(browser.state(bufnr)).rows, {})
    end)

    it("round-trips a path holding consecutive spaces", function()
        -- The location is the last column, so a run of spaces inside a path
        -- cannot read as a column boundary
        local root = vim.fn.tempname()
        vim.fn.mkdir(root .. "/.sidenote", "p")
        local path = root .. "/two  spaces.lua"
        local fh = assert(io.open(path, "w"))
        fh:write(table.concat(SOURCE, "\n") .. "\n")
        fh:close()

        local source = vim.fn.bufadd(path)
        vim.fn.bufload(source)
        annotate(source, 4, { "the note" })

        local bufnr = assert(browser.open(source, { config = opts() }))
        local applied, problems = browser.write(bufnr, {
            confirm = function()
                error("an untouched listing must produce no actions to confirm")
            end,
        })
        assert.eq(applied, 0)
        assert.eq_deep(problems, {})
    end)

    it("intercepts :w through a BufWriteCmd on the browser buffer", function()
        local bufnr = assert(browser.open(project_buffer(), { config = opts() }))
        local found = vim.api.nvim_get_autocmds({ event = "BufWriteCmd", buffer = bufnr })
        assert.gt(#found, 0)
    end)
end)

describe("browser.row_at", function()
    it("finds the annotation a header line stands for", function()
        local source = project_buffer()
        local id = annotate(source, 4, { "the note" })
        local bufnr = assert(browser.open(source, { config = opts() }))
        assert.eq(assert(browser.row_at(bufnr, 1)).entry.id, id)
    end)

    it("finds the annotation a prose line belongs to", function()
        local source = project_buffer()
        local id = annotate(source, 4, { "the note", "a body line" })
        local bufnr = assert(browser.open(source, { config = opts() }))
        assert.eq(assert(browser.row_at(bufnr, 2)).entry.id, id)
    end)

    it("is nil past the end of the listing", function()
        local bufnr = assert(browser.open(project_buffer(), { config = opts() }))
        assert.is_nil(browser.row_at(bufnr, 1))
    end)
end)
