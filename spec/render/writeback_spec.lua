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
        editor = { style = "split", position = "right", size = 60 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Build a project with one source file open in a buffer.
---@return integer bufnr
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

---Capture one annotation and hand back what was stored.
---@param bufnr integer
---@param line integer
---@return string root
---@return sidenote.Annotation
local function annotated(bufnr, line)
    local result = assert(
        capture.run(bufnr, { scope = "lines", range = { line, 0, line, 0 }, config = opts() })
    )
    return result.root, assert(store.read(result.root, result.id))
end

---@param bufnr integer
---@param lnum integer 1-based line to insert above
---@param lines string[]
local function insert_above(bufnr, lnum, lines)
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum - 1, false, lines)
end

describe("session.written", function()
    it("rewrites hints and re-captures the anchor when the annotation moved", function()
        -- Re-baselining is what stops drift compounding: the next resolve
        -- starts from where the code is now, not where it was captured
        local bufnr = project_buffer()
        local root, before = annotated(bufnr, 4)
        insert_above(bufnr, 4, { "  local pad = 0" })

        assert.eq(session.written(bufnr, opts()), 1)
        local after = assert(store.read(root, before.id))
        assert.eq(after.line_start, 5)
        assert.eq(after.text, before.text, "the anchor itself did not change")
        assert.neq(after.prefix, before.prefix, "context is re-captured at the new place")
        assert.neq(after.file_sha, before.file_sha)
        assert.eq(after.captured, before.captured, "capture time is history, not state")
    end)

    it("refreshes only the file hash and verified stamp when nothing moved", function()
        local bufnr = project_buffer()
        local root, before = annotated(bufnr, 1)
        -- Change the file below the annotation, leaving its position alone
        vim.api.nvim_buf_set_lines(bufnr, 4, 5, false, { "end -- trailing note" })

        assert.eq(session.written(bufnr, opts()), 1)
        local after = assert(store.read(root, before.id))
        assert.eq(after.line_start, before.line_start)
        assert.eq(after.text, before.text)
        assert.eq(after.prefix, before.prefix)
        assert.neq(after.file_sha, before.file_sha)
    end)

    it("writes nothing when the file has not changed", function()
        local bufnr = project_buffer()
        local root, before = annotated(bufnr, 4)
        assert.eq(session.written(bufnr, opts()), 0)
        assert.eq(store.read(root, before.id).file_sha, before.file_sha)
    end)

    it("never overwrites the anchor of a note it could not attach", function()
        -- The resolver only guessed (or gave up); writing that back would
        -- replace a good anchor with an unverified position
        local bufnr = project_buffer()
        local root, before = annotated(bufnr, 4)
        vim.api.nvim_buf_set_lines(bufnr, 3, 4, false, { "  return 1 + offset" })

        assert.eq(session.written(bufnr, opts()), 0)
        local after = assert(store.read(root, before.id))
        assert.eq(after.text, before.text)
        assert.eq(after.file_sha, before.file_sha)
        assert.eq(after.verified, before.verified)
    end)

    it("refreshes a file-wide note's hash, which keeps the fast path warm", function()
        local bufnr = project_buffer()
        local result = assert(capture.run(bufnr, { scope = "file", config = opts() }))
        insert_above(bufnr, 1, { "-- changed" })

        assert.eq(session.written(bufnr, opts()), 1)
        local after = assert(store.read(result.root, result.id))
        assert.eq(after.scope, "file")
        assert.neq(after.file_sha, "")
    end)
end)

