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
        editor = { style = "split", position = "right", size = 60 },
    }
end

local SOURCE = { "local M = {}", "", "function M.f()", "  return 1", "end" }

---Build a project with one source file open in a buffer.
---@return integer bufnr
local function project_buffer()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.annotations", "p")
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
