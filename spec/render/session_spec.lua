local session = require("sidenote.session")
local capture = require("sidenote.capture")
local render = require("sidenote.render")

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
---@return integer
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

describe("session.entries", function()
    it("is empty for a buffer with no annotations", function()
        assert.eq_deep(session.entries(project_buffer(), opts()), {})
    end)

    it("finds an annotation captured in the same buffer", function()
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        local entries = session.entries(bufnr, opts())
        assert.eq(#entries, 1)
        assert.eq(entries[1].status, "attached")
        assert.eq(entries[1].line_start, 4)
    end)

    it("relocates an annotation after the buffer shifts", function()
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "-- header" })

        local entries = session.entries(bufnr, opts())
        assert.eq(entries[1].line_start, 5)
    end)

    it("reports an annotation whose anchor is gone as orphaned, with no position", function()
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "totally", "different" })

        local entries = session.entries(bufnr, opts())
        assert.eq(entries[1].status, "orphaned")
        assert.is_nil(entries[1].line_start)
    end)

    it("ignores annotations belonging to a different source file", function()
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "file", config = opts() })

        local other = vim.api.nvim_create_buf(false, true)
        -- Parenthesized: gsub returns a count as its second value, which would
        -- otherwise arrive as an extra argument
        vim.api.nvim_buf_set_name(
            other,
            (vim.api.nvim_buf_get_name(bufnr):gsub("m%.lua$", "n.lua"))
        )
        vim.api.nvim_buf_set_lines(other, 0, -1, false, SOURCE)
        assert.eq_deep(session.entries(other, opts()), {})
    end)

    it("returns an empty list rather than failing when no store resolves", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. "/loose.lua")
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, SOURCE)
        assert.eq_deep(session.entries(bufnr, opts()), {})
    end)

    it("sorts entries by line so navigation order is stable", function()
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "lines", range = { 5, 0, 5, 0 }, config = opts() })
        capture.run(bufnr, { scope = "lines", range = { 1, 0, 1, 0 }, config = opts() })

        local entries = session.entries(bufnr, opts())
        assert.eq(entries[1].line_start, 1)
        assert.eq(entries[2].line_start, 5)
    end)
end)

describe("session.entries while the buffer is edited", function()
    it("reports the span its mark tracked, not a fresh resolution", function()
        -- Between paints the mark has followed every keystroke; resolving
        -- the stored content again would fight the edit in progress
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "lines", range = { 3, 0, 5, 0 }, config = opts() })
        session.refresh(bufnr, opts())
        vim.api.nvim_buf_set_lines(bufnr, 3, 3, false, { "  local wedge = 0" })

        local entries = session.entries(bufnr, opts())
        assert.eq(entries[1].line_start, 3)
        assert.eq(entries[1].line_end, 6)
        assert.eq(entries[1].status, "attached")
        assert.eq(entries[1].resolution.tier, "live")
    end)

    it("moves with edits above the span, without touching the store", function()
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        session.refresh(bufnr, opts())
        vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "-- header" })

        local entries = session.entries(bufnr, opts())
        assert.eq(entries[1].line_start, 5)
        assert.eq(entries[1].line_end, 5)
    end)

    it("falls back to the resolver for a span deleted outright", function()
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        session.refresh(bufnr, opts())
        vim.api.nvim_buf_set_lines(bufnr, 3, 4, false, {})

        local entries = session.entries(bufnr, opts())
        assert.eq(entries[1].status, "orphaned")
    end)

    it("resolves as before when nothing was ever painted", function()
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "-- header" })
        assert.eq(session.entries(bufnr, opts())[1].line_start, 5)
    end)
end)

describe("session.refresh", function()
    it("paints a mark for each placed annotation", function()
        local bufnr = project_buffer()
        capture.run(bufnr, { scope = "lines", range = { 4, 0, 4, 0 }, config = opts() })
        assert.eq(session.refresh(bufnr, opts()), 1)
        assert.eq(#vim.api.nvim_buf_get_extmarks(bufnr, render.NAMESPACE, 0, -1, {}), 1)
    end)

    it("paints nothing for a buffer with no annotations", function()
        assert.eq(session.refresh(project_buffer(), opts()), 0)
    end)
end)
