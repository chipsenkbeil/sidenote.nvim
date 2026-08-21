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
---Anchor status is not among them: recomputed on every render and persisted
---nowhere, a text column for it would be a field you can type into that is
---overwritten a moment later, so it lives in the sign column instead. Nor is
---the summary, which stays with the prose it opens.
---@type sidenote.browser.Column[]
M.COLUMNS = {
    { name = "kind", width = 4 },
    -- Content-sized so a listing of nothing but open notes carries no dead pad
    { name = "state", width = 0 },
    { name = "pen", width = 0 },
    { name = "location", width = 0 },
}

---What the pen column renders when a row carries none.
M.NO_PEN = "-"

---Spaces between one column and the next.
---
---Two, so that a run of two spaces is unambiguously a boundary while a single
---space inside a path is not.
M.GAP = 2

---Reduce `prose` to the canonical form a render reproduces exactly.
---
---1. Trailing blank lines go.
---2. A whitespace-only line inside the prose is empty, since a trim-on-save
---   hook would empty it anyway.
---3. The summary line loses the whitespace at either end of it, because a
---   closed fold previews it and the preview trims.
---
---Every other line is verbatim. The caller diffs an edited buffer against
---this form, so a baseline normalized any other way reports an edit nobody
---made, and then applies it.
---@param prose string[]
---@return string[]
function M.normalize(prose)
    local out = {}
    for i, line in ipairs(prose) do
        if i == 1 then
            out[i] = line:match("^%s*(.-)%s*$")
        elseif not line:match("%S") then
            out[i] = ""
        else
            out[i] = line
        end
    end
    while #out > 0 and not out[#out]:match("%S") do
        out[#out] = nil
    end
    return out
end

---@param row sidenote.browser.Row
---@return string[] cells kind, state, pen and location, unpadded
local function cells(row)
    local rec = row.entry.record
    return { rec.kind, rec.state, rec.pen or M.NO_PEN, location.format(rec) }
end

---Measure each column, widening the unfixed ones to their widest cell.
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
        if i < #cell then
            local pad = width[i] - vim.fn.strdisplaywidth(text) + M.GAP
            parts[#parts + 1] = (" "):rep(math.max(pad, M.GAP))
        end
    end
    return (table.concat(parts):gsub("%s+$", ""))
end

---Render every row as one header line followed by its prose.
---@param rows sidenote.browser.Row[]
---@return string[] lines
---@return integer[] headers one line number per row, in the same order
function M.rows(rows)
    local prose, all = {}, {}
    for i, row in ipairs(rows) do
        prose[i] = M.normalize(row.prose)
        all[i] = cells(row)
    end

    local width = widths(all)
    local lines, headers = {}, {}
    for i, row in ipairs(rows) do
        lines[#lines + 1] = header(row.entry.id, all[i], width)
        headers[i] = #lines
        for n = 1, #prose[i] do
            -- At the margin: a header's concealed id is the grammar's only marker
            lines[#lines + 1] = prose[i][n]
        end
    end
    return lines, headers
end

return M
