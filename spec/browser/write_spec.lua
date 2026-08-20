local browser = require("sidenote.browser")
local capture = require("sidenote.capture")
local render = require("sidenote.browser.render")
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
        editor = { style = "split", position = "right", size = 60 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---@return integer source
local function project_buffer()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.annotations", "p")
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
local function annotate(source, line, prose)
    local cfg = opts()
    local result =
        assert(capture.run(source, { scope = "lines", range = { line, 0, line, 0 }, config = cfg }))
    local fh = assert(io.open(store.prose_path(result.root, result.id, cfg.filetype), "w"))
    fh:write(table.concat(prose, "\n") .. "\n")
    fh:close()
    return result.id
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
        -- Any text-bearing line will do; capture refuses the blank one
        local lines = { 1, 3, 4, 5 }
        for i, prose in ipairs(shapes) do
            annotate(source, lines[math.min(i, #lines)], prose)
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
        lines[#lines + 1] = (" "):rep(render.PROSE_INDENT) .. "a body line"
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
        assert.eq(#problems, 1)
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

    it("refuses to write when a path holds consecutive spaces", function()
        -- Such a path is indistinguishable from a column boundary, and would
        -- otherwise diff as a move to a truncated location
        local root = vim.fn.tempname()
        vim.fn.mkdir(root .. "/.annotations", "p")
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
                error("a dialog appeared for a listing that cannot be read back")
            end,
        })
        assert.eq(applied, 0)
        assert.eq(#problems, 1)
        assert.contains(problems[1], "consecutive spaces")
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

describe("browser column navigation", function()
    local LINE = "/01J9F3K2X7Q4V8M2ZC5T0BQWE note  open      m.lua:4    the summary"

    it("steps forward through the columns", function()
        local kind = assert(browser.next_column(LINE, 1))
        assert.eq(LINE:sub(kind, kind + 3), "note")
        local state = assert(browser.next_column(LINE, kind))
        assert.eq(LINE:sub(state, state + 3), "open")
        local loc = assert(browser.next_column(LINE, state))
        assert.eq(LINE:sub(loc, loc + 6), "m.lua:4")
    end)

    it("stops at the last column rather than wrapping", function()
        local summary = LINE:find("the summary")
        assert.is_nil(browser.next_column(LINE, summary))
    end)

    it("steps backward through the columns", function()
        local summary = LINE:find("the summary")
        local loc = assert(browser.prev_column(LINE, summary))
        assert.eq(LINE:sub(loc, loc + 6), "m.lua:4")
    end)

    it("stops at the first column rather than wrapping", function()
        local kind = assert(browser.next_column(LINE, 1))
        assert.is_nil(browser.prev_column(LINE, kind))
    end)

    it("does nothing on a prose line, which has no columns", function()
        assert.is_nil(browser.next_column("    a body line", 1))
        assert.is_nil(browser.prev_column("    a body line", 5))
    end)
end)
