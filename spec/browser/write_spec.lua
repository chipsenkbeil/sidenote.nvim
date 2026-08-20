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
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

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
    it("repaints the source buffer of a rescoped annotation", function()
        -- The write moved the record's anchor; the code window's mark moves
        -- with it now, not at that buffer's next save
        local source = project_buffer()
        annotate(source, 4, { "the note" })
        require("sidenote.session").refresh(source, opts())
        local bufnr = assert(browser.open(source, { config = opts() }))

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines[1] = lines[1]:gsub("m%.lua:4", "m.lua:2")
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

        assert.eq(browser.write(bufnr, { confirm = always_yes }), 1)
        local marks =
            vim.api.nvim_buf_get_extmarks(source, require("sidenote.render").NAMESPACE, 0, -1, {})
        assert.eq(#marks, 1)
        assert.eq(marks[1][2], 1, "the sign sits on the new line")
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
        -- cannot read as a boundary; the old refusal went with its reason
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
