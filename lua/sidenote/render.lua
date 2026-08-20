local highlight = require("sidenote.highlight")

---@class sidenote.render.Entry
---@field id string annotation this mark stands for
---@field status sidenote.Status anchor status, deciding the styling
---@field line_start? integer first line, 1-based, absent when unplaced
---@field line_end? integer last line, inclusive
---@field col_start? integer first byte column, 1-based, for a range's exact span
---@field col_end? integer last byte column, inclusive

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

---Where an entry's ink starts: a range's own column, else the line's start.
---@param entry sidenote.render.Entry
---@return integer col 0-based byte column
local function span_start(entry)
    if entry.col_start and entry.col_start > 0 then
        return entry.col_start - 1
    end
    return 0
end

---Where an entry's ink ends: a range's own column, else its last line's text.
---@param bufnr integer
---@param entry sidenote.render.Entry
---@return integer row 0-based
---@return integer col exclusive byte column
local function span_end(bufnr, entry)
    if entry.col_end and entry.col_end > 0 then
        return entry.line_end - 1, entry.col_end
    end
    local last = vim.api.nvim_buf_get_lines(bufnr, entry.line_end - 1, entry.line_end, false)[1]
    return entry.line_end - 1, #(last or "")
end

---@param bufnr integer
---@param entry sidenote.render.Entry
---@param style string
---@return integer|nil col 0-based start column, nil when nothing is drawn
---@return table|nil opts extmark options
local function mark_opts(bufnr, entry, style)
    local group = highlight.GROUPS[entry.status]
    if style == "sign" then
        -- A ranged sign mark repeats its glyph on every covered line, and here
        -- `end_row` is inclusive, unlike a highlight's
        return 0,
            {
                end_row = entry.line_end - 1,
                sign_text = highlight.SIGNS[entry.status],
                sign_hl_group = group,
            }
    end
    if style == "virt_text" then
        return 0,
            { virt_text = { { highlight.SIGNS[entry.status], group } }, virt_text_pos = "eol" }
    end

    -- Ink over the text and only the text, the way a marker pen reads: exact
    -- columns for a range, through the last line's end otherwise
    if style == "highlight" or style == "underline" then
        local end_row, end_col = span_end(bufnr, entry)
        return span_start(entry),
            {
                end_row = end_row,
                end_col = end_col,
                hl_group = style == "highlight" and highlight.MARKS[entry.status]
                    or highlight.UNDERLINES[entry.status],
            }
    end
    return nil, nil
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
            local col, mark = mark_opts(bufnr, entry, opts.style)
            if mark then
                mark.priority = highlight.PRIORITIES[entry.status]
                vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, entry.line_start - 1, col, mark)
                placed = placed + 1
            end
            if overlay then
                local ink, range = mark_opts(bufnr, entry, "highlight")
                range.priority = highlight.PRIORITIES[entry.status]
                vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, entry.line_start - 1, ink, range)
            end
        end
    end
    return placed
end

return M
