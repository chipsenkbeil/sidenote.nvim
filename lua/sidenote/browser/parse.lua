local location = require("sidenote.location")
local record = require("sidenote.core.record")
local render = require("sidenote.browser.render")

---@class sidenote.browser.Field
---@field first integer first byte column the field occupies, 1-based
---@field last integer last byte column, inclusive

---@class sidenote.browser.Parsed
---@field id string annotation id the row stands for
---@field lnum integer buffer line the header sat on, 1-based
---@field kind string kind column exactly as written
---@field state string state column exactly as written
---@field pen string|nil pen column, nil when it held the `-` placeholder
---@field location string location column exactly as written
---@field prose string[] the lines beneath the header, summary first
---@field fields table<string, sidenote.browser.Field> mapping of column name -> the byte range it occupies

---@class sidenote.browser.ParseError
---@field lnum integer buffer line the error belongs to, 1-based
---@field message string what is wrong, phrased for the user

---Reads an edited browser buffer back into intents.
---
---Two kinds of line, told apart by one marker: a line opening with the
---concealed `/<id> ` prefix is a header, and every other line is prose of the
---header above it, verbatim. Syntactic only: nothing here touches the
---filesystem, so a whole edit can be parsed and reported on without a store.
---@class sidenote.browser.parse
local M = {}

---Columns that carry a value before the location, in order.
local LEADING = { "kind", "state", "pen" }

---@param row sidenote.browser.Parsed
---@return string|nil err
local function check(row)
    if not record.KINDS[row.kind] then
        return ("unknown kind %q; expected note or todo"):format(row.kind)
    end
    if not record.STATES[row.state] then
        return ("unknown state %q; expected open, resolved, wontfix or archived"):format(row.state)
    end
    -- Shape only: whether the pen is configured needs the config, which a
    -- parser does not have
    if row.pen ~= nil and not row.pen:match("^%w[%w_-]*$") then
        return ("%q is not a pen; use a word, or - for none"):format(row.pen)
    end
    local _, err = location.parse(row.location)
    return err
end

---Read a header line into its id and columns.
---
---Ids are word characters alone, so a prose line mentioning /etc/hosts can
---never read as a header. Columns are separated by a run of two or more
---spaces; the location comes last and runs to the end of the line.
---@param text string
---@return sidenote.browser.Parsed|nil row nil when the line is no header
---@return string|nil err set only when a header is malformed
function M.header(text)
    local id, rest = text:match("^/(%w+) (.*)$")
    if not id then
        return nil, nil
    end
    -- The concealed prefix is not part of the columns, but its width still
    -- counts towards the byte offsets a caller will move the cursor to
    local offset = #text - #rest

    local row = { id = id, prose = {}, fields = {} }
    local cursor = 1
    for _, name in ipairs(LEADING) do
        local gap_first, gap_last = rest:find("%s%s+", cursor)
        if not gap_first then
            return nil, "expected kind, state, pen and a location, separated by two or more spaces"
        end
        row[name] = rest:sub(cursor, gap_first - 1)
        row.fields[name] = { first = offset + cursor, last = offset + gap_first - 1 }
        cursor = gap_last + 1
    end
    if row.pen == render.NO_PEN then
        row.pen = nil
    end

    local trimmed = (rest:sub(cursor):gsub("%s+$", ""))
    row.location = trimmed
    row.fields.location = { first = offset + cursor, last = offset + cursor + #trimmed - 1 }

    local err = check(row)
    if err then
        return nil, err
    end
    return row, nil
end

---Read a whole edited buffer into rows and the errors they carry.
---
---An error names the line it came from rather than aborting the pass, so one
---bad row reports against itself and the rest still parse.
---@param lines string[]
---@return sidenote.browser.Parsed[]
---@return sidenote.browser.ParseError[]
function M.buffer(lines)
    local rows, errors, seen = {}, {}, {}
    local current, blanks = nil, 0

    ---@param lnum integer
    ---@param message string
    local function fail(lnum, message)
        errors[#errors + 1] = { lnum = lnum, message = message }
    end

    for lnum, text in ipairs(lines) do
        if not text:match("%S") then
            -- A blank line is prose only when more prose follows; a trailing spacer is dropped
            blanks = blanks + 1
        else
            local row, err = M.header(text)
            if err then
                current = nil
                fail(lnum, err)
            elseif not row then
                if not current then
                    fail(lnum, "prose with no annotation above it")
                else
                    for _ = 1, blanks do
                        current.prose[#current.prose + 1] = ""
                    end
                    current.prose[#current.prose + 1] = text
                end
            elseif seen[row.id] then
                current = nil
                fail(
                    lnum,
                    ("id already used on line %d; two rows cannot share one annotation"):format(
                        seen[row.id]
                    )
                )
            else
                row.lnum = lnum
                seen[row.id] = lnum
                rows[#rows + 1] = row
                current = row
            end
            blanks = 0
        end
    end

    for _, row in ipairs(rows) do
        row.prose = render.normalize(row.prose)
    end
    return rows, errors
end

return M