describe("session.written from a live mark", function()
    ---Capture a span and paint it, so a mark exists to track the edits.
    ---@param bufnr integer
    ---@param first integer
    ---@param last integer
    ---@return string root
    ---@return sidenote.Annotation
    local function painted(bufnr, first, last)
        local result = assert(
            capture.run(bufnr, { scope = "lines", range = { first, 0, last, 0 }, config = opts() })
        )
        session.refresh(bufnr, opts())
        return result.root, assert(store.read(result.root, result.id))
    end

    it("grows the anchor over a line typed inside the span", function()
        local bufnr = project_buffer()
        local root, before = painted(bufnr, 3, 5)
        vim.api.nvim_buf_set_lines(bufnr, 3, 3, false, { "  local extra = 2" })

        assert.eq(session.written(bufnr, opts()), 1)
        local after = assert(store.read(root, before.id))
        assert.eq(after.line_start, 3)
        assert.eq(after.line_end, 6)
        assert.contains(after.text, "extra")
    end)

    it("shrinks the anchor when a line inside the span is deleted", function()
        local bufnr = project_buffer()
        local root, before = painted(bufnr, 3, 5)
        vim.api.nvim_buf_set_lines(bufnr, 3, 4, false, {})

        assert.eq(session.written(bufnr, opts()), 1)
        local after = assert(store.read(root, before.id))
        assert.eq(after.line_end, 4)
        assert.falsy(after.text:find("return", 1, true))
    end)

    it("re-baselines an edit made in place inside the span", function()
        -- The resolver alone refuses this save; the mark watched the user
        -- make the edit, so it is an assertion rather than a guess
        local bufnr = project_buffer()
        local root, before = painted(bufnr, 4, 4)
        vim.api.nvim_buf_set_text(bufnr, 3, 9, 3, 10, { "offset" })

        assert.eq(session.written(bufnr, opts()), 1)
        local after = assert(store.read(root, before.id))
        assert.eq(after.text, "  return offset")
        assert.eq(after.line_start, 4)
    end)

    it("refuses a span typed over wholesale, whose mark collapsed", function()
        -- Replacing the entire text deletes everything the mark covered, and
        -- what was typed at the crater is not provably the same note's code
        local bufnr = project_buffer()
        local root, before = painted(bufnr, 4, 4)
        vim.api.nvim_buf_set_lines(bufnr, 3, 4, false, { "  yield_all(handles)" })

        assert.eq(session.written(bufnr, opts()), 0)
        assert.eq(assert(store.read(root, before.id)).text, before.text)
    end)

    it("leaves the record alone when the span was deleted outright", function()
        -- Deleting is not editing: nothing asserts a new home for the note
        local bufnr = project_buffer()
        local root, before = painted(bufnr, 3, 5)
        vim.api.nvim_buf_set_lines(bufnr, 2, 5, false, {})

        assert.eq(session.written(bufnr, opts()), 0)
        local after = assert(store.read(root, before.id))
        assert.eq(after.text, before.text)
        assert.eq(after.verified, before.verified)
    end)

    it("follows a span cut here and pasted elsewhere in the file", function()
        -- To the mark a cut is a delete, so the resolver takes over and
        -- finds the text at its new home
        local bufnr = project_buffer()
        local root, before = painted(bufnr, 4, 4)
        vim.api.nvim_buf_set_lines(bufnr, 3, 4, false, {})
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "  return 1" })

        assert.eq(session.written(bufnr, opts()), 1)
        assert.eq(assert(store.read(root, before.id)).line_start, 5)
    end)

    it("does not re-baseline from a mark placed on a guess", function()
        -- A drifted placement is the resolver's best idea, not the user's
        -- assertion; editing near it must not launder the guess into truth
        local bufnr = project_buffer()
        local root, before = painted(bufnr, 4, 4)

        -- Re-painting over a rewritten span leaves the mark on a guess
        vim.api.nvim_buf_set_lines(bufnr, 3, 4, false, { "  return 1 + offset" })
        session.refresh(bufnr, opts())
        vim.api.nvim_buf_set_lines(bufnr, 3, 4, false, { "  return 2 + offset" })

        assert.eq(session.written(bufnr, opts()), 0)
        assert.eq(assert(store.read(root, before.id)).text, before.text)
    end)
end)
