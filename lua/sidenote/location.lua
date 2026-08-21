---@class sidenote.Location
---@field path string annotated file, as written in the location text
---@field scope "file"|"lines"|"range" how much of the file the annotation covers
---@field line_start integer first line, 1-based, or 0 for file scope
---@field line_end integer last line, inclusive
---@field col_start integer first byte column, 1-based, or 0 when no column was given
---@field col_end integer last byte column, inclusive

---The textual form of an annotation's target: `path:15:4-20:10`.
---
---Lines and columns are 1-indexed and columns are byte offsets, matching
---`line()` and `col()`. Scope is derived from which parts are present, so
---editing a location is how an annotation changes scope.
---@class sidenote.location
local M = {}

---Reject a captured path that still carries a position.
---
---The greedy path capture is what lets a path hold colons, and it is also what
---lets `a.lua:15:4-20` read as the path `a.lua:15` with lines 4-20.
---@param path string captured path, which may still end in a position
---@return string|nil err nil when the path carries no position
local function reject_dangling_position(path)
    if path:match(":%d+$") or path:match("%-%d+$") then
        return "mixed forms are not allowed: write both sides as line or as line:col"
    end
    return nil
end

---Parse `text` into a location, deriving its scope from the parts present.
---@param text string
---@return sidenote.Location|nil
---@return string|nil err why text is not a location
function M.parse(text)
    if type(text) ~= "string" or text == "" then
        return nil, "empty location"
    end

    -- Most specific first, since a shorter form's pattern also matches a longer one
    local path, ls, cs, le, ce = text:match("^(.*):(%d+):(%d+)%-(%d+):(%d+)$")
    if not path then
        path, ls, le = text:match("^(.*):(%d+)%-(%d+)$")
        if path then
            local err = reject_dangling_position(path)
            if err then
                return nil, err
            end
        end
    end
    if not path then
        path, ls = text:match("^(.*):(%d+)$")
        if path then
            local err = reject_dangling_position(path)
            if err then
                return nil, err
            end
            le = ls
        end
    end

    if not path then
        return {
            path = text,
            scope = "file",
            line_start = 0,
            line_end = 0,
            col_start = 0,
            col_end = 0,
        }
    end
    if path == "" then
        return nil, "location has a position but no path"
    end

    -- A literal `:0` is an invalid column, not an omitted one
    local has_cols = cs ~= nil
    local line_start, line_end = tonumber(ls), tonumber(le)
    local col_start, col_end = tonumber(cs) or 0, tonumber(ce) or 0

    if line_start < 1 or line_end < 1 then
        return nil, "lines are 1-indexed; 0 is not a line"
    end
    if has_cols and (col_start < 1 or col_end < 1) then
        return nil, "columns are 1-indexed; 0 is not a column"
    end
    if line_end < line_start then
        return nil, ("range end is before its start (%d before %d)"):format(line_end, line_start)
    end
    if line_end == line_start and has_cols and col_end < col_start then
        return nil,
            ("range end is before its start (column %d before %d)"):format(col_end, col_start)
    end

    return {
        path = path,
        scope = has_cols and "range" or "lines",
        line_start = line_start,
        line_end = line_end,
        col_start = col_start,
        col_end = col_end,
    }
end

---Render a location or a record as its textual form.
---@param loc sidenote.Location|sidenote.Annotation
---@return string
function M.format(loc)
    if loc.scope == "file" then
        return loc.path
    end
    if loc.col_start and loc.col_start > 0 then
        return ("%s:%d:%d-%d:%d"):format(
            loc.path,
            loc.line_start,
            loc.col_start,
            loc.line_end,
            loc.col_end
        )
    end
    if loc.line_start == loc.line_end then
        return ("%s:%d"):format(loc.path, loc.line_start)
    end
    return ("%s:%d-%d"):format(loc.path, loc.line_start, loc.line_end)
end

---Describe a line that falls past the end of the file it points into.
---@param path string annotated file the line points into
---@param line integer line that falls outside the file
---@param count integer number of lines the file holds
---@return string err
local function past_end(path, line, count)
    return ("line %d is past the end of %s, which has %d lines"):format(line, path, count)
end

---Check `loc` against real file content, clamping each column to its line's length.
---
---A line past the end of the file is refused rather than clamped, and `loc`
---itself is never mutated.
---@param loc sidenote.Location
---@param content string|nil nil when the file does not exist
---@return sidenote.Location|nil
---@return string|nil err why loc does not fit the content
function M.validate(loc, content)
    if content == nil then
        return nil, ("%s does not exist"):format(loc.path)
    end
    if loc.scope == "file" then
        return loc, nil
    end

    local hash = require("sidenote.core.hash")
    local lines = hash.split(content)
    local count = content == "" and 0 or #lines

    if loc.line_start > count then
        return nil, past_end(loc.path, loc.line_start, count)
    end
    if loc.line_end > count then
        return nil, past_end(loc.path, loc.line_end, count)
    end

    local out = vim.deepcopy(loc)
    if out.col_start > 0 then
        out.col_start = math.min(out.col_start, #lines[out.line_start])
        out.col_end = math.min(out.col_end, #lines[out.line_end])
    end
    return out, nil
end

return M
