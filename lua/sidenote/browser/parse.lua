local location = require("sidenote.location")
local record = require("sidenote.core.record")
local render = require("sidenote.browser.render")

---@class sidenote.browser.Field
---@field first integer first byte column the field occupies, 1-based
---@field last integer last byte column, inclusive

---@class sidenote.browser.Parsed
---@field id string|nil annotation id, absent when the row is a create
---@field lnum integer buffer line the header sat on, 1-based
---@field kind string kind column exactly as written
---@field state string state column exactly as written
---@field location string location column exactly as written
---@field prose string[] the indented lines beneath the header, summary first
---@field fields table<string, sidenote.browser.Field> column ranges, for <Tab>

---@class sidenote.browser.ParseError
---@field lnum integer buffer line the error belongs to, 1-based
---@field message string what is wrong, phrased for the user

---Reads an edited browser buffer back into intents.
---
---Syntactic only: nothing here touches the filesystem, so a whole edit can be
---parsed and reported on without a store. Anything needing a file on disk is
---the applying layer's job.
---@class sidenote.browser.parse
local M = {}

---Columns that carry a value before the location, in order.
local LEADING = { "kind", "state" }

---@param text string
---@return integer leading spaces the renderer would have added
local function indent_of(text)
    return math.min(#(text:match("^ *") or ""), render.PROSE_INDENT)
end

---@param row sidenote.browser.Parsed
---@return string|nil err
local function check(row)
    if not record.KINDS[row.kind] then
        return ("unknown kind %q; expected note or todo"):format(row.kind)
    end
    if not record.STATES[row.state] then
        return ("unknown state %q; expected open, resolved, wontfix or archived"):format(row.state)
    end
    local _, err = location.parse(row.location)
    return err
end

---Read one column-0 line into an id and its three columns.
---
---A line carrying an id is an existing annotation; one without is a create.
---Columns are separated by a run of two or more spaces; the location comes
---last and runs to the end of the line, so even a path holding such a run
---cannot be misread.
---@param text string
---@return sidenote.browser.Parsed|nil
---@return string|nil err
function M.header(text)
    local id, rest = text:match("^/(%S+) (.*)$")
    -- The concealed prefix is not part of the columns, but its width still
    -- counts towards the byte offsets a caller will move the cursor to
    local offset = id and (#text - #rest) or 0
    rest = rest or text

    local row = { id = id, prose = {}, fields = {} }
    local cursor = 1
    for _, name in ipairs(LEADING) do
        local gap_first, gap_last = rest:find("%s%s+", cursor)
        if not gap_first then
            return nil, "expected kind, state and a location, separated by two or more spaces"
        end
        row[name] = rest:sub(cursor, gap_first - 1)
        row.fields[name] = { first = offset + cursor, last = offset + gap_first - 1 }
        cursor = gap_last + 1
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
            -- Held rather than stored: a blank line is prose only when more
            -- prose follows it, so a spacer before the next row is dropped
            blanks = blanks + 1
        elseif text:match("^%s") then
            if not current then
                fail(lnum, "indented prose with no annotation above it")
            else
                for _ = 1, blanks do
                    current.prose[#current.prose + 1] = ""
                end
                current.prose[#current.prose + 1] = text:sub(indent_of(text) + 1)
            end
            blanks = 0
        else
            blanks = 0
            local row, err = M.header(text)
            if not row then
                current = nil
                fail(lnum, err)
            elseif row.id and seen[row.id] then
                current = nil
                fail(
                    lnum,
                    ("id already used on line %d; two rows cannot share one annotation"):format(
                        seen[row.id]
                    )
                )
            else
                row.lnum = lnum
                if row.id then
                    seen[row.id] = lnum
                end
                rows[#rows + 1] = row
                current = row
            end
        end
    end

    for _, row in ipairs(rows) do
        row.prose = render.normalize(row.prose)
    end
    return rows, errors
end

return M
