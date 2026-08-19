---@class sidenote.window.Opts
---@field style "split"|"float"|"current"|"tab" surface to open the buffer in
---@field position? "left"|"right"|"top"|"bottom" side a split takes
---@field size? integer columns for a vertical split, rows for a horizontal one
---@field focus? boolean whether the cursor moves into the new window

---Opens buffers in whichever surface the user configured.
---
---Every window the plugin creates comes through here, so preview and editor
---cannot drift apart on placement.
---@class sidenote.window
local M = {}

---Users configure top and bottom; `nvim_open_win` speaks above and below.
---@type table<string, string>
local SPLIT_DIRECTION = { left = "left", right = "right", top = "above", bottom = "below" }

---@type table<string, boolean>
local VERTICAL = { left = true, right = true }

local DEFAULT_WIDTH = 60

---@param bufnr integer
---@param focus boolean
---@param size integer|nil
---@return integer winid
local function open_float(bufnr, focus, size)
    local width = size or DEFAULT_WIDTH
    local height = math.max(1, math.min(vim.o.lines - 4, vim.api.nvim_buf_line_count(bufnr)))
    return vim.api.nvim_open_win(bufnr, focus, {
        relative = "editor",
        row = math.max(0, math.floor((vim.o.lines - height) / 2)),
        col = math.max(0, math.floor((vim.o.columns - width) / 2)),
        width = width,
        height = height,
        border = "rounded",
        style = "minimal",
    })
end

---@param bufnr integer
---@param opts sidenote.window.Opts
---@return integer winid
function M.open(bufnr, opts)
    local focus = opts.focus == true

    if opts.style == "current" then
        vim.api.nvim_win_set_buf(0, bufnr)
        return vim.api.nvim_get_current_win()
    end

    if opts.style == "tab" then
        vim.cmd.tabnew()
        local winid = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(winid, bufnr)
        return winid
    end

    if opts.style == "float" then
        return open_float(bufnr, focus, opts.size)
    end

    local position = opts.position or "right"
    local config = { split = SPLIT_DIRECTION[position] or position }
    if VERTICAL[position] then
        config.width = opts.size
    else
        config.height = opts.size
    end
    return vim.api.nvim_open_win(bufnr, focus, config)
end

---@param winid integer|nil
function M.close(winid)
    if winid and vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
    end
end

return M
