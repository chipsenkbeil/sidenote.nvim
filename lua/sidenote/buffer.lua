---@class sidenote.buffer.Target
---@field path string absolute path of the buffer's file
---@field content string full buffer text
---@field scope "file"|"lines"|"range" what the annotation will cover
---@field line_start integer first line, 1-based, or 0 for file scope
---@field line_end integer last line, inclusive
---@field col_start integer first byte column, 1-based, or 0 outside range scope
---@field col_end integer last byte column, inclusive

---@class sidenote.buffer.TargetOpts
---@field scope "file"|"lines"|"range" what to capture
---@field range? integer[] line_start, col_start, line_end, col_end, with 1-indexed lines

---Reads a buffer into the shape the record layer wants.
---@class sidenote.buffer
local M = {}

---@param bufnr integer
---@param opts sidenote.buffer.TargetOpts
---@return sidenote.buffer.Target|nil
---@return string|nil err
function M.target(bufnr, opts)
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path == "" then
        return nil, "buffer has no file name, so there is nothing to anchor to"
    end
    -- Resolve symlinks so this path and the project root stay comparable; on
    -- macOS /var and /tmp are links into /private
    path = vim.uv.fs_realpath(path) or path

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    if opts.scope == "file" then
        return {
            path = path,
            content = content,
            scope = "file",
            line_start = 0,
            line_end = 0,
            col_start = 0,
            col_end = 0,
        }
    end

    local range = opts.range
    local line_start, col_start, line_end, col_end = range[1], range[2], range[3], range[4]
    if line_end < line_start then
        line_start, line_end = line_end, line_start
        col_start, col_end = col_end, col_start
    end
    if line_end > #lines then
        return nil,
            ("line %d is past the end of the buffer, which has %d lines"):format(line_end, #lines)
    end

    return {
        path = path,
        content = content,
        scope = opts.scope,
        line_start = line_start,
        line_end = line_end,
        col_start = opts.scope == "range" and col_start or 0,
        col_end = opts.scope == "range" and col_end or 0,
    }
end

return M
