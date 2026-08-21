---Hashing and text-normalization helpers.
---@class sidenote.core.hash
local M = {}

---Hash `text` with SHA-256.
---@param text string
---@return string sha 64-char lowercase hex
function M.sha256(text)
    return vim.fn.sha256(text)
end

---Split `content` into lines.
---
---A single trailing newline does not produce a final empty element; interior
---blank lines are preserved. An empty string yields one empty line, never an
---empty list.
---@param content string
---@return string[]
function M.split(content)
    local lines = {}
    local start = 1
    while true do
        local nl = content:find("\n", start, true)
        if not nl then
            lines[#lines + 1] = content:sub(start)
            break
        end
        lines[#lines + 1] = content:sub(start, nl - 1)
        start = nl + 1
    end
    if #lines > 1 and lines[#lines] == "" then
        lines[#lines] = nil
    end
    return lines
end

---Strip leading and trailing whitespace from `text`.
---@param text string
---@return string
function M.trim(text)
    return (text:match("^%s*(.-)%s*$"))
end

---Collapse whitespace runs to a single space and trim each line, then rejoin.
---
---Makes reindented and respaced code compare equal while keeping line
---structure, so a reformat does not read as a different anchor.
---@param text string
---@return string
function M.normalize(text)
    local out = {}
    for _, line in ipairs(M.split(text)) do
        local collapsed = line:gsub("%s+", " ")
        out[#out + 1] = M.trim(collapsed)
    end
    return table.concat(out, "\n")
end

---Join the `lines` from `first` to `last` with newlines.
---
---Both bounds are 1-based and inclusive, and are clamped to the available
---range, so an out-of-range request yields what exists rather than failing.
---@param lines string[]
---@param first integer
---@param last integer
---@return string
function M.slice(lines, first, last)
    local lo = math.max(1, first)
    local hi = math.min(#lines, last)
    if lo > hi then
        return ""
    end
    local out = {}
    for i = lo, hi do
        out[#out + 1] = lines[i]
    end
    return table.concat(out, "\n")
end

return M
