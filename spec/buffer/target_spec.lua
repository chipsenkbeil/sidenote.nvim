local buffer = require("sidenote.buffer")

---@param lines string[]
---@param name? string
---@return integer
local function scratch(lines, name)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_name(bufnr, name or (vim.fn.tempname() .. ".lua"))
    return bufnr
end

local LINES = { "local M = {}", "", "function M.f()", "  return 1", "end" }

describe("buffer.target file scope", function()
    it("captures the whole file with no position", function()
        local target = buffer.target(scratch(LINES), { scope = "file" })
        assert.eq(target.scope, "file")
        assert.eq(target.line_start, 0)
        assert.eq(target.content, table.concat(LINES, "\n"))
    end)

    it("reports a symlink-resolved absolute path", function()
        -- On macOS /var is a link into /private/var, so an unresolved path
        -- would not match the project root the store computes
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        local path = dir .. "/m.lua"
        local fh = assert(io.open(path, "w"))
        fh:write("x = 1\n")
        fh:close()

        local target = buffer.target(scratch(LINES, path), { scope = "file" })
        assert.eq(target.path, vim.uv.fs_realpath(path))
    end)
end)

describe("buffer.target line scope", function()
    it("captures a single 1-indexed line", function()
        local target = buffer.target(scratch(LINES), { scope = "lines", range = { 3, 0, 3, 0 } })
        assert.eq(target.scope, "lines")
        assert.eq(target.line_start, 3)
        assert.eq(target.line_end, 3)
        assert.eq(target.col_start, 0)
    end)

    it("drops columns, since a line annotation covers whole lines", function()
        local target = buffer.target(scratch(LINES), { scope = "lines", range = { 3, 7, 3, 9 } })
        assert.eq(target.col_start, 0)
        assert.eq(target.col_end, 0)
    end)
end)

describe("buffer.target range scope", function()
    it("captures a multi-line range with its columns", function()
        local target = buffer.target(scratch(LINES), { scope = "range", range = { 3, 1, 5, 3 } })
        assert.eq(target.scope, "range")
        assert.eq(target.line_start, 3)
        assert.eq(target.col_start, 1)
        assert.eq(target.line_end, 5)
        assert.eq(target.col_end, 3)
    end)

    it("normalizes a backwards selection", function()
        local target = buffer.target(scratch(LINES), { scope = "range", range = { 5, 3, 3, 1 } })
        assert.eq(target.line_start, 3)
        assert.eq(target.line_end, 5)
        assert.eq(target.col_start, 1)
        assert.eq(target.col_end, 3)
    end)
end)

describe("buffer.target rejections", function()
    it("refuses a buffer with no file name", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local target, err = buffer.target(bufnr, { scope = "file" })
        assert.is_nil(target)
        assert.match(err, "name")
    end)

    it("refuses a range past the end of the buffer", function()
        local target, err =
            buffer.target(scratch(LINES), { scope = "lines", range = { 99, 0, 99, 0 } })
        assert.is_nil(target)
        assert.match(err, "99")
    end)

    it("accepts the very last line", function()
        assert.not_nil(buffer.target(scratch(LINES), { scope = "lines", range = { 5, 0, 5, 0 } }))
    end)
end)
