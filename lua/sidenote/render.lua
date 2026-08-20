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

---Per-buffer overrides of the configured highlight default.
---@type table<integer, boolean>
local overrides = {}

---Whether range highlights show in a buffer, under the configured mode.
---@param bufnr integer
---@param mode string|nil off, on, always or never; nil reads as off
---@return boolean
function M.highlighted(bufnr, mode)
    if mode == "always" then
        return true
    end
    if mode == "never" then
        return false
    end
    local override = overrides[bufnr]
    if override ~= nil then
        return override
    end
    return mode == "on"
end

---Flip a buffer's range highlights, the way `:set spell!` flips spelling.
---@param bufnr integer
---@param mode string|nil the configured default
---@return boolean|nil shown nil when the mode pins highlights on or off
function M.toggle(bufnr, mode)
    if mode == "always" or mode == "never" then
        return nil
    end
    overrides[bufnr] = not M.highlighted(bufnr, mode)
    return overrides[bufnr]
end

---@param entry sidenote.render.Entry
---@param style string
---@return table|nil opts extmark options, or nil when nothing should be drawn
local function mark_opts(entry, style)
    local group = highlight.GROUPS[entry.status]
    if style == "sign" then
        -- A ranged sign mark repeats its glyph on every covered line, and here
        -- `end_row` is inclusive, unlike a highlight's
        return {
            end_row = entry.line_end - 1,
            sign_text = highlight.SIGNS[entry.status],
            sign_hl_group = group,
        }
    end
    if style == "virt_text" then
        return { virt_text = { { highlight.SIGNS[entry.status], group } }, virt_text_pos = "eol" }
    end

    -- `end_row` is the line *after* the last annotated one, since the range is
    -- exclusive; stopping at `line_end - 1` leaves a range's last line unmarked
    if style == "highlight" then
        return { end_row = entry.line_end, end_col = 0, hl_group = group, hl_eol = true }
    end
    if style == "underline" then
        -- No hl_eol: an underline belongs under the text, not trailing off it
        return {
            end_row = entry.line_end,
            end_col = 0,
            hl_group = highlight.UNDERLINES[entry.status],
        }
    end
    return nil
end

---Clear and repaint every entry, returning how many were actually placed.
---@param bufnr integer
---@param entries sidenote.render.Entry[]
---@param opts {style: string, highlight?: string}
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

    -- The overlay repeats the highlight style on top of the configured one,
    -- so it adds nothing when highlight already is the style
    local overlay = opts.style ~= "highlight" and M.highlighted(bufnr, opts.highlight)

    local count = vim.api.nvim_buf_line_count(bufnr)
    local placed = 0
    for _, entry in ipairs(entries) do
        -- An unplaced or out-of-range entry is skipped rather than clamped:
        -- clamping is how an annotation ends up pointing at unrelated code
        if entry.line_start and entry.line_end and entry.line_end <= count then
            local mark = mark_opts(entry, opts.style)
            if mark then
                mark.priority = highlight.PRIORITIES[entry.status]
                vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, entry.line_start - 1, 0, mark)
                placed = placed + 1
            end
            if overlay then
                local range = mark_opts(entry, "highlight")
                range.priority = highlight.PRIORITIES[entry.status]
                vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, entry.line_start - 1, 0, range)
            end
        end
    end
    return placed
end

return M
