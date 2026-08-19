---Picks the next annotation worth jumping to.
---
---Pure over a list of entries, so it needs no buffer and no window.
---@class sidenote.navigate
local M = {}

---Statuses with a position a reader can trust.
---
---An ambiguous, orphaned, or missing anchor has nowhere meaningful to land,
---and jumping there is worse than not jumping.
---@type table<sidenote.Status, boolean>
M.NAVIGABLE = { attached = true, drifted = true }

---@param entry sidenote.session.Entry
---@return boolean
local function navigable(entry)
    return M.NAVIGABLE[entry.status] == true and entry.line_start ~= nil
end

---First navigable entry below `line`, wrapping to the top of the file.
---@param entries sidenote.session.Entry[]
---@param line integer
---@return sidenote.session.Entry|nil
function M.next(entries, line)
    local first
    for _, entry in ipairs(entries) do
        if navigable(entry) then
            first = first or entry
            if entry.line_start > line then
                return entry
            end
        end
    end
    return first
end

---Last navigable entry above `line`, wrapping to the bottom of the file.
---@param entries sidenote.session.Entry[]
---@param line integer
---@return sidenote.session.Entry|nil
function M.prev(entries, line)
    local found, last
    for _, entry in ipairs(entries) do
        if navigable(entry) then
            last = entry
            if entry.line_start < line then
                found = entry
            end
        end
    end
    return found or last
end

return M
