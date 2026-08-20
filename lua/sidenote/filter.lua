---Which annotations pass a narrowing, shared by every surface that narrows.
---@class sidenote.filter
local M = {}

---@class sidenote.Filter
---@field status? sidenote.Status keep only annotations the resolver put here
---@field kind? "note"|"todo" keep only notes or only requests to act
---@field state? string keep only one lifecycle position
---@field path? string keep only paths containing this, literally

---@param entry sidenote.session.Entry
---@param filter sidenote.Filter
---@return boolean
function M.survives(entry, filter)
    return (filter.status == nil or entry.status == filter.status)
        and (filter.kind == nil or entry.record.kind == filter.kind)
        and (filter.state == nil or entry.record.state == filter.state)
        and (filter.path == nil or entry.record.path:find(filter.path, 1, true) ~= nil)
end

---The entries of `entries` that pass `filter`.
---@param entries sidenote.session.Entry[]
---@param filter sidenote.Filter|nil nil keeps everything
---@return sidenote.session.Entry[]
function M.narrow(entries, filter)
    if not filter or vim.tbl_isempty(filter) then
        return entries
    end
    local kept = {}
    for _, entry in ipairs(entries) do
        if M.survives(entry, filter) then
            kept[#kept + 1] = entry
        end
    end
    return kept
end

return M
