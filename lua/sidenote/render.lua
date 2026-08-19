local highlight = require("sidenote.highlight")

---@class sidenote.render.Entry
---@field id string annotation this mark stands for
---@field status sidenote.Status anchor status, deciding the styling
---@field line_start? integer first line, 1-based, absent when unplaced
---@field line_end? integer last line, inclusive

---Paints resolved annotations into a buffer.
---
---Takes already-resolved entries rather than records, so it never consults the
---store and can be exercised against a scratch buffer.
---@class sidenote.render
local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("sidenote")

---Groups are defined on first paint rather than at plugin load, so the entry
---point stays free of eager requires.
local defined = false

---@param bufnr integer
function M.clear(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, M.NAMESPACE, 0, -1)
end

---@param entry sidenote.render.Entry
---@param style string
---@return table|nil opts extmark options, or nil when nothing should be drawn
local function mark_opts(entry, style)
    local group = highlight.GROUPS[entry.status]
    if style == "sign" then
        return { sign_text = highlight.SIGNS[entry.status], sign_hl_group = group }
    end
    if style == "virt_text" then
        return { virt_text = { { highlight.SIGNS[entry.status], group } }, virt_text_pos = "eol" }
    end
    if style == "highlight" or style == "underline" then
        return { end_row = entry.line_end - 1, end_col = 0, hl_group = group, hl_eol = true }
    end
    return nil
end

---Clear and repaint every entry, returning how many were actually placed.
---@param bufnr integer
---@param entries sidenote.render.Entry[]
---@param opts {style: string}
---@return integer placed
function M.paint(bufnr, entries, opts)
    if not defined then
        highlight.setup()
        defined = true
    end

    M.clear(bufnr)
    if opts.style == "none" then
        return 0
    end

    local count = vim.api.nvim_buf_line_count(bufnr)
    local placed = 0
    for _, entry in ipairs(entries) do
        -- An unplaced or out-of-range entry is skipped rather than clamped:
        -- clamping is how an annotation ends up pointing at unrelated code
        if entry.line_start and entry.line_end and entry.line_end <= count then
            local mark = mark_opts(entry, opts.style)
            if mark then
                vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, entry.line_start - 1, 0, mark)
                placed = placed + 1
            end
        end
    end
    return placed
end

return M
