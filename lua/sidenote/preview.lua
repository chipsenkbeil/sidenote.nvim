local store = require("sidenote.store")
local window = require("sidenote.window")

---Glance at a note without leaving the code.
---
---Owns a namespace separate from the indicator one, so dismissing a preview
---never clears the signs a buffer is showing.
---@class sidenote.preview
local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("sidenote.preview")

local PLACEHOLDER = "(empty note)"

---@type integer|nil
local current

---@return integer|nil winid
function M.winid()
    if current and vim.api.nvim_win_is_valid(current) then
        return current
    end
    return nil
end

function M.hide()
    window.close(M.winid())
    current = nil
end

---@param entry sidenote.session.Entry
---@param filetype string
---@param max_lines integer
---@return string[]
local function prose_lines(entry, filetype, max_lines)
    local prose = store.prose(entry.root, entry.id, filetype) or ""
    local lines = {}
    for line in (prose .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end
    if #lines == 0 then
        return { PLACEHOLDER }
    end
    while #lines > max_lines do
        lines[#lines] = nil
    end
    return lines
end

---Show a note's prose in the configured preview surface.
---@param entry sidenote.session.Entry
---@param opts sidenote.PreviewConfig
---@param filetype string
function M.show(entry, opts, filetype)
    M.hide()
    if opts.style == "none" then
        return
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, prose_lines(entry, filetype, opts.max_lines))
    vim.bo[bufnr].filetype = filetype
    vim.bo[bufnr].modifiable = false

    local style = opts.style == "split" and "split" or "float"
    current = window.open(bufnr, { style = style, position = "right", size = 60 })
end

return M
