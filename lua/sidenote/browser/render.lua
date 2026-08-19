local location = require("sidenote.location")

---@class sidenote.browser.Row
---@field entry sidenote.session.Entry resolved annotation this row stands for
---@field prose string[] the note's prose, one line per entry

---@class sidenote.browser.Column
---@field name string record field this column carries
---@field width integer fixed render width, or 0 when sized to its content

---Turns annotations into the browser's buffer lines.
---
---Nothing here reads disk or touches a buffer, so a row can be built by hand
---and the rendering checked on its own.
---@class sidenote.browser.render
local M = {}

---Columns in the order they are written, every one owned by the user.
---
---Anchor status is deliberately not among them: it is recomputed on every
---render and persisted nowhere, so a text column for it would be a field you
---can type into that is overwritten a moment later. It goes in the sign column.
---@type sidenote.browser.Column[]
M.COLUMNS = {
    { name = "kind", width = 4 },
    { name = "state", width = 8 },
    { name = "location", width = 0 },
    { name = "summary", width = 0 },
}

---Spaces between one column and the next.
---
---Two, so that a run of two spaces is unambiguously a boundary while a single
---space inside a summary or a path is not.
M.GAP = 2

---Spaces prefixing every prose line below the summary.
M.PROSE_INDENT = 4

---The canonical form of a note's prose: what rendering can reproduce exactly.
---
---Two rules. Trailing blank lines go, and the summary line loses the
---whitespace at either end of it.
---
---The summary is the only line that cannot carry its own leading whitespace,
---because it sits behind the location column's padding and parsing cannot tell
---one run of spaces from the other. Trailing whitespace goes for a second
---reason: the renderer strips the end of every line so a save hook does not
---produce a diff on its own.
---
---Exported because the browser keeps the result as its diff baseline. A
---baseline normalized differently from what was rendered would report an edit
---nobody made, and then apply it.
---@param prose string[]
---@return string[]
function M.normalize(prose)
    local out = {}
    for i, line in ipairs(prose) do
        out[i] = i == 1 and line:match("^%s*(.-)%s*$") or line
    end
    while #out > 0 and not out[#out]:match("%S") do
        out[#out] = nil
    end
    return out
end

---Whether a row's location would survive being read back out of the buffer.
---
---Columns are separated by a run of two or more spaces, so a path holding such
---a run is indistinguishable from a column boundary and would parse as a
---truncated location with the rest spilling into the summary. Rare, and worth
---catching rather than applying.
---@param row sidenote.browser.Row
---@return boolean
function M.ambiguous(row)
    return location.format(row.entry.record):find("%s%s") ~= nil
end

---@param row sidenote.browser.Row
---@param prose string[] the row's normalized prose
---@return string[] cells kind, state, location and summary, unpadded
local function cells(row, prose)
    local rec = row.entry.record
    return { rec.kind, rec.state, location.format(rec), prose[1] or "" }
end

---Width of each column, taking the widest cell where the column is not fixed.
---@param all string[][] cells for every row
---@return integer[]
local function widths(all)
    local out = {}
    for i, column in ipairs(M.COLUMNS) do
        out[i] = column.width
        if column.width == 0 then
            for _, cell in ipairs(all) do
                out[i] = math.max(out[i], vim.fn.strdisplaywidth(cell[i]))
            end
        end
    end
    return out
end

---@param id string
---@param cell string[]
---@param width integer[]
---@return string
local function header(id, cell, width)
    local parts = { ("/%s "):format(id) }
    for i, text in ipairs(cell) do
        parts[#parts + 1] = text
        -- The final column is never padded; anything after it would be
        -- trailing whitespace for a save hook to strip back off
        if i < #cell then
            local pad = width[i] - vim.fn.strdisplaywidth(text) + M.GAP
            parts[#parts + 1] = (" "):rep(math.max(pad, M.GAP))
        end
    end
    return (table.concat(parts):gsub("%s+$", ""))
end

---Render every row as one header line plus its indented prose.
---
---The second return is the buffer line each row's header landed on, which is
---where a caller places that annotation's status sign.
---@param rows sidenote.browser.Row[]
---@return string[] lines
---@return integer[] headers one line number per row, in the same order
function M.rows(rows)
    local prose, all = {}, {}
    for i, row in ipairs(rows) do
        prose[i] = M.normalize(row.prose)
        all[i] = cells(row, prose[i])
    end

    local width = widths(all)
    local indent = (" "):rep(M.PROSE_INDENT)
    local lines, headers = {}, {}
    for i, row in ipairs(rows) do
        lines[#lines + 1] = header(row.entry.id, all[i], width)
        headers[i] = #lines
        for n = 2, #prose[i] do
            -- A blank line stays empty rather than indented, since a
            -- trim-trailing-whitespace hook would strip the indent anyway
            lines[#lines + 1] = prose[i][n]:match("%S") and (indent .. prose[i][n]) or ""
        end
    end
    return lines, headers
end

return M
